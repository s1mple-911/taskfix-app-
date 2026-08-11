-- ============================================================================
-- TASKFIX_LOYIHA_RLS.sql — "Bosqichi menga biriktirilgan loyihani KO'RAMAN"
-- (BRIEF_TASKFIX_LOYIHA.md 3-band)
-- ============================================================================
-- Asilbek RUN qiladi (Supabase SQL Editor, postgres roli).
-- ADDITIVE + IDEMPOTENT: mavjud policy'lar O'CHIRILMAYDI, O'ZGARTIRILMAYDI.
-- Faqat YANGI (permissive) policy qo'shiladi — PostgreSQL bir jadvaldagi bir
-- necha PERMISSIVE policy'ni OR bilan birlashtiradi, ya'ni mavjud kirish
-- huquqi HECH QACHON torayib qolmaydi.
--
-- MUAMMO: loyiha ichidagi bosqich (task) menga biriktirilgan, lekin loyihaning
--         o'zini ko'ra olmayman (projects SELECT policy'si odatda faqat
--         is_ws_manager / project_members ga ochiq) → "Loyiha topilmadi yoki
--         ruxsat yo'q".
--
-- YECHIM (3 policy + 1 funksiya):
--   1) public.can_see_project(project, user) — SECURITY DEFINER yordamchi.
--      ⚠️ Tanasida `p_user = (SELECT auth.uid())` sharti BOR — funksiya
--         PostgREST orqali (`/rpc/can_see_project`) ham chaqirilishi mumkin,
--         bu shartsiz u boshqa odam haqida ma'lumot bergan bo'lardi.
--   2) projects_select_assignee              — loyihani ko'rish
--   3) tasks_select_project_member           — o'sha loyihaning BOSHQA bosqichlari
--   4) project_members_select_project_view   — "A'zolar" tabi bo'sh qolmasin
--      ⚠️ 3 va 4 FAQAT KERAK BO'LSA qo'shiladi (skript o'zi o'lchab qaror qiladi;
--         mavjud policy allaqachon barcha ws a'zolariga ochiq bo'lsa
--         ortiqcha policy = ortiqcha yuk → qo'shilmaydi, NOTICE yoziladi).
--      ⚠️ 4-si `project_members.workspace_id` ustuni BO'LSAGINA qo'shiladi —
--         busiz policy `projects` ga subquery talab qilardi va mavjud projects
--         policy'si project_members'ga qarasa 42P17 rekursiya chiqardi.
--
-- 🔴 REKURSIYA XAVFI VA UNING YECHIMI
--   can_see_project() `tasks` ni o'qiydi. Agar u ODDIY (SECURITY INVOKER)
--   funksiya bo'lsa va `tasks` RLS'i o'z navbatida `projects` ga qarasa →
--   projects policy → tasks RLS → projects policy → ... = 42P17
--   ("infinite recursion detected in policy for relation ...").
--   Shuning uchun funksiya SECURITY DEFINER: u egasi (postgres) huquqi bilan
--   ishlaydi va `tasks` RLS'ini CHETLAB O'TADI → zanjir uzilади, rekursiya yo'q.
--   ⚠️ Bu faraz emas — pastdagi tekshiruv bloki har namunaviy foydalanuvchi
--      uchun `authenticated` roli ostida HAQIQIY so'rov yuboradi; 42P17 chiqsa
--      skript RAISE EXCEPTION bilan to'xtaydi va hamma narsa qaytadi.
--   ⚠️ Shu sababli policy ichida `workspace_members` inline subquery YO'Q
--      (CLAUDE.md 8-qoida) — faqat is_ws_member() ishlatiladi.
--
-- 🔴 XAVFSIZLIK TEKSHIRUVI (TASKFIX_SCALE.sql naqshi)
--   O'zgarishdan OLDIN va KEYIN har namunaviy foydalanuvchi uchun
--   `authenticated` roli ostida ko'rinadigan qatorlar sanaladi (projects,
--   tasks, project_members, task_comments). KEYINGI son KUTILGAN songa AYNAN
--   teng bo'lishi shart:
--       kutilgan_projects = oldin_jami - oldin_AP + AP_hajmi
--       kutilgan_tasks    = oldin_jami - oldin_AP + AP_dagi_jami_vazifa
--       kutilgan_a'zolar  = oldin_jami - oldin_AP + AP_dagi_jami_a'zo
--   (AP = "assignee loyihalari" — foydalanuvchi a'zo bo'lgan ws dagi, unga
--    bosqich biriktirilgan loyihalar to'plami.)
--   Bitta raqam farq qilsa (ko'paysa ham, kamaysa ham) → RAISE EXCEPTION →
--   BUTUN tranzaksiya qaytadi. "Nazorat" foydalanuvchilari (hech bir loyihada
--   bajaruvchi BO'LMAGAN ws a'zolari) uchun esa HECH BIR jadvalda bitta ham
--   qator qo'shilmasligi kerak.
--   ⚠️ "Nazorat" ro'yxati `public.tasks` dagi HAQIQIY bajaruvchilar to'plamiga
--      qarab tuziladi (kesilgan namunaga emas) — aks holda 15 dan ortiq
--      bajaruvchi bo'lganda ular xato "nazorat" deb belgilanib, skript SOXTA
--      "XAVFSIZLIK BUZILDI" bilan yiqilardi.
--
-- 🔴 QACHON RUN QILINADI — KAM TRAFIK VAQTIDA (kechqurun/dam olish kuni)
--   `CREATE POLICY` `projects` / `tasks` / `project_members` ga
--   **ACCESS EXCLUSIVE** qulf oladi va u COMMIT gacha ushlab turiladi; tekshiruv
--   esa har namunaviy foydalanuvchi uchun to'liq skan qiladi (25 foydalanuvchi ×
--   4–5 so'rov × 2 faza ≈ 200 skan). Ya'ni skript ishlayotgan bir necha
--   soniya/daqiqa davomida **ILOVA VAZIFA VA LOYIHA O'QIY OLMAYDI** (so'rovlar
--   qulfni kutadi). Bu vaqtinchalik va xavfsiz, lekin ish vaqtida sezilarli.
--   Namuna hajmini kamaytirish kerak bo'lsa: v_max_users / v_max_ctl.
--
-- ROLLBACK: fayl oxirida.
-- ============================================================================

-- ⚠️ TRANZAKSIYA — TARTIB MUHIM, O'ZGARTIRMANG:
--    `BEGIN;` va undan keyingi `SET TRANSACTION ...` skriptdagi ENG BIRINCHI
--    ikki buyruq bo'lishi SHART. `SET TRANSACTION ISOLATION LEVEL` tranzaksiyada
--    birorta so'rov bajarilgunga qadar chaqirilishi kerak (aks holda 25001).
--    Supabase SQL Editor butun skriptni O'ZI bitta tranzaksiyada yuboradi —
--    u yerda `BEGIN;` "there is already a transaction in progress" ogohlantirishi
--    bilan e'tiborsiz qoldiriladi, `SET TRANSACTION` esa baribir ishlaydi
--    (undan oldin hech qanday so'rov yo'q).
BEGIN;
-- 🔴 REPEATABLE READ — busiz "oldin" va "keyin" sanoqlari BOSHQA sessiyaning
--    yozuvi (yangi vazifa/loyiha) sababli farq qilib, xavfsizlik tekshiruvi
--    SOXTA "XAVFSIZLIK BUZILDI" bilan yiqilardi. Bu daraja ma'lumot suratini
--    qotiradi; katalog (policy) o'zgarishlari esa baribir ko'rinadi — shuning
--    uchun yangi policy'lar "keyin" fazasida to'g'ri hisobga olinadi.
-- ⚠️ AGAR "25001: SET TRANSACTION ISOLATION LEVEL must be called before any
--    query" XATOSI CHIQSA — quyidagi qatorni izohga oling (`-- SET TRANSACTION…`)
--    va skriptni QAYTA RUN qiling. Yo'qoladigan yagona narsa — parallel yozuvdan
--    himoya; xavfsizlik tekshiruvining o'zi va policy'lar o'zgarishsiz qoladi.
--    (Bu holatda skript ishlayotganda hech kim vazifa/loyiha qo'shmasin.)
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;


-- ════════════════════════════════════════════════════════════════════════════
-- 0) DIAGNOSTIKA — FAQAT O'QIYDI. Hech narsa o'zgarmaydi.
--    Natijani "Messages"/"Notices" bo'limida o'qing.
-- ════════════════════════════════════════════════════════════════════════════
DO $diag$
DECLARE
  r    RECORD;
  v_t  text;
  v_n  int;
BEGIN
  RAISE NOTICE '════════ DIAGNOSTIKA (o''zgarishdan OLDINGI holat) ════════';

  FOREACH v_t IN ARRAY ARRAY['projects','tasks','project_members'] LOOP
    IF to_regclass('public.' || v_t) IS NULL THEN
      RAISE WARNING 'public.% jadvali YO''Q', v_t;
      CONTINUE;
    END IF;
    SELECT count(*) INTO v_n
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = v_t AND c.relrowsecurity;
    RAISE NOTICE '── public.% : RLS %', v_t,
      CASE WHEN v_n > 0 THEN 'YOQILGAN' ELSE '❗ O''CHIQ' END;
  END LOOP;

  FOR r IN
    SELECT tablename, policyname, cmd, permissive,
           array_to_string(roles, ',') AS roles, qual, with_check
      FROM pg_policies
     WHERE schemaname = 'public' AND tablename IN ('projects','tasks','project_members')
     ORDER BY tablename, cmd, policyname
  LOOP
    RAISE NOTICE '   [%] % (% · % · %)  USING: %  CHECK: %',
      r.tablename, r.policyname, r.cmd, r.permissive, r.roles,
      coalesce(r.qual, '—'), coalesce(r.with_check, '—');
  END LOOP;

  -- 🔴 RESTRICTIVE policy — alohida sanaladi. PERMISSIVE policy'lar OR bilan
  --    qo'shiladi, RESTRICTIVE esa AND bilan QO'LLANADI: bittasi bo'lsa yangi
  --    "assignee" policy'si YETARLI BO'LMASLIGI mumkin (foydalanuvchi baribir
  --    ko'rmaydi) va tekshiruv "policy kutilganday ishlamadi" deb yiqiladi.
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='public' AND tablename IN ('projects','tasks','project_members')
     AND permissive = 'RESTRICTIVE';
  IF v_n > 0 THEN
    RAISE WARNING '⚠️ % ta RESTRICTIVE policy bor (yuqoridagi ro''yxatda "RESTRICTIVE" deb turadi). Ular AND bilan qo''llanadi — yangi PERMISSIVE policy ularni YENGA OLMAYDI. Skript yiqilsa birinchi navbatda shularni tekshiring.', v_n;
  ELSE
    RAISE NOTICE '   RESTRICTIVE policy yo''q — yangi PERMISSIVE policy to''liq kuchga kiradi.';
  END IF;

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname IN ('is_ws_member','is_ws_manager');
  RAISE NOTICE '   is_ws_member/is_ws_manager: % ta funksiya topildi', v_n;
  RAISE NOTICE '════════ DIAGNOSTIKA TUGADI ════════';
END $diag$;


-- ── Natija/tekshiruv jadvallari ────────────────────────────────────────────
--    ⚠️ Bular TRANZAKSIYA ICHIDA yaratiladi: skript yiqilsa ular ham qaytadi va
--       oxiridagi SELECT'lar umuman bajarilmaydi (Supabase Editor butun skriptni
--       bitta tranzaksiyada yuboradi). Xato holatida natijani "Messages"
--       bo'limidagi NOTICE/EXCEPTION matnidan o'qing — u yerda hamma raqam bor.
DROP TABLE IF EXISTS pg_temp.prj_ap;
CREATE TEMP TABLE pg_temp.prj_ap (
  uid    uuid PRIMARY KEY,
  ap     text[] NOT NULL DEFAULT '{}',   -- "assignee loyihalari" (projects.id::text)
  ap_prj int    NOT NULL DEFAULT 0,      -- AP dagi loyiha soni
  ap_tsk bigint NOT NULL DEFAULT 0,      -- AP loyihalaridagi JAMI vazifa (RLS'siz)
  ap_pm  bigint NOT NULL DEFAULT 0,      -- AP loyihalaridagi JAMI project_members qatori
  turi   text   NOT NULL                 -- 'assignee' | 'nazorat'
);
DROP TABLE IF EXISTS pg_temp.prj_snap;
CREATE TEMP TABLE pg_temp.prj_snap (
  faza text, uid uuid,
  n_prj bigint, n_prj_ap bigint,
  n_tsk bigint, n_tsk_ap bigint,
  n_pm  bigint, n_pm_ap  bigint,
  n_cmt bigint
);
DROP TABLE IF EXISTS pg_temp.prj_res;
CREATE TEMP TABLE pg_temp.prj_res (ord int, bosqich text, nom text, qiymat text, izoh text);

SET LOCAL search_path = public, extensions;

DO $main$
DECLARE
  -- ══════════ SOZLAMALAR ══════════
  v_max_users CONSTANT int := 15;   -- namunaga olinadigan assignee soni
  v_max_ctl   CONSTANT int := 10;   -- "nazorat" (AP bo'sh) foydalanuvchi soni

  u            RECORD;
  r            RECORD;
  v_idtype     text;
  v_sig        text;
  v_c_prj      bigint;
  v_c_prj_ap   bigint;
  v_c_tsk      bigint;
  v_c_tsk_ap   bigint;
  v_c_pm       bigint;
  v_c_pm_ap    bigint;
  v_c_cmt      bigint;
  v_n          int;
  v_has_cmt    boolean;
  v_has_pm     boolean;   -- project_members jadvali bor
  v_pm_ws      boolean;   -- project_members da workspace_id ustuni bor (policy uchun SHART)
  v_prj_rls    boolean;
  v_tsk_rls    boolean;
  v_pm_rls     boolean;
  v_prj_sel    int;
  v_tsk_sel    int;
  v_pm_sel     int;
  v_restr      int;
  v_restr_note text := '';
  v_prj_added  boolean := false;
  v_tsk_added  boolean := false;
  v_pm_added   boolean := false;
  v_tsk_need   boolean := false;
  v_pm_need    boolean := false;
  v_tsk_reason text;
  v_pm_reason  text;
  v_qual       text;
  v_exp_prj    bigint;
  v_exp_tsk    bigint;
  v_exp_pm     bigint;
  v_gain_prj   bigint := 0;
  v_gain_tsk   bigint := 0;
BEGIN

-- ══════════════════════════════════════════════════════════════════════════
-- 1) OLD SHARTLAR
-- ══════════════════════════════════════════════════════════════════════════
IF to_regclass('public.projects') IS NULL THEN
  RAISE EXCEPTION 'public.projects jadvali topilmadi — avval loyiha migratsiyasi (34) ishga tushirilishi kerak.';
END IF;
IF to_regclass('public.tasks') IS NULL THEN
  RAISE EXCEPTION 'public.tasks jadvali topilmadi.';
END IF;
IF NOT EXISTS (
  SELECT 1 FROM information_schema.columns
   WHERE table_schema='public' AND table_name='tasks' AND column_name='project_id'
) THEN
  RAISE EXCEPTION 'public.tasks.project_id ustuni yo''q — loyiha moduli ishlamaydi (34-migratsiya).';
END IF;
IF NOT EXISTS (
  SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'is_ws_member'
) THEN
  RAISE EXCEPTION 'is_ws_member() topilmadi. Avval 39_employee_details.sql (yoki 35_fix_projects_rls.sql) ishga tushirilishi kerak. ⚠️ Policy ichida workspace_members inline subquery YOZILMAYDI (42P17) — shu sababli funksiya SHART.';
END IF;

-- projects.id turi (uuid/bigint — qaysi bo'lsa ham to'g'ri ishlasin)
SELECT format_type(a.atttypid, a.atttypmod) INTO v_idtype
  FROM pg_attribute a
 WHERE a.attrelid = 'public.projects'::regclass AND a.attname = 'id' AND a.attnum > 0;
IF v_idtype IS NULL THEN
  RAISE EXCEPTION 'public.projects.id ustuni topilmadi.';
END IF;
v_sig := v_idtype || ', uuid';
RAISE NOTICE 'projects.id turi: %  → can_see_project(%) ', v_idtype, v_sig;

-- RLS holati
SELECT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                WHERE n.nspname='public' AND c.relname='projects' AND c.relrowsecurity) INTO v_prj_rls;
SELECT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                WHERE n.nspname='public' AND c.relname='tasks' AND c.relrowsecurity) INTO v_tsk_rls;
SELECT count(*) INTO v_prj_sel FROM pg_policies
 WHERE schemaname='public' AND tablename='projects' AND permissive='PERMISSIVE' AND cmd IN ('SELECT','ALL');
SELECT count(*) INTO v_tsk_sel FROM pg_policies
 WHERE schemaname='public' AND tablename='tasks' AND permissive='PERMISSIVE' AND cmd IN ('SELECT','ALL');

-- tasks.project_id turi projects.id turi bilan bir xil bo'lishi SHART —
-- aks holda can_see_project() ichidagi solishtirish va policy noto'g'ri ishlardi.
IF (SELECT format_type(a.atttypid, a.atttypmod) FROM pg_attribute a
     WHERE a.attrelid='public.tasks'::regclass AND a.attname='project_id')
   IS DISTINCT FROM v_idtype THEN
  RAISE EXCEPTION 'tasks.project_id turi projects.id (%) turidan farq qiladi — bu skript bunday sxemani qo''llab-quvvatlamaydi.', v_idtype;
END IF;

v_has_cmt := to_regclass('public.task_comments') IS NOT NULL;
v_has_pm  := to_regclass('public.project_members') IS NOT NULL;
-- project_members uchun 2 shart: workspace_id ustuni BOR va project_id turi mos.
-- ⚠️ Hisoblash IF ichida: `'public.project_members'::regclass` jadval yo'q bo'lsa
--    XATO beradi (SQL da AND qisqa tutashuvi KAFOLATLANMAYDI).
v_pm_ws := false;
IF v_has_pm THEN
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='project_members'
                    AND column_name='workspace_id')
         AND (SELECT format_type(a.atttypid, a.atttypmod) FROM pg_attribute a
               WHERE a.attrelid = 'public.project_members'::regclass AND a.attname = 'project_id')
             IS NOT DISTINCT FROM v_idtype
    INTO v_pm_ws;
  SELECT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                  WHERE n.nspname='public' AND c.relname='project_members' AND c.relrowsecurity) INTO v_pm_rls;
  SELECT count(*) INTO v_pm_sel FROM pg_policies
   WHERE schemaname='public' AND tablename='project_members' AND permissive='PERMISSIVE' AND cmd IN ('SELECT','ALL');
ELSE
  v_pm_rls := false; v_pm_sel := 0;
END IF;

-- 🔴 RESTRICTIVE policy bo'lsa yangi PERMISSIVE policy YETARLI BO'LMASLIGI mumkin
--    (RESTRICTIVE AND bilan qo'llanadi). Xato xabarlarida shu eslatma qo'shiladi.
SELECT count(*) INTO v_restr FROM pg_policies
 WHERE schemaname='public' AND tablename IN ('projects','tasks','project_members')
   AND permissive = 'RESTRICTIVE';
IF v_restr > 0 THEN
  v_restr_note := ' ⚠️ DIQQAT: bu jadvallarda ' || v_restr || ' ta RESTRICTIVE policy bor — ular AND bilan qo''llanadi va yangi PERMISSIVE policy ularni yenga olmaydi. Avval SHUNI tekshiring.';
  RAISE WARNING '%', v_restr_note;
END IF;

-- Ma'lumot anomaliyasi: bosqichning workspace'i loyihanikidan farq qilsa,
-- "kutilgan sanoq" formulasi (9-bo'lim) noto'g'ri chiqishi mumkin.
-- Normal bazada bu 0 — shuning uchun faqat ogohlantiramiz.
SELECT count(*) INTO v_n
  FROM public.tasks t JOIN public.projects p ON p.id = t.project_id
 WHERE t.workspace_id IS DISTINCT FROM p.workspace_id;
IF v_n > 0 THEN
  RAISE WARNING '⚠️ % ta vazifaning workspace_id si o''z loyihasinikidan FARQ qiladi (ma''lumot anomaliyasi). Xavfsizlik tekshiruvi shu sababli "kutilmagan farq" deb yiqilishi mumkin — bu policy xatosi emas, avval ma''lumotni tuzating.', v_n;
END IF;

-- ══════════════════════════════════════════════════════════════════════════
-- 2) NAMUNA — kim qaysi loyihada "assignee" (AP = assignee loyihalari)
--    ⚠️ Faqat loyiha workspace'ida A'ZO bo'lgan foydalanuvchilar olinadi —
--       yangi policy ham aynan shu shartni qo'yadi (is_ws_member).
-- ══════════════════════════════════════════════════════════════════════════
INSERT INTO pg_temp.prj_ap (uid, ap, turi)
SELECT t.assigned_to, array_agg(DISTINCT t.project_id::text), 'assignee'
  FROM public.tasks t
  JOIN public.projects p ON p.id = t.project_id
 WHERE t.assigned_to IS NOT NULL
   AND t.project_id IS NOT NULL
   AND EXISTS (SELECT 1 FROM public.workspace_members wm
                WHERE wm.user_id = t.assigned_to AND wm.workspace_id = p.workspace_id)
 GROUP BY t.assigned_to
 ORDER BY t.assigned_to
 LIMIT v_max_users;

-- "Nazorat" foydalanuvchilari: ws a'zosi, lekin HECH BIR loyihada bajaruvchi emas.
-- Ular uchun HECH NARSA o'zgarmasligi kerak (eng qattiq tekshiruv shu).
-- 🔴 Shart `public.tasks` dagi HAQIQIY bajaruvchilar to'plamiga qaraydi,
--    pg_temp.prj_ap ga EMAS: yuqoridagi namuna `LIMIT` bilan KESILGAN, shuning
--    uchun 15 dan ortiq bajaruvchi bo'lsa 16-chisi "nazorat" bo'lib tushib
--    qolardi — policy uning loyihasini ochadi, tekshiruv esa buni "kutilmagan
--    o'sish" deb o'qib SOXTA "XAVFSIZLIK BUZILDI" bilan hammasini qaytarardi.
INSERT INTO pg_temp.prj_ap (uid, ap, turi)
SELECT DISTINCT wm.user_id, '{}'::text[], 'nazorat'
  FROM public.workspace_members wm
 WHERE NOT EXISTS (
         SELECT 1 FROM public.tasks t
          WHERE t.assigned_to = wm.user_id AND t.project_id IS NOT NULL)
   AND NOT EXISTS (SELECT 1 FROM pg_temp.prj_ap a WHERE a.uid = wm.user_id)
 ORDER BY wm.user_id
 LIMIT v_max_ctl;

UPDATE pg_temp.prj_ap a
   SET ap_prj = coalesce(cardinality(a.ap), 0),
       ap_tsk = (SELECT count(*) FROM public.tasks t
                  WHERE t.project_id::text = ANY (a.ap)
                    AND EXISTS (SELECT 1 FROM public.workspace_members wm
                                 WHERE wm.user_id = a.uid AND wm.workspace_id = t.workspace_id));

-- project_members: AP loyihalaridagi jami qator (faqat a'zo bo'lgan ws da)
IF v_pm_ws THEN
  UPDATE pg_temp.prj_ap a
     SET ap_pm = (SELECT count(*) FROM public.project_members pm
                   WHERE pm.project_id::text = ANY (a.ap)
                     AND EXISTS (SELECT 1 FROM public.workspace_members wm
                                  WHERE wm.user_id = a.uid AND wm.workspace_id = pm.workspace_id));
END IF;

SELECT count(*) INTO v_n FROM pg_temp.prj_ap WHERE turi='assignee';
RAISE NOTICE 'Namuna: % ta assignee + % ta nazorat foydalanuvchisi',
  v_n, (SELECT count(*) FROM pg_temp.prj_ap WHERE turi='nazorat');
IF v_n = 0 THEN
  RAISE WARNING 'Hech bir loyiha bosqichi ws a''zosiga biriktirilmagan — o''lchov namunasi bo''sh. Policy baribir qo''shiladi (kelajakdagi biriktirishlar uchun), lekin "oldin/keyin" farqi 0 bo''ladi.';
END IF;

-- ══════════════════════════════════════════════════════════════════════════
-- 3) SNAPSHOT — OLDIN (authenticated roli ostida, HAQIQIY RLS bilan)
-- ══════════════════════════════════════════════════════════════════════════
-- ⚠️ Sanoqlar O'ZGARUVCHIGA yig'iladi va temp jadvalga FAQAT `RESET ROLE` dan
--    KEYIN yoziladi: `authenticated` roli ostida temp jadvalga yozish huquqi yo'q
--    (TASKFIX_SCALE.sql da ham aynan shu tartib).
FOR u IN SELECT * FROM pg_temp.prj_ap ORDER BY uid LOOP
  BEGIN
    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', u.uid::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    EXECUTE 'SELECT count(*) FROM public.projects' INTO v_c_prj;
    EXECUTE 'SELECT count(*) FROM public.projects WHERE id::text = ANY ($1)'
      INTO v_c_prj_ap USING u.ap;
    EXECUTE 'SELECT count(*) FROM public.tasks' INTO v_c_tsk;
    EXECUTE 'SELECT count(*) FROM public.tasks WHERE project_id::text = ANY ($1)'
      INTO v_c_tsk_ap USING u.ap;
    v_c_pm := NULL; v_c_pm_ap := NULL;
    IF v_has_pm THEN
      EXECUTE 'SELECT count(*) FROM public.project_members' INTO v_c_pm;
      EXECUTE 'SELECT count(*) FROM public.project_members WHERE project_id::text = ANY ($1)'
        INTO v_c_pm_ap USING u.ap;
    END IF;
    v_c_cmt := NULL;
    IF v_has_cmt THEN
      EXECUTE 'SELECT count(*) FROM public.task_comments' INTO v_c_cmt;
    END IF;

    EXECUTE 'RESET ROLE';
    INSERT INTO pg_temp.prj_snap (faza, uid, n_prj, n_prj_ap, n_tsk, n_tsk_ap, n_pm, n_pm_ap, n_cmt)
    VALUES ('oldin', u.uid, v_c_prj, v_c_prj_ap, v_c_tsk, v_c_tsk_ap, v_c_pm, v_c_pm_ap, v_c_cmt);
  EXCEPTION WHEN OTHERS THEN
    BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    IF SQLSTATE = '42P17' THEN
      RAISE EXCEPTION 'REKURSIYA (42P17) O''ZGARISHDAN OLDIN ham bor edi: %. Bu skript sababi EMAS — mavjud policy''lardagi halqani (yuqoridagi diagnostikaga qarang) avval tuzating.', SQLERRM;
    END IF;
    RAISE EXCEPTION 'OLDIN-snapshot xatosi (% / %): %', u.uid, SQLSTATE, SQLERRM;
  END;
END LOOP;
RAISE NOTICE 'OLDIN-snapshot olindi (% ta foydalanuvchi)', (SELECT count(*) FROM pg_temp.prj_snap WHERE faza='oldin');

-- ══════════════════════════════════════════════════════════════════════════
-- 4) `tasks` uchun qo'shimcha policy KERAKMI? — TAXMIN EMAS, O'LCHOV.
--    Kerak = kamida bitta assignee o'z loyihasidagi BARCHA bosqichni ko'rmayapti.
-- ══════════════════════════════════════════════════════════════════════════
-- Ikki mustaqil signal:
--   (a) O'LCHOV — namunadagi assignee o'z loyihasidagi barcha bosqichni ko'rmayapti.
--   (b) MATN   — mavjud tasks SELECT policy'si foydalanuvchi ustunlariga
--                (assigned_to/created_by/...) bog'liq, ya'ni ws a'zosi hamma
--                vazifani ko'rmaydi.
-- ⚠️ (a) yolg'iz YETARLI EMAS: namunaga faqat owner/admin tushib qolsa ular
--    baribir hammasini ko'radi va "gap" ko'rinmaydi. Shuning uchun ikkisi OR.
--    Teskari yo'nalishda xato bo'lmaydi: agar vazifalar allaqachon butun ws ga
--    ochiq bo'lsa, policy matnida ham foydalanuvchi ustunlari bo'lmaydi →
--    ortiqcha policy qo'shilmaydi.
SELECT string_agg(coalesce(qual,''), ' | ') INTO v_qual
  FROM pg_policies
 WHERE schemaname='public' AND tablename='tasks' AND permissive='PERMISSIVE' AND cmd IN ('SELECT','ALL');

IF EXISTS (SELECT 1 FROM pg_policies
            WHERE schemaname='public' AND tablename='tasks' AND policyname='tasks_select_project_member') THEN
  v_tsk_need   := true;
  v_tsk_reason := 'policy allaqachon mavjud (qayta RUN) — saqlanadi';
ELSIF EXISTS (
  SELECT 1 FROM pg_temp.prj_ap a
    JOIN pg_temp.prj_snap s ON s.uid = a.uid AND s.faza = 'oldin'
   WHERE a.ap_prj > 0 AND s.n_tsk_ap < a.ap_tsk
) THEN
  v_tsk_need   := true;
  v_tsk_reason := 'o''lchov: assignee o''z loyihasidagi barcha bosqichni KO''RMAYAPTI';
ELSIF v_qual IS NULL THEN
  v_tsk_need   := false;
  v_tsk_reason := 'tasks''da PERMISSIVE SELECT policy yo''q — tegilmaydi';
ELSIF v_qual ~* '(assigned_to|created_by|acceptor_id|submitter_id)' THEN
  v_tsk_need   := true;
  v_tsk_reason := 'o''lchovda kamchilik ko''rinmadi (namunadagilar ehtimol owner/admin), lekin mavjud policy foydalanuvchi ustunlariga bog''liq → xavfsiz tomon tanlandi';
ELSE
  v_tsk_need   := false;
  v_tsk_reason := 'o''lchov ham, policy matni ham: vazifalar allaqachon butun ws a''zolariga ochiq → ortiqcha policy qo''shilmadi';
END IF;
RAISE NOTICE 'tasks policy qarori: % (%)', CASE WHEN v_tsk_need THEN 'KERAK' ELSE 'KERAK EMAS' END, v_tsk_reason;

-- ── 4b) `project_members` — "A'zolar" tabi bo'sh qolmasin ──────────────────
-- Loyihani ko'rgan uning taklif qilingan a'zolarini ham ko'rishi kerak
-- (aks holda mijozdagi "A'zolar" tabi bo'sh/xato bo'lib turadi).
-- 🔴 SHART: `project_members.workspace_id` ustuni BO'LISHI kerak. Busiz
--    policy ichida workspace'ni bilish uchun `projects` ga subquery yozish
--    kerak bo'lardi — u `projects` RLS'ini uyg'otadi va mavjud projects
--    policy'si project_members'ga qarasa (taklif qilingan a'zo naqshi —
--    ehtimoli katta) 42P17 REKURSIYA hosil bo'lardi. Shuning uchun ustun
--    bo'lmasa policy QO'SHILMAYDI, sabab ochiq yoziladi.
IF NOT v_has_pm THEN
  v_pm_need := false; v_pm_reason := 'project_members jadvali yo''q';
ELSIF NOT v_pm_ws THEN
  v_pm_need := false;
  v_pm_reason := 'project_members da workspace_id ustuni yo''q — policy projects ga subquery talab qilardi (42P17 rekursiya xavfi) → ataylab qo''shilmadi';
ELSIF EXISTS (SELECT 1 FROM pg_policies
               WHERE schemaname='public' AND tablename='project_members'
                 AND policyname='project_members_select_project_view') THEN
  v_pm_need := true; v_pm_reason := 'policy allaqachon mavjud (qayta RUN) — saqlanadi';
ELSIF EXISTS (
  SELECT 1 FROM pg_temp.prj_ap a
    JOIN pg_temp.prj_snap s ON s.uid = a.uid AND s.faza = 'oldin'
   WHERE a.ap_prj > 0 AND s.n_pm_ap < a.ap_pm
) THEN
  v_pm_need := true; v_pm_reason := 'o''lchov: assignee o''z loyihasi a''zolarini KO''RMAYAPTI';
ELSIF EXISTS (SELECT 1 FROM pg_temp.prj_ap WHERE ap_prj > 0 AND ap_pm > 0) THEN
  v_pm_need := false; v_pm_reason := 'o''lchov: a''zolar ro''yxati allaqachon ko''rinadi → ortiqcha policy qo''shilmadi';
ELSE
  -- O'lchov signal bermadi (AP loyihalarida umuman taklif qilingan a'zo yo'q).
  -- Mavjud policy matni foydalanuvchi ustuniga bog'liq bo'lsa — xavfsiz tomon.
  SELECT string_agg(coalesce(qual,''), ' | ') INTO v_qual
    FROM pg_policies
   WHERE schemaname='public' AND tablename='project_members'
     AND permissive='PERMISSIVE' AND cmd IN ('SELECT','ALL');
  IF v_qual IS NOT NULL AND v_qual ~* '(user_id|added_by)' THEN
    v_pm_need := true;
    v_pm_reason := 'o''lchov signal bermadi (AP loyihalarida taklif qilingan a''zo yo''q), lekin mavjud policy user_id ga bog''liq → xavfsiz tomon';
  ELSE
    v_pm_need := false;
    v_pm_reason := 'o''lchov ham, policy matni ham: a''zolar ro''yxati allaqachon ochiq → qo''shilmadi';
  END IF;
END IF;
RAISE NOTICE 'project_members policy qarori: % (%)', CASE WHEN v_pm_need THEN 'KERAK' ELSE 'KERAK EMAS' END, v_pm_reason;

-- ══════════════════════════════════════════════════════════════════════════
-- 5) YORDAMCHI FUNKSIYA — can_see_project()
--    🔴 SECURITY DEFINER: `tasks` RLS'ini chetlab o'tadi → policy zanjirida
--       rekursiya (42P17) YUZAGA KELMAYDI. Pastda tirik sinaladi.
--    🔴 anon/authenticated dan REVOKE → keyin faqat EXECUTE beriladi
--       (tf_set_profile_email naqshi). EXECUTE authenticated'ga SHART:
--       RLS ifodasi CHAQIRUVCHI huquqi bilan baholanadi.
-- ══════════════════════════════════════════════════════════════════════════
-- Eski, boshqa imzoli nusxalar (id turi o'zgargan bo'lsa) — tozalanadi.
-- ⚠️ Agar biror policy o'sha nusxaga bog'liq bo'lsa DROP xato beradi va
--    butun tranzaksiya qaytadi (jimgina buzilmaydi).
FOR r IN
  SELECT p.oid, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'can_see_project'
LOOP
  IF lower(btrim(r.args)) IS DISTINCT FROM lower(btrim(v_sig)) THEN
    RAISE NOTICE 'Eski imzo o''chirilmoqda: can_see_project(%)', r.args;
    EXECUTE format('DROP FUNCTION public.can_see_project(%s)', r.args);
  END IF;
END LOOP;

EXECUTE format($f$
  CREATE OR REPLACE FUNCTION public.can_see_project(p_project %s, p_user uuid)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
  AS $body$
    -- 🔴 `p_user = auth.uid()` — MAJBURIY QATOR, OLIB TASHLAMANG.
    --    Funksiya `authenticated` ga EXECUTE bilan ochiq, ya'ni uni PostgREST
    --    orqali TO'G'RIDAN-TO'G'RI chaqirish mumkin:
    --        POST /rest/v1/rpc/can_see_project {p_project, p_user}
    --    Bu qatorsiz istalgan foydalanuvchi ixtiyoriy p_user/p_project yuborib,
    --    o'zi a'zo bo'lmagan workspace'dagi "falon odam falon loyihada
    --    bajaruvchimi?" savoliga javob ola olardi (SECURITY DEFINER tasks
    --    RLS'ini chetlab o'tadi). Policy'lar doim (SELECT auth.uid()) uzatgani
    --    uchun bu shart RLS ishiga umuman ta'sir qilmaydi.
    SELECT p_project IS NOT NULL
       AND p_user   IS NOT NULL
       AND p_user   = (SELECT auth.uid())
       AND EXISTS (
             SELECT 1 FROM public.tasks t
              WHERE t.project_id = p_project
                AND t.assigned_to = p_user
           );
  $body$;
$f$, v_idtype);

EXECUTE format('COMMENT ON FUNCTION public.can_see_project(%s) IS %L', v_sig,
  'Loyiha ichida shu foydalanuvchiga biriktirilgan bosqich bormi? SECURITY DEFINER — tasks RLS''ini chetlab o''tadi, shu sababli projects policy''sidan chaqirilganda 42P17 rekursiya bo''lmaydi. FAQAT RLS policy''lari uchun; workspace tekshiruvi policy tomonida (is_ws_member).');

EXECUTE format('REVOKE ALL ON FUNCTION public.can_see_project(%s) FROM PUBLIC', v_sig);
IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
  EXECUTE format('REVOKE ALL ON FUNCTION public.can_see_project(%s) FROM anon', v_sig);
END IF;
IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
  EXECUTE format('REVOKE ALL ON FUNCTION public.can_see_project(%s) FROM authenticated', v_sig);
  EXECUTE format('GRANT EXECUTE ON FUNCTION public.can_see_project(%s) TO authenticated', v_sig);
ELSE
  RAISE EXCEPTION '`authenticated` roli topilmadi — bu Supabase bazasi emasmi?';
END IF;
RAISE NOTICE 'can_see_project(%) yaratildi (SECURITY DEFINER, faqat authenticated EXECUTE)', v_sig;

-- Tezlik: EXISTS(project_id, assigned_to) uchun kompozit indeks (additive).
-- ⚠️ QISMAN (`WHERE project_id IS NOT NULL`): vazifalarning katta qismi
--    loyihasiz — ular indeksga umuman kirmaydi (indeks kichik, yozuv arzon).
--    Funksiyadagi shart doim `project_id = <qiymat>` bo'lgani uchun planner
--    qisman indeksni bemalol ishlatadi.
CREATE INDEX IF NOT EXISTS idx_tasks_project_assigned
  ON public.tasks (project_id, assigned_to)
  WHERE project_id IS NOT NULL;

-- ══════════════════════════════════════════════════════════════════════════
-- 6) POLICY: projects — assignee loyihani ko'radi
--    ⚠️ (SELECT auth.uid()) bilan o'ralgan — TASKFIX_SCALE.sql naqshi
--       (InitPlan: har qator uchun qayta hisoblanmaydi).
-- ══════════════════════════════════════════════════════════════════════════
IF NOT v_prj_rls THEN
  RAISE WARNING 'public.projects da RLS O''CHIQ — policy qo''shilmadi. Sabab: RLS o''chiq bo''lsa policy umuman baholanmaydi (hamma hamma narsani ko''radi); bu yerda policy qo''shish soxta xavfsizlik tuyg''usi berardi. Avval asosiy loyiha RLS''ini yoqing (35_fix_projects_rls.sql).';
ELSIF v_prj_sel = 0 THEN
  RAISE WARNING 'public.projects da PERMISSIVE SELECT policy UMUMAN YO''Q — policy qo''shilmadi. Sabab: bu holatda hozir hech kim loyihani ko''rmayapti; yolg''iz "assignee" policy''si asosiy ko''rish qoidasining o''rnini bosib qolardi (owner/admin baribir ko''rmasdi). Avval asosiy projects SELECT policy''sini tiklang (35_fix_projects_rls.sql), keyin bu skriptni qayta ishga tushiring.';
ELSE
  DROP POLICY IF EXISTS projects_select_assignee ON public.projects;
  EXECUTE $p$
    CREATE POLICY projects_select_assignee ON public.projects
      FOR SELECT TO authenticated
      USING ( is_ws_member(workspace_id, (SELECT auth.uid()))
              AND can_see_project(id, (SELECT auth.uid())) )
  $p$;
  v_prj_added := true;
  RAISE NOTICE '✅ projects_select_assignee policy qo''shildi';
END IF;

-- ══════════════════════════════════════════════════════════════════════════
-- 7) POLICY: tasks — o'sha loyihaning BOSHQA bosqichlari (faqat kerak bo'lsa)
-- ══════════════════════════════════════════════════════════════════════════
IF NOT v_tsk_need THEN
  RAISE NOTICE 'tasks_select_project_member QO''SHILMADI — %', v_tsk_reason;
ELSIF NOT v_tsk_rls THEN
  RAISE WARNING 'public.tasks da RLS O''CHIQ — tasks policy''si qo''shilmadi (baribir baholanmasdi).';
ELSIF v_tsk_sel = 0 THEN
  RAISE WARNING 'public.tasks da PERMISSIVE SELECT policy YO''Q — tasks policy''si qo''shilmadi (avval asosiy vazifa policy''si kerak).';
ELSE
  DROP POLICY IF EXISTS tasks_select_project_member ON public.tasks;
  EXECUTE $p$
    CREATE POLICY tasks_select_project_member ON public.tasks
      FOR SELECT TO authenticated
      USING ( project_id IS NOT NULL
              AND is_ws_member(workspace_id, (SELECT auth.uid()))
              AND can_see_project(project_id, (SELECT auth.uid())) )
  $p$;
  v_tsk_added := true;
  RAISE NOTICE '✅ tasks_select_project_member policy qo''shildi — %', v_tsk_reason;
END IF;

-- ══════════════════════════════════════════════════════════════════════════
-- 7b) POLICY: project_members — loyihaning taklif qilingan a'zolari ro'yxati
-- ══════════════════════════════════════════════════════════════════════════
IF NOT v_pm_need THEN
  RAISE NOTICE 'project_members_select_project_view QO''SHILMADI — %', v_pm_reason;
ELSIF NOT v_pm_rls THEN
  RAISE WARNING 'public.project_members da RLS O''CHIQ — policy qo''shilmadi (baribir baholanmasdi).';
ELSIF v_pm_sel = 0 THEN
  RAISE WARNING 'public.project_members da PERMISSIVE SELECT policy YO''Q — policy qo''shilmadi (avval asosiy policy kerak).';
ELSE
  DROP POLICY IF EXISTS project_members_select_project_view ON public.project_members;
  EXECUTE $p$
    CREATE POLICY project_members_select_project_view ON public.project_members
      FOR SELECT TO authenticated
      USING ( is_ws_member(workspace_id, (SELECT auth.uid()))
              AND can_see_project(project_id, (SELECT auth.uid())) )
  $p$;
  v_pm_added := true;
  RAISE NOTICE '✅ project_members_select_project_view policy qo''shildi — %', v_pm_reason;
END IF;

-- ══════════════════════════════════════════════════════════════════════════
-- 8) SNAPSHOT — KEYIN (aynan shu so'rovlar, aynan shu foydalanuvchilar)
--    Bu ayni paytda REKURSIYA (42P17) TESTI hamdir: yangi policy zanjirida
--    halqa bo'lsa quyidagi so'rovlar shu yerda yiqiladi.
-- ══════════════════════════════════════════════════════════════════════════
FOR u IN SELECT * FROM pg_temp.prj_ap ORDER BY uid LOOP
  BEGIN
    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', u.uid::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    EXECUTE 'SELECT count(*) FROM public.projects' INTO v_c_prj;
    EXECUTE 'SELECT count(*) FROM public.projects WHERE id::text = ANY ($1)'
      INTO v_c_prj_ap USING u.ap;
    EXECUTE 'SELECT count(*) FROM public.tasks' INTO v_c_tsk;
    EXECUTE 'SELECT count(*) FROM public.tasks WHERE project_id::text = ANY ($1)'
      INTO v_c_tsk_ap USING u.ap;
    v_c_pm := NULL; v_c_pm_ap := NULL;
    IF v_has_pm THEN
      EXECUTE 'SELECT count(*) FROM public.project_members' INTO v_c_pm;
      EXECUTE 'SELECT count(*) FROM public.project_members WHERE project_id::text = ANY ($1)'
        INTO v_c_pm_ap USING u.ap;
    END IF;
    v_c_cmt := NULL;
    IF v_has_cmt THEN
      EXECUTE 'SELECT count(*) FROM public.task_comments' INTO v_c_cmt;
    END IF;

    EXECUTE 'RESET ROLE';
    INSERT INTO pg_temp.prj_snap (faza, uid, n_prj, n_prj_ap, n_tsk, n_tsk_ap, n_pm, n_pm_ap, n_cmt)
    VALUES ('keyin', u.uid, v_c_prj, v_c_prj_ap, v_c_tsk, v_c_tsk_ap, v_c_pm, v_c_pm_ap, v_c_cmt);
  EXCEPTION WHEN OTHERS THEN
    BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    IF SQLSTATE = '42P17' THEN
      RAISE EXCEPTION 'REKURSIYA (42P17) YANGI POLICY SABABLI: %. Demak can_see_project() SECURITY DEFINER bo''lishiga qaramay tasks RLS''i baholanyapti (funksiya egasi jadval egasi emas / FORCE ROW LEVEL SECURITY yoqilgan). HAMMASI QAYTARILDI.', SQLERRM;
    END IF;
    RAISE EXCEPTION 'KEYIN-snapshot xatosi (% / %): % — HAMMASI QAYTARILDI', u.uid, SQLSTATE, SQLERRM;
  END;
END LOOP;

-- ══════════════════════════════════════════════════════════════════════════
-- 9) 🔴 XAVFSIZLIK TEKSHIRUVI — kutilgan sondan bitta ham farq bo'lmasin
-- ══════════════════════════════════════════════════════════════════════════
FOR u IN
  SELECT a.uid, a.turi, a.ap_prj, a.ap_tsk, a.ap_pm,
         o.n_prj AS o_prj, o.n_prj_ap AS o_prj_ap, o.n_tsk AS o_tsk, o.n_tsk_ap AS o_tsk_ap,
         o.n_pm  AS o_pm,  o.n_pm_ap  AS o_pm_ap,  o.n_cmt AS o_cmt,
         k.n_prj AS k_prj, k.n_prj_ap AS k_prj_ap, k.n_tsk AS k_tsk, k.n_tsk_ap AS k_tsk_ap,
         k.n_pm  AS k_pm,  k.n_pm_ap  AS k_pm_ap,  k.n_cmt AS k_cmt
    FROM pg_temp.prj_ap a
    JOIN pg_temp.prj_snap o ON o.uid = a.uid AND o.faza = 'oldin'
    JOIN pg_temp.prj_snap k ON k.uid = a.uid AND k.faza = 'keyin'
   ORDER BY a.uid
LOOP
  -- 9.1 projects: kutilgan = oldingi jami − oldingi AP + AP hajmi
  v_exp_prj := CASE WHEN v_prj_added THEN u.o_prj - u.o_prj_ap + u.ap_prj ELSE u.o_prj END;
  IF u.k_prj IS DISTINCT FROM v_exp_prj THEN
    RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (projects): foydalanuvchi % — oldin %, kutilgan %, keyin %. AP=% ta loyiha (oldin ko''ringani %). % — HAMMASI ORQAGA QAYTARILDI.',
      u.uid, u.o_prj, v_exp_prj, u.k_prj, u.ap_prj, u.o_prj_ap,
      CASE WHEN u.k_prj > v_exp_prj THEN 'KUTILMAGAN O''SISH — policy ortiqcha qator ochdi'
           ELSE 'KAMAYISH — kirish huquqi torayib qoldi' END;
  END IF;
  IF v_prj_added AND u.k_prj_ap IS DISTINCT FROM u.ap_prj::bigint THEN
    RAISE EXCEPTION 'TEKSHIRUV (projects): foydalanuvchi % o''zining % ta assignee-loyihasidan atigi % tasini ko''rmoqda — policy kutilganday ishlamadi.%  HAMMASI QAYTARILDI.',
      u.uid, u.ap_prj, u.k_prj_ap, v_restr_note;
  END IF;

  -- 9.2 tasks: kutilgan = oldingi jami − oldingi AP + AP dagi jami vazifa
  v_exp_tsk := CASE WHEN v_tsk_added THEN u.o_tsk - u.o_tsk_ap + u.ap_tsk ELSE u.o_tsk END;
  IF u.k_tsk IS DISTINCT FROM v_exp_tsk THEN
    RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (tasks): foydalanuvchi % — oldin %, kutilgan %, keyin %. AP vazifalari: % (oldin ko''ringani %). % %  HAMMASI ORQAGA QAYTARILDI.',
      u.uid, u.o_tsk, v_exp_tsk, u.k_tsk, u.ap_tsk, u.o_tsk_ap,
      CASE WHEN u.k_tsk > v_exp_tsk THEN 'KUTILMAGAN O''SISH' ELSE 'KAMAYISH' END, v_restr_note;
  END IF;

  -- 9.2b project_members: kutilgan = oldingi jami − oldingi AP + AP dagi jami qator
  v_exp_pm := CASE WHEN v_pm_added THEN u.o_pm - u.o_pm_ap + u.ap_pm ELSE u.o_pm END;
  IF v_has_pm AND u.k_pm IS DISTINCT FROM v_exp_pm THEN
    RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (project_members): foydalanuvchi % — oldin %, kutilgan %, keyin %. AP a''zolari: % (oldin ko''ringani %). % %  HAMMASI ORQAGA QAYTARILDI.',
      u.uid, u.o_pm, v_exp_pm, u.k_pm, u.ap_pm, u.o_pm_ap,
      CASE WHEN u.k_pm > v_exp_pm THEN 'KUTILMAGAN O''SISH' ELSE 'KAMAYISH' END, v_restr_note;
  END IF;

  -- 9.3 NAZORAT foydalanuvchisi (AP bo'sh): HECH BIR jadvalda o'zgarish bo'lmasin
  IF u.turi = 'nazorat' THEN
    IF u.k_prj IS DISTINCT FROM u.o_prj OR u.k_tsk IS DISTINCT FROM u.o_tsk
       OR u.k_pm IS DISTINCT FROM u.o_pm OR u.k_cmt IS DISTINCT FROM u.o_cmt THEN
      RAISE EXCEPTION 'XAVFSIZLIK BUZILDI: NAZORAT foydalanuvchisi % ga yangi ma''lumot ochildi (projects %→%, tasks %→%, a''zolar %→%, izohlar %→%). Bu foydalanuvchi hech bir loyihada bajaruvchi EMAS — unga hech narsa ochilmasligi kerak edi. HAMMASI QAYTARILDI.',
        u.uid, u.o_prj, u.k_prj, u.o_tsk, u.k_tsk, u.o_pm, u.k_pm, u.o_cmt, u.k_cmt;
    END IF;
  ELSIF v_has_cmt AND u.k_cmt IS DISTINCT FROM u.o_cmt THEN
    -- Izohlar policy'si tasks'ga tayanadi → vazifa ko'rinishi kengaysa izoh ham
    -- kengayishi MUMKIN. Bu kutilgan oqibat (bosqichni ko'rgan uni muhokamasini
    -- ham ko'radi), shuning uchun XATO emas — lekin ochiq yoziladi.
    RAISE NOTICE 'ℹ️ % : task_comments % → % (o''z loyihasidagi bosqich izohlari — kutilgan oqibat)',
      u.uid, u.o_cmt, u.k_cmt;
  END IF;

  v_gain_prj := v_gain_prj + (u.k_prj - u.o_prj);
  v_gain_tsk := v_gain_tsk + (u.k_tsk - u.o_tsk);
END LOOP;

RAISE NOTICE '✅ XAVFSIZLIK: barcha sanoqlar kutilganday. Yangi ko''ringan: % ta loyiha qatori, % ta vazifa qatori (faqat assignee o''z loyihasida).',
  v_gain_prj, v_gain_tsk;

-- ══════════════════════════════════════════════════════════════════════════
-- 10) NATIJA jadvali
-- ══════════════════════════════════════════════════════════════════════════
INSERT INTO pg_temp.prj_res VALUES
  (1, 'funksiya', 'can_see_project(' || v_sig || ')', 'yaratildi',
      'SECURITY DEFINER · STABLE · faqat authenticated EXECUTE'),
  (2, 'policy', 'projects_select_assignee',
      CASE WHEN v_prj_added THEN 'qo''shildi' ELSE 'QO''SHILMADI' END,
      CASE WHEN v_prj_added THEN 'is_ws_member + can_see_project'
           WHEN NOT v_prj_rls THEN 'projects da RLS o''chiq'
           ELSE 'projects da PERMISSIVE SELECT policy yo''q' END),
  (3, 'policy', 'tasks_select_project_member',
      CASE WHEN v_tsk_added THEN 'qo''shildi' ELSE 'QO''SHILMADI' END, v_tsk_reason),
  (4, 'policy', 'project_members_select_project_view',
      CASE WHEN v_pm_added THEN 'qo''shildi' ELSE 'QO''SHILMADI' END, v_pm_reason),
  (5, 'indeks', 'idx_tasks_project_assigned', 'bor', 'tasks(project_id, assigned_to) WHERE project_id IS NOT NULL'),
  (6, 'xavfsizlik', 'tekshirilgan foydalanuvchi',
      (SELECT count(*)::text FROM pg_temp.prj_ap),
      (SELECT count(*)::text FROM pg_temp.prj_ap WHERE turi='nazorat') || ' tasi NAZORAT (ularda 0 o''zgarish shart)'),
  (7, 'xavfsizlik', 'yangi ko''ringan qator',
      v_gain_prj::text || ' loyiha / ' || v_gain_tsk::text || ' vazifa',
      'faqat o''z bosqichi bor loyihalar'),
  (8, 'xavfsizlik', 'RESTRICTIVE policy',
      CASE WHEN v_restr > 0 THEN v_restr::text || ' ta' ELSE 'yo''q' END,
      CASE WHEN v_restr > 0 THEN 'AND bilan qo''llanadi — yangi PERMISSIVE policy ularni yenga olmaydi'
           ELSE 'yangi PERMISSIVE policy to''liq kuchga kiradi' END);

RAISE NOTICE '════ TUGADI — pastdagi jadvalga qarang ════';
END
$main$;

COMMIT;

-- ══════════ NATIJA ══════════
SELECT bosqich, nom, qiymat, izoh FROM pg_temp.prj_res ORDER BY ord;

-- Kim nima ko'rdi (oldin → keyin)
SELECT a.turi,
       a.uid,
       a.ap_prj                        AS assignee_loyiha,
       o.n_prj || ' → ' || k.n_prj     AS loyihalar,
       o.n_tsk || ' → ' || k.n_tsk     AS vazifalar,
       coalesce(o.n_pm::text, '—') || ' → ' || coalesce(k.n_pm::text, '—') AS azolar
  FROM pg_temp.prj_ap a
  JOIN pg_temp.prj_snap o ON o.uid = a.uid AND o.faza='oldin'
  JOIN pg_temp.prj_snap k ON k.uid = a.uid AND k.faza='keyin'
 ORDER BY a.turi, a.uid;


-- ============================================================================
-- QANDAY O'QISH
-- ============================================================================
--  • "policy · qo'shildi" — ish bitdi. Bosqichi biriktirilgan hodim endi
--    loyihani va uning barcha bosqichlarini KO'RADI (faqat ko'radi —
--    o'zgartirish mijozda ham, keyingi qadamlarda serverda ham owner/admin'da).
--  • "QO'SHILMADI" bo'lsa — izoh ustunida sababi yozilgan (RLS o'chiq /
--    asosiy policy yo'q / kerak emas). Bu XATO emas, ongli qaror.
--  • Xavfsizlik qatori: "yangi ko'ringan qator" — faqat assignee'ning o'z
--    loyihalari. NAZORAT foydalanuvchilarida 0 bo'lishi SHART, aks holda
--    skript RAISE EXCEPTION bilan to'xtagan va HECH NARSA o'zgarmagan bo'lardi.
--
-- ============================================================================
-- ROLLBACK (kerak bo'lsa — shu 4 buyruq, tartib MUHIM: avval policy, keyin funksiya)
-- ============================================================================
--   DROP POLICY IF EXISTS projects_select_assignee            ON public.projects;
--   DROP POLICY IF EXISTS tasks_select_project_member         ON public.tasks;
--   DROP POLICY IF EXISTS project_members_select_project_view ON public.project_members;
--   DROP FUNCTION IF EXISTS public.can_see_project(uuid, uuid);   -- projects.id uuid bo'lsa
--   -- (agar projects.id bigint bo'lsa: DROP FUNCTION public.can_see_project(bigint, uuid);
--   --  aniq imzoni ko'rish: SELECT pg_get_function_identity_arguments(oid)
--   --    FROM pg_proc WHERE proname='can_see_project';)
--   -- Indeks qolishi mumkin (zararsiz), o'chirish: DROP INDEX IF EXISTS public.idx_tasks_project_assigned;
-- Rollbackdan keyin holat skriptdan OLDINGIDEK bo'ladi: mavjud policy'lar
-- umuman tegilmagani uchun tiklash kerak emas.
-- ============================================================================
