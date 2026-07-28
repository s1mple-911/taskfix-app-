-- ============================================================
-- TASKFIX_SEARCH.sql — universal qidiruv uchun indekslar (ADDITIVE, IXTIYORIY)
-- ============================================================
-- Ilova bu fayl ISHGA TUSHIRILMASA HAM to'liq ishlaydi — bu faqat tezlik
-- uchun. Universal qidiruv (gs* moduli, index.html) server tomonda
-- `ilike '%term%'` ishlatadi:
--     tasks.title / tasks.description
--     projects.name / projects.description
--     positions.name
-- `%term%` (boshida joker) oddiy B-tree indeksdan FOYDALANMAYDI — seq scan
-- bo'ladi. Kichik workspace'da bu sezilmaydi; vazifalar soni o'sganda
-- (~10k+) pg_trgm GIN indeksi qidiruvni bir necha barobar tezlashtiradi.
--
-- Xodim/telefon qidiruvi bu yerda YO'Q — u klient tomonda (wsMembers keshi,
-- raqamlarga normallashtirib) bajariladi, shuning uchun indeks kerak emas.
--
-- Idempotent: qayta-qayta ishga tushirsa bo'ladi.
-- Oxirida tekshiruv bor — biror indeks yaratilmasa RAISE EXCEPTION beradi
-- (jimgina o'tib ketmaydi).
-- ============================================================

-- ── 1) pg_trgm ────────────────────────────────────────────────
-- Supabase'da kengaytmalar odatda `extensions` sxemasida turadi. Agar shu
-- sxema bo'lsa — o'sha yerga, bo'lmasa — sukut bo'yicha sxemaga.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm') THEN
    RAISE NOTICE 'pg_trgm allaqachon o''rnatilgan';
  ELSIF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'extensions') THEN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions';
  ELSE
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_trgm';
  END IF;
END $$;

-- ── 2) GIN trigram indekslari ─────────────────────────────────
-- gin_trgm_ops operator klassi pg_trgm qaysi sxemada bo'lsa o'sha yerda —
-- shuning uchun to'liq nom bilan yozamiz (search_path'ga bog'liq bo'lmaymiz).
DO $$
DECLARE
  ext_schema text;
  ops        text;
  t          record;
BEGIN
  SELECT n.nspname INTO ext_schema
    FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
   WHERE e.extname = 'pg_trgm';
  IF ext_schema IS NULL THEN
    RAISE EXCEPTION 'pg_trgm o''rnatilmadi — indekslar yaratilmaydi';
  END IF;
  ops := quote_ident(ext_schema) || '.gin_trgm_ops';

  FOR t IN
    SELECT * FROM (VALUES
      ('tasks',     'title',       'idx_tasks_title_trgm'),
      ('tasks',     'description', 'idx_tasks_desc_trgm'),
      ('projects',  'name',        'idx_projects_name_trgm'),
      ('projects',  'description', 'idx_projects_desc_trgm'),
      ('positions', 'name',        'idx_positions_name_trgm')
    ) AS v(tbl, col, idx)
  LOOP
    -- Jadval/ustun yo'q bo'lsa jimgina o'tkazamiz, lekin NOTICE qoldiramiz
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = t.tbl AND column_name = t.col
    ) THEN
      RAISE NOTICE 'O''tkazildi: public.%.% mavjud emas', t.tbl, t.col;
      CONTINUE;
    END IF;
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS %I ON public.%I USING gin (%I %s)',
      t.idx, t.tbl, t.col, ops
    );
    RAISE NOTICE 'OK: % (public.%.%)', t.idx, t.tbl, t.col;
  END LOOP;
END $$;

-- ── 3) Tekshiruv — jimgina o'tmasin ───────────────────────────
DO $$
DECLARE
  missing text := '';
  t       record;
BEGIN
  FOR t IN
    SELECT * FROM (VALUES
      ('tasks',     'title',       'idx_tasks_title_trgm'),
      ('tasks',     'description', 'idx_tasks_desc_trgm'),
      ('projects',  'name',        'idx_projects_name_trgm'),
      ('projects',  'description', 'idx_projects_desc_trgm'),
      ('positions', 'name',        'idx_positions_name_trgm')
    ) AS v(tbl, col, idx)
  LOOP
    -- Ustun bor, lekin indeks yo'q = haqiqiy muammo
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = t.tbl AND column_name = t.col
    ) AND NOT EXISTS (
      SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = t.idx
    ) THEN
      missing := missing || ' ' || t.idx;
    END IF;
  END LOOP;

  IF missing <> '' THEN
    RAISE EXCEPTION 'Quyidagi indekslar yaratilmadi:%', missing;
  END IF;
  RAISE NOTICE '✅ TASKFIX_SEARCH.sql — barcha kerakli indekslar joyida';
END $$;

-- ── 4) Tekshirib ko'rish (ixtiyoriy, qo'lda) ──────────────────
-- EXPLAIN ANALYZE
-- SELECT id, title FROM public.tasks
--  WHERE workspace_id = '<WS_UUID>'
--    AND (title ILIKE '%hisobot%' OR description ILIKE '%hisobot%')
--  ORDER BY created_at DESC LIMIT 30;
