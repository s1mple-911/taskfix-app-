-- ============================================================================
-- TASKFIX_PLANNER.sql — Vazifa VAQT ORALIG'I + boshqaning rejasini ko'rish
-- (BRIEF_TASKFIX_PLANNER_DASH.md 2 va 3-band)
-- ============================================================================
-- Asilbek RUN qiladi (Supabase SQL Editor, postgres roli).
-- ADDITIVE + IDEMPOTENT: mavjud ustun/policy/trigger O'CHIRILMAYDI,
-- O'ZGARTIRILMAYDI. Faqat YANGI obyektlar qo'shiladi. Qayta RUN xavfsiz.
--
-- ── MUAMMO ──────────────────────────────────────────────────────────────────
--   Rejalashtirgich (planner) hozir FAQAT localStorage'da yashaydi:
--       localStorage['planner_<wsId>_<userId>'] = {taskId: {date, start, dur}}
--   (index.html: plnGetSchedule / plnSaveSchedule / plnScheduleTask).
--   Bu ikki yangi talabni IMKONSIZ qiladi:
--     • vazifa YARATUVCHISI qo'ygan vaqt oralig'i BAJARUVCHINING
--       rejalashtirgichida ko'rinishi kerak (boshqa brauzer, boshqa qurilma);
--     • ruxsati bor odam (masalan CEO) BOSHQA xodimning ish grafigini
--       ko'rishi kerak.
--   Ikkalasi ham ma'lumot BAZADA bo'lishini talab qiladi.
--
-- ── NIMA QO'SHILADI ─────────────────────────────────────────────────────────
--   1) public.tasks ga 3 ustun    — plan_date (date), plan_start / plan_end
--                                   (smallint, kun boshidan DAQIQA)
--      + 3 CHECK (conrelid bilan skoplangan) + 1 qisman indeks
--   2) public.workspace_members ga — can_view_others_planner boolean
--                                    NOT NULL DEFAULT false
--   3) public.can_view_planner(p_ws, p_target, p_user) — SECURITY DEFINER
--   4) public.wm_planner_flag_guard() + wm_planner_flag_guard_trg
--      🔴 bayroqni FAQAT owner/admin yoza oladi (pastda: nega trigger)
--   5) POLICY tasks_select_planner_shared — PERMISSIVE SELECT (additive)
--   6) Kerak bo'lsagina: POLICY wm_update_manager_planner (skript o'zi o'lchab
--      qaror qiladi — mavjud UPDATE policy yetarli bo'lsa QO'SHILMAYDI)
--
-- ── NIMA O'ZGARMAYDI (🔴 tegilmaydi) ────────────────────────────────────────
--   • tasks.deadline — bir belgi ham tegilmaydi. plan_* va deadline MUSTAQIL:
--     foydalanuvchi birini, ikkinchisini yoki hech birini tanlaydi.
--   • tasks ning MAVJUD SELECT/INSERT/UPDATE/DELETE policy'lari.
--   • workspace_members ning MAVJUD policy'lari (role, a'zolik mantiqi).
--   • projects, task_history, employee_details, hr_* — umuman tegilmaydi.
--   • Hech qanday MA'LUMOT o'zgarmaydi (yangi ustunlar NULL / false bilan
--     tug'iladi). Skriptdagi "tirik" sinovlar sentinel-rollback bilan
--     bajariladi — bitta qator ham haqiqatda yozilmaydi.
--
-- ── BUSIZ ILOVA QANDAY ISHLAYDI ─────────────────────────────────────────────
--   Bu fayl RUN qilinmasa ilova AVVALGIDEK ishlaydi: rejalashtirgich
--   localStorage'da qoladi (faqat o'zim, faqat shu brauzer), vazifa yaratishda
--   "vaqt oralig'i" saqlanmaydi va "kimning rejasi" tanlagichi ko'rinmaydi.
--   Mijoz ustun yo'qligini PGRST204 / 42703 bilan aniqlaydi va sababni ochiq
--   aytadi (jimgina yutmaydi — CLAUDE.md 6-qoida).
--
-- ── 🔴 localStorage MIGRATSIYASI — BU SKRIPTNING ISHI EMAS ──────────────────
--   SQL brauzerdagi localStorage'ga TEGA OLMAYDI. Mavjud rejalar
--   (`planner_<wsId>_<userId>`) bazaga MIJOZ tomonidan, birinchi ochilishda,
--   BIR MARTA ko'chiriladi (boshqa agentning ishi):
--       {taskId: {date, start, dur}}  →  plan_date = date,
--                                        plan_start = start,
--                                        plan_end   = start + dur
--   SQL tomondan hech narsa talab qilinmaydi — ustunlar tayyor tursa bo'ldi.
--   Ko'chirish TUGAGACH ham localStorage kalitini o'chirmaslik tavsiya etiladi
--   (zaxira); takror ko'chirishni mijoz o'z bayrog'i bilan to'sadi.
--
-- ── ⚠️ NEGA smallint (DAQIQA), `time` EMAS ──────────────────────────────────
--   Mavjud planner butun mexanikasi DAQIQA bilan ishlaydi: {start, dur} —
--   blok surish/o'lchash, setka (PLN_H_START*60), lane hisobi — hammasi
--   butun son. `time` bo'lsa har o'qish/yozishda ikki tomonlama konvertatsiya
--   kerak bo'lardi va "yarim tun"/mintaqa chekka holatlari paydo bo'lardi.
--   `timestamptz` esa umuman noto'g'ri: reja BIZNES KUNIga (Toshkent) tegishli,
--   lahzaga emas — foydalanuvchi chet elda ochsa blok kunni almashtirib
--   yuborardi (dof* moduli bilan bir xil saboq).
--   smallint diapazoni −32768..32767 — 0..1440 bemalol sig'adi (2 bayt).
--
-- ── RUN TARTIBI ─────────────────────────────────────────────────────────────
--   1) 39_employee_details.sql (yoki 35_fix_projects_rls.sql) → is_ws_member(),
--      is_ws_manager() MAVJUD bo'lishi SHART (CLAUDE.md 8-qoida: policy ichida
--      workspace_members inline subquery YOZILMAYDI → 42P17).
--   2) TASKFIX_PLANNER.sql  ← SHU FAYL
--   Boshqa fayllarga bog'liq emas (TASKFIX_LOYIHA*.sql, HR fayllari bilan
--   to'qnashmaydi — ular boshqa jadval/policy nomlariga tegadi).
--
-- ── ⚠️ QACHON RUN QILINADI — KAM TRAFIK VAQTIDA ─────────────────────────────
--   `ALTER TABLE ... ADD CONSTRAINT ... CHECK` va `CREATE POLICY` `tasks`
--   jadvaliga **ACCESS EXCLUSIVE** qulf oladi va uni COMMIT gacha ushlab
--   turadi. Yangi ustunlar to'liq NULL bo'lgani uchun CHECK skani tez
--   (ustun qiymatsiz — Postgres baribir jadvalni bir marta o'qiydi), lekin
--   katta bazada va ish vaqtida bu bir necha soniya "vazifa o'qilmaydi"
--   degani. Kechqurun/dam olish kuni ishga tushiring.
--
-- ── 🔴 QOLGAN XAVF (ochiq aytiladi, yashirilmaydi) ──────────────────────────
--   RLS **QATOR** darajasida ishlaydi, ustun darajasida emas. Ya'ni ruxsat
--   berilgan odam (CEO) boshqa xodimning REJALI vazifasini butun QATORI bilan
--   ko'radi: sarlavha, tavsif, izohlar (izohlar policy'si tasks'ga tayansa).
--   Agar faqat "band vaqt" ko'rinishi kerak bo'lsa — alohida VIEW yoki
--   SECURITY DEFINER RPC kerak (bu fayl uni QILMAYDI, ataylab: brief
--   "boshqa userlar planner'ini ko'ra oladi" deydi).
--   ⚠️ Nishon FAQAT `plan_date IS NOT NULL` bo'lgan qatorlar — rejasiz
--   vazifalar bu policy orqali HECH QACHON ochilmaydi.
--
-- TEXT/boolean + CHECK ishlatilgan (ENUM emas) — 30/32-migratsiyalar saboqi.
-- Fayl oxirida QAYTARISH (rollback) bo'limi bor.
-- ============================================================================

-- ⚠️ TRANZAKSIYA — TARTIB MUHIM, O'ZGARTIRMANG:
--    `BEGIN;` va `SET TRANSACTION ...` skriptdagi ENG BIRINCHI ikki buyruq
--    bo'lishi shart (aks holda 25001). Supabase SQL Editor butun skriptni o'zi
--    bitta tranzaksiyada yuboradi — u yerda `BEGIN;` ogohlantirish bilan
--    e'tiborsiz qoldiriladi, `SET TRANSACTION` esa baribir ishlaydi.
BEGIN;
-- 🔴 REPEATABLE READ — busiz "oldin" va "keyin" sanoqlari BOSHQA sessiyaning
--    yozuvi (yangi vazifa) sababli farq qilib, xavfsizlik tekshiruvi SOXTA
--    "XAVFSIZLIK BUZILDI" bilan yiqilardi.
-- ⚠️ AGAR "25001: SET TRANSACTION ISOLATION LEVEL must be called before any
--    query" chiqsa — quyidagi qatorni izohga oling va qayta RUN qiling.
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;


-- ════════════════════════════════════════════════════════════════════════════
-- 0) DIAGNOSTIKA — FAQAT O'QIYDI. Natijani "Messages"/"Notices" da o'qing.
--    🔴 Mavjud policy'larni KO'RMASDAN yangi policy qo'shilmaydi: RESTRICTIVE
--       policy bo'lsa yangi PERMISSIVE policy YETARLI BO'LMAYDI (AND bilan
--       qo'llanadi), UPDATE policy'si esa "bajaruvchi plan_* ni yoza oladimi"
--       degan savolga javob beradi.
-- ════════════════════════════════════════════════════════════════════════════
DO $diag$
DECLARE
  r   RECORD;
  v_t text;
  v_n int;
BEGIN
  RAISE NOTICE '════════ DIAGNOSTIKA (o''zgarishdan OLDINGI holat) ════════';

  FOREACH v_t IN ARRAY ARRAY['tasks','workspace_members'] LOOP
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
     WHERE schemaname = 'public' AND tablename IN ('tasks','workspace_members')
     ORDER BY tablename, cmd, policyname
  LOOP
    RAISE NOTICE '   [%] % (% · % · %)  USING: %  CHECK: %',
      r.tablename, r.policyname, r.cmd, r.permissive, r.roles,
      coalesce(r.qual, '—'), coalesce(r.with_check, '—');
  END LOOP;

  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='public' AND tablename IN ('tasks','workspace_members')
     AND permissive = 'RESTRICTIVE';
  IF v_n > 0 THEN
    RAISE WARNING '⚠️ % ta RESTRICTIVE policy bor — ular AND bilan qo''llanadi va yangi PERMISSIVE policy ularni YENGA OLMAYDI. Skript yiqilsa birinchi navbatda shularni tekshiring.', v_n;
  ELSE
    RAISE NOTICE '   RESTRICTIVE policy yo''q — yangi PERMISSIVE policy to''liq kuchga kiradi.';
  END IF;

  -- `tasks` UPDATE policy'lari — planner'da blokni sudrab qo'yish aynan shu
  -- policy orqali o'tadi (plan_* alohida ruxsat talab QILMAYDI: RLS qator
  -- darajasida ishlaydi).
  FOR r IN
    SELECT policyname, permissive, qual, with_check
      FROM pg_policies
     WHERE schemaname='public' AND tablename='tasks' AND cmd IN ('UPDATE','ALL')
     ORDER BY policyname
  LOOP
    RAISE NOTICE '   tasks UPDATE policy: % (%) USING: % CHECK: %',
      r.policyname, r.permissive, coalesce(r.qual,'—'), coalesce(r.with_check,'—');
  END LOOP;

  RAISE NOTICE '════════ DIAGNOSTIKA TUGADI ════════';
END $diag$;


-- ════════════════════════════════════════════════════════════════════════════
-- 1) OLD SHARTLAR — noto'g'ri/yarim bazada ishga tushmasin
-- ════════════════════════════════════════════════════════════════════════════
DO $pre$
BEGIN
  IF to_regclass('public.tasks') IS NULL THEN
    RAISE EXCEPTION 'public.tasks topilmadi — bu TaskFix bazasi emasmi?';
  END IF;
  IF to_regclass('public.workspace_members') IS NULL THEN
    RAISE EXCEPTION 'public.workspace_members topilmadi — bu TaskFix bazasi emasmi?';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name='assigned_to') THEN
    RAISE EXCEPTION 'public.tasks.assigned_to ustuni yo''q — reja bajaruvchiga bog''lanadi, busiz modul ma''nosiz.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name='workspace_id') THEN
    RAISE EXCEPTION 'public.tasks.workspace_id ustuni yo''q.';
  END IF;

  -- 🔴 CLAUDE.md 8-qoida: policy ichida workspace_members inline subquery
  --    YOZILMAYDI (42P17 rekursiya) — shu sababli bu ikki funksiya SHART.
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='is_ws_member') THEN
    RAISE EXCEPTION 'is_ws_member() topilmadi. Avval 39_employee_details.sql (yoki 35_fix_projects_rls.sql) ni ishga tushiring.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='is_ws_manager') THEN
    RAISE EXCEPTION 'is_ws_manager() topilmadi. Avval 35_fix_projects_rls.sql / 39_employee_details.sql ni ishga tushiring.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    RAISE EXCEPTION '`authenticated` roli topilmadi — bu Supabase bazasi emasmi?';
  END IF;
END $pre$;


-- ════════════════════════════════════════════════════════════════════════════
-- 2) tasks — VAQT ORALIG'I ustunlari (ADDITIVE)
--    plan_start / plan_end — kun boshidan DAQIQA (yuqoridagi izohga qarang).
--    Misol: Dushanba 14:00–16:00 → plan_date='2026-08-24', 840 … 960.
-- ════════════════════════════════════════════════════════════════════════════
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS plan_date  date;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS plan_start smallint;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS plan_end   smallint;

COMMENT ON COLUMN public.tasks.plan_date  IS 'Rejalashtirgichdagi KUN (biznes kuni, Asia/Tashkent). deadline dan MUSTAQIL.';
COMMENT ON COLUMN public.tasks.plan_start IS 'Reja boshlanishi — kun boshidan daqiqa (0..1439). Mijozdagi {start} bilan bir xil birlik.';
COMMENT ON COLUMN public.tasks.plan_end   IS 'Reja tugashi — kun boshidan daqiqa (1..1440). Mijozdagi {start + dur}.';

-- 🔴 CHECK'lar idempotent: DROP → ADD. `ALTER TABLE ... DROP CONSTRAINT IF
--    EXISTS` jadvalga SKOPLANGAN, ya'ni bir xil nomli boshqa jadval
--    cheklovi tegilmaydi (conname GLOBAL UNIQUE EMAS — tekshiruv bloki ham
--    shuning uchun conrelid bilan qidiradi).
ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS tasks_plan_start_chk;
ALTER TABLE public.tasks
  ADD CONSTRAINT tasks_plan_start_chk
  CHECK (plan_start IS NULL OR (plan_start >= 0 AND plan_start <= 1439));

ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS tasks_plan_end_chk;
ALTER TABLE public.tasks
  ADD CONSTRAINT tasks_plan_end_chk
  CHECK (plan_end IS NULL OR (plan_end >= 1 AND plan_end <= 1440));

-- 🔴 UCHLIGI BIRGA: yo uchalasi ham bo'sh, yo uchalasi ham to'la (va oxiri
--    boshidan keyin). Busiz "sana bor, soat yo'q" kabi yarim qator paydo
--    bo'lardi va mijoz uni blok qilib chiza olmasdi (start=null → NaN).
ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS tasks_plan_triple_chk;
ALTER TABLE public.tasks
  ADD CONSTRAINT tasks_plan_triple_chk
  CHECK (
    (plan_date IS NULL AND plan_start IS NULL AND plan_end IS NULL)
    OR
    (plan_date IS NOT NULL AND plan_start IS NOT NULL AND plan_end IS NOT NULL
     AND plan_end > plan_start)
  );

-- Indeks: "falon xodimning falon kundagi rejasi" so'rovi uchun.
-- ⚠️ QISMAN (`WHERE plan_date IS NOT NULL`): vazifalarning katta qismi
--    rejasiz — ular indeksga umuman kirmaydi (indeks kichik, yozuv arzon).
--    Yangi policy ham doim `plan_date IS NOT NULL` bilan keladi.
CREATE INDEX IF NOT EXISTS idx_tasks_ws_assigned_plan
  ON public.tasks (workspace_id, assigned_to, plan_date)
  WHERE plan_date IS NOT NULL;


-- ════════════════════════════════════════════════════════════════════════════
-- 3) workspace_members — "boshqalarning rejasini ko'rish" bayrog'i
--    🔴 NEGA `positions` EMAS (HR muharriri naqshidan farqli):
--       hr_editor LAVOZIMga bog'langan edi ("HR lavozimidagi HAR KIM"), bu
--       esa SHAXSGA beriladigan ruxsat — brief aynan shunday aytadi:
--       "admin HAR USERGA beradi", "masalan CEO ga ochaman". Lavozimga bog'lash
--       bitta CEO ga ruxsat berish uchun butun lavozimni ochib yuborardi.
--    ⚠️ Ruxsat WORKSPACE bo'yicha: odam ikki workspace'da bo'lsa, biriga
--       ochilib ikkinchisida yopiq qolishi mumkin (qator har ws uchun alohida).
-- ════════════════════════════════════════════════════════════════════════════
ALTER TABLE public.workspace_members
  ADD COLUMN IF NOT EXISTS can_view_others_planner boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.workspace_members.can_view_others_planner IS
  'true → bu a''zo SHU workspace''dagi boshqa a''zolarning rejasini (tasks.plan_*) ko''ra oladi. Faqat owner/admin yoza oladi (wm_planner_flag_guard_trg). Default false.';


-- ════════════════════════════════════════════════════════════════════════════
-- 4) can_view_planner() — YAGONA ruxsat nuqtasi
--    🔴 SECURITY DEFINER: workspace_members ni RLS'siz o'qiydi → policy
--       zanjirida rekursiya (42P17) yuzaga kelmaydi va CLAUDE.md 8-qoidasi
--       buzilmaydi (inline subquery policy ICHIDA emas, funksiya ichida).
-- ════════════════════════════════════════════════════════════════════════════
-- Eski, boshqa imzoli nusxa qolgan bo'lsa — tozalanadi.
-- ⚠️ Biror policy o'sha nusxaga bog'liq bo'lsa DROP xato beradi va butun
--    tranzaksiya qaytadi (jimgina buzilmaydi).
DO $drop$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid, pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='can_view_planner'
  LOOP
    IF lower(btrim(r.args)) IS DISTINCT FROM 'p_ws uuid, p_target uuid, p_user uuid' THEN
      RAISE NOTICE 'Eski imzo o''chirilmoqda: can_view_planner(%)', r.args;
      EXECUTE format('DROP FUNCTION public.can_view_planner(%s)', r.args);
    END IF;
  END LOOP;
END $drop$;

CREATE OR REPLACE FUNCTION public.can_view_planner(p_ws uuid, p_target uuid, p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $body$
  -- 🔴 `p_user = (SELECT auth.uid())` — MAJBURIY QATOR, OLIB TASHLAMANG.
  --    Funksiya `authenticated` ga EXECUTE bilan ochiq, ya'ni uni PostgREST
  --    orqali TO'G'RIDAN-TO'G'RI chaqirish mumkin:
  --        POST /rest/v1/rpc/can_view_planner {p_ws, p_target, p_user}
  --    Bu qatorsiz istalgan foydalanuvchi ixtiyoriy p_user yuborib,
  --    "falon odam falon workspace'da boshqalarning rejasini ko'radimi?"
  --    savoliga javob ola olardi (SECURITY DEFINER RLS'ni chetlab o'tadi).
  --    Policy doim (SELECT auth.uid()) uzatgani uchun bu shart RLS ishiga
  --    umuman ta'sir qilmaydi.
  SELECT p_ws   IS NOT NULL
     AND p_user IS NOT NULL
     AND p_user = (SELECT auth.uid())
     AND (
           -- 1) o'zini DOIM ko'radi
           p_target = p_user
           -- 2) owner/admin doim ko'radi
        OR public.is_ws_manager(p_ws, p_user)
           -- 3) ruxsat berilgan a'zo — ikkovi ham SHU ws a'zosi bo'lishi shart
        OR ( p_target IS NOT NULL
             AND public.is_ws_member(p_ws, p_user)
             AND public.is_ws_member(p_ws, p_target)
             AND EXISTS (
                   SELECT 1 FROM public.workspace_members wm
                    WHERE wm.workspace_id = p_ws
                      AND wm.user_id      = p_user
                      AND wm.can_view_others_planner
                 ) )
     );
$body$;

COMMENT ON FUNCTION public.can_view_planner(uuid, uuid, uuid) IS
  'p_user p_target ning rejasini (tasks.plan_*) ko''ra oladimi? o''zi / owner-admin / can_view_others_planner bayrog''i. SECURITY DEFINER — workspace_members ni RLS''siz o''qiydi (42P17 rekursiya bo''lmasin). Tanasida p_user = auth.uid() qorovuli MAJBURIY.';

-- 🔴 REVOKE ... FROM PUBLIC YETARLI EMAS: Supabase'da
--    `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO
--     anon, authenticated` o'rnatilgan bo'lishi mumkin — u holda YANGI
--    funksiya `anon` ga TO'G'RIDAN grant oladi va PUBLIC dan REVOKE unga
--    ta'sir qilmaydi. Shuning uchun aniq `FROM anon` REVOKE qilinadi
--    (busiz pastdagi tekshiruv otilib butun skript qaytarilardi).
REVOKE ALL ON FUNCTION public.can_view_planner(uuid, uuid, uuid) FROM PUBLIC;
DO $grant$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.can_view_planner(uuid, uuid, uuid) FROM anon';
  END IF;
  EXECUTE 'REVOKE ALL ON FUNCTION public.can_view_planner(uuid, uuid, uuid) FROM authenticated';
  -- EXECUTE authenticated'ga SHART: RLS ifodasi CHAQIRUVCHI huquqi bilan
  -- baholanadi (can_see_project naqshi).
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.can_view_planner(uuid, uuid, uuid) TO authenticated';
END $grant$;


-- ════════════════════════════════════════════════════════════════════════════
-- 5) 🔴 BAYROQ QOROVULI — trigger (policy EMAS)
--    NEGA POLICY YETMAYDI: PERMISSIVE policy'lar OR bilan birlashadi. Agar
--    workspace_members da "a'zo O'Z qatorini yangilay oladi" degan MAVJUD
--    policy bo'lsa (odatiy naqsh), yangi PERMISSIVE policy uni TORAYTIRA
--    OLMAYDI — oddiy a'zo o'ziga bayroqni QO'YIB OLARDI. RESTRICTIVE policy
--    qo'shish esa mavjud yozuv oqimlarini (rol, a'zolik) buzish xavfi.
--    Ustun darajasidagi GRANT ham mo'rt (ustunlar ro'yxati vaqt bilan o'zgaradi).
--    Yagona to'g'ri, ADDITIV va aniq nishonli yechim — BEFORE trigger:
--    u FAQAT shu bayroq o'zgarganda ishlaydi, boshqa hech narsaga tegmaydi.
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.wm_planner_flag_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $body$
DECLARE
  v_uid     uuid;
  v_ws      uuid;
  v_changed boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Yangi a'zo `false` bilan qo'shilsa — hech qanday tekshiruv kerak emas
    -- (taklifni qabul qilish oqimi buzilmasin). Faqat DARROV `true` bilan
    -- qo'shishga urinish tekshiriladi.
    v_changed := coalesce(NEW.can_view_others_planner, false);
    v_ws      := NEW.workspace_id;
  ELSE
    v_changed := coalesce(NEW.can_view_others_planner, false)
                 IS DISTINCT FROM coalesce(OLD.can_view_others_planner, false);
    v_ws      := coalesce(OLD.workspace_id, NEW.workspace_id);
  END IF;

  IF NOT v_changed THEN
    RETURN NEW;   -- 🔴 bayroq tegilmagan → trigger MUTLAQO aralashmaydi
  END IF;

  v_uid := (SELECT auth.uid());

  -- Server tomoni (service_role / SQL Editor / EF): JWT yo'q → to'sib
  -- bo'lmaydi va to'sish kerak ham emas (u allaqachon to'liq huquqli).
  IF v_uid IS NULL THEN
    RETURN NEW;
  END IF;
  IF current_user IN ('postgres', 'supabase_admin', 'service_role') THEN
    RETURN NEW;
  END IF;

  IF public.is_ws_manager(v_ws, v_uid) THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Rejalashtirgich ruxsatini (can_view_others_planner) faqat workspace egasi yoki admini o''zgartira oladi.'
    USING ERRCODE = '42501';
END
$body$;

COMMENT ON FUNCTION public.wm_planner_flag_guard() IS
  'workspace_members.can_view_others_planner ni faqat owner/admin o''zgartira olsin. Bayroq tegilmagan yozuvlarga UMUMAN aralashmaydi.';

DROP TRIGGER IF EXISTS wm_planner_flag_guard_trg ON public.workspace_members;
CREATE TRIGGER wm_planner_flag_guard_trg
  BEFORE INSERT OR UPDATE ON public.workspace_members
  FOR EACH ROW EXECUTE FUNCTION public.wm_planner_flag_guard();


-- ════════════════════════════════════════════════════════════════════════════
-- 6) GRANT — yangi ustunlar mijozga ko'rinsin/yozilsin
--    ⚠️ Supabase odatda `authenticated` ga JADVAL darajasida to'liq huquq
--    beradi — u holda yangi ustunlar avtomatik qamrab olinadi va bu bo'lim
--    hech narsa qilmaydi. Lekin agar kimdir USTUN darajasida grant yozgan
--    bo'lsa (GRANT SELECT(col1,col2) …), YANGI ustun ro'yxatga KIRMAYDI va
--    mijoz "column does not exist" emas, "permission denied" oladi — sabab
--    tushunarsiz bo'lardi. Shuning uchun kerak bo'lsagina aniq grant beramiz.
-- ════════════════════════════════════════════════════════════════════════════
DO $cols$
BEGIN
  IF NOT has_column_privilege('authenticated', 'public.tasks', 'plan_date', 'SELECT') THEN
    EXECUTE 'GRANT SELECT (plan_date, plan_start, plan_end) ON public.tasks TO authenticated';
    RAISE NOTICE 'GRANT SELECT(plan_*) ON tasks TO authenticated — ustun darajasidagi grant aniqlandi';
  END IF;
  IF NOT has_column_privilege('authenticated', 'public.tasks', 'plan_date', 'UPDATE') THEN
    EXECUTE 'GRANT UPDATE (plan_date, plan_start, plan_end) ON public.tasks TO authenticated';
    RAISE NOTICE 'GRANT UPDATE(plan_*) ON tasks TO authenticated — ustun darajasidagi grant aniqlandi';
  END IF;
  IF NOT has_column_privilege('authenticated', 'public.tasks', 'plan_date', 'INSERT') THEN
    EXECUTE 'GRANT INSERT (plan_date, plan_start, plan_end) ON public.tasks TO authenticated';
    RAISE NOTICE 'GRANT INSERT(plan_*) ON tasks TO authenticated — ustun darajasidagi grant aniqlandi';
  END IF;
  IF NOT has_column_privilege('authenticated', 'public.workspace_members', 'can_view_others_planner', 'SELECT') THEN
    EXECUTE 'GRANT SELECT (can_view_others_planner) ON public.workspace_members TO authenticated';
    RAISE NOTICE 'GRANT SELECT(can_view_others_planner) — ustun darajasidagi grant aniqlandi';
  END IF;
  IF NOT has_column_privilege('authenticated', 'public.workspace_members', 'can_view_others_planner', 'UPDATE') THEN
    EXECUTE 'GRANT UPDATE (can_view_others_planner) ON public.workspace_members TO authenticated';
    RAISE NOTICE 'GRANT UPDATE(can_view_others_planner) — ustun darajasidagi grant aniqlandi';
  END IF;
END $cols$;


-- ── O'lchov/natija jadvallari ───────────────────────────────────────────────
--    ⚠️ TRANZAKSIYA ICHIDA yaratiladi: skript yiqilsa ular ham qaytadi va
--       oxiridagi SELECT'lar bajarilmaydi. Xato holatida hamma raqam
--       "Messages" bo'limidagi NOTICE/EXCEPTION matnida bo'ladi.
DROP TABLE IF EXISTS pg_temp.pln_u;
CREATE TEMP TABLE pg_temp.pln_u (
  uid    uuid PRIMARY KEY,
  turi   text   NOT NULL,               -- 'menejer' | 'ruxsatli' | 'nazorat'
  s_ids  text[] NOT NULL DEFAULT '{}',  -- yangi policy OCHADIGAN vazifa id'lari
  s_n    bigint NOT NULL DEFAULT 0,     -- shu to'plamning HAQIQIY hajmi
  s_cut  boolean NOT NULL DEFAULT false,-- to'plam kesilganmi (juda katta)
  o_ids  text[] NOT NULL DEFAULT '{}',  -- BOSHQALARNING rejali vazifalari (sizish testi)
  o_n    bigint NOT NULL DEFAULT 0
);
DROP TABLE IF EXISTS pg_temp.pln_snap;
CREATE TEMP TABLE pg_temp.pln_snap (
  faza text, uid uuid,
  n_tsk bigint,   -- ko'rinadigan JAMI vazifa
  n_s   bigint,   -- ulardan s_ids ichidagilari
  n_o   bigint,   -- ulardan o_ids ichidagilari
  n_wm  bigint    -- ko'rinadigan workspace_members qatori (o'zgarmasligi shart)
);
DROP TABLE IF EXISTS pg_temp.pln_res;
CREATE TEMP TABLE pg_temp.pln_res (ord int, bosqich text, nom text, qiymat text, izoh text);

SET LOCAL search_path = public, extensions;


-- ════════════════════════════════════════════════════════════════════════════
-- 7) ASOSIY BLOK — o'lchov → policy → o'lchov → tirik sinov → tekshiruv
-- ════════════════════════════════════════════════════════════════════════════
DO $main$
DECLARE
  -- ══════════ SOZLAMALAR ══════════
  -- ⚠️ Har namunaviy foydalanuvchi uchun 4 ta to'liq sanoq bajariladi va
  --    ular `tasks` ni RLS bilan skanerlaydi (RLS ifodasi har qatorda
  --    is_ws_member chaqiradi). Skript sekin ishlasa AVVAL SHU IKKI SONNI
  --    kamaytiring — tekshiruv mantiqi o'zgarmaydi, faqat namuna kichrayadi.
  v_max_mgr  CONSTANT int := 5;     -- namunaga olinadigan menejer soni
  v_max_mem  CONSTANT int := 10;    -- har toifadan oddiy a'zo soni
  v_max_ids  CONSTANT int := 5000;  -- bitta foydalanuvchi uchun id massivi chegarasi

  u             RECORD;
  v_n           bigint;
  v_i           int;
  v_txt         text;
  v_src         text;
  v_qual        text;
  v_tsk_rls     boolean;
  v_wm_rls      boolean;
  v_tsk_sel     int;
  v_restr       int;
  v_restr_note  text := '';
  v_pol_added   boolean := false;
  v_pol_reason  text;
  v_wmpol_added boolean := false;
  v_wmpol_note  text;
  v_c_tsk       bigint;
  v_c_s         bigint;
  v_c_o         bigint;
  v_c_wm        bigint;
  v_exp         bigint;
  v_gain        bigint := 0;

  -- tirik sinov uchun
  v_imp_ok      boolean := false;   -- impersonatsiya (jwt) harnessi ishlayaptimi
  v_ws          uuid;
  v_mgr         uuid;
  v_m1          uuid;
  v_m2          uuid;
  v_ws2         uuid;
  v_x2          uuid;
  v_probe       text;
  v_t_self      text := 'o''tkazib yuborildi';
  v_t_mgr       text := 'o''tkazib yuborildi';
  v_t_deny      text := 'o''tkazib yuborildi';
  v_t_flag      text := 'o''tkazib yuborildi';
  v_t_imp       text := 'o''tkazib yuborildi';
  v_t_xws       text := 'o''tkazib yuborildi';
  v_t_wr_mem    text := 'o''tkazib yuborildi';
  v_t_wr_mgr    text := 'o''tkazib yuborildi';
  v_t_upd       text := 'o''tkazib yuborildi';
  v_task_id     text;
BEGIN

-- ══════════════════════════════════════════════════════════════════════════
-- 7.1) Holat: RLS, policy'lar
-- ══════════════════════════════════════════════════════════════════════════
SELECT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                WHERE n.nspname='public' AND c.relname='tasks' AND c.relrowsecurity) INTO v_tsk_rls;
SELECT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                WHERE n.nspname='public' AND c.relname='workspace_members' AND c.relrowsecurity) INTO v_wm_rls;
SELECT count(*) INTO v_tsk_sel FROM pg_policies
 WHERE schemaname='public' AND tablename='tasks' AND permissive='PERMISSIVE' AND cmd IN ('SELECT','ALL');
SELECT count(*) INTO v_restr FROM pg_policies
 WHERE schemaname='public' AND tablename IN ('tasks','workspace_members') AND permissive='RESTRICTIVE';
IF v_restr > 0 THEN
  v_restr_note := ' ⚠️ DIQQAT: bu jadvallarda ' || v_restr || ' ta RESTRICTIVE policy bor — ular AND bilan qo''llanadi va yangi PERMISSIVE policy ularni yenga olmaydi.';
  RAISE WARNING '%', v_restr_note;
END IF;

-- ══════════════════════════════════════════════════════════════════════════
-- 7.2) NAMUNA — kim qaysi toifada
--    🔴 Toifa `is_ws_manager()` orqali aniqlanadi, `role` USTUNI orqali emas:
--       ustun nomi/qiymatlari bu repoda kafolatlanmagan, funksiya esa butun
--       ilovaning yagona haqiqat manbai.
--    ⚠️ "menejer" va "ruxsatli" shartlari KESILGAN namunaga emas, HAQIQIY
--       ma'lumotga qaraydi — aks holda LIMIT dan tashqarida qolgan menejer
--       "nazorat" deb belgilanib, tekshiruv SOXTA "XAVFSIZLIK BUZILDI" bilan
--       yiqilardi (TASKFIX_LOYIHA_RLS.sql saboqi).
-- ══════════════════════════════════════════════════════════════════════════
INSERT INTO pg_temp.pln_u (uid, turi)
SELECT DISTINCT wm.user_id, 'menejer'
  FROM public.workspace_members wm
 WHERE public.is_ws_manager(wm.workspace_id, wm.user_id)
 ORDER BY wm.user_id
 LIMIT v_max_mgr;

INSERT INTO pg_temp.pln_u (uid, turi)
SELECT DISTINCT wm.user_id, 'ruxsatli'
  FROM public.workspace_members wm
 WHERE coalesce(wm.can_view_others_planner, false)
   AND NOT EXISTS (SELECT 1 FROM public.workspace_members w2
                    WHERE w2.user_id = wm.user_id
                      AND public.is_ws_manager(w2.workspace_id, w2.user_id))
   AND NOT EXISTS (SELECT 1 FROM pg_temp.pln_u a WHERE a.uid = wm.user_id)
 ORDER BY wm.user_id
 LIMIT v_max_mem;

INSERT INTO pg_temp.pln_u (uid, turi)
SELECT DISTINCT wm.user_id, 'nazorat'
  FROM public.workspace_members wm
 WHERE NOT EXISTS (SELECT 1 FROM public.workspace_members w2
                    WHERE w2.user_id = wm.user_id
                      AND public.is_ws_manager(w2.workspace_id, w2.user_id))
   AND NOT EXISTS (SELECT 1 FROM public.workspace_members w3
                    WHERE w3.user_id = wm.user_id
                      AND coalesce(w3.can_view_others_planner, false))
   AND NOT EXISTS (SELECT 1 FROM pg_temp.pln_u a WHERE a.uid = wm.user_id)
 ORDER BY wm.user_id
 LIMIT v_max_mem;

-- Har foydalanuvchi uchun: yangi policy AYNAN qaysi qatorlarni ochadi?
-- ⚠️ Bu yerda can_view_planner() CHAQIRILMAYDI — u auth.uid() ga bog'liq va
--    postgres roli ostida (JWT yo'q) doim false qaytaradi. Shuning uchun
--    mantiq QO'LDA ko'chirilgan; ikkalasi bir xilligini pastdagi "keyin"
--    o'lchovi TIRIK tasdiqlaydi (k_s = s_n bo'lishi shart).
UPDATE pg_temp.pln_u a
   SET s_n = (SELECT count(*) FROM public.tasks t
               WHERE t.plan_date IS NOT NULL
                 AND public.is_ws_member(t.workspace_id, a.uid)
                 AND ( t.assigned_to = a.uid
                       OR public.is_ws_manager(t.workspace_id, a.uid)
                       OR ( t.assigned_to IS NOT NULL
                            AND public.is_ws_member(t.workspace_id, t.assigned_to)
                            AND EXISTS (SELECT 1 FROM public.workspace_members wm
                                         WHERE wm.workspace_id = t.workspace_id
                                           AND wm.user_id = a.uid
                                           AND wm.can_view_others_planner) ) )),
       s_ids = coalesce((SELECT array_agg(q.id) FROM (
                 SELECT t.id::text AS id FROM public.tasks t
                  WHERE t.plan_date IS NOT NULL
                    AND public.is_ws_member(t.workspace_id, a.uid)
                    AND ( t.assigned_to = a.uid
                          OR public.is_ws_manager(t.workspace_id, a.uid)
                          OR ( t.assigned_to IS NOT NULL
                               AND public.is_ws_member(t.workspace_id, t.assigned_to)
                               AND EXISTS (SELECT 1 FROM public.workspace_members wm
                                            WHERE wm.workspace_id = t.workspace_id
                                              AND wm.user_id = a.uid
                                              AND wm.can_view_others_planner) ) )
                  ORDER BY t.id LIMIT v_max_ids) q), '{}'::text[]),
       -- Sizish testi uchun: BOSHQA odamning rejali vazifalari (o'sha ws da)
       o_n = (SELECT count(*) FROM public.tasks t
               WHERE t.plan_date IS NOT NULL
                 AND t.assigned_to IS DISTINCT FROM a.uid
                 AND public.is_ws_member(t.workspace_id, a.uid)),
       o_ids = coalesce((SELECT array_agg(q.id) FROM (
                 SELECT t.id::text AS id FROM public.tasks t
                  WHERE t.plan_date IS NOT NULL
                    AND t.assigned_to IS DISTINCT FROM a.uid
                    AND public.is_ws_member(t.workspace_id, a.uid)
                  ORDER BY t.id LIMIT v_max_ids) q), '{}'::text[]);

UPDATE pg_temp.pln_u SET s_cut = (s_n > v_max_ids);

SELECT count(*) INTO v_n FROM pg_temp.pln_u;
RAISE NOTICE 'Namuna: % ta foydalanuvchi (% menejer / % ruxsatli / % nazorat)',
  v_n,
  (SELECT count(*) FROM pg_temp.pln_u WHERE turi='menejer'),
  (SELECT count(*) FROM pg_temp.pln_u WHERE turi='ruxsatli'),
  (SELECT count(*) FROM pg_temp.pln_u WHERE turi='nazorat');

SELECT count(*) INTO v_n FROM public.tasks WHERE plan_date IS NOT NULL;
IF v_n = 0 THEN
  RAISE NOTICE 'ℹ️ Bazada hali BITTA ham rejali vazifa yo''q (plan_date hammasida NULL) — bu BIRINCHI RUN uchun normal. Sanoq o''lchovi bo''sh chiqadi, lekin pastdagi TIRIK sinovlar (can_view_planner semantikasi, bayroq qorovuli) to''liq bajariladi.';
END IF;

-- ══════════════════════════════════════════════════════════════════════════
-- 7.3) SNAPSHOT — OLDIN (authenticated roli ostida, HAQIQIY RLS bilan)
--    ⚠️ Sanoqlar avval O'ZGARUVCHIGA yig'iladi, temp jadvalga esa FAQAT
--       `RESET ROLE` dan KEYIN yoziladi: `authenticated` ostida temp jadvalga
--       yozish huquqi yo'q (TASKFIX_SCALE / LOYIHA_RLS naqshi).
--    🔴 Har impersonatsiyadan keyin `request.jwt.claims` TOZALANADI — aks
--       holda keyingi postgres-tomon buyruqlarida auth.uid() hamon o'sha
--       odamni qaytarib, bayroq trigger'i noto'g'ri ishga tushardi.
-- ══════════════════════════════════════════════════════════════════════════
FOR u IN SELECT * FROM pg_temp.pln_u ORDER BY uid LOOP
  BEGIN
    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', u.uid::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    EXECUTE 'SELECT count(*) FROM public.tasks' INTO v_c_tsk;
    EXECUTE 'SELECT count(*) FROM public.tasks WHERE id::text = ANY ($1)' INTO v_c_s USING u.s_ids;
    EXECUTE 'SELECT count(*) FROM public.tasks WHERE id::text = ANY ($1)' INTO v_c_o USING u.o_ids;
    EXECUTE 'SELECT count(*) FROM public.workspace_members' INTO v_c_wm;

    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO pg_temp.pln_snap (faza, uid, n_tsk, n_s, n_o, n_wm)
    VALUES ('oldin', u.uid, v_c_tsk, v_c_s, v_c_o, v_c_wm);
  EXCEPTION WHEN OTHERS THEN
    BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM set_config('request.jwt.claims', '', true);
    IF SQLSTATE = '42P17' THEN
      RAISE EXCEPTION 'REKURSIYA (42P17) O''ZGARISHDAN OLDIN ham bor edi: %. Bu skript sababi EMAS — mavjud policy''lardagi halqani avval tuzating.', SQLERRM;
    END IF;
    RAISE EXCEPTION 'OLDIN-snapshot xatosi (% / %): %', u.uid, SQLSTATE, SQLERRM;
  END;
END LOOP;
RAISE NOTICE 'OLDIN-snapshot olindi (% ta foydalanuvchi)', (SELECT count(*) FROM pg_temp.pln_snap WHERE faza='oldin');

-- ══════════════════════════════════════════════════════════════════════════
-- 7.4) POLICY: tasks — boshqaning REJA bloklari ko'rinsin
--    🔴 `is_ws_member(workspace_id, auth.uid())` policy ICHIDA ham bor:
--       can_view_planner ning "o'zini doim ko'radi" shoxi a'zolikni
--       tekshirmaydi (spec shunday), ya'ni jamoadan CHIQARILGAN xodim
--       (rmxDoRemove faqat workspace_members dan chiqaradi, tasks.assigned_to
--       o'sha uid'da QOLADI) o'z eski rejali vazifalarini ko'rib turardi.
--       Bu qator o'sha teshikni yopadi.
-- ══════════════════════════════════════════════════════════════════════════
IF NOT v_tsk_rls THEN
  v_pol_reason := 'public.tasks da RLS O''CHIQ — policy baholanmaydi, qo''shish soxta xavfsizlik tuyg''usi berardi';
  RAISE WARNING '%', v_pol_reason;
ELSIF v_tsk_sel = 0 THEN
  v_pol_reason := 'public.tasks da PERMISSIVE SELECT policy UMUMAN YO''Q — yolg''iz "planner" policy''si asosiy ko''rish qoidasi o''rnini bosib qolardi. Avval asosiy tasks SELECT policy''sini tiklang.';
  RAISE WARNING '%', v_pol_reason;
ELSE
  DROP POLICY IF EXISTS tasks_select_planner_shared ON public.tasks;
  EXECUTE $p$
    CREATE POLICY tasks_select_planner_shared ON public.tasks
      FOR SELECT TO authenticated
      USING ( plan_date IS NOT NULL
              AND is_ws_member(workspace_id, (SELECT auth.uid()))
              AND can_view_planner(workspace_id, assigned_to, (SELECT auth.uid())) )
  $p$;
  v_pol_added  := true;
  v_pol_reason := 'is_ws_member + can_view_planner, faqat plan_date IS NOT NULL qatorlar';
  RAISE NOTICE '✅ tasks_select_planner_shared policy qo''shildi';
END IF;

-- ══════════════════════════════════════════════════════════════════════════
-- 7.5) SNAPSHOT — KEYIN (aynan shu so'rovlar, aynan shu foydalanuvchilar)
--    Bu ayni paytda REKURSIYA (42P17) testi hamdir.
-- ══════════════════════════════════════════════════════════════════════════
FOR u IN SELECT * FROM pg_temp.pln_u ORDER BY uid LOOP
  BEGIN
    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', u.uid::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    EXECUTE 'SELECT count(*) FROM public.tasks' INTO v_c_tsk;
    EXECUTE 'SELECT count(*) FROM public.tasks WHERE id::text = ANY ($1)' INTO v_c_s USING u.s_ids;
    EXECUTE 'SELECT count(*) FROM public.tasks WHERE id::text = ANY ($1)' INTO v_c_o USING u.o_ids;
    EXECUTE 'SELECT count(*) FROM public.workspace_members' INTO v_c_wm;

    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO pg_temp.pln_snap (faza, uid, n_tsk, n_s, n_o, n_wm)
    VALUES ('keyin', u.uid, v_c_tsk, v_c_s, v_c_o, v_c_wm);
  EXCEPTION WHEN OTHERS THEN
    BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM set_config('request.jwt.claims', '', true);
    IF SQLSTATE = '42P17' THEN
      RAISE EXCEPTION 'REKURSIYA (42P17) YANGI POLICY SABABLI: %. Demak can_view_planner() SECURITY DEFINER bo''lishiga qaramay workspace_members RLS''i baholanyapti (funksiya egasi jadval egasi emas / FORCE ROW LEVEL SECURITY yoqilgan). HAMMASI QAYTARILDI.', SQLERRM;
    END IF;
    RAISE EXCEPTION 'KEYIN-snapshot xatosi (% / %): % — HAMMASI QAYTARILDI', u.uid, SQLSTATE, SQLERRM;
  END;
END LOOP;

-- ══════════════════════════════════════════════════════════════════════════
-- 7.6) 🔴 XAVFSIZLIK TEKSHIRUVI — kutilgan sondan bitta ham farq bo'lmasin
--    Kutilgan = oldingi_jami − oldin_ko'ringan_S + S_hajmi
--    (S = yangi policy ochadigan to'plam). Yangi policy PERMISSIVE bo'lgani
--    uchun son KAMAYA OLMAYDI; o'sish esa FAQAT S ichida bo'lishi shart.
-- ══════════════════════════════════════════════════════════════════════════
FOR u IN
  SELECT a.uid, a.turi, a.s_n, a.s_cut, a.o_n, cardinality(a.s_ids) AS s_len,
         o.n_tsk AS o_tsk, o.n_s AS o_s, o.n_o AS o_o, o.n_wm AS o_wm,
         k.n_tsk AS k_tsk, k.n_s AS k_s, k.n_o AS k_o, k.n_wm AS k_wm
    FROM pg_temp.pln_u a
    JOIN pg_temp.pln_snap o ON o.uid = a.uid AND o.faza='oldin'
    JOIN pg_temp.pln_snap k ON k.uid = a.uid AND k.faza='keyin'
   ORDER BY a.uid
LOOP
  -- (a) KAMAYISH — hech qachon bo'lmasligi kerak (PERMISSIVE qo'shildi)
  IF u.k_tsk < u.o_tsk THEN
    RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (tasks KAMAYDI): foydalanuvchi % — oldin %, keyin %. PERMISSIVE policy kirish huquqini TORAYTIRA OLMAYDI, demak boshqa nimadir buzilgan.% HAMMASI QAYTARILDI.',
      u.uid, u.o_tsk, u.k_tsk, v_restr_note;
  END IF;

  -- (b) ANIQ SON — to'plam kesilmagan bo'lsa
  IF NOT u.s_cut THEN
    v_exp := CASE WHEN v_pol_added THEN u.o_tsk - u.o_s + u.s_len ELSE u.o_tsk END;
    IF u.k_tsk IS DISTINCT FROM v_exp THEN
      RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (tasks): foydalanuvchi % (%) — oldin %, kutilgan %, keyin %. Yangi policy ochishi kerak bo''lgan to''plam: % ta (oldin ko''ringani %). KUTILMAGAN O''SISH — policy ortiqcha qator ochdi.% HAMMASI QAYTARILDI.',
        u.uid, u.turi, u.o_tsk, v_exp, u.k_tsk, u.s_len, u.o_s, v_restr_note;
    END IF;
    IF v_pol_added AND u.k_s IS DISTINCT FROM u.s_len THEN
      RAISE EXCEPTION 'TEKSHIRUV (tasks): foydalanuvchi % o''ziga ochilishi kerak bo''lgan % ta rejali vazifadan atigi % tasini ko''rmoqda — policy KUTILGANDAY ISHLAMADI (can_view_planner mantiqi bilan o''lchov mantiqi mos kelmadi).% HAMMASI QAYTARILDI.',
        u.uid, u.s_len, u.k_s, v_restr_note;
    END IF;
  ELSE
    RAISE NOTICE 'ℹ️ % : to''plam % ta (chegara % dan katta) — aniq formula o''tkazib yuborildi, faqat "kamaymadi" tekshirildi.', u.uid, u.s_n, v_max_ids;
  END IF;

  -- (c) SIZISH — "nazorat" (menejer emas, bayroq yo'q) foydalanuvchiga
  --     BOSHQA odamning rejali vazifasi QO'SHIMCHA ochilmasligi SHART.
  IF u.turi = 'nazorat' AND u.k_o IS DISTINCT FROM u.o_o THEN
    RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (SIZISH): ruxsatsiz foydalanuvchi % ga boshqa odamlarning rejali vazifalari ochildi (% → %). Bu foydalanuvchi na menejer, na can_view_others_planner egasi. HAMMASI QAYTARILDI.',
      u.uid, u.o_o, u.k_o;
  END IF;

  -- (d) workspace_members ko'rinishi O'ZGARMASLIGI shart (biz unga SELECT
  --     policy qo'shmadik — faqat ustun va trigger).
  IF u.k_wm IS DISTINCT FROM u.o_wm THEN
    RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (workspace_members): foydalanuvchi % uchun ko''rinadigan a''zolik qatori % → % ga o''zgardi. Bu skript wm SELECT huquqiga TEGMASLIGI kerak edi. HAMMASI QAYTARILDI.',
      u.uid, u.o_wm, u.k_wm;
  END IF;

  v_gain := v_gain + (u.k_tsk - u.o_tsk);
END LOOP;

RAISE NOTICE '✅ XAVFSIZLIK (sanoq): barcha sanoqlar kutilganday. Yangi ko''ringan jami: % ta vazifa qatori (faqat reja bloklari).', v_gain;

-- ══════════════════════════════════════════════════════════════════════════
-- 7.7) TIRIK SINOV — can_view_planner() semantikasi va bayroq qorovuli
--    🔴 Sanoq o'lchovi birinchi RUN da bo'sh chiqadi (hali reja yo'q), shuning
--       uchun ASOSIY kafolat aynan shu bo'lim.
--    ⚠️ Har sinov SENTINEL-ROLLBACK bilan: yozuv qiladigan sinovlar ichki
--       blokda ataylab EXCEPTION bilan tugatiladi → subtranzaksiya qaytadi va
--       bazada BITTA qator ham o'zgarmaydi.
-- ══════════════════════════════════════════════════════════════════════════
-- (0) Harness sanity: set_config('request.jwt.claims') haqiqatan auth.uid()
--     ga ta'sir qiladimi? (Eski auth.uid() 'request.jwt.claim.sub' ni o'qishi
--     mumkin — u holda impersonatsiya ISHLAMAYDI va sinovlar SOXTA "true"
--     bermasligi uchun umuman o'tkazib yuboriladi.)
SELECT uid INTO v_m1 FROM pg_temp.pln_u ORDER BY uid LIMIT 1;
IF v_m1 IS NOT NULL THEN
  BEGIN
    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', v_m1::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE 'SELECT (SELECT auth.uid())::text' INTO v_txt;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    v_imp_ok := (v_txt IS NOT DISTINCT FROM v_m1::text);
  EXCEPTION WHEN OTHERS THEN
    BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM set_config('request.jwt.claims', '', true);
    v_imp_ok := false;
  END;
END IF;
IF NOT v_imp_ok THEN
  RAISE WARNING '⚠️ Impersonatsiya harnessi ishlamadi (auth.uid() request.jwt.claims dan o''qimayapti) — TIRIK sinovlar o''tkazib yuborildi. Struktura tekshiruvlari (funksiya tanasi, grant, trigger, policy) baribir bajariladi. Modulni prodga chiqarishdan oldin QO''LDA sinang: oddiy a''zo boshqa xodim rejasini KO''RMASLIGI va bayroqni QO''YA OLMASLIGI shart.';
END IF;
v_m1 := NULL;

-- Sinov uchun (ws, menejer, a'zo1, a'zo2) to'rtligini topamiz.
-- ⚠️ BOSQICHMA-BOSQICH, uch tomonlama JOIN bilan EMAS: `wa × wb × wc` dekart
--    ko'paytmasi 126 a'zoli workspace'da ~2 million qator bo'lib, har qatorda
--    is_ws_manager() chaqirilardi (skript daqiqalab qotib qolardi).
IF v_imp_ok THEN
  SELECT wa.workspace_id, wa.user_id INTO v_ws, v_mgr
    FROM public.workspace_members wa
   WHERE public.is_ws_manager(wa.workspace_id, wa.user_id)
     AND EXISTS (SELECT 1 FROM public.workspace_members wb
                  WHERE wb.workspace_id = wa.workspace_id
                    AND wb.user_id <> wa.user_id
                    AND NOT public.is_ws_manager(wb.workspace_id, wb.user_id))
   ORDER BY wa.workspace_id, wa.user_id
   LIMIT 1;

  IF v_ws IS NOT NULL THEN
    -- a'zo1: oddiy a'zo, bayrog'i O'CHIQ (3-sinov aynan shunga tayanadi)
    SELECT wb.user_id INTO v_m1
      FROM public.workspace_members wb
     WHERE wb.workspace_id = v_ws
       AND wb.user_id <> v_mgr
       AND NOT coalesce(wb.can_view_others_planner, false)
       AND NOT public.is_ws_manager(v_ws, wb.user_id)
     ORDER BY wb.user_id LIMIT 1;

    -- a'zo2: "boshqa odam" roli — u ham oddiy a'zo bo'lsin
    SELECT wc.user_id INTO v_m2
      FROM public.workspace_members wc
     WHERE wc.workspace_id = v_ws
       AND wc.user_id <> v_mgr
       AND wc.user_id IS DISTINCT FROM v_m1
       AND NOT public.is_ws_manager(v_ws, wc.user_id)
     ORDER BY wc.user_id LIMIT 1;

    IF v_m1 IS NULL OR v_m2 IS NULL THEN
      v_ws := NULL;   -- to'liq to'rtlik yig'ilmadi
    END IF;
  END IF;

  IF v_ws IS NULL THEN
    RAISE NOTICE 'ℹ️ Sinov uchun (menejer + 2 ta bayroqsiz oddiy a''zo) bo''lgan workspace topilmadi — semantik sinovlar o''tkazib yuborildi. Bu XATO emas, lekin prodga chiqishdan oldin qo''lda sinang.';
  END IF;
END IF;

IF v_imp_ok AND v_ws IS NOT NULL THEN
  -- (1) O'ZINI DOIM ko'radi
  PERFORM set_config('request.jwt.claims',
           json_build_object('sub', v_m1::text, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT public.can_view_planner($1,$2,$3)::text' INTO v_txt USING v_ws, v_m1, v_m1;
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claims', '', true);
  IF v_txt IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'TIRIK SINOV YIQILDI (o''zini ko''rish): can_view_planner(ws, men, men) = % (kutilgan true). HAMMASI QAYTARILDI.', coalesce(v_txt,'NULL');
  END IF;
  v_t_self := '✅ true';

  -- (2) MENEJER a'zoning rejasini ko'radi
  PERFORM set_config('request.jwt.claims',
           json_build_object('sub', v_mgr::text, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT public.can_view_planner($1,$2,$3)::text' INTO v_txt USING v_ws, v_m1, v_mgr;
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claims', '', true);
  IF v_txt IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'TIRIK SINOV YIQILDI (menejer): can_view_planner(ws, a''zo, menejer) = % (kutilgan true) — owner/admin doim ko''rishi kerak. HAMMASI QAYTARILDI.', coalesce(v_txt,'NULL');
  END IF;
  v_t_mgr := '✅ true';

  -- (3) 🔴 RUXSATSIZ a'zo BOSHQANI KO'RMAYDI (eng muhim sinov)
  PERFORM set_config('request.jwt.claims',
           json_build_object('sub', v_m1::text, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT public.can_view_planner($1,$2,$3)::text' INTO v_txt USING v_ws, v_m2, v_m1;
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claims', '', true);
  IF v_txt IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (tirik sinov): ruxsatsiz a''zo uchun can_view_planner(ws, boshqa, men) = % (kutilgan false). HAMMASI QAYTARILDI.', coalesce(v_txt,'NULL');
  END IF;
  v_t_deny := '✅ false';

  -- (4) PostgREST qorovuli: p_user ≠ auth.uid() → DOIM false
  PERFORM set_config('request.jwt.claims',
           json_build_object('sub', v_m1::text, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT public.can_view_planner($1,$2,$3)::text' INTO v_txt USING v_ws, v_m2, v_mgr;
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claims', '', true);
  IF v_txt IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'XAVFSIZLIK BUZILDI: can_view_planner boshqa odam (p_user ≠ auth.uid()) haqida javob berdi = %. Funksiya tanasidagi `p_user = (SELECT auth.uid())` qorovuli buzilgan. HAMMASI QAYTARILDI.', coalesce(v_txt,'NULL');
  END IF;
  v_t_imp := '✅ false';

  -- (5) BAYROQ YOQILGANDA → true. Bayroq VAQTINCHA yoqiladi va
  --     sentinel-rollback bilan QAYTARILADI (bazada iz qolmaydi).
  BEGIN
    UPDATE public.workspace_members
       SET can_view_others_planner = true
     WHERE workspace_id = v_ws AND user_id = v_m1;

    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', v_m1::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE 'SELECT public.can_view_planner($1,$2,$3)::text' INTO v_txt USING v_ws, v_m2, v_m1;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);

    -- ⚠️ Sentinel: subtranzaksiyani ataylab qaytaramiz (yuqoridagi UPDATE
    --    yo'qoladi). Natija xato MATNIDA olib chiqiladi.
    RAISE EXCEPTION 'PLN_PROBE:flag:%', coalesce(v_txt,'NULL') USING ERRCODE = '22000';
  EXCEPTION WHEN OTHERS THEN
    BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM set_config('request.jwt.claims', '', true);
    IF SQLERRM LIKE 'PLN_PROBE:flag:%' THEN
      v_probe := replace(SQLERRM, 'PLN_PROBE:flag:', '');
      IF v_probe IS DISTINCT FROM 'true' THEN
        RAISE EXCEPTION 'TIRIK SINOV YIQILDI (bayroq): can_view_others_planner=true bo''lgan a''zo uchun can_view_planner = % (kutilgan true) — ruxsat berish ISHLAMAYDI. HAMMASI QAYTARILDI.', v_probe;
      END IF;
      v_t_flag := '✅ true';
    ELSE
      RAISE EXCEPTION 'Bayroq sinovi kutilmagan xato bilan tugadi (%): % — HAMMASI QAYTARILDI', SQLSTATE, SQLERRM;
    END IF;
  END;

  -- (6) 🔴 BOSHQA WORKSPACE ga sizmaydi (agar bunday ma'lumot bo'lsa)
  SELECT w2.workspace_id, w2.user_id INTO v_ws2, v_x2
    FROM public.workspace_members w2
   WHERE w2.workspace_id <> v_ws
     AND NOT EXISTS (SELECT 1 FROM public.workspace_members w3
                      WHERE w3.workspace_id = w2.workspace_id AND w3.user_id = v_m1)
   ORDER BY w2.workspace_id, w2.user_id
   LIMIT 1;
  IF v_ws2 IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', v_m1::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE 'SELECT public.can_view_planner($1,$2,$3)::text' INTO v_txt USING v_ws2, v_x2, v_m1;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    IF v_txt IS DISTINCT FROM 'false' THEN
      RAISE EXCEPTION 'XAVFSIZLIK BUZILDI: a''zo BO''LMAGAN workspace uchun can_view_planner = % (kutilgan false). HAMMASI QAYTARILDI.', coalesce(v_txt,'NULL');
    END IF;
    v_t_xws := '✅ false';
  END IF;

  -- (7) 🔴 ODDIY A'ZO BAYROQNI O'ZIGA QO'YA OLMAYDI
  BEGIN
    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', v_m1::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE 'UPDATE public.workspace_members SET can_view_others_planner = true
              WHERE workspace_id = $1 AND user_id = $2' USING v_ws, v_m1;
    GET DIAGNOSTICS v_i = ROW_COUNT;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RAISE EXCEPTION 'PLN_PROBE:wrmem:%', v_i USING ERRCODE = '22000';
  EXCEPTION WHEN OTHERS THEN
    BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM set_config('request.jwt.claims', '', true);
    IF SQLERRM LIKE 'PLN_PROBE:wrmem:%' THEN
      -- Sentinel'ga yetib keldi = trigger XATO OTMADI. Endi qator soni hal
      -- qiladi: >0 bo'lsa yozuv HAQIQATAN o'tgan (falokat), 0 bo'lsa RLS
      -- allaqachon to'sgan (qorovul ishlamadi, lekin sizish ham yo'q).
      v_i := replace(SQLERRM, 'PLN_PROBE:wrmem:', '')::int;
      IF v_i > 0 THEN
        RAISE EXCEPTION 'XAVFSIZLIK BUZILDI: oddiy a''zo can_view_others_planner ni O''ZIGA QO''YA OLDI (% qator yangilandi). wm_planner_flag_guard_trg ishlamadi. HAMMASI QAYTARILDI.', v_i;
      END IF;
      v_t_wr_mem := '✅ to''sildi (RLS, 0 qator)';
    ELSIF SQLSTATE = '42501' THEN
      v_t_wr_mem := '✅ to''sildi (42501)';
    ELSE
      -- RLS 0 qator qaytargan bo'lsa ham yozuv bo'lmagan — bu ham to'silish.
      v_t_wr_mem := '✅ to''sildi (' || SQLSTATE || ')';
    END IF;
  END;

  -- (8) MENEJER bayroqni qo'ya oladimi? (o'lchov — policy kerakmi degan savol)
  BEGIN
    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', v_mgr::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE 'UPDATE public.workspace_members SET can_view_others_planner = true
              WHERE workspace_id = $1 AND user_id = $2' USING v_ws, v_m1;
    GET DIAGNOSTICS v_i = ROW_COUNT;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RAISE EXCEPTION 'PLN_PROBE:wrmgr:%', v_i USING ERRCODE = '22000';
  EXCEPTION WHEN OTHERS THEN
    BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM set_config('request.jwt.claims', '', true);
    IF SQLERRM LIKE 'PLN_PROBE:wrmgr:%' THEN
      v_i := replace(SQLERRM, 'PLN_PROBE:wrmgr:', '')::int;
      v_t_wr_mgr := CASE WHEN v_i > 0 THEN '✅ ' || v_i || ' qator' ELSE '❗ 0 qator (RLS to''sdi)' END;
    ELSE
      v_t_wr_mgr := '❗ xato: ' || SQLSTATE;
    END IF;
  END;

  -- Menejer yoza olmasa — MAVJUD policy yetarli emas → ADDITIVE PERMISSIVE
  -- UPDATE policy qo'shamiz.
  -- ⚠️ Bu policy menejerga workspace_members ning BOSHQA ustunlarini ham
  --    yangilash yo'lini ochadi (RLS qator darajasida). Shuning uchun u
  --    FAQAT o'lchov "ishlamayapti" deganda qo'shiladi, taxmin bilan emas.
  IF v_t_wr_mgr LIKE '❗%' THEN
    IF NOT v_wm_rls THEN
      v_wmpol_note := 'workspace_members da RLS o''chiq — policy kerak emas, sabab boshqa (yuqoridagi xatoga qarang)';
      RAISE WARNING '%', v_wmpol_note;
    ELSE
      DROP POLICY IF EXISTS wm_update_manager_planner ON public.workspace_members;
      EXECUTE $wp$
        CREATE POLICY wm_update_manager_planner ON public.workspace_members
          FOR UPDATE TO authenticated
          USING ( is_ws_manager(workspace_id, (SELECT auth.uid())) )
          WITH CHECK ( is_ws_manager(workspace_id, (SELECT auth.uid())) )
      $wp$;
      v_wmpol_added := true;
      v_wmpol_note  := 'mavjud UPDATE policy menejerga yozishga ruxsat bermadi → additive PERMISSIVE policy qo''shildi';
      RAISE WARNING '⚠️ %. DIQQAT: bu policy owner/admin ga workspace_members qatorini yangilash yo''lini ochadi (faqat qator darajasida cheklab bo''ladi). Agar bu kerak bo''lmasa: DROP POLICY wm_update_manager_planner ON public.workspace_members; — u holda bayroqni faqat service_role/SQL orqali qo''yish mumkin bo''ladi.', v_wmpol_note;

      -- Qayta o'lchov: endi ishlayaptimi?
      BEGIN
        PERFORM set_config('request.jwt.claims',
                 json_build_object('sub', v_mgr::text, 'role', 'authenticated')::text, true);
        EXECUTE 'SET LOCAL ROLE authenticated';
        EXECUTE 'UPDATE public.workspace_members SET can_view_others_planner = true
                  WHERE workspace_id = $1 AND user_id = $2' USING v_ws, v_m1;
        GET DIAGNOSTICS v_i = ROW_COUNT;
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
        RAISE EXCEPTION 'PLN_PROBE:wrmgr2:%', v_i USING ERRCODE = '22000';
      EXCEPTION WHEN OTHERS THEN
        BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
        PERFORM set_config('request.jwt.claims', '', true);
        IF SQLERRM LIKE 'PLN_PROBE:wrmgr2:%' THEN
          v_i := replace(SQLERRM, 'PLN_PROBE:wrmgr2:', '')::int;
          v_t_wr_mgr := CASE WHEN v_i > 0 THEN '✅ ' || v_i || ' qator (yangi policy bilan)'
                             ELSE '❗ 0 qator — yangi policy ham yetmadi' END;
        ELSE
          v_t_wr_mgr := '❗ xato: ' || SQLSTATE;
        END IF;
      END;
      IF v_t_wr_mgr LIKE '❗%' THEN
        RAISE WARNING '❗ MENEJER BAYROQNI QO''YA OLMAYAPTI (%). Sabab ehtimol RESTRICTIVE policy yoki GRANT. Modulning qolgan qismi ishlaydi, lekin "ruxsat berish" UI''si 0 qator qaytaradi va mijoz buni ochiq aytadi. Qo''lda hal qiling.', v_t_wr_mgr;
      END IF;
    END IF;
  ELSE
    v_wmpol_note := 'mavjud UPDATE policy yetarli — yangi policy QO''SHILMADI (ortiqcha huquq berilmadi)';
    RAISE NOTICE '%', v_wmpol_note;
  END IF;

  -- (9) tasks UPDATE — bajaruvchi o'z plan_* ini yoza oladimi?
  --     ⚠️ RLS QATOR darajasida ishlaydi: agar bajaruvchi o'z vazifasini
  --        yangilay olsa (bugun changeStatus shunday ishlayapti), plan_*
  --        uchun ALOHIDA policy KERAK EMAS. Shuni o'lchab tasdiqlaymiz.
  --        Yozuv sentinel-rollback bilan qaytariladi.
  SELECT t.id::text INTO v_task_id
    FROM public.tasks t
   WHERE t.workspace_id = v_ws AND t.assigned_to = v_m1
   ORDER BY t.id DESC LIMIT 1;
  IF v_task_id IS NULL THEN
    RAISE NOTICE 'ℹ️ % ga biriktirilgan vazifa topilmadi — tasks UPDATE o''lchovi o''tkazib yuborildi.', v_m1;
  ELSE
    BEGIN
      PERFORM set_config('request.jwt.claims',
               json_build_object('sub', v_m1::text, 'role', 'authenticated')::text, true);
      EXECUTE 'SET LOCAL ROLE authenticated';
      EXECUTE 'UPDATE public.tasks SET plan_date = $1, plan_start = 540, plan_end = 600
                WHERE id::text = $2' USING current_date, v_task_id;
      GET DIAGNOSTICS v_i = ROW_COUNT;
      EXECUTE 'RESET ROLE';
      PERFORM set_config('request.jwt.claims', '', true);
      RAISE EXCEPTION 'PLN_PROBE:tupd:%', v_i USING ERRCODE = '22000';
    EXCEPTION WHEN OTHERS THEN
      BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
      PERFORM set_config('request.jwt.claims', '', true);
      IF SQLERRM LIKE 'PLN_PROBE:tupd:%' THEN
        v_i := replace(SQLERRM, 'PLN_PROBE:tupd:', '')::int;
        v_t_upd := CASE WHEN v_i > 0 THEN '✅ mavjud policy QOPLAYDI (yangi policy kerak emas)'
                        ELSE '❗ 0 qator — bajaruvchi o''z vazifasini yangilay olmayapti' END;
      ELSE
        v_t_upd := '❗ xato: ' || SQLSTATE || ' — ' || left(SQLERRM, 120);
      END IF;
    END;
    IF v_t_upd LIKE '❗%' THEN
      RAISE WARNING '❗ tasks UPDATE o''lchovi: %. Demak bajaruvchi rejalashtirgichda blokni sudrab QO''YA OLMAYDI (mijoz 0 qator oladi). Bu skript tasks UPDATE policy''siga ATAYLAB tegmaydi (yozuv huquqini kengaytirish alohida qaror) — Asilbek/Fable hal qilsin.', v_t_upd;
    END IF;
  END IF;
END IF;

-- ══════════════════════════════════════════════════════════════════════════
-- 7.8) STRUKTURA TEKSHIRUVI — "bor deb o'ylash" emas, katalogdan O'QISH
-- ══════════════════════════════════════════════════════════════════════════
-- (a) 3 ustun
FOREACH v_txt IN ARRAY ARRAY['plan_date','plan_start','plan_end'] LOOP
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name=v_txt) THEN
    RAISE EXCEPTION 'tasks.% ustuni yaratilmadi — HAMMASI QAYTARILDI.', v_txt;
  END IF;
END LOOP;
IF (SELECT data_type FROM information_schema.columns
     WHERE table_schema='public' AND table_name='tasks' AND column_name='plan_start') <> 'smallint' THEN
  RAISE EXCEPTION 'tasks.plan_start turi smallint EMAS — eski/boshqa sxema aniqlandi. HAMMASI QAYTARILDI.';
END IF;
IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='workspace_members'
                  AND column_name='can_view_others_planner') THEN
  RAISE EXCEPTION 'workspace_members.can_view_others_planner ustuni yaratilmadi — HAMMASI QAYTARILDI.';
END IF;

-- (b) 3 CHECK — 🔴 conrelid bilan SKOPLANGAN (conname global unique EMAS)
FOREACH v_txt IN ARRAY ARRAY['tasks_plan_start_chk','tasks_plan_end_chk','tasks_plan_triple_chk'] LOOP
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'public.tasks'::regclass AND contype = 'c' AND conname = v_txt) THEN
    RAISE EXCEPTION 'CHECK % public.tasks da topilmadi — HAMMASI QAYTARILDI.', v_txt;
  END IF;
END LOOP;
SELECT pg_get_constraintdef(oid) INTO v_txt FROM pg_constraint
 WHERE conrelid='public.tasks'::regclass AND conname='tasks_plan_triple_chk';
IF v_txt !~ 'plan_end > plan_start' THEN
  RAISE EXCEPTION 'tasks_plan_triple_chk ichida `plan_end > plan_start` yo''q: % — HAMMASI QAYTARILDI.', v_txt;
END IF;

-- (c) can_view_planner tanasida auth.uid() QOROVULI
--     ⚠️ Izohlar OLIB TASHLANADI: kod qatori o'chirilib izoh qoldirilgan
--        holat sezilmay qolmasin (hr_is_editor naqshi).
SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='can_view_planner' AND p.pronargs = 3
 LIMIT 1;
IF v_src IS NULL THEN
  RAISE EXCEPTION 'can_view_planner(uuid,uuid,uuid) tanasi o''qilmadi — funksiya yaratilmadimi?';
END IF;
IF v_src !~ 'p_user\s*=\s*\(\s*SELECT\s+auth\.uid\(\)' THEN
  RAISE EXCEPTION 'can_view_planner() KODIDA `p_user = (SELECT auth.uid())` qorovuli YO''Q (izoh hisobga olinmaydi) — funksiya PostgREST orqali begona odam haqida ma''lumot berardi. HAMMASI QAYTARILDI.';
END IF;
IF v_src NOT LIKE '%is_ws_member%' OR v_src NOT LIKE '%is_ws_manager%' THEN
  RAISE EXCEPTION 'can_view_planner() KODIDA is_ws_member/is_ws_manager yo''q — a''zolik tekshiruvisiz ruxsat berilardi. HAMMASI QAYTARILDI.';
END IF;
IF v_src NOT LIKE '%can_view_others_planner%' THEN
  RAISE EXCEPTION 'can_view_planner() KODIDA can_view_others_planner bayrog''i o''qilmayapti — ruxsat mexanizmi yo''q. HAMMASI QAYTARILDI.';
END IF;

-- (d) anon EXECUTE OLMASLIGI shart
IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
  IF has_function_privilege('anon', 'public.can_view_planner(uuid,uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'can_view_planner() `anon` ga EXECUTE bilan ochiq qolgan (ALTER DEFAULT PRIVILEGES) — REVOKE ishlamadi. HAMMASI QAYTARILDI.';
  END IF;
END IF;
IF NOT has_function_privilege('authenticated', 'public.can_view_planner(uuid,uuid,uuid)', 'EXECUTE') THEN
  RAISE EXCEPTION 'can_view_planner() `authenticated` ga EXECUTE bermayapti — RLS ifodasi chaqiruvchi huquqi bilan baholanadi, policy ishlamasdi. HAMMASI QAYTARILDI.';
END IF;

-- (e) BAYROQ QOROVULI trigger'i o'z joyida va bayroqni tekshiryaptimi
IF NOT EXISTS (SELECT 1 FROM pg_trigger
                WHERE tgrelid='public.workspace_members'::regclass
                  AND tgname='wm_planner_flag_guard_trg' AND NOT tgisinternal) THEN
  RAISE EXCEPTION 'wm_planner_flag_guard_trg trigger''i yo''q — oddiy a''zo bayroqni o''ziga qo''yib olardi. HAMMASI QAYTARILDI.';
END IF;
SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='wm_planner_flag_guard' LIMIT 1;
IF v_src IS NULL OR v_src NOT LIKE '%is_ws_manager%' OR v_src NOT LIKE '%can_view_others_planner%' THEN
  RAISE EXCEPTION 'wm_planner_flag_guard() KODIDA is_ws_manager / can_view_others_planner tekshiruvi yo''q — qorovul ma''nosiz. HAMMASI QAYTARILDI.';
END IF;

-- (e2) 🔴 "Oddiy a'zo bayroqni yoza oladimi?" — POLICY MATNINI o'qiymiz.
--      Agar workspace_members da a'zoga O'Z qatorini yangilashga ruxsat
--      beradigan PERMISSIVE UPDATE policy bo'lsa (`user_id = auth.uid()`
--      naqshi), ustun darajasida to'sish policy bilan MUMKIN EMAS — yagona
--      himoya trigger'da (yuqorida (e) da mavjudligi majburlangan). Bu
--      holatni jimgina o'tkazib yubormaymiz: ochiq NOTICE yoziladi.
SELECT string_agg(coalesce(qual,'') || ' | ' || coalesce(with_check,''), '  ##  ')
  INTO v_qual
  FROM pg_policies
 WHERE schemaname='public' AND tablename='workspace_members'
   AND permissive='PERMISSIVE' AND cmd IN ('UPDATE','ALL');
IF v_qual IS NULL THEN
  RAISE NOTICE 'ℹ️ workspace_members da PERMISSIVE UPDATE policy YO''Q — a''zo umuman yoza olmaydi; bayroqni owner/admin service_role yoki wm_update_manager_planner orqali qo''yadi.';
ELSIF v_qual ~* 'user_id' AND v_qual ~* 'uid\(\)' THEN
  RAISE NOTICE '⚠️ workspace_members UPDATE policy''si a''zoga O''Z qatorini yangilash yo''lini ochadi (% ). Shuning uchun bayroq PERMISSIVE policy bilan EMAS, wm_planner_flag_guard_trg trigger''i bilan qo''riqlanadi (yuqorida mavjudligi majburlandi, tirik sinov: 15-qator).', left(v_qual, 200);
ELSE
  RAISE NOTICE 'ℹ️ workspace_members UPDATE policy''si a''zoning o''z qatoriga bog''liq emas (%). Bayroq baribir trigger bilan qo''riqlanadi.', left(v_qual, 200);
END IF;

-- (f) Yangi tasks policy: PERMISSIVE + plan_date sharti
IF v_pol_added THEN
  SELECT permissive, qual INTO v_txt, v_qual FROM pg_policies
   WHERE schemaname='public' AND tablename='tasks' AND policyname='tasks_select_planner_shared';
  IF v_txt IS DISTINCT FROM 'PERMISSIVE' THEN
    RAISE EXCEPTION 'tasks_select_planner_shared PERMISSIVE emas (%) — RESTRICTIVE policy mavjud kirish huquqini TORAYTIRIB yuborardi. HAMMASI QAYTARILDI.', coalesce(v_txt,'NULL');
  END IF;
  IF v_qual !~ 'plan_date IS NOT NULL' THEN
    RAISE EXCEPTION 'tasks_select_planner_shared da `plan_date IS NOT NULL` sharti YO''Q (%) — rejasiz vazifalar ham ochilib ketardi. HAMMASI QAYTARILDI.', coalesce(v_qual,'NULL');
  END IF;
  IF v_qual !~ 'can_view_planner' OR v_qual !~ 'is_ws_member' THEN
    RAISE EXCEPTION 'tasks_select_planner_shared shartida can_view_planner / is_ws_member yo''q (%) — HAMMASI QAYTARILDI.', coalesce(v_qual,'NULL');
  END IF;
END IF;

-- (g) Mavjud policy'lar joyidami? (biz faqat QO'SHDIK — hech narsa
--     o'chirilmasligi kerak edi)
-- ⚠️ Shart `< v_tsk_sel`, `< v_tsk_sel + 1` EMAS: QAYTA RUN da policy allaqachon
--    mavjud bo'lgani uchun "oldingi" sanoq uni O'Z ICHIGA OLADI va +1 talab
--    qilinsa skript ikkinchi RUN da SOXTA xato bilan yiqilardi.
SELECT count(*) INTO v_n FROM pg_policies
 WHERE schemaname='public' AND tablename='tasks' AND permissive='PERMISSIVE' AND cmd IN ('SELECT','ALL');
IF v_n < v_tsk_sel THEN
  RAISE EXCEPTION 'tasks da PERMISSIVE SELECT policy soni KAMAYDI (% ← %) — mavjud policy o''chib ketgan. HAMMASI QAYTARILDI.', v_n, v_tsk_sel;
END IF;
IF v_pol_added AND NOT EXISTS (
     SELECT 1 FROM pg_policies
      WHERE schemaname='public' AND tablename='tasks' AND policyname='tasks_select_planner_shared') THEN
  RAISE EXCEPTION 'tasks_select_planner_shared policy''si katalogda yo''q — yaratilmadimi? HAMMASI QAYTARILDI.';
END IF;

RAISE NOTICE '✅ STRUKTURA: ustunlar, CHECK''lar, funksiya qorovullari, trigger va policy tekshirildi.';

-- ══════════════════════════════════════════════════════════════════════════
-- 7.9) NATIJA jadvali
-- ══════════════════════════════════════════════════════════════════════════
-- Tirik sinov umuman bajarilmagan bo'lsa sababi ochiq yozilsin (bo'sh katak
-- "hammasi joyida" degan yolg'on taassurot bermasin).
IF v_wmpol_note IS NULL THEN
  v_wmpol_note := 'o''lchanmadi — tirik sinov o''tkazib yuborildi (menejer bayroqni yoza oladimi, QO''LDA tekshiring)';
END IF;

INSERT INTO pg_temp.pln_res VALUES
  (1,  'ustun', 'tasks.plan_date / plan_start / plan_end', 'bor',
       'date + smallint(daqiqa). deadline TEGILMAGAN — ikkovi mustaqil'),
  (2,  'cheklov', 'tasks_plan_start/end/triple_chk', '3 ta',
       '0..1439 / 1..1440 / uchligi birga va end > start'),
  (3,  'indeks', 'idx_tasks_ws_assigned_plan', 'bor',
       'tasks(workspace_id, assigned_to, plan_date) WHERE plan_date IS NOT NULL'),
  (4,  'ustun', 'workspace_members.can_view_others_planner', 'bor',
       'boolean NOT NULL DEFAULT false — SHAXSGA beriladi (lavozimga emas)'),
  (5,  'funksiya', 'can_view_planner(uuid,uuid,uuid)', 'yaratildi',
       'SECURITY DEFINER · STABLE · faqat authenticated EXECUTE · auth.uid() qorovuli'),
  (6,  'trigger', 'wm_planner_flag_guard_trg', 'bor',
       'bayroqni faqat owner/admin o''zgartira oladi (policy bilan buni qilib bo''lmasdi)'),
  (7,  'policy', 'tasks_select_planner_shared',
       CASE WHEN v_pol_added THEN 'qo''shildi' ELSE 'QO''SHILMADI' END, v_pol_reason),
  (8,  'policy', 'wm_update_manager_planner',
       CASE WHEN v_wmpol_added THEN 'qo''shildi' ELSE 'QO''SHILMADI' END, coalesce(v_wmpol_note,'—')),
  (9,  'sinov', 'o''zini ko''radi',            v_t_self,   'can_view_planner(ws, men, men)'),
  (10, 'sinov', 'menejer ko''radi',            v_t_mgr,    'owner/admin doim'),
  (11, 'sinov', '🔴 ruxsatsiz KO''RMAYDI',      v_t_deny,   'eng muhim sinov'),
  (12, 'sinov', 'bayroq bilan ko''radi',       v_t_flag,   'bayroq vaqtincha yoqildi va QAYTARILDI'),
  (13, 'sinov', 'begona p_user (PostgREST)',  v_t_imp,    'p_user ≠ auth.uid() → false'),
  (14, 'sinov', 'boshqa workspace',           v_t_xws,    'a''zo bo''lmagan ws → false'),
  (15, 'sinov', '🔴 a''zo bayroqni yoza olmaydi', v_t_wr_mem, 'trigger to''sishi shart'),
  (16, 'sinov', 'menejer bayroqni yozadi',    v_t_wr_mgr, 'UI shu orqali ruxsat beradi'),
  (17, 'sinov', 'bajaruvchi plan_* yozadi',   v_t_upd,    'mavjud tasks UPDATE policy''si qoplaydimi'),
  (18, 'xavfsizlik', 'tekshirilgan foydalanuvchi',
       (SELECT count(*)::text FROM pg_temp.pln_u),
       (SELECT count(*)::text FROM pg_temp.pln_u WHERE turi='nazorat') || ' tasi NAZORAT (ularda sizish 0 bo''lishi shart)'),
  (19, 'xavfsizlik', 'yangi ko''ringan qator', v_gain::text || ' vazifa',
       'faqat reja bloklari (plan_date IS NOT NULL)'),
  (20, 'xavfsizlik', 'RESTRICTIVE policy',
       CASE WHEN v_restr > 0 THEN v_restr::text || ' ta' ELSE 'yo''q' END,
       CASE WHEN v_restr > 0 THEN 'AND bilan qo''llanadi — yangi PERMISSIVE policy ularni yenga olmaydi'
            ELSE 'yangi PERMISSIVE policy to''liq kuchga kiradi' END),
  (21, 'eslatma', 'localStorage migratsiyasi', 'MIJOZ ishi',
       'planner_<ws>_<uid> → plan_date/plan_start/plan_end (start+dur). SQL buni QILMAYDI.');

RAISE NOTICE '════ TUGADI — pastdagi jadvalga qarang ════';
END
$main$;

COMMIT;

-- ══════════ NATIJA ══════════
SELECT bosqich, nom, qiymat, izoh FROM pg_temp.pln_res ORDER BY ord;

-- Kim nima ko'rdi (oldin → keyin)
SELECT a.turi,
       a.uid,
       a.s_n                       AS ochilishi_kerak,
       o.n_tsk || ' → ' || k.n_tsk AS vazifalar,
       o.n_s   || ' → ' || k.n_s   AS reja_bloklari,
       o.n_o   || ' → ' || k.n_o   AS boshqalarniki
  FROM pg_temp.pln_u a
  JOIN pg_temp.pln_snap o ON o.uid = a.uid AND o.faza='oldin'
  JOIN pg_temp.pln_snap k ON k.uid = a.uid AND k.faza='keyin'
 ORDER BY a.turi, a.uid;


-- ============================================================================
-- QANDAY O'QISH
-- ============================================================================
--  • "policy · qo'shildi" + "🔴 ruxsatsiz KO'RMAYDI ✅ false" — ish bitdi.
--  • "sinov · o'tkazib yuborildi" — bazada mos ma'lumot topilmadi (masalan
--    bitta ws da menejer + 2 oddiy a'zo yo'q) yoki impersonatsiya harnessi
--    ishlamadi. Bu XATO emas, lekin prodga chiqishdan oldin QO'LDA sinang.
--  • "❗" belgisi bor qator — modul ishlaydi, lekin bir qismi ishlamaydi;
--    yonidagi izohda sabab bor (jimgina yutilmaydi).
--  • "boshqalarniki" ustuni NAZORAT foydalanuvchilarida o'zgargan bo'lsa
--    skript RAISE EXCEPTION bilan to'xtagan va HECH NARSA o'zgarmagan bo'lardi.
--
-- ── 🔴 RUN'DAN KEYIN — MIJOZ TOMONIDA NIMA QILINADI (boshqa agent) ──────────
--   1) localStorage `planner_<wsId>_<userId>` → bazaga BIR MARTA ko'chirish:
--        plan_date  = date
--        plan_start = start
--        plan_end   = start + (dur || 60)
--      Har `update` da `{error}` tekshiriladi + `.select()` bilan qator soni
--      (RLS jimgina to'smasin — CLAUDE.md 6-qoida). Ko'chirish bayrog'i
--      localStorage'da saqlanadi, takror ko'chirish bo'lmasin.
--   2) Vazifa yaratishda "vaqt oralig'i" → plan_date/plan_start/plan_end.
--      Uchligi BIRGA yuboriladi (DB CHECK aks holda 23514 beradi).
--   3) Planner: "Kimning rejasi" tanlagichi — faqat
--      `workspace_members.can_view_others_planner` true bo'lganda yoki
--      owner/admin da ko'rinadi (server baribir RLS bilan to'sadi).
--   4) Ustun yo'q bazada (SQL run qilinmagan) ilova AVVALGIDEK ishlashi shart:
--      PGRST204/42703 → mijoz sababni ochiq aytadi, localStorage'ga tushadi.
--
-- ============================================================================
-- QAYTARISH (ROLLBACK) — kerak bo'lsa, TARTIB MUHIM
-- ============================================================================
--   -- 1) policy'lar (funksiyaga bog'liq — avval ular)
--   DROP POLICY IF EXISTS tasks_select_planner_shared ON public.tasks;
--   DROP POLICY IF EXISTS wm_update_manager_planner   ON public.workspace_members;
--   -- 2) trigger + funksiyalar
--   DROP TRIGGER  IF EXISTS wm_planner_flag_guard_trg ON public.workspace_members;
--   DROP FUNCTION IF EXISTS public.wm_planner_flag_guard();
--   DROP FUNCTION IF EXISTS public.can_view_planner(uuid, uuid, uuid);
--   -- 3) indeks (zararsiz, qolsa ham bo'ladi)
--   DROP INDEX IF EXISTS public.idx_tasks_ws_assigned_plan;
--   -- 4) ⚠️ USTUNLAR — faqat MA'LUMOT KERAK EMASLIGIGA ishonch bo'lsa:
--   --    bu rejalarni BUTUNLAY o'chiradi (localStorage'dan ko'chirilgani ham).
--   -- ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS tasks_plan_triple_chk;
--   -- ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS tasks_plan_end_chk;
--   -- ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS tasks_plan_start_chk;
--   -- ALTER TABLE public.tasks DROP COLUMN IF EXISTS plan_end;
--   -- ALTER TABLE public.tasks DROP COLUMN IF EXISTS plan_start;
--   -- ALTER TABLE public.tasks DROP COLUMN IF EXISTS plan_date;
--   -- ALTER TABLE public.workspace_members DROP COLUMN IF EXISTS can_view_others_planner;
--
-- Rollbackdan keyin holat skriptdan OLDINGIDEK bo'ladi: mavjud policy'lar,
-- trigger'lar va ustunlar umuman tegilmagani uchun tiklash kerak emas.
-- ============================================================================
