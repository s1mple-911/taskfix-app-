-- ============================================================================
-- TASKFIX_SCALE.sql — 2-bosqich (INDEKS) + 3-bosqich (RLS)
-- ============================================================================
-- Stress-test o'lchoviga asoslangan (50 000 vazifa):
--   Ro'yxat LIMITsiz : 176ms raw → 855ms RLS · SEQ SCAN
--   Ro'yxat LIMIT100 : 218ms raw → 836ms RLS · SEQ SCAN
--   Holat / Kalendar : SEQ SCAN
--   Hisobot          : 22ms raw → 809ms RLS  (≈36×)
--
-- ⚠️ HAMMASI BITTA TRANZAKSIYADA. PostgreSQL'da DDL ham tranzaksion:
--    tekshiruvlardan birortasi yiqilsa — indekslar ham, policy o'zgarishlari
--    ham ORQAGA QAYTADI. Bazada yarim holat qolmaydi.
--
-- ⚠️ XAVFSIZLIK — eng nozik qism. Skript policy matnini o'zgartiradi,
--    shuning uchun:
--      1) O'zgarishdan OLDIN har foydalanuvchi HAR jadvalda nechta qator
--         ko'rishi sanab olinadi (RLS bilan, authenticated roli ostida)
--      2) O'zgarishdan KEYIN xuddi shu sanoq qaytariladi
--      3) Bitta raqam farq qilsa → RAISE EXCEPTION → hamma narsa qaytadi
--    Ya'ni "tezlashdi-yu ko'rinish o'zgardi" holati MUMKIN EMAS.
--
-- ⚠️ Policy'larning ASL matni public.taskfix_rls_backup jadvaliga saqlanadi.
--    Qaytarish kerak bo'lsa: TASKFIX_SCALE_ROLLBACK.sql
--
-- NIMA QILADI (semantikani O'ZGARTIRMAYDI):
--   • Indeks: (workspace_id, created_at DESC), (workspace_id, status),
--     (workspace_id, deadline) + workspace_members(user_id, workspace_id)
--   • RLS: policy ichidagi `auth.uid()` → `(SELECT auth.uid())`.
--     Bu Supabase'ning rasmiy tavsiyasi: auth.uid() STABLE, lekin policy
--     ifodasida u HAR QATOR uchun qayta chaqiriladi. Skalyar subquery'ga
--     o'ralganda planner uni InitPlan qiladi — BIR MARTA hisoblanadi.
--     Mantiq bir xil qoladi, faqat necha marta hisoblanishi o'zgaradi.
--
-- NATIJA: oxirgi SELECT — before/after jadval.
-- ============================================================================

-- ── Natija/tekshiruv jadvallari (sessiyaga tegishli) ───────────────────────
DROP TABLE IF EXISTS pg_temp.scale_res;
CREATE TEMP TABLE pg_temp.scale_res (
  bosqich text, nom text, oldin text, keyin text, izoh text, ord int
);
DROP TABLE IF EXISTS pg_temp.rls_snap;
CREATE TEMP TABLE pg_temp.rls_snap (
  faza text, tbl text, uid uuid, n bigint
);

BEGIN;

-- ⚠️ Supabase SQL Editor skriptni allaqachon tranzaksiyada bajaradi, shuning
--    uchun bu BEGIN "there is already a transaction in progress" OGOHLANTIRISHI
--    berishi mumkin — bu zararsiz. BEGIN/COMMIT ataylab qoldirilgan: editor
--    o'ramasa ham atomiklik kafolatlansin.

-- Policy matni pg_policies dan O'QILIB, qayta ALTER POLICY ga BERILADI.
-- Aynan bir xil qayta talqin qilinishi uchun search_path ni qat'iy belgilaymiz.
SET LOCAL search_path = public, extensions;

DO $scale$
DECLARE
  -- ══════════ SOZLAMALAR ══════════
  -- RLS optimallashtiriladigan jadvallar (o'lchovda qatnashganlari + ular bilan
  -- birga o'qiladiganlar). Kengaytirish mumkin, lekin har qo'shilgan jadval
  -- xavfsizlik tekshiruviga ham qo'shiladi (sekinroq, lekin xavfsizroq).
  v_tables   CONSTANT text[] := ARRAY['tasks','task_comments','task_subtasks',
                                      'task_attachments','projects','project_members'];
  v_max_users CONSTANT int := 15;   -- xavfsizlik tekshiruvi uchun namuna foydalanuvchi soni
  -- Yakka ustunli indekslar (status/deadline). SUKUT BO'YICHA O'CHIQ —
  -- pastdagi izohda sabab.
  v_add_singles CONSTANT boolean := false;

  r          RECORD;
  u          RECORD;
  v_ws       uuid;
  v_cnt      bigint;
  v_sql      text;
  v_new_q    text;
  v_new_c    text;
  v_changed  int := 0;
  v_ord      int := 0;
  v_json     jsonb;
  v_raw      numeric;
  v_rls      numeric;
  v_diff     text;
BEGIN

-- ══════════════════════════════════════════════════════════════════════════
-- 0) O'LCHOV UCHUN WORKSPACE — eng ko'p vazifasi borini olamiz
-- ══════════════════════════════════════════════════════════════════════════
SELECT workspace_id INTO v_ws
  FROM public.tasks GROUP BY workspace_id ORDER BY count(*) DESC LIMIT 1;
IF v_ws IS NULL THEN
  RAISE EXCEPTION 'public.tasks bo''sh — o''lchash uchun ma''lumot yo''q';
END IF;
SELECT count(*) INTO v_cnt FROM public.tasks WHERE workspace_id = v_ws;
RAISE NOTICE 'O''lchov workspace: %  (% ta vazifa)', v_ws, v_cnt;
IF v_cnt < 5000 THEN
  RAISE WARNING 'Bu ws da atigi % ta vazifa bor. Shuncha ma''lumotda SEQ SCAN — TO''G''RI tanlov (indeks o''qishdan arzon). Indeks foydasini ko''rish uchun TASKFIX_STRESS_VOLUME.sql bilan 50k qator hosil qiling.', v_cnt;
END IF;

-- ══════════════════════════════════════════════════════════════════════════
-- 1) OLDIN: o'lchov (EXPLAIN ANALYZE, raw + RLS)
-- ══════════════════════════════════════════════════════════════════════════
CREATE TEMP TABLE IF NOT EXISTS pg_temp._q (nom text, sql text, ord int);
DELETE FROM pg_temp._q;
INSERT INTO pg_temp._q VALUES
 ('royxat_limitsiz', format('SELECT * FROM public.tasks WHERE workspace_id = %L ORDER BY created_at DESC', v_ws), 1),
 ('royxat_limit100', format('SELECT * FROM public.tasks WHERE workspace_id = %L ORDER BY created_at DESC LIMIT 100', v_ws), 2),
 ('holat',           format('SELECT * FROM public.tasks WHERE workspace_id = %L AND status = ''new''', v_ws), 3),
 ('kalendar',        format('SELECT * FROM public.tasks WHERE workspace_id = %L AND deadline >= now() - interval ''15 days'' AND deadline < now() + interval ''15 days''', v_ws), 4),
 ('hisobot',         format('SELECT status, count(*) FROM public.tasks WHERE workspace_id = %L GROUP BY status', v_ws), 5);

FOR r IN SELECT * FROM pg_temp._q ORDER BY ord LOOP
  EXECUTE 'EXPLAIN (ANALYZE, FORMAT JSON) ' || r.sql INTO v_json;
  v_raw := (v_json -> 0 ->> 'Execution Time')::numeric;
  v_rls := NULL;
  BEGIN
    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', (SELECT id::text FROM auth.users ORDER BY created_at LIMIT 1),
                               'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE 'EXPLAIN (ANALYZE, FORMAT JSON) ' || r.sql INTO v_json;
    v_rls := (v_json -> 0 ->> 'Execution Time')::numeric;
    EXECUTE 'RESET ROLE';
  EXCEPTION WHEN OTHERS THEN
    BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
  END;
  v_ord := v_ord + 1;
  INSERT INTO pg_temp.scale_res VALUES ('o''lchov', r.nom,
    round(v_raw,1)::text || ' / ' || coalesce(round(v_rls,1)::text,'—'), NULL,
    'raw / rls (ms)', v_ord);
END LOOP;

-- ══════════════════════════════════════════════════════════════════════════
-- 2) XAVFSIZLIK SNAPSHOT — kim nimani ko'radi (O'ZGARISHDAN OLDIN)
-- ══════════════════════════════════════════════════════════════════════════
FOR u IN
  SELECT DISTINCT wm.user_id AS id FROM public.workspace_members wm
   ORDER BY wm.user_id LIMIT v_max_users
LOOP
  FOREACH v_sql IN ARRAY v_tables LOOP
    CONTINUE WHEN to_regclass('public.' || v_sql) IS NULL;
    BEGIN
      PERFORM set_config('request.jwt.claims',
               json_build_object('sub', u.id::text, 'role', 'authenticated')::text, true);
      EXECUTE 'SET LOCAL ROLE authenticated';
      EXECUTE format('SELECT count(*) FROM public.%I', v_sql) INTO v_cnt;
      EXECUTE 'RESET ROLE';
      INSERT INTO pg_temp.rls_snap VALUES ('oldin', v_sql, u.id, v_cnt);
    EXCEPTION WHEN OTHERS THEN
      BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
      INSERT INTO pg_temp.rls_snap VALUES ('oldin', v_sql, u.id, -1);   -- xato = -1
    END;
  END LOOP;
END LOOP;
SELECT count(*) INTO v_cnt FROM pg_temp.rls_snap WHERE faza = 'oldin';
RAISE NOTICE 'Xavfsizlik snapshot: % ta (foydalanuvchi × jadval) sanoq olindi', v_cnt;

-- ══════════════════════════════════════════════════════════════════════════
-- 3) INDEKSLAR
-- ══════════════════════════════════════════════════════════════════════════
-- ⚠️ NEGA KOMPOZIT, YAKKA EMAS:
--    Brief'da `tasks(status)` va `tasks(deadline)` yakka indekslari ham bor edi.
--    Lekin o'lchovdagi so'rovlar HAR DOIM workspace_id bilan birga keladi:
--        WHERE workspace_id = X AND status = 'new'
--        WHERE workspace_id = X AND deadline BETWEEN ...
--    Bunday holatda (workspace_id, status) kompoziti yakka (status) dan
--    QAT'IYAN yaxshiroq: yakka status indeksi 4 xil qiymatga ega (juda past
--    selektivlik) va planner uni deyarli hech qachon tanlamaydi.
--    Brief'ning o'z qoidasi: "Ortiqcha indeks qo'shma — har indeks yozishni
--    sekinlashtiradi". Shuning uchun yakkalari SUKUT BO'YICHA QO'SHILMAYDI.
--    Kerak deb hisoblasangiz: yuqorida v_add_singles := true qiling.
-- ⚠️ id ham indeksda: frontend sahifalashi ORDER BY created_at DESC, id DESC
--    bilan ishlaydi (created_at teng bo'lsa sahifalar aralashmasligi uchun).
--    id bo'lmasa planner indeksdan keyin qo'shimcha sort qilardi.
CREATE INDEX IF NOT EXISTS idx_tasks_ws_created  ON public.tasks (workspace_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_tasks_ws_status   ON public.tasks (workspace_id, status);
CREATE INDEX IF NOT EXISTS idx_tasks_ws_deadline ON public.tasks (workspace_id, deadline);

IF v_add_singles THEN
  CREATE INDEX IF NOT EXISTS idx_tasks_status   ON public.tasks (status);
  CREATE INDEX IF NOT EXISTS idx_tasks_deadline ON public.tasks (deadline);
  RAISE NOTICE 'Yakka indekslar ham qo''shildi (v_add_singles = true)';
END IF;

-- RLS subquery'si uchun: workspace_id IN (SELECT ... WHERE user_id = auth.uid())
CREATE INDEX IF NOT EXISTS idx_ws_members_user_ws ON public.workspace_members (user_id, workspace_id);

INSERT INTO pg_temp.scale_res VALUES ('indeks', 'qo''shildi', NULL,
  'idx_tasks_ws_created, idx_tasks_ws_status, idx_tasks_ws_deadline, idx_ws_members_user_ws',
  CASE WHEN v_add_singles THEN '+ yakka status/deadline' ELSE 'yakka status/deadline QO''SHILMADI (kompozit yetarli)' END, 100);

-- ══════════════════════════════════════════════════════════════════════════
-- 4) RLS: auth.uid() → (SELECT auth.uid())
-- ══════════════════════════════════════════════════════════════════════════
-- Asl matnni saqlaymiz (qaytarish uchun)
CREATE TABLE IF NOT EXISTS public.taskfix_rls_backup (
  id          bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  saqlangan   timestamptz NOT NULL DEFAULT now(),
  schemaname  text, tablename text, policyname text,
  cmd         text, roles text, permissive text,
  qual        text, with_check text
);
COMMENT ON TABLE public.taskfix_rls_backup IS
  'TASKFIX_SCALE.sql o''zgartirishidan OLDINGI RLS policy matnlari. Qaytarish: TASKFIX_SCALE_ROLLBACK.sql';

FOR r IN
  SELECT p.schemaname, p.tablename, p.policyname, p.cmd, p.permissive,
         array_to_string(p.roles, ',') AS roles, p.qual, p.with_check
    FROM pg_policies p
   WHERE p.schemaname = 'public'
     AND p.tablename = ANY (v_tables)
     AND (coalesce(p.qual,'') ~ 'auth\.(uid|jwt|role)\(\)'
       OR coalesce(p.with_check,'') ~ 'auth\.(uid|jwt|role)\(\)')
LOOP
  -- auth.uid() dan tashqari auth.jwt() / auth.role() ham xuddi shu muammoga ega
  -- (har qator uchun qayta chaqiriladi) va o'rash ular uchun ham xavfsiz.
  -- 1-qadam: ALLAQACHON o'ralganlarini vaqtincha belgilab qo'yamiz (ikki
  --          marta o'ralib "((SELECT (SELECT auth.uid())))" bo'lib qolmasin)
  -- 2-qadam: qolgan yalang'och chaqiruvlarni o'raymiz
  -- 3-qadam: belgini qaytaramiz
  v_new_q := r.qual;
  v_new_c := r.with_check;
  IF v_new_q IS NOT NULL THEN
    v_new_q := regexp_replace(v_new_q, '\(\s*SELECT\s+auth\.(uid|jwt|role)\(\)\s*\)', '@@W:\1@@', 'gi');
    v_new_q := regexp_replace(v_new_q, 'auth\.(uid|jwt|role)\(\)', '(SELECT auth.\1())', 'gi');
    v_new_q := regexp_replace(v_new_q, '@@W:(uid|jwt|role)@@', '(SELECT auth.\1())', 'g');
  END IF;
  IF v_new_c IS NOT NULL THEN
    v_new_c := regexp_replace(v_new_c, '\(\s*SELECT\s+auth\.(uid|jwt|role)\(\)\s*\)', '@@W:\1@@', 'gi');
    v_new_c := regexp_replace(v_new_c, 'auth\.(uid|jwt|role)\(\)', '(SELECT auth.\1())', 'gi');
    v_new_c := regexp_replace(v_new_c, '@@W:(uid|jwt|role)@@', '(SELECT auth.\1())', 'g');
  END IF;

  CONTINUE WHEN v_new_q IS NOT DISTINCT FROM r.qual
            AND v_new_c IS NOT DISTINCT FROM r.with_check;

  INSERT INTO public.taskfix_rls_backup (schemaname, tablename, policyname, cmd, roles, permissive, qual, with_check)
  VALUES (r.schemaname, r.tablename, r.policyname, r.cmd, r.roles, r.permissive, r.qual, r.with_check);

  v_sql := format('ALTER POLICY %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
  IF v_new_q IS NOT NULL THEN v_sql := v_sql || format(' USING (%s)', v_new_q); END IF;
  IF v_new_c IS NOT NULL THEN v_sql := v_sql || format(' WITH CHECK (%s)', v_new_c); END IF;
  EXECUTE v_sql;

  v_changed := v_changed + 1;
  RAISE NOTICE '  ✎ %.% : % policy''si optimallashtirildi', r.tablename, r.policyname, r.cmd;
END LOOP;

RAISE NOTICE 'RLS: % ta policy o''zgartirildi', v_changed;
INSERT INTO pg_temp.scale_res VALUES ('rls', 'o''zgartirilgan policy', NULL, v_changed::text,
  'auth.uid() → (SELECT auth.uid())', 200);

-- ══════════════════════════════════════════════════════════════════════════
-- 5) XAVFSIZLIK TEKSHIRUVI — ko'rinish O'ZGARMAGANIGA ishonch
-- ══════════════════════════════════════════════════════════════════════════
FOR u IN SELECT DISTINCT uid AS id FROM pg_temp.rls_snap WHERE faza = 'oldin' LOOP
  FOREACH v_sql IN ARRAY v_tables LOOP
    CONTINUE WHEN to_regclass('public.' || v_sql) IS NULL;
    BEGIN
      PERFORM set_config('request.jwt.claims',
               json_build_object('sub', u.id::text, 'role', 'authenticated')::text, true);
      EXECUTE 'SET LOCAL ROLE authenticated';
      EXECUTE format('SELECT count(*) FROM public.%I', v_sql) INTO v_cnt;
      EXECUTE 'RESET ROLE';
      INSERT INTO pg_temp.rls_snap VALUES ('keyin', v_sql, u.id, v_cnt);
    EXCEPTION WHEN OTHERS THEN
      BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
      INSERT INTO pg_temp.rls_snap VALUES ('keyin', v_sql, u.id, -1);
    END;
  END LOOP;
END LOOP;

SELECT string_agg(format('%s/%s: %s→%s', a.tbl, a.uid, a.n, b.n), ' | ')
  INTO v_diff
  FROM pg_temp.rls_snap a
  JOIN pg_temp.rls_snap b ON b.faza='keyin' AND b.tbl=a.tbl AND b.uid=a.uid
 WHERE a.faza='oldin' AND a.n IS DISTINCT FROM b.n;

IF v_diff IS NOT NULL THEN
  RAISE EXCEPTION 'XAVFSIZLIK BUZILDI: RLS o''zgarishidan keyin ko''rinadigan qatorlar soni FARQ QILDI → %  — HAMMASI ORQAGA QAYTARILDI', v_diff;
END IF;

SELECT count(*) INTO v_cnt FROM pg_temp.rls_snap WHERE faza='keyin';
RAISE NOTICE '✅ Xavfsizlik: % ta sanoq bir xil qoldi — ko''rinish o''zgarmadi', v_cnt;
INSERT INTO pg_temp.scale_res VALUES ('xavfsizlik', 'ko''rinadigan qator sanog''i',
  'bir xil', 'bir xil', v_cnt::text || ' ta (foydalanuvchi × jadval) tekshirildi', 300);

-- ══════════════════════════════════════════════════════════════════════════
-- 6) KEYIN: qayta o'lchov
-- ══════════════════════════════════════════════════════════════════════════
FOR r IN SELECT * FROM pg_temp._q ORDER BY ord LOOP
  EXECUTE 'EXPLAIN (ANALYZE, FORMAT JSON) ' || r.sql INTO v_json;
  v_raw := (v_json -> 0 ->> 'Execution Time')::numeric;
  v_rls := NULL;
  BEGIN
    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', (SELECT id::text FROM auth.users ORDER BY created_at LIMIT 1),
                               'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE 'EXPLAIN (ANALYZE, FORMAT JSON) ' || r.sql INTO v_json;
    v_rls := (v_json -> 0 ->> 'Execution Time')::numeric;
    EXECUTE 'RESET ROLE';
  EXCEPTION WHEN OTHERS THEN
    BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
  END;
  UPDATE pg_temp.scale_res
     SET keyin = round(v_raw,1)::text || ' / ' || coalesce(round(v_rls,1)::text,'—'),
         izoh  = izoh || CASE WHEN v_json::text LIKE '%Seq Scan%' THEN ' · ⚠️ hamon SEQ SCAN' ELSE ' · ✓ Index Scan' END
   WHERE bosqich = 'o''lchov' AND nom = r.nom;
END LOOP;

RAISE NOTICE '════ TUGADI — pastdagi jadvalga qarang ════';
END
$scale$;

COMMIT;

-- ══════════ NATIJA ══════════
SELECT bosqich, nom, oldin, keyin, izoh FROM pg_temp.scale_res ORDER BY ord;

-- ============================================================================
-- QANDAY O'QISH
-- ============================================================================
-- o'lchov qatorlari: "raw / rls (ms)" — oldin va keyin.
--   • rls sezilarli kamaysa → auth.uid() o'rash ishladi
--   • "✓ Index Scan" → indeks ishlatilyapti
--   • "⚠️ hamon SEQ SCAN" → jadval KICHIK bo'lsa bu NORMAL: 400 qatorda
--     Postgres seq scan'ni ataylab tanlaydi (indeksdan arzon). Katta jadvalda
--     ham SEQ SCAN qolsa — menga ko'rsating, sabab boshqa (masalan RLS ifodasi
--     indeksni to'sadi yoki statistika eskirgan → ANALYZE public.tasks).
--
-- xavfsizlik qatori: "bir xil" bo'lishi SHART. Aks holda skript
--   RAISE EXCEPTION bilan to'xtagan va HECH NARSA o'zgarmagan bo'lardi.
--
-- Qaytarish kerak bo'lsa: TASKFIX_SCALE_ROLLBACK.sql
-- ============================================================================
