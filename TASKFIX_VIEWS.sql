-- ============================================================================
-- TASKFIX_VIEWS.sql — vazifani BAJARUVCHI necha marta ochib ko'rgani (👁 N)
-- ============================================================================
-- NIMA QILADI
--   Yangi jadval `public.task_views` — har (vazifa, ko'ruvchi) juftligi uchun
--   ochish soni. Ilova vazifa detalini ochganda BITTA RPC chaqiradi:
--       sb.rpc('task_view_bump', { p_task_id: <task.id> })  →  yangi son (int)
--   va uni 👁 N ko'rinishida chiqaradi.
--
-- 🔴 FAQAT BAJARUVCHI HISOBLANADI
--   Sanoq faqat `tasks.assigned_to = auth.uid()` bo'lganda oshadi.
--   Yaratgan (created_by), qabul qiluvchi (acceptor_id), admin/owner — ochsa
--   ham sanalmaydi; ular uchun RPC mavjud sonni (yoki 0) qaytaradi, yozmaydi.
--   Sabab: ko'rsatkichning ma'nosi "xodim vazifasini ko'rdimi?" — boshqa
--   odamlar ochgani bu savolga javob bermaydi va sonni ishonchsiz qilardi.
--
-- NEGA SHUNDAY QURILGAN
--   • YOZUV FAQAT RPC ORQALI. `task_views` da INSERT/UPDATE/DELETE policy
--     UMUMAN YO'Q — ya'ni mijoz PostgREST orqali to'g'ridan-to'g'ri yoza
--     olmaydi (o'zining sonini 100 qilib qo'ya olmaydi). Yagona yo'l —
--     SECURITY DEFINER `task_view_bump()`, unda qorovul bor.
--   • `workspace_id` DENORMALIZATSIYA qilingan (loyihadagi task_history /
--     org_* naqshi): RLS policy'si `tasks` ga JOIN qilmasin — aks holda
--     tasks RLS'i bilan chalkashuv va ortiqcha xarajat bo'lardi.
--   • RLS policy ichida `workspace_members` inline subquery YOZILMAYDI
--     (42P17 rekursiya, CLAUDE.md 8-qoida) — faqat `is_ws_member()`.
--   • `task_id` TIPI `tasks.id` DAN DINAMIK olinadi (TASKFIX_HISTORY.sql
--     naqshi): repoda 1–37 migratsiyalar yo'q, tipni qattiq yozib qo'ymaymiz.
--     Tekshiruv: butun son (smallint/integer/bigint) bo'lishi shart, aks holda
--     RPC imzosi (bigint) mos kelmaydi va skript DARROV to'xtaydi.
--
-- ADDITIVE + IDEMPOTENT: mavjud jadval/ustun/policy'larga TEGMAYDI, faqat
-- yangi jadval + indeks + funksiya + 1 ta SELECT policy qo'shadi.
-- Qayta RUN xavfsiz.
--
-- RUN TARTIBI
--   1) 39_employee_details.sql  (is_ws_member() shu yerda yaratilgan)
--   2) TASKFIX_VIEWS.sql        ← shu fayl
--   Boshqa TASKFIX_*.sql fayllariga bog'liq emas, istalgan vaqtda ishlaydi.
--
-- BUSIZ ILOVA YIQILMAYDI: RPC topilmasa (PGRST202/42883) mijoz 👁 belgisini
-- ko'rsatmaydi, qolgan hamma narsa o'zgarishsiz ishlaydi.
--
-- ESLATMA: TEXT + CHECK (ENUM emas) — bu faylda ENUM bo'lishi mumkin bo'lgan
-- maydon yo'q, lekin qoida shu (30/32-migratsiyalardagi saboq).
-- ============================================================================

BEGIN;

-- ── 0) OLDINDAN TEKSHIRUV ───────────────────────────────────────────────────
DO $$
DECLARE
  v_type text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'public' AND c.relname = 'tasks') THEN
    RAISE EXCEPTION 'public.tasks topilmadi — noto''g''ri baza?';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'public' AND c.relname = 'workspaces') THEN
    RAISE EXCEPTION 'public.workspaces topilmadi — noto''g''ri baza?';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'auth' AND c.relname = 'users') THEN
    RAISE EXCEPTION 'auth.users topilmadi — bu Supabase bazasi emasmi?';
  END IF;

  -- is_ws_member() — RLS uchun MAJBURIY (inline subquery yozilmaydi, 8-qoida)
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'is_ws_member'
  ) THEN
    RAISE EXCEPTION 'is_ws_member() topilmadi. Avval 39_employee_details.sql ni ishga tushiring.';
  END IF;

  -- RPC qorovuli aynan shu ikki ustunga tayanadi
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name='assigned_to') THEN
    RAISE EXCEPTION 'public.tasks.assigned_to ustuni yo''q — bajaruvchi qorovuli qurilmaydi. To''xtatildi.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name='workspace_id') THEN
    RAISE EXCEPTION 'public.tasks.workspace_id ustuni yo''q — RLS uchun workspace_id olinmaydi. To''xtatildi.';
  END IF;

  -- tasks.id butun son bo'lishi SHART (RPC imzosi bigint)
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_type
    FROM pg_attribute a
   WHERE a.attrelid = 'public.tasks'::regclass
     AND a.attname = 'id' AND a.attnum > 0 AND NOT a.attisdropped;

  IF v_type IS NULL THEN
    RAISE EXCEPTION 'public.tasks.id ustuni topilmadi';
  END IF;
  IF v_type NOT IN ('bigint', 'integer', 'smallint') THEN
    RAISE EXCEPTION 'public.tasks.id tipi "%" — kutilgani butun son (bigint/integer/smallint). task_view_bump(p_task_id bigint) imzosi mos kelmaydi. To''xtatildi (hech narsa o''zgartirilmadi).', v_type;
  END IF;

  RAISE NOTICE 'tasks.id tipi: % — mos.', v_type;
END $$;


-- ── 1) JADVAL (task_id tipi tasks.id dan olinadi) ───────────────────────────
-- PK (task_id, viewer_id) — bir odam bir vazifa uchun BITTA qator; sanoq
-- shu qatorda o'sadi (har ochish uchun yangi qator YOZILMAYDI — 126 hodim ×
-- minglab vazifa × har kun ochish jadvalni shishirardi va 👁 N uchun
-- har safar count(*) kerak bo'lardi).
DO $$
DECLARE
  v_type text;
BEGIN
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_type
    FROM pg_attribute a
   WHERE a.attrelid = 'public.tasks'::regclass
     AND a.attname = 'id' AND a.attnum > 0 AND NOT a.attisdropped;

  EXECUTE format($f$
    CREATE TABLE IF NOT EXISTS public.task_views (
      task_id         %s          NOT NULL REFERENCES public.tasks(id)      ON DELETE CASCADE,
      viewer_id       uuid        NOT NULL REFERENCES auth.users(id)        ON DELETE CASCADE,
      workspace_id    uuid        NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
      view_count      int         NOT NULL DEFAULT 0,
      first_viewed_at timestamptz NOT NULL DEFAULT now(),
      last_viewed_at  timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (task_id, viewer_id)
    )
  $f$, v_type);

  RAISE NOTICE 'task_views.task_id tipi: % (tasks.id dan olindi)', v_type;
END $$;

COMMENT ON TABLE public.task_views IS
  'Vazifani BAJARUVCHI (tasks.assigned_to) necha marta ochib ko''rgani. Yozuv FAQAT task_view_bump() RPC orqali (INSERT/UPDATE/DELETE policy ataylab YO''Q). Boshqa rollar (yaratgan/qabul qiluvchi/admin) ochsa sanalmaydi.';
COMMENT ON COLUMN public.task_views.view_count IS
  'Ochishlar soni. Birinchi ochishda 1 bo''ladi (DEFAULT 0 faqat qorovul sifatida — RPC har doim 1 dan boshlab yozadi).';
COMMENT ON COLUMN public.task_views.workspace_id IS
  'Denormalizatsiya — RLS policy''si tasks ga JOIN qilmasligi uchun (task_history/org_* naqshi). Manba: tasks.workspace_id, RPC yozadi.';

-- ── 2) INDEKS ───────────────────────────────────────────────────────────────
-- PK (task_id, viewer_id) — "bitta vazifa, bitta odam" so'rovini qoplaydi.
-- Bu indeks — workspace bo'yicha ommaviy o'qish uchun (hisobot / ro'yxatga
-- 👁 sonlarini birdan olib kelish: .eq('workspace_id',…).in('task_id',[…])).
CREATE INDEX IF NOT EXISTS idx_task_views_ws_task
  ON public.task_views (workspace_id, task_id);


-- ── 3) RLS ──────────────────────────────────────────────────────────────────
-- KO'RISH: workspace a'zosi (👁 N vazifa kartasida hammaga ko'rinadi).
-- YOZISH:  policy YO'Q → PostgREST orqali hech kim yoza olmaydi.
--          Yagona yo'l — SECURITY DEFINER task_view_bump() (jadval egasi
--          nomidan ishlaydi va RLS'ni chetlab o'tadi).
-- ⚠️ FORCE ROW LEVEL SECURITY QO'YILMAYDI — qo'yilsa egaga ham RLS qo'llanib,
--    SECURITY DEFINER funksiya ham yoza olmasdi (modul jimgina o'lardi).
-- ⚠️ workspace_members inline subquery YOZILMAYDI (42P17) — is_ws_member().
ALTER TABLE public.task_views ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "task_views_select" ON public.task_views;
CREATE POLICY "task_views_select" ON public.task_views
  AS PERMISSIVE FOR SELECT TO authenticated
  USING ( is_ws_member(workspace_id, (SELECT auth.uid())) );

-- 🔴 INSERT / UPDATE / DELETE policy ATAYLAB YO'Q. Qo'shmang:
--    ular bo'lsa foydalanuvchi o'z view_count'ini xohlagancha yozib
--    (yoki boshqasinikini o'chirib) ko'rsatkichni ishonchsiz qilardi.

-- Qo'shimcha himoya (RLS ustiga grant qatlami): jadval darajasida ham yozuv
-- huquqi olib tashlanadi. Supabase yangi jadvallarga default privileges bilan
-- anon/authenticated ga ALL beradi; RLS baribir to'sadi, lekin "yozuv faqat
-- RPC orqali" qoidasi shu bilan ikki qatlamli bo'ladi.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.task_views FROM authenticated';
    EXECUTE 'GRANT SELECT ON TABLE public.task_views TO authenticated';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON TABLE public.task_views FROM anon';
  END IF;
END $$;


-- ── 4) RPC — YAGONA YOZUV NUQTASI ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.task_view_bump(p_task_id bigint)
RETURNS int
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $body$
DECLARE
  v_uid uuid;
  v_asg uuid;
  v_ws  uuid;
  v_n   int;
BEGIN
  -- 1) Kim so'rayapti
  v_uid := (SELECT auth.uid());
  IF v_uid IS NULL OR p_task_id IS NULL THEN
    RETURN 0;                      -- anon / noto'g'ri chaqiruv — jim 0
  END IF;

  -- 2) Vazifa (SECURITY DEFINER — tasks RLS'i chetlab o'tiladi, shuning uchun
  --    quyidagi qorovullar MAJBURIY)
  SELECT t.assigned_to, t.workspace_id
    INTO v_asg, v_ws
    FROM public.tasks t
   WHERE t.id = p_task_id;

  IF NOT FOUND THEN
    RETURN 0;                      -- vazifa yo'q / o'chirilgan — jim 0
  END IF;

  -- 3) 🔴 ASOSIY QOROVUL — MAJBURIY QATOR, OLIB TASHLAMANG.
  --    Faqat BAJARUVCHI ochgani sanaladi. Yaratgan, qabul qiluvchi, admin,
  --    owner — hech kim sonni oshira olmaydi.
  --    Bu shartsiz funksiya "istalgan odam istalgan vazifaning sonini
  --    oshirsin" degan bo'lib qolardi (u `authenticated` ga EXECUTE bilan
  --    ochiq va PostgREST orqali to'g'ridan-to'g'ri chaqiriladi:
  --        POST /rest/v1/rpc/task_view_bump {p_task_id}).
  --    IS DISTINCT FROM — assigned_to NULL bo'lgan holat ham to'g'ri to'siladi
  --    (NULL <> uuid → NULL → IF ishlamasdi va sanoq oshib ketardi).
  IF v_asg IS DISTINCT FROM v_uid THEN
    SELECT tv.view_count INTO v_n
      FROM public.task_views tv
     WHERE tv.task_id = p_task_id AND tv.viewer_id = v_uid;
    RETURN COALESCE(v_n, 0);       -- o'zgartirmaymiz, mavjud sonni qaytaramiz
  END IF;

  -- 4) 🔴 IKKINCHI QOROVUL: jamoadan chiqarilgan odam sanamasin.
  --    "Xodimni o'chirish" (rmxDoRemove) uni faqat workspace_members'dan
  --    chiqaradi; ba'zi vazifalarda assigned_to o'sha uid'da qolishi mumkin.
  --    is_ws_member() ham SECURITY DEFINER — rekursiya yo'q (8-qoida).
  IF NOT is_ws_member(v_ws, v_uid) THEN
    RETURN 0;
  END IF;

  -- 5) Sanoq. Birinchi ochish → 1.
  INSERT INTO public.task_views AS tv (task_id, viewer_id, workspace_id, view_count)
  VALUES (p_task_id, v_uid, v_ws, 1)
  ON CONFLICT (task_id, viewer_id) DO UPDATE
     SET view_count     = tv.view_count + 1,
         last_viewed_at = now(),
         -- vazifa boshqa workspace'ga ko'chsa RLS to'g'ri qolsin
         workspace_id   = EXCLUDED.workspace_id
  RETURNING tv.view_count INTO v_n;

  RETURN COALESCE(v_n, 0);
END;
$body$;

COMMENT ON FUNCTION public.task_view_bump(bigint) IS
  'Vazifani BAJARUVCHI ochganini sanaydi va yangi sonni qaytaradi. SECURITY DEFINER — task_views ga yozishning YAGONA yo''li (jadvalda INSERT/UPDATE/DELETE policy yo''q). Tanasida MAJBURIY qorovullar: auth.uid() bor, tasks.assigned_to IS DISTINCT FROM auth.uid() bo''lsa YOZMAYDI, is_ws_member() bo''lmasa yozmaydi. Bajaruvchi bo''lmaganlarga mavjud sonni (yoki 0) qaytaradi.';

REVOKE ALL ON FUNCTION public.task_view_bump(bigint) FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.task_view_bump(bigint) FROM anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.task_view_bump(bigint) FROM authenticated';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.task_view_bump(bigint) TO authenticated';
  END IF;
END $$;


-- ── 5) TEKSHIRUV — JIMGINA O'TMASIN ─────────────────────────────────────────
DO $$
DECLARE
  v_cnt  int;
  v_pk   text;
  v_src  text;
  v_norm text;   -- v_src, izohsiz + bo'shliqlar normallashtirilgan + UPPER (5.i)
  v_pols text;
BEGIN
  -- 5.a) Jadval bor
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname='public' AND c.relname='task_views') THEN
    RAISE EXCEPTION 'task_views yaratilmadi';
  END IF;

  -- 5.b) Ustunlar to'liq (jadval avval BOSHQA sxema bilan yaratilgan bo'lishi
  --      mumkin — CREATE TABLE IF NOT EXISTS bunday holatni jimgina o'tkazadi)
  SELECT count(*) INTO v_cnt FROM information_schema.columns
   WHERE table_schema='public' AND table_name='task_views'
     AND column_name IN ('task_id','viewer_id','workspace_id','view_count',
                         'first_viewed_at','last_viewed_at');
  IF v_cnt <> 6 THEN
    RAISE EXCEPTION 'task_views ustunlari to''liq emas (% / 6) — jadval avval boshqa sxema bilan yaratilgan bo''lishi mumkin. Qo''lda tekshiring.', v_cnt;
  END IF;

  -- 5.c) PK aynan (task_id, viewer_id) — sanoq shu juftlikda o'sadi.
  --      Boshqa PK bo'lsa ON CONFLICT (task_id, viewer_id) ishlamaydi.
  SELECT string_agg(a.attname, ',' ORDER BY k.ord) INTO v_pk
    FROM pg_constraint c
    CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
   WHERE c.conrelid = 'public.task_views'::regclass AND c.contype = 'p';
  IF v_pk IS DISTINCT FROM 'task_id,viewer_id' THEN
    RAISE EXCEPTION 'task_views PK noto''g''ri: "%" (kutilgan "task_id,viewer_id")', COALESCE(v_pk, '(yo''q)');
  END IF;

  -- 5.d) Indeks
  IF NOT EXISTS (SELECT 1 FROM pg_indexes
                  WHERE schemaname='public' AND tablename='task_views'
                    AND indexname='idx_task_views_ws_task') THEN
    RAISE EXCEPTION 'idx_task_views_ws_task indeksi yaratilmadi';
  END IF;

  -- 5.e) RLS yoqilgan
  SELECT count(*) INTO v_cnt FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname='public' AND c.relname='task_views' AND c.relrowsecurity;
  IF v_cnt = 0 THEN
    RAISE EXCEPTION 'task_views da RLS yoqilmadi — jadval hammaga ochiq qolardi!';
  END IF;

  -- 5.f) SELECT policy bor VA haqiqatan workspace bilan cheklaydi
  --   ⚠️ Faqat NOM bo'yicha tekshirish yetarli emas: kimdir shu nomdagi
  --      policy'ni `USING (true)` bilan qayta yozsa, tekshiruv o'tib ketardi va
  --      boshqa workspace a'zosi ham 👁 sonlarini o'qiy olardi. Shuning uchun
  --      shartning O'ZI (qual) tekshiriladi.
  SELECT upper(regexp_replace(qual, '\s+', ' ', 'g')) INTO v_pols
    FROM pg_policies
   WHERE schemaname='public' AND tablename='task_views'
     AND policyname='task_views_select' AND cmd='SELECT';
  IF v_pols IS NULL THEN
    RAISE EXCEPTION 'task_views_select policy''si yaratilmadi (yoki cmd SELECT emas) — RLS yoqiq, policy yo''q = hech kim 👁 sonini ko''ra olmasdi.';
  END IF;
  -- Ikki bo'lak alohida qidiriladi: pg_get_expr ustunni ba'zan jadval nomi
  -- bilan chiqaradi ("task_views.workspace_id") — yolg'on musbat bo'lmasin.
  IF strpos(v_pols, 'IS_WS_MEMBER(') = 0 OR strpos(v_pols, 'WORKSPACE_ID') = 0 THEN
    RAISE EXCEPTION 'task_views_select policy''sida is_ws_member(workspace_id, ...) sharti yo''q — hozirgi shart: %. Begona workspace a''zosi ham 👁 sonlarini ko''rardi. To''xtatildi.', v_pols;
  END IF;
  v_pols := NULL;   -- 5.g da qayta ishlatiladi

  -- 5.g) 🔴 YOZUV policy'si YO'Qligi (kelajakda kimdir qo'shib qo'ysa —
  --      shu yerda to'xtaydi; sanoqni qo'lda yozish yo'li ochilib ketmasin)
  SELECT string_agg(policyname || ' (' || cmd || ')', ', ') INTO v_pols
    FROM pg_policies
   WHERE schemaname='public' AND tablename='task_views' AND cmd <> 'SELECT';
  IF v_pols IS NOT NULL THEN
    RAISE EXCEPTION 'task_views da yozuv policy''si topildi: % — yozuv FAQAT task_view_bump() orqali bo''lishi kerak. To''xtatildi.', v_pols;
  END IF;

  -- 5.h) Funksiya bor va SECURITY DEFINER
  SELECT count(*) INTO v_cnt
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='task_view_bump' AND p.prosecdef;
  IF v_cnt = 0 THEN
    RAISE EXCEPTION 'task_view_bump() yaratilmadi yoki SECURITY DEFINER emas (SECURITY DEFINER bo''lmasa RLS yozuvni to''sadi — sanoq hech qachon ishlamasdi).';
  END IF;

  -- 5.i) 🔴 Funksiya TANASIDAGI qorovullar joyidami?
  --   IZOHLAR AVVAL TOZALANADI (TASKFIX_HR_EDITORS.sql 4.b2 naqshi): tanadagi
  --   🔴 ogohlantirish izohlarida aynan shu matnlar ("assigned_to",
  --   "IS DISTINCT FROM", "auth.uid()") bor — xom matnda qidirsak KOD QATORI
  --   o'chirilib izoh qoldirilgan holatni sezmasdik.
  --   pronargs = 1 — eski overload qolib ketgan bazada noto'g'ri funksiya
  --   tekshirilmasin.
  SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='task_view_bump' AND p.pronargs = 1
   LIMIT 1;

  IF v_src IS NULL THEN
    RAISE EXCEPTION 'task_view_bump(bigint) tanasi o''qilmadi — funksiya yaratilmadimi?';
  END IF;

  -- 🔴 YAKKA KALIT SO'Z BILAN TEKSHIRILMAYDI — BIRLASHGAN NAQSH bilan.
  --   Sabab: "assigned_to" tanada IKKI joyda uchraydi — haqiqiy qorovulda VA
  --   oddiy `SELECT t.assigned_to ... INTO v_asg` qatorida. Yakka kalit so'z
  --   qidirilsa, kimdir qorovul IF blokini BUTUNLAY o'chirsa ham tekshiruv
  --   o'tib ketardi (sanoq har kim uchun oshadigan bo'lib qolardi — jimgina).
  --   Shuning uchun butun qorovul IFODASI qidiriladi.
  -- Normallashtirish: izohlar allaqachon olib tashlangan (yuqorida), endi
  --   ketma-ket bo'shliq/qator uzilishi BITTA probelga aylantiriladi va UPPER
  --   qilinadi → qatorga bo'lib yozish yoki qo'shimcha probel naqshni buzmaydi
  --   (yolg'on musbat bo'lmasin), lekin KOD o'chirilsa darrov ushlanadi.
  -- strpos() ishlatiladi (LIKE emas): naqshlarda `_` bor va u LIKE'da
  --   "istalgan bitta belgi" degani — tekshiruv bo'shashib ketmasin.
  v_norm := upper(regexp_replace(v_src, '\s+', ' ', 'g'));

  IF strpos(v_norm, 'V_UID := (SELECT AUTH.UID())') = 0 THEN
    RAISE EXCEPTION 'task_view_bump() KODIDA "v_uid := (SELECT auth.uid())" topilmadi (izoh hisobga olinmaydi) — kim ko''rayotgani aniqlanmasdi. To''xtatildi.';
  END IF;

  IF strpos(v_norm, 'T.ASSIGNED_TO, T.WORKSPACE_ID INTO V_ASG, V_WS') = 0 THEN
    RAISE EXCEPTION 'task_view_bump() KODIDA "SELECT t.assigned_to, t.workspace_id INTO v_asg, v_ws" topilmadi (izoh hisobga olinmaydi) — qorovul solishtiradigan v_asg endi tasks.assigned_to dan olinmayapti. To''xtatildi.';
  END IF;

  -- 🔴 ASOSIY QOROVUL — butun ifoda: IF + solishtiruv + THEN
  IF strpos(v_norm, 'IF V_ASG IS DISTINCT FROM V_UID THEN') = 0 THEN
    RAISE EXCEPTION 'task_view_bump() KODIDA "IF v_asg IS DISTINCT FROM v_uid THEN" qorovuli topilmadi (izoh hisobga olinmaydi) — bajaruvchi bo''lmagan istalgan odam istalgan vazifaning sonini oshirardi. To''xtatildi.';
  END IF;

  -- 🔴 IKKINCHI QOROVUL — butun ifoda (yakka "is_ws_member" YETARLI EMAS)
  IF strpos(v_norm, 'IF NOT IS_WS_MEMBER(V_WS, V_UID) THEN') = 0 THEN
    RAISE EXCEPTION 'task_view_bump() KODIDA "IF NOT is_ws_member(v_ws, v_uid) THEN" qorovuli topilmadi (izoh hisobga olinmaydi) — jamoadan chiqarilgan xodim sanoqni oshira olardi. To''xtatildi.';
  END IF;

  -- 5.j) Huquqlar: authenticated EXECUTE qila oladi, anon YO'Q
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated')
     AND NOT has_function_privilege('authenticated', 'public.task_view_bump(bigint)', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated roli task_view_bump() ni chaqira olmaydi — ilova 👁 sonini yoza olmasdi.';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon')
     AND has_function_privilege('anon', 'public.task_view_bump(bigint)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon roli task_view_bump() ni chaqira oladi — kirmagan foydalanuvchiga ochiq qolgan. To''xtatildi.';
  END IF;

  RAISE NOTICE '✅ task_views tayyor: RLS yoqiq, 1 ta SELECT policy, yozuv policy''si yo''q, task_view_bump() SECURITY DEFINER + 3 qorovul.';
END $$;

COMMIT;

-- ============================================================================
-- MIJOZ TOMONI (index.html) — shu faylda O'ZGARISH YO'Q, ma'lumot uchun
-- ============================================================================
-- Vazifa detali ochilganda:
--
--   const { data, error } = await sb.rpc('task_view_bump', { p_task_id: t.id });
--   if (error) { console.error('task_view_bump:', error); }   // fon amali —
--   else { /* data = yangi son (int), 👁 data */ }             // toast SHART EMAS
--
-- ⚠️ `{ error }` DOIM tekshiriladi (supabase-js throw QILMAYDI, CLAUDE.md 6-qoida).
-- ⚠️ RPC yo'q bo'lsa (bu fayl RUN qilinmagan) xato kodi 42883 / PGRST202 keladi —
--    mijoz 👁 belgisini ko'rsatmasligi kerak, ilova buzilmasin.
-- ⚠️ Ro'yxatda ommaviy ko'rsatish uchun jadvalni to'g'ridan o'qish mumkin:
--       sb.from('task_views').select('task_id,viewer_id,view_count')
--         .eq('workspace_id', currentWs.id).in('task_id', ids)
--    (SELECT policy a'zoga ochiq; indeks idx_task_views_ws_task shuni qoplaydi.)
--
-- QAYTARISH (rollback) — kerak bo'lsa qo'lda:
--   DROP FUNCTION IF EXISTS public.task_view_bump(bigint);
--   DROP TABLE IF EXISTS public.task_views;
-- ============================================================================
