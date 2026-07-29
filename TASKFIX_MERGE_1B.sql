-- ============================================================================
-- TASKFIX_MERGE_1B.sql — 1b: dublikat xodimlarni BIRLASHTIRISH
-- ============================================================================
-- ⚠️ BU FAYL YOZADI. Oldin PITR / backup nuqtasi borligiga ishonch hosil qiling.
--
-- ⚠️ FAQAT QUYIDAGI 2 JUFTLIK UCHUN (uuid'lar qattiq yozilgan). Universal
--    merge EMAS. Kelajakda yana dublikat chiqsa: avval TASKFIX_MERGE_DIAG.sql,
--    keyin yangi merge fayli.
--
--      Nodir      KEEP d7d8f5f3-821c-4c45-896b-e0e6a2de8c42 (login qiladi, 1 vazifa)
--                 REM  eb0d0a9e-71dc-4bad-acdf-672c6c0f4a23 (email yo'q, 5 vazifa)
--      Saidakbar  KEEP 840a22ea-4315-4eeb-8efa-15b45561a27b (12 vazifa)
--                 REM  50ef8131-75be-4a0e-a760-2341edf21df2 (0 vazifa)
--
-- ATOMIK: butun fayl BITTA tranzaksiya. Birorta tekshiruv yiqilsa —
--         HAMMASI ORQAGA QAYTADI, bazada hech narsa o'zgarmaydi.
--
-- IDEMPOTENT: ikkinchi marta ishga tushirilsa — ko'chiradigan narsa qolmaydi,
--             tekshiruvlar o'tadi, hech narsa buzilmaydi.
--
-- ─── NEGA HAVOLALAR QO'LDA RO'YXAT EMAS, DINAMIK TOPILADI ───────────────────
-- Brief "diagnostikada chiqqan TO'LIQ ro'yxatni ishlat, biror joy qolmasin"
-- deydi. Qo'lda ko'chirilgan ro'yxatga ishonish o'rniga bu skript
-- birlashtirish PAYTIDA public + storage sxemasidagi HAR uuid ustunini
-- (va uuid saqlashi mumkin bo'lgan matn ustunlarini) o'zi skanerlaydi va
-- REMOVE uchraган joyning HAMMASINI ko'chiradi. Ya'ni diagnostikadan keyin
-- yangi qator/ustun qo'shilgan bo'lsa ham qolib ketmaydi.
--
-- ─── UNIQUE TO'QNASHUV ──────────────────────────────────────────────────────
-- workspace_members (ws, user), project_members (project, user),
-- employee_details/branches/schedule_days (ws, user, ...) — ikkala profil ham
-- qator egallagan bo'lsa UPDATE 23505 beradi. Shuning uchun har ustun uchun
-- shu ustunni O'Z ICHIGA OLGAN UNIQUE indekslar topiladi va to'qnashadigan
-- REMOVE qatorlari OLDIN o'chiriladi, qolgani ko'chiriladi.
-- employee_details esa o'chirilishdan OLDIN maydon-maydon birlashtiriladi
-- (lavozim/filial/telefon KEEP da bo'sh bo'lsa REMOVE dan to'ldiriladi).
--
-- ─── RASM (Storage) ─────────────────────────────────────────────────────────
-- Fayl yo'li {ws}/{uid}.jpg. SQL fayl ko'chira olmaydi (Storage API kerak) —
-- skript oxirida NOTICE bilan xabar beradi.
-- ============================================================================

BEGIN;

-- ── Xavfsizlik: SQL Editor'da tasodifan yarim bajarilib qolmasin ────────────
SET LOCAL statement_timeout = '300s';

DO $merge$
DECLARE
  -- ⚠️ SOZLAMALAR
  v_del_auth  boolean := true;   -- REMOVE ning auth.users qatorini ham o'chirish
                                 -- (faqat hech qachon login qilmagan bo'lsa)
  v_strict    boolean := true;   -- kutilgan vazifa sonidan farq bo'lsa TO'XTA

  p           RECORD;
  c           RECORD;
  ix          RECORD;
  v_sql       text;
  v_others    text;
  v_n         bigint;
  v_moved     bigint;
  v_deleted   bigint;
  v_rem_prof  jsonb;
  v_col       text;
  v_report    text := '';
  v_left      text;
  v_cnt       bigint;
  v_auth_ok   boolean;
BEGIN
FOR p IN
  SELECT * FROM (VALUES
    ('Nodir',
     'd7d8f5f3-821c-4c45-896b-e0e6a2de8c42'::uuid,
     'eb0d0a9e-71dc-4bad-acdf-672c6c0f4a23'::uuid,
     6::bigint),
    ('Saidakbar Muhiddinov',
     '840a22ea-4315-4eeb-8efa-15b45561a27b'::uuid,
     '50ef8131-75be-4a0e-a760-2341edf21df2'::uuid,
     12::bigint)
  ) AS t(label, keep_id, remove_id, expect_tasks)
LOOP
  RAISE NOTICE '════════ % : KEEP=%  REMOVE=% ════════', p.label, p.keep_id, p.remove_id;

  -- ── 0) Himoya ─────────────────────────────────────────────────────────────
  IF p.keep_id = p.remove_id THEN
    RAISE EXCEPTION '%: KEEP va REMOVE bir xil — to''xtatildi', p.label;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p.keep_id) THEN
    RAISE EXCEPTION '%: KEEP profil (%) topilmadi — noto''g''ri uuid yoki noto''g''ri baza', p.label, p.keep_id;
  END IF;

  -- REMOVE profil qatorini SAQLAB olamiz (o'chirgandan keyin bo'sh maydonlarni
  -- to'ldirish uchun). O'chirishdan KEYIN to'ldiramiz — shunda email/telefon
  -- kabi UNIQUE ustunlarda to'qnashuv bo'lmaydi.
  SELECT to_jsonb(pr) INTO v_rem_prof FROM public.profiles pr WHERE pr.id = p.remove_id;
  IF v_rem_prof IS NULL THEN
    RAISE NOTICE '  ℹ REMOVE profil allaqachon yo''q — faqat qolgan havolalar tekshiriladi (idempotent)';
  END IF;

  -- ── 1) employee_details: maydon-maydon birlashtirish (o'chishdan OLDIN) ───
  --    Sabab: (workspace_id,user_id) PK → 2-bosqichdagi to'qnashuv-o'chirish
  --    REMOVE qatorini yo'q qiladi. Undan oldin KEEP da BO'SH bo'lgan
  --    ustunlarni (lavozim, telefon, tug'ilgan sana...) REMOVE dan olamiz.
  IF to_regclass('public.employee_details') IS NOT NULL THEN
    FOR v_col IN
      SELECT column_name FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'employee_details'
         AND column_name NOT IN ('workspace_id', 'user_id', 'created_at', 'updated_at')
    LOOP
      EXECUTE format(
        'UPDATE public.employee_details k SET %I = r.%I '
        'FROM public.employee_details r '
        'WHERE k.user_id = $1 AND r.user_id = $2 AND k.workspace_id = r.workspace_id '
        '  AND (k.%I IS NULL OR btrim(k.%I::text) = '''') '
        '  AND r.%I IS NOT NULL AND btrim(r.%I::text) <> ''''',
        v_col, v_col, v_col, v_col, v_col, v_col)
      USING p.keep_id, p.remove_id;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      IF v_n > 0 THEN
        RAISE NOTICE '  ↪ employee_details.% : KEEP bo''sh edi, REMOVE dan to''ldirildi', v_col;
      END IF;
    END LOOP;
  END IF;

  -- ── 2) HAR uuid ustuni: to'qnashuvni hal qilib, havolani ko'chirish ───────
  --    'auth' sxemasi ATAYLAB chetda: auth.identities/sessions ni KEEP ga
  --    ko'chirish = login identitetlarini birlashtirish, bu xavfli va kerak
  --    emas (REMOVE akkaunt login qilmaydi va oxirida o'chiriladi).
  FOR c IN
    SELECT n.nspname::text AS sch, cl.relname::text AS tbl,
           a.attname::text AS col, cl.oid AS reloid
      FROM pg_attribute a
      JOIN pg_class     cl ON cl.oid = a.attrelid
      JOIN pg_namespace n  ON n.oid = cl.relnamespace
     WHERE a.atttypid = 'uuid'::regtype
       AND a.attnum > 0 AND NOT a.attisdropped
       AND cl.relkind IN ('r', 'p')
       AND n.nspname IN ('public', 'storage')
       -- profiles.id — profilning O'ZI, u 4-bosqichda o'chiriladi
       AND NOT (n.nspname = 'public' AND cl.relname = 'profiles' AND a.attname = 'id')
     ORDER BY 1, 2, 3
  LOOP
    EXECUTE format('SELECT count(*) FROM %I.%I WHERE %I = $1', c.sch, c.tbl, c.col)
      INTO v_n USING p.remove_id;
    CONTINUE WHEN v_n = 0;

    -- 2a) Shu ustunni o'z ichiga olgan UNIQUE indekslar — to'qnashuvni oldindan hal qilamiz
    FOR ix IN
      SELECT i.indexrelid::regclass::text AS idxname,
             (SELECT array_agg(att.attname ORDER BY k.ord)
                FROM unnest(i.indkey::smallint[]) WITH ORDINALITY AS k(attnum, ord)
                JOIN pg_attribute att ON att.attrelid = i.indrelid AND att.attnum = k.attnum
             ) AS cols,
             (i.indpred IS NOT NULL) AS is_partial,
             (i.indexprs IS NOT NULL) AS has_expr
        FROM pg_index i
       WHERE i.indrelid = c.reloid AND i.indisunique
    LOOP
      CONTINUE WHEN ix.cols IS NULL OR NOT (c.col = ANY (ix.cols::text[]));

      IF ix.has_expr OR ix.is_partial THEN
        -- Ifodali/shartli unique indeks: to'qnashuvni ishonchli hisoblab bo'lmaydi.
        -- Qator o'chirib yuborish o'rniga UPDATE ga qo'yib beramiz: to'qnashuv
        -- bo'lsa 23505 chiqadi va BUTUN tranzaksiya qaytadi (jimgina yo'qolmaydi).
        RAISE NOTICE '  ⚠ %.% : % indeksi ifodali/shartli — to''qnashuv oldindan tozalanmadi',
                     c.tbl, c.col, ix.idxname;
        CONTINUE;
      END IF;

      SELECT string_agg(format('k.%I IS NOT DISTINCT FROM r.%I', x, x), ' AND ')
        INTO v_others
        FROM unnest(ix.cols) AS x
       WHERE x::text <> c.col;

      IF v_others IS NULL THEN
        -- Ustunning o'zi yagona kalit (1:1) — KEEP da qator bo'lsa REMOVE niki ortiqcha
        v_sql := format(
          'DELETE FROM %I.%I r WHERE r.%I = $2 AND EXISTS (SELECT 1 FROM %I.%I k WHERE k.%I = $1)',
          c.sch, c.tbl, c.col, c.sch, c.tbl, c.col);
      ELSE
        v_sql := format(
          'DELETE FROM %I.%I r WHERE r.%I = $2 AND EXISTS ('
          '  SELECT 1 FROM %I.%I k WHERE k.%I = $1 AND %s)',
          c.sch, c.tbl, c.col, c.sch, c.tbl, c.col, v_others);
      END IF;

      EXECUTE v_sql USING p.keep_id, p.remove_id;
      GET DIAGNOSTICS v_deleted = ROW_COUNT;
      IF v_deleted > 0 THEN
        RAISE NOTICE '  ✂ %.%.% : % ta REMOVE qatori o''chirildi (KEEP da allaqachon bor — % )',
                     c.sch, c.tbl, c.col, v_deleted, ix.idxname;
        v_report := v_report || format(E'\n  o''chirildi  %s.%s (%s) : %s', c.tbl, c.col, ix.idxname, v_deleted);
      END IF;
    END LOOP;

    -- 2b) Qolgan havolalarni KEEP ga ko'chiramiz
    EXECUTE format('UPDATE %I.%I SET %I = $1 WHERE %I = $2', c.sch, c.tbl, c.col, c.col)
      USING p.keep_id, p.remove_id;
    GET DIAGNOSTICS v_moved = ROW_COUNT;
    IF v_moved > 0 THEN
      RAISE NOTICE '  → %.%.% : % ta qator KEEP ga ko''chirildi', c.sch, c.tbl, c.col, v_moved;
      v_report := v_report || format(E'\n  ko''chirildi %s.%s : %s', c.tbl, c.col, v_moved);
    END IF;
  END LOOP;

  -- ── 3) MATN ustunlarida saqlangan uid (polimorf havolalar) ────────────────
  --    Masalan activity_logs.entity_id (entity_type='employee' bo'lganda uid).
  --    Faqat AYNAN teng bo'lganlar ko'chiriladi (substring EMAS — rasm yo'li
  --    kabi joylarga tegmaymiz, u pastda alohida xabar qilinadi).
  FOR c IN
    SELECT n.nspname::text AS sch, cl.relname::text AS tbl, a.attname::text AS col
      FROM pg_attribute a
      JOIN pg_class     cl ON cl.oid = a.attrelid
      JOIN pg_namespace n  ON n.oid = cl.relnamespace
     WHERE a.atttypid IN ('text'::regtype, 'varchar'::regtype)
       AND a.attnum > 0 AND NOT a.attisdropped
       AND cl.relkind IN ('r', 'p')
       AND n.nspname IN ('public', 'storage')
       AND a.attname::text ~* '(_id$|_by$|_uid$|^id$|user)'
     ORDER BY 1, 2, 3
  LOOP
    EXECUTE format('UPDATE %I.%I SET %I = $1 WHERE %I = $2', c.sch, c.tbl, c.col, c.col)
      USING p.keep_id::text, p.remove_id::text;
    GET DIAGNOSTICS v_moved = ROW_COUNT;
    IF v_moved > 0 THEN
      RAISE NOTICE '  → (matn) %.%.% : % ta qator KEEP ga ko''chirildi', c.sch, c.tbl, c.col, v_moved;
      v_report := v_report || format(E'\n  ko''chirildi %s.%s (matn) : %s', c.tbl, c.col, v_moved);
    END IF;
  END LOOP;

  -- ── 4) REMOVE profilni o'chirish ─────────────────────────────────────────
  DELETE FROM public.profiles WHERE id = p.remove_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  IF v_deleted > 0 THEN
    RAISE NOTICE '  🗑 profiles: REMOVE qatori o''chirildi';
  END IF;

  -- ── 5) KEEP dagi BO'SH maydonlarni REMOVE dan to'ldirish ─────────────────
  --    REMOVE qatori endi yo'q → email/telefon kabi UNIQUE ustunlarda
  --    to'qnashuv bo'lmaydi. KEEP da qiymat BOR bo'lsa TEGILMAYDI.
  IF v_rem_prof IS NOT NULL THEN
    FOR v_col IN
      SELECT column_name FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'profiles'
         AND column_name NOT IN ('id', 'created_at', 'updated_at')
         AND data_type IN ('text', 'character varying')
    LOOP
      IF coalesce(btrim(v_rem_prof ->> v_col), '') <> '' THEN
        EXECUTE format(
          'UPDATE public.profiles SET %I = $2 WHERE id = $1 AND (%I IS NULL OR btrim(%I) = '''')',
          v_col, v_col, v_col)
        USING p.keep_id, btrim(v_rem_prof ->> v_col);
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n > 0 THEN
          RAISE NOTICE '  ↪ profiles.% : KEEP bo''sh edi, REMOVE dan to''ldirildi (%)', v_col, btrim(v_rem_prof ->> v_col);
        END IF;
      END IF;
    END LOOP;
  END IF;

  -- ── 6) auth.users: yetim qolgan REMOVE akkaunti ──────────────────────────
  --    FAQAT hech qachon login qilmagan bo'lsa o'chiriladi. Login qilgan
  --    bo'lsa — TEGILMAYDI va xabar beriladi (odam qo'lda qaror qiladi).
  IF v_del_auth THEN
    SELECT (u.last_sign_in_at IS NULL) INTO v_auth_ok
      FROM auth.users u WHERE u.id = p.remove_id;
    IF v_auth_ok IS NULL THEN
      RAISE NOTICE '  ℹ auth.users: REMOVE qatori yo''q (idempotent)';
    ELSIF v_auth_ok THEN
      -- Ichki BEGIN/EXCEPTION — auth sxemasidagi kutilmagan FK/trigger butun
      -- birlashtirishni qaytarib yubormasin. Xato JIMGINA yutilmaydi: WARNING.
      BEGIN
        DELETE FROM auth.users WHERE id = p.remove_id;
        RAISE NOTICE '  🗑 auth.users: REMOVE o''chirildi (hech qachon login qilmagan)';
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '  ⚠ auth.users REMOVE (%) o''chirilmadi: %. Birlashtirish DAVOM ETDI — bu qatorni keyin qo''lda o''chiring (Supabase Auth paneli).',
          p.remove_id, SQLERRM;
      END;
    ELSE
      RAISE WARNING '  ⚠ auth.users: REMOVE (%) LOGIN QILGAN — o''chirilmadi. Qo''lda ko''rib chiqing.', p.remove_id;
    END IF;
  END IF;

  -- ── 7) TEKSHIRUV — jimgina o'tmasin ──────────────────────────────────────
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p.keep_id) THEN
    RAISE EXCEPTION '%: KEEP profil YO''Q BO''LIB QOLDI — to''xtatildi', p.label;
  END IF;
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id = p.remove_id) THEN
    RAISE EXCEPTION '%: REMOVE profil hamon bor — o''chirish ishlamadi', p.label;
  END IF;

  -- 7a) REMOVE uid HECH QAYERDA qolmadimi (qayta skanerlash — 2-bosqichning isboti)
  v_left := '';
  FOR c IN
    SELECT n.nspname::text AS sch, cl.relname::text AS tbl, a.attname::text AS col
      FROM pg_attribute a
      JOIN pg_class     cl ON cl.oid = a.attrelid
      JOIN pg_namespace n  ON n.oid = cl.relnamespace
     WHERE a.atttypid = 'uuid'::regtype
       AND a.attnum > 0 AND NOT a.attisdropped
       AND cl.relkind IN ('r', 'p')
       AND n.nspname IN ('public', 'storage')
  LOOP
    EXECUTE format('SELECT count(*) FROM %I.%I WHERE %I = $1', c.sch, c.tbl, c.col)
      INTO v_cnt USING p.remove_id;
    IF v_cnt > 0 THEN
      v_left := v_left || format('%s.%s.%s=%s ', c.sch, c.tbl, c.col, v_cnt);
    END IF;
  END LOOP;
  IF v_left <> '' THEN
    RAISE EXCEPTION '%: REMOVE uid hamon havola qilinmoqda → % — to''xtatildi (hech narsa saqlanmadi)', p.label, v_left;
  END IF;

  -- 7b) Kutilgan vazifa soni
  SELECT count(*) INTO v_cnt FROM public.tasks WHERE assigned_to = p.keep_id;
  IF v_cnt <> p.expect_tasks THEN
    IF v_strict THEN
      RAISE EXCEPTION '%: KEEP ga biriktirilgan vazifa soni % (kutilgan %) — to''xtatildi. Diagnostikadan keyin ma''lumot o''zgargan bo''lishi mumkin; sonni tekshirib, faylda kutilgan qiymatni yangilang.',
        p.label, v_cnt, p.expect_tasks;
    ELSE
      RAISE WARNING '%: KEEP vazifa soni % (kutilgan %)', p.label, v_cnt, p.expect_tasks;
    END IF;
  ELSE
    RAISE NOTICE '  ✅ %: KEEP ga biriktirilgan vazifa = % (kutilganidek)', p.label, v_cnt;
  END IF;

  -- 7c) Rasm — SQL ko'chira olmaydi
  IF to_regclass('storage.objects') IS NOT NULL THEN
    SELECT count(*) INTO v_cnt FROM storage.objects o WHERE o.name LIKE '%' || p.remove_id::text || '%';
    IF v_cnt > 0 THEN
      RAISE WARNING '  📷 %: Storage''da REMOVE uid li % ta fayl bor ({ws}/{uid}.jpg). SQL ularni ko''chira olmaydi — Storage API (move) kerak. employee_details.photo_path o''sha yo''lni ko''rsatib turadi, rasm KO''RINADI, lekin 41-migratsiya policy''si yo''ldan uid o''qigani uchun xodimning O''ZI ko''ra olmasligi mumkin (manager ko''radi).',
        p.label, v_cnt;
    END IF;
  END IF;

  RAISE NOTICE '  ✅ % — birlashtirildi', p.label;
END LOOP;

RAISE NOTICE E'════════ XULOSA ════════%', coalesce(nullif(v_report, ''), E'\n  (ko''chiriladigan narsa topilmadi — idempotent qayta ishga tushirish)');
END
$merge$;

COMMIT;

-- ============================================================================
-- RUN'DAN KEYIN — nazorat so'rovlari (faqat o'qish, ixtiyoriy)
-- ============================================================================
-- SELECT id, full_name, email, phone FROM public.profiles
--  WHERE id IN ('d7d8f5f3-821c-4c45-896b-e0e6a2de8c42',
--               '840a22ea-4315-4eeb-8efa-15b45561a27b');
--
-- SELECT assigned_to, count(*) FROM public.tasks
--  WHERE assigned_to IN ('d7d8f5f3-821c-4c45-896b-e0e6a2de8c42',
--                        '840a22ea-4315-4eeb-8efa-15b45561a27b')
--  GROUP BY 1;   -- kutilgan: 6 va 12
--
-- Dublikat qoldimi: TASKFIX_MERGE_DIAG.sql ni qayta ishga tushiring —
-- A-bo'limi bo'sh bo'lishi kerak.
--
-- ============================================================================
-- XATO CHIQSA
-- ============================================================================
--   Har qanday xato = BUTUN TRANZAKSIYA QAYTDI, bazada hech narsa o'zgarmadi.
--   Xato matnini menga yuboring:
--     "KEEP ga biriktirilgan vazifa soni X (kutilgan Y)"
--         → diagnostikadan keyin kimdir vazifani qayta biriktirgan.
--           Sonni tekshirib, VALUES ro'yxatidagi kutilgan qiymatni yangilang.
--     "REMOVE uid hamon havola qilinmoqda → ..."
--         → ko'rsatilgan jadval UNIQUE to'qnashuv tufayli ko'chmagan.
--           Matnni menga bering — o'sha jadval uchun alohida qoida yozamiz.
--     "23505 duplicate key ..."
--         → ifodali/shartli unique indeks. Xabardagi indeks nomini bering.
-- ============================================================================
