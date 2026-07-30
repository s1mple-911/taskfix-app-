-- ============================================================================
-- TASKFIX_STRESS_SMOKE.sql — 10 QATORLI SINOV (avval SHUNI ishga tushiring)
-- ============================================================================
-- Maqsad: TASKFIX_STRESS_VOLUME.sql dagi INSERT'ning AYNAN o'zini 10 qator
-- bilan sinab ko'rish. Sintaksis va TIP xatolari (bigint/integer, interval,
-- massiv indeksi) shu yerda 2 soniyada chiqadi — 50k qator kutmasdan.
--
-- ⚠️ IZ QOLDIRMAYDI: 10 qator ko'rsatiladi va O'SHA ZAHOTI o'chiriladi.
--    Test workspace ham (agar shu skript yaratgan bo'lsa) o'chiriladi.
--    Prod workspace'larga TEGILMAYDI (uuid qattiq yozilgan + qora ro'yxat).
--
-- Natija: 10 qatorlik jadval. Chiqsa — VOLUME fayli ham ishlaydi.
-- ============================================================================

DROP TABLE IF EXISTS pg_temp.smoke_sample;
CREATE TEMP TABLE pg_temp.smoke_sample (
  id_txt text, title text, description text, status text,
  priority_level int, assigned_to uuid, deadline timestamptz, created_at timestamptz
);

DO $smoke$
DECLARE
  v_ws         CONSTANT uuid := 'a57e5511-0000-4d00-9000-000057e55001';
  v_ws_name    CONSTANT text := 'ZZZ STRESS TEST — o''chirish uchun';
  v_blacklist  CONSTANT uuid[] := ARRAY['12b22aa6-dc45-4197-ae84-2e32e3cd56c2'::uuid];  -- Aros prod
  v_owner      uuid;
  v_ws_created boolean := false;
  v_had        bigint;
  v_n          bigint;
BEGIN
  -- ── Himoya ──
  IF v_ws = ANY (v_blacklist) THEN
    RAISE EXCEPTION 'TO''XTATILDI: nishon ws qora ro''yxatda (prod!)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.workspaces WHERE id = v_ws AND name <> v_ws_name) THEN
    RAISE EXCEPTION 'TO''XTATILDI: % ws bor va nomi test belgisiga mos emas — hech narsa qilinmadi.', v_ws;
  END IF;

  SELECT id INTO v_owner FROM auth.users ORDER BY created_at LIMIT 1;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'auth.users bo''sh'; END IF;

  -- ── Test ws (kerak bo'lsa) ──
  IF NOT EXISTS (SELECT 1 FROM public.workspaces WHERE id = v_ws) THEN
    INSERT INTO public.workspaces (id, kind, name, owner_id)
    VALUES (v_ws, 'organization', v_ws_name, v_owner);
    v_ws_created := true;
  END IF;
  SELECT count(*) INTO v_had FROM public.tasks WHERE workspace_id = v_ws;

  -- ══════════ SINOV: VOLUME faylidagi INSERT'ning AYNAN o'zi ══════════
  INSERT INTO public.tasks (workspace_id, title, description, status, priority_level,
                            created_by, assigned_to, deadline, created_at)
  SELECT
    v_ws,
    'Stress test vazifa #' || g::text || ' ' || substr(md5(g::text), 1, 8),
    'Avtomatik hosil qilingan test ma''lumot ' || substr(md5((g * 7)::text), 1, 24),
    CASE (g % 4)::int
      WHEN 0 THEN 'new'
      WHEN 1 THEN 'in_progress'
      WHEN 2 THEN 'completed'
      ELSE 'qabul_kutilyapti'
    END,
    (g % 11)::int,
    v_owner,
    CASE WHEN (g % 3)::int = 0 THEN v_owner ELSE NULL END,
    now() + make_interval(days => ((g % 120) - 60)::int),
    now() - make_interval(days => (g % 365)::int)
  FROM generate_series(1::bigint, 10::bigint) AS s(g);

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE '✓ INSERT ishladi — % qator', v_n;

  -- Ko'rish uchun nusxa (o'chirishdan oldin)
  INSERT INTO pg_temp.smoke_sample
  SELECT t.id::text, t.title, t.description, t.status, t.priority_level,
         t.assigned_to, t.deadline, t.created_at
    FROM public.tasks t
   WHERE t.workspace_id = v_ws
   ORDER BY t.created_at DESC
   LIMIT 10;

  -- ── Tozalash: shu skript qo'shgan qatorlarni o'chiramiz ──
  DELETE FROM public.tasks
   WHERE workspace_id = v_ws
     AND title LIKE 'Stress test vazifa #%';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE '✓ tozalandi — % qator o''chirildi', v_n;

  -- Ws'ni faqat SHU skript yaratgan va bo'sh bo'lsa o'chiramiz
  IF v_ws_created AND v_had = 0
     AND NOT EXISTS (SELECT 1 FROM public.tasks WHERE workspace_id = v_ws) THEN
    DELETE FROM public.workspace_members WHERE workspace_id = v_ws;
    DELETE FROM public.workspaces WHERE id = v_ws;
    RAISE NOTICE '✓ test workspace o''chirildi (iz qolmadi)';
  END IF;

  -- Tekshiruv — jimgina o'tmasin
  IF EXISTS (SELECT 1 FROM public.tasks WHERE workspace_id = v_ws AND title LIKE 'Stress test vazifa #%') THEN
    RAISE EXCEPTION 'Tozalash to''liq bo''lmadi — qo''lda tekshiring';
  END IF;

  RAISE NOTICE '════ SMOKE OK — endi TASKFIX_STRESS_VOLUME.sql ni ishga tushirsangiz bo''ladi ════';
END
$smoke$;

-- 10 qator: ma'lumot ko'rinishi to'g'rimi (holatlar, prioritet, deadline)
SELECT * FROM pg_temp.smoke_sample ORDER BY created_at DESC;

-- ============================================================================
-- Xato chiqsa — matnini menga yuboring. Kutilgan xatolar va ma'nosi:
--   "function repeat(unknown, bigint) does not exist"  → tip xatosi (tuzatilgan)
--   "array subscript must have type integer"           → tip xatosi (tuzatilgan)
--   "operator does not exist: bigint * interval"       → tip xatosi (tuzatilgan)
--   "new row violates check constraint ...status..."   → tasks.status CHECK
--        ilova yozadigan qiymatlarni qabul qilmayapti — menga ayting
--   "null value in column ... violates not-null"       → tasks da men bilmagan
--        MAJBURIY ustun bor — xato matnidagi ustun nomini menga ayting
-- ============================================================================
