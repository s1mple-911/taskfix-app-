-- ============================================================================
-- TASKFIX_HR_RECRUITING.sql — HR: hodim ishga olish (nomzod + bir martalik link)
-- ============================================================================
-- MANBA: BRIEF_TASKFIX_HR_RECRUITING.md → "CC (Fable) QARORLARI" D1–D10.
--
-- 🔴 2026-08-18 — QAYTA RUN QILING (D10, Asilbek qarori)
--    Skript avval ishga tushirilgan bo'lsa ham QAYTA ishga tushirilishi SHART:
--      • hr_apply_submit() O'ZGARDI — shartnoma (contract_path) nomzod uchun
--        IXTIYORIY bo'ldi va `referred_by` oq ro'yxatdan CHIQARILDI.
--      • hr_candidates ga YANGI ustun qo'shildi: taskfix_user_id.
--    Qayta RUN xavfsiz (butun skript idempotent).
--
-- ── D10: SHARTNOMA · KIM TAKLIF QILDI · LAVOZIM — FAQAT HR TO'LDIRADI ──────
--    Nomzodning apply sahifasida bu uchtasi UMUMAN YO'Q. DB tomonida:
--      • contract_path   — nomzod yuborsa qabul qilinadi (prefiks tekshiriladi),
--                          yubormasa HR yuklagan qiymat SAQLANADI (COALESCE).
--      • referred_by     — hr_apply_submit() oq ro'yxatida YO'Q, mijoz yuborsa
--                          e'tiborsiz qoladi (taqiqlangan kalitlar ro'yxatida).
--      • position_id     — avvaldan HR tomoni (oq ro'yxatda hech qachon yo'q).
-- Bu fayl 1-BOSQICH: FAQAT DB. `index.html` va `hr-apply.html` alohida
-- bosqichlarda yoziladi va bu skript ularsiz ham to'liq ishga tushadi.
--
-- ── NIMA QO'SHILADI ─────────────────────────────────────────────────────────
--   1) public.hr_candidates    — nomzod kartasi (shaxsiy ma'lumot + HR tomoni)
--   2) public.hr_apply_tokens  — BIR MARTALIK apply havolasi (D3)
--   3) Storage bucket `hr-docs` (PRIVATE) + 5 ta policy (D2)
--   4) 3 ta SECURITY DEFINER funksiya:
--        public.hr_token_open(uuid)          → boolean
--        public.hr_apply_peek(uuid)          → jsonb  {ok,state,company_name}
--        public.hr_apply_submit(uuid,jsonb)  → jsonb  {ok,state|error}
--   5) RLS: ikkala jadvalda ham 4 tadan policy, FAQAT `TO authenticated`
--        shart = is_ws_manager(ws) OR hr_is_editor(ws, auth.uid())   (D9)
--
-- ── NIMA O'ZGARMAYDI (🔴 hech narsaga tegilmaydi) ───────────────────────────
--   • Mavjud jadvallar: workspaces, positions, org_folders, org_people,
--     employee_details, tasks, projects, workspace_members — na ustun, na
--     policy, na trigger o'zgaradi. `positions` (D4) va `org_folders` (D5)
--     faqat FK NISHONI sifatida ishlatiladi.
--   • Mavjud Storage bucket'lari (employee-photos, avatars, attachments) va
--     ularning policy'lari — TEGILMAYDI. Yangi policy'lar `hrdocs_*` prefiksi
--     bilan va hammasi `bucket_id = 'hr-docs'` bilan chegaralangan.
--   • hr_settings / HR Service yoqilishi — tegilmaydi.
--
-- ── BUSIZ ILOVA QANDAY ISHLAYDI ─────────────────────────────────────────────
--   Bu fayl RUN qilinmasa TaskFix AVVALGIDEK ishlaydi: "Hodim ishga olish"
--   bo'limi jadval yo'qligini aniqlaydi va sababni ochiq aytadi (PGRST205 /
--   42P01), qolgan hamma modul (vazifa, loyiha, Org Schema, jamoa) o'zgarishsiz.
--
-- ── RUN TARTIBI ─────────────────────────────────────────────────────────────
--   1) 39_employee_details.sql   → positions, is_ws_member(), is_ws_manager()
--   2) TASKFIX_HR.sql            → org_folders (filial), org_touch()
--   3) TASKFIX_HR_EDITORS.sql    → hr_is_editor()   ⚠️ IXTIYORIY, lekin tavsiya
--   4) TASKFIX_HR_RECRUITING.sql ← SHU FAYL
--
--   ⚠️ 3-qadam (hr_is_editor) HALI RUN QILINMAGAN bo'lsa ham bu skript
--      TO'LIQ ishlaydi: policy'lar FAQAT `is_ws_manager` bilan yoziladi va
--      RAISE NOTICE bilan ochiq aytiladi (jimgina emas). Keyinroq
--      TASKFIX_HR_EDITORS.sql ni ishga tushirib, SHU faylni QAYTA run qilsangiz
--      policy'lar avtomat `OR hr_is_editor(...)` bilan qayta yoziladi.
--
-- ── STORAGE YO'L SXEMASI (ikki xil, boshqa yo'l QABUL QILINMAYDI) ───────────
--   apply/<token>/<fayl>              ← NOMZOD yuklaydi (anon, token bilan)
--   ws/<workspace_id>/<...>/<fayl>    ← HR yuklaydi (authenticated)
--   🔴 anon uchun FAQAT INSERT policy bor. SELECT/UPDATE/DELETE YO'Q →
--      write-only: token bilan ham hech kim hech qanday faylni O'QIY OLMAYDI.
--      Shu sababli apply sahifasida preview MAHALLIY bo'lishi shart
--      (URL.createObjectURL(file)) — D2.
--   🔴 TOKEN YO'LDA KICHIK HARFDA: Postgres uuid'ni doim kichik harfga
--      keltiradi. Mijoz (`hr-apply.html` → hraToken()) URL'dagi tokenni
--      toLowerCase() qiladi, hr_apply_submit esa prefiksni katta-kichik
--      harfga SEZGIR EMAS holda solishtiradi (ikki qatlam). Busiz katta
--      harfli havola bilan kelgan nomzod fayllarni MUVAFFAQIYATLI yuklab,
--      keyin "Hujjatlar to'liq yuklanmadi" xatosida abadiy tiqilib qolardi.
--
-- ⚠️ MIJOZ TOMONI UCHUN OGOHLANTIRISH (2-bosqich): `hr-apply.html` Supabase
--    klientini ALBATTA sessiyasiz qurishi kerak —
--      createClient(url, anonKey, { auth: { persistSession: false,
--        autoRefreshToken: false, storageKey: 'tf-hr-apply' } })
--    aks holda o'sha brauzerda TaskFix'ga kirgan odam apply sahifasini ochsa
--    so'rov `authenticated` roli bilan ketadi, anon INSERT policy'si esa
--    QO'LLANMAYDI va yuklash RLS xatosi bilan to'xtaydi.
--
-- TEXT + CHECK ishlatilgan (ENUM emas) — 30/32-migratsiyalardagi saboq.
-- RLS ichida workspace_members inline subquery YO'Q (42P17) — CLAUDE.md 8-qoida.
-- ADDITIVE + IDEMPOTENT: qayta RUN xavfsiz.
-- Fayl oxirida QAYTARISH (rollback) bo'limi bor.
-- ============================================================================

BEGIN;

-- ════════════════════════════════════════════════════════════════════════════
-- 0) OLD SHART — noto'g'ri/yarim bazada ishga tushmasin
-- ════════════════════════════════════════════════════════════════════════════
DO $do$
BEGIN
  IF to_regclass('public.workspaces') IS NULL THEN
    RAISE EXCEPTION 'public.workspaces topilmadi — bu TaskFix bazasi emasmi?';
  END IF;

  IF to_regclass('public.positions') IS NULL THEN
    RAISE EXCEPTION 'public.positions topilmadi. Avval 39_employee_details.sql ni ishga tushiring (lavozim — D4).';
  END IF;

  IF to_regclass('public.org_folders') IS NULL THEN
    RAISE EXCEPTION 'public.org_folders topilmadi. Avval TASKFIX_HR.sql ni ishga tushiring (filial — D5).';
  END IF;

  IF to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION 'auth.users topilmadi — bu Supabase bazasi emasmi?';
  END IF;

  IF to_regclass('storage.buckets') IS NULL OR to_regclass('storage.objects') IS NULL THEN
    RAISE EXCEPTION 'storage.buckets/storage.objects topilmadi — Supabase Storage yoqilmaganmi?';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'is_ws_manager') THEN
    RAISE EXCEPTION 'is_ws_manager() topilmadi. Avval 35_fix_projects_rls.sql / 39_employee_details.sql ni ishga tushiring.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    RAISE EXCEPTION '`authenticated` roli topilmadi — bu Supabase bazasi emasmi?';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    RAISE EXCEPTION '`anon` roli topilmadi — public apply sahifasi (D1/D2) ishlamas edi.';
  END IF;
END $do$;


-- ════════════════════════════════════════════════════════════════════════════
-- 1) public.hr_candidates — nomzod kartasi
-- ════════════════════════════════════════════════════════════════════════════
-- 🔴 NEGA DEYARLI HAMMA USTUN NULLABLE
--    Forma IKKI yo'ldan bosqichma-bosqich to'ladi: (a) HR "yangi xodim"
--    yaratganda faqat bo'sh qator + link bo'ladi (status='draft'); (b) nomzod
--    o'zi to'ldirgach pending bo'ladi. DB darajasidagi NOT NULL bu oqimni
--    sindirardi (bo'sh qator umuman yaratilmasdi). Majburiylik MIJOZDA va
--    hr_apply_submit() ICHIDA (pastda 6-bo'lim).
--    NOT NULL faqat: workspace_id, status, want_* bayroqlari, created_at.
CREATE TABLE IF NOT EXISTS public.hr_candidates (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id  uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,

  -- D8: draft → pending → hired | rejected   (TEXT + CHECK, ENUM EMAS)
  status        text NOT NULL DEFAULT 'draft',

  -- ── Shaxsiy (nomzod/HR to'ldiradi) ───────────────────────────────────────
  full_name            text,
  birth_date           date,
  gender               text,     -- 'm' | 'f'  (ixtiyoriy)
  pinfl                text,     -- JSHSHIR, 14 raqam
  passport_serial      text,     -- AA1234567
  passport_issued_by   text,
  passport_issued_at   date,
  passport_expires_at  date,
  address              text,
  phone                text,
  parent_name          text,
  parent_phone         text,
  email                text,

  -- ── Fayllar: Storage YO'LI (path), URL EMAS ──────────────────────────────
  -- 🔴 URL saqlanmaydi: bucket private, havola signed URL bilan HR tomonida
  --    (createSignedUrls, PHOTO_TTL_SEC) vaqtinchalik hosil qilinadi.
  photo_path                  text,
  passport_front_path         text,
  passport_back_path          text,
  parent_passport_front_path  text,
  parent_passport_back_path   text,
  contract_path               text,

  -- ── HR tomoni (nomzodga KO'RINMAYDI — brief 44-qator) ────────────────────
  position_id       uuid REFERENCES public.positions(id)   ON DELETE SET NULL,  -- D4
  branch_folder_id  uuid REFERENCES public.org_folders(id) ON DELETE SET NULL,  -- D5
  hired_by_user_id  uuid REFERENCES auth.users(id)         ON DELETE SET NULL,
  taskfix_user_id   uuid REFERENCES auth.users(id)         ON DELETE SET NULL,
  referred_by       text,
  start_date        date,
  notes             text,

  -- ── BOX'lar (D6): tanlov SAQLANADI, amal alohida va idempotent ───────────
  want_taskfix_invite  boolean NOT NULL DEFAULT false,
  want_kassa           boolean NOT NULL DEFAULT false,
  taskfix_invited_at   timestamptz,
  kassa_created_at     timestamptz,
  kassa_error          text,

  -- ── Rozilik (D7 / brief 64-qator) ────────────────────────────────────────
  consent_at       timestamptz,
  consent_version  text,

  -- ── Audit ────────────────────────────────────────────────────────────────
  created_by    uuid,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz,
  submitted_at  timestamptz          -- nomzod formani YUBORGAN lahza
);

-- Qayta RUN: avvalgi (yarim) versiyada yetishmagan ustunlar qo'shiladi
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS status                     text NOT NULL DEFAULT 'draft';
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS full_name                  text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS birth_date                 date;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS gender                     text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS pinfl                      text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS passport_serial            text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS passport_issued_by         text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS passport_issued_at         date;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS passport_expires_at        date;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS address                    text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS phone                      text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS parent_name                text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS parent_phone               text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS email                      text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS photo_path                 text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS passport_front_path        text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS passport_back_path         text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS parent_passport_front_path text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS parent_passport_back_path  text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS contract_path              text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS position_id                uuid REFERENCES public.positions(id)   ON DELETE SET NULL;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS branch_folder_id           uuid REFERENCES public.org_folders(id) ON DELETE SET NULL;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS hired_by_user_id           uuid REFERENCES auth.users(id)         ON DELETE SET NULL;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS taskfix_user_id            uuid REFERENCES auth.users(id)         ON DELETE SET NULL;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS referred_by                text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS start_date                 date;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS notes                      text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS want_taskfix_invite        boolean NOT NULL DEFAULT false;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS want_kassa                 boolean NOT NULL DEFAULT false;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS taskfix_invited_at         timestamptz;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS kassa_created_at           timestamptz;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS kassa_error                text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS consent_at                 timestamptz;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS consent_version            text;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS created_by                 uuid;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS created_at                 timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS updated_at                 timestamptz;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS submitted_at               timestamptz;

ALTER TABLE public.hr_candidates ALTER COLUMN status SET DEFAULT 'draft';

-- ── CHECK'lar (idempotent: DROP → ADD; conrelid bilan skoplangan) ──────────
-- ⚠️ Hammasi "IS NULL OR ..." (statusdan tashqari) — bosqichma-bosqich
--    to'ladigan forma buzilmasin.
ALTER TABLE public.hr_candidates DROP CONSTRAINT IF EXISTS hr_candidates_status_chk;
ALTER TABLE public.hr_candidates ADD  CONSTRAINT hr_candidates_status_chk
  CHECK (status IN ('draft','pending','hired','rejected'));

ALTER TABLE public.hr_candidates DROP CONSTRAINT IF EXISTS hr_candidates_gender_chk;
ALTER TABLE public.hr_candidates ADD  CONSTRAINT hr_candidates_gender_chk
  CHECK (gender IS NULL OR gender IN ('m','f'));

ALTER TABLE public.hr_candidates DROP CONSTRAINT IF EXISTS hr_candidates_pinfl_chk;
ALTER TABLE public.hr_candidates ADD  CONSTRAINT hr_candidates_pinfl_chk
  CHECK (pinfl IS NULL OR pinfl ~ '^[0-9]{14}$');

ALTER TABLE public.hr_candidates DROP CONSTRAINT IF EXISTS hr_candidates_passport_chk;
ALTER TABLE public.hr_candidates ADD  CONSTRAINT hr_candidates_passport_chk
  CHECK (passport_serial IS NULL OR passport_serial ~ '^[A-Za-z]{2}[0-9]{7}$');

-- Ro'yxat so'rovi: .eq(workspace_id).eq(status).order(created_at desc)
CREATE INDEX IF NOT EXISTS hr_candidates_ws_status_idx
  ON public.hr_candidates (workspace_id, status, created_at DESC);

COMMENT ON TABLE public.hr_candidates IS
  'HR: ishga olinayotgan nomzod. status: draft (link berildi, nomzod hali to''ldirmagan) → pending (yuborildi) → hired | rejected. Shaxsiy ma''lumot MAXFIY: RLS faqat is_ws_manager / hr_is_editor. Fayllar hr-docs bucketida (path saqlanadi, URL emas).';
COMMENT ON COLUMN public.hr_candidates.want_taskfix_invite IS
  'HR tanlovi: TaskFix''ga taklif yuborilsinmi? D6 — TANLOV saqlanadi, AMAL alohida va idempotent (taskfix_invited_at bilan). Nomzod bu maydonni HECH QACHON yoza olmaydi (hr_apply_submit oq ro''yxatida yo''q).';
COMMENT ON COLUMN public.hr_candidates.want_kassa IS
  'HR tanlovi: Xarajat/kassa ochilsinmi? D6 — natija kassa_created_at / kassa_error da. Nomzod yoza olmaydi.';
COMMENT ON COLUMN public.hr_candidates.photo_path IS
  'Storage YO''LI (hr-docs bucket): apply/<token>/... yoki ws/<workspace_id>/... . URL EMAS — bucket private.';
COMMENT ON COLUMN public.hr_candidates.taskfix_user_id IS
  'TaskFix taklifi qabul qilingach yaratilgan foydalanuvchi — kassa EF si uchun ishonchli bog''lanish (email o''zgarsa ham uzilmaydi). Faqat HR tomoni yozadi: hr_apply_submit() oq ro''yxatida YO''Q.';
COMMENT ON COLUMN public.hr_candidates.consent_at IS
  'Shaxsiy ma''lumotlarga rozilik lahzasi. hr_apply_submit() ni O''ZI now() bilan yozadi — mijozdan qabul qilinmaydi.';


-- ════════════════════════════════════════════════════════════════════════════
-- 2) public.hr_apply_tokens — BIR MARTALIK apply havolasi (D3)
-- ════════════════════════════════════════════════════════════════════════════
-- Ochiq token = used_at IS NULL AND expires_at > now().
-- 🔴 "Bir marta" kafolati SAQLASHDA emas, hr_apply_submit() ichidagi ATOMIK
--    da'voda: UPDATE ... WHERE used_at IS NULL AND expires_at > now().
--    Ikki marta yuborish / poyga — imkonsiz.
CREATE TABLE IF NOT EXISTS public.hr_apply_tokens (
  token         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id  uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  candidate_id  uuid NOT NULL REFERENCES public.hr_candidates(id) ON DELETE CASCADE,
  created_by    uuid,
  created_at    timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  used_at       timestamptz,
  used_ua       text
);

ALTER TABLE public.hr_apply_tokens ADD COLUMN IF NOT EXISTS created_by uuid;
ALTER TABLE public.hr_apply_tokens ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.hr_apply_tokens ADD COLUMN IF NOT EXISTS expires_at timestamptz NOT NULL DEFAULT (now() + interval '7 days');
ALTER TABLE public.hr_apply_tokens ADD COLUMN IF NOT EXISTS used_at    timestamptz;
ALTER TABLE public.hr_apply_tokens ADD COLUMN IF NOT EXISTS used_ua    text;

ALTER TABLE public.hr_apply_tokens ALTER COLUMN expires_at SET DEFAULT (now() + interval '7 days');

CREATE INDEX IF NOT EXISTS hr_apply_tokens_cand_idx ON public.hr_apply_tokens (candidate_id);
CREATE INDEX IF NOT EXISTS hr_apply_tokens_ws_idx   ON public.hr_apply_tokens (workspace_id, created_at DESC);

COMMENT ON TABLE public.hr_apply_tokens IS
  'Bir martalik apply havolasi: taskfix.org/hr-apply.html?t=<token>. Ochiq = used_at IS NULL AND expires_at > now(). Yopilishi ATOMIK — hr_apply_submit() ichidagi optimistik da''vo. Token uuid: taxmin qilib bo''lmaydi.';
COMMENT ON COLUMN public.hr_apply_tokens.used_ua IS
  'Yuborgan brauzerning User-Agent qatori (audit). PostgREST request.headers dan olinadi; bo''lmasa payload._ua. 300 belgigacha kesiladi.';


-- ════════════════════════════════════════════════════════════════════════════
-- 3) updated_at trigger — MAVJUD public.org_touch() QAYTA ISHLATILADI
-- ════════════════════════════════════════════════════════════════════════════
-- ⚠️ Yangi funksiya YOZILMAYDI. org_touch() TASKFIX_HR.sql da yaratilgan va
--    org_folders/org_people/hr_settings uchun ishlatiladi. Faqat u YO'Q bo'lsa
--    (kutilmagan holat) aynan o'sha tanasi bilan yaratiladi.
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'org_touch') THEN
    EXECUTE $f$
      CREATE OR REPLACE FUNCTION public.org_touch()
      RETURNS trigger LANGUAGE plpgsql AS $b$
      BEGIN
        NEW.updated_at := now();
        RETURN NEW;
      END $b$;
    $f$;
    RAISE NOTICE 'org_touch() topilmadi — TASKFIX_HR.sql dagi bilan AYNAN bir xil tanasi bilan yaratildi.';
  END IF;
END $do$;

DROP TRIGGER IF EXISTS hr_candidates_touch_trg ON public.hr_candidates;
CREATE TRIGGER hr_candidates_touch_trg BEFORE UPDATE ON public.hr_candidates
  FOR EACH ROW EXECUTE FUNCTION public.org_touch();
-- hr_apply_tokens da updated_at YO'Q → trigger ham yo'q (ataylab).


-- ════════════════════════════════════════════════════════════════════════════
-- 4) GRANT qatlami (RLS ustiga)
-- ════════════════════════════════════════════════════════════════════════════
-- 🔴 anon ikkala jadvalga ham UMUMAN tegmaydi: na policy, na GRANT.
--    Nomzod DB ga faqat hr_apply_submit() SECURITY DEFINER RPC orqali yozadi.
-- ⚠️ authenticated ga SELECT SHART: storage policy'sidagi
--    `EXISTS (SELECT 1 FROM public.hr_apply_tokens ...)` shu huquq bilan
--    baholanadi (8-bo'limga qarang).
REVOKE ALL ON TABLE public.hr_candidates   FROM anon;
REVOKE ALL ON TABLE public.hr_apply_tokens FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_candidates   TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_apply_tokens TO authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- 5) RLS (D9) — TO authenticated, is_ws_manager OR hr_is_editor
-- ════════════════════════════════════════════════════════════════════════════
-- 🔴 anon uchun policy YO'Q → RLS yoqilgan jadvalda policy bo'lmasa hech narsa
--    ko'rinmaydi/yozilmaydi. Passport/JSHSHIR sizib chiqmaydi.
-- ⚠️ workspace_members inline subquery YOZILMAYDI (42P17) — faqat
--    is_ws_manager() / hr_is_editor(), ikkovi ham SECURITY DEFINER.
-- ⚠️ Policy'lar DINAMIK yaratiladi: hr_is_editor() bo'lmasa uni matnga
--    qo'shsak CREATE POLICY 42883 bilan yiqilardi.
ALTER TABLE public.hr_candidates   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_apply_tokens ENABLE ROW LEVEL SECURITY;

DO $do$
DECLARE
  v_hr   boolean;
  v_cond text;
  t      text;
BEGIN
  v_hr := EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'hr_is_editor' AND p.pronargs = 2
  );

  IF v_hr THEN
    v_cond := '( is_ws_manager(workspace_id, (SELECT auth.uid()))'
           || ' OR hr_is_editor(workspace_id, (SELECT auth.uid())) )';
  ELSE
    v_cond := '( is_ws_manager(workspace_id, (SELECT auth.uid())) )';
    RAISE NOTICE '⚠️ hr_is_editor() TOPILMADI (TASKFIX_HR_EDITORS.sql ishga tushirilmagan).';
    RAISE NOTICE '   Policy''lar FAQAT is_ws_manager bilan yozildi → owner/admin BO''LMAGAN HR';
    RAISE NOTICE '   nomzodlarni ko''ra ham, yarata ham olmaydi (xavfsiz tomon).';
    RAISE NOTICE '   Tuzatish: TASKFIX_HR_EDITORS.sql → keyin SHU faylni QAYTA run qiling.';
  END IF;

  FOREACH t IN ARRAY ARRAY['hr_candidates','hr_apply_tokens'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_select', t);
    EXECUTE format('CREATE POLICY %I ON public.%I AS PERMISSIVE FOR SELECT TO authenticated USING %s',
                   t || '_select', t, v_cond);

    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_insert', t);
    EXECUTE format('CREATE POLICY %I ON public.%I AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK %s',
                   t || '_insert', t, v_cond);

    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_update', t);
    EXECUTE format('CREATE POLICY %I ON public.%I AS PERMISSIVE FOR UPDATE TO authenticated USING %s WITH CHECK %s',
                   t || '_update', t, v_cond, v_cond);

    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_delete', t);
    EXECUTE format('CREATE POLICY %I ON public.%I AS PERMISSIVE FOR DELETE TO authenticated USING %s',
                   t || '_delete', t, v_cond);
  END LOOP;
END $do$;


-- ════════════════════════════════════════════════════════════════════════════
-- 6) SECURITY DEFINER FUNKSIYALAR
-- ════════════════════════════════════════════════════════════════════════════

-- ── 6.1) hr_token_open(uuid) → boolean ─────────────────────────────────────
-- Token OCHIQmi? BITTA haqiqat manbai: Storage policy ham, apply sahifasi ham
-- shundan foydalanadi (D3). anon ga EXECUTE SHART — anon INSERT policy'si
-- aynan shu funksiyani chaqiradi (policy chaqiruvchi rol huquqi bilan
-- baholanadi).
-- ⚠️ Faqat boolean qaytaradi: nomzod ham, workspace ham, sana ham sizmaydi.
CREATE OR REPLACE FUNCTION public.hr_token_open(p_token uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  SELECT p_token IS NOT NULL
     AND EXISTS (
           SELECT 1
             FROM public.hr_apply_tokens t
            WHERE t.token      = p_token
              AND t.used_at    IS NULL
              AND t.expires_at > now()
         );
$fn$;

COMMENT ON FUNCTION public.hr_token_open(uuid) IS
  'Apply tokeni ochiqmi (ishlatilmagan va muddati o''tmagan)? SECURITY DEFINER — hr_apply_tokens RLS''ini chetlab o''tadi, chunki anon o''sha jadvalni umuman ko''ra olmaydi. FAQAT boolean qaytaradi (hech qanday ma''lumot sizmaydi). Storage `hrdocs_anon_insert` policy''si va apply sahifasi shundan foydalanadi.';

REVOKE ALL ON FUNCTION public.hr_token_open(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hr_token_open(uuid) TO anon, authenticated;


-- ── 6.2) hr_apply_peek(uuid) → jsonb ───────────────────────────────────────
-- 🔴 FAQAT {ok, state, company_name} (brief 44-qator, D3).
--    Lavozim, filial, box, HR izohi, nomzod ma'lumoti, boshqa nomzodlar —
--    HECH BIRI QAYTMAYDI. Funksiya `hr_candidates` ga UMUMAN murojaat qilmaydi
--    (buni oxirgi tekshiruv bloki majburlaydi).
-- ⚠️ company_name FAQAT state='open' da qaytadi: eskirgan/ishlatilgan token
--    bilan tashkilot nomini yig'ib bo'lmasin.
CREATE OR REPLACE FUNCTION public.hr_apply_peek(p_token uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_ws   uuid;
  v_used timestamptz;
  v_exp  timestamptz;
  v_name text;
BEGIN
  IF p_token IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'state', 'invalid');
  END IF;

  SELECT t.workspace_id, t.used_at, t.expires_at
    INTO v_ws, v_used, v_exp
    FROM public.hr_apply_tokens t
   WHERE t.token = p_token;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'state', 'invalid');
  END IF;
  IF v_used IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'state', 'used');
  END IF;
  IF v_exp <= now() THEN
    RETURN jsonb_build_object('ok', false, 'state', 'expired');
  END IF;

  SELECT w.name INTO v_name FROM public.workspaces w WHERE w.id = v_ws;

  RETURN jsonb_build_object(
    'ok',           true,
    'state',        'open',
    'company_name', COALESCE(v_name, '')
  );
END;
$fn$;

COMMENT ON FUNCTION public.hr_apply_peek(uuid) IS
  'Apply sahifasi ochilganda holatni qaytaradi: {ok, state: open|used|expired|invalid, company_name}. 🔴 BOSHQA HECH NARSA qaytmaydi (lavozim/filial/box/nomzod ma''lumoti) — brief 44-qator. company_name faqat state=open da.';

REVOKE ALL ON FUNCTION public.hr_apply_peek(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hr_apply_peek(uuid) TO anon, authenticated;


-- ── 6.3) hr_apply_submit(uuid, jsonb) → jsonb ──────────────────────────────
-- 🔴 UCHTA QAT'IY QOIDA (o'zgartirmang — oxirgi tekshiruv bloki majburlaydi):
--   (1) OQ RO'YXAT: p_payload dan FAQAT quyidagi kalitlar `->>` bilan
--       NOMMA-NOM o'qiladi. status / workspace_id / want_* / position_id /
--       branch_folder_id / hired_by_user_id / taskfix_invited_at /
--       taskfix_user_id / kassa_* / consent_at / submitted_at / created_by /
--       referred_by (D10 — HR maydoni) — MIJOZDAN QABUL QILINMAYDI.
--       Butun jsonb qatorga hech qachon yozilmaydi (jsonb_populate_record YO'Q).
--       ⚠️ `consent` (checkbox) oq ro'yxatda BOR, lekin u qatorga YOZILMAYDI —
--       faqat shart sifatida tekshiriladi (true bo'lmasa yuborish rad etiladi).
--       `consent_at` esa hamon SERVERDA (now()) qo'yiladi.
--   (2) VALIDATSIYA TOKENNI DA'VO QILISHDAN OLDIN. Sabab: funksiya bitta
--       statement — da'vodan KEYINGI `RETURN` UPDATE'ni QAYTARMAYDI, ya'ni
--       xato formatda yuborilgan forma tokenni yoqib yuborardi va odam
--       ikkinchi marta to'ldira olmasdi.
--   (3) ATOMIK DA'VO: UPDATE ... WHERE used_at IS NULL AND expires_at > now()
--       RETURNING candidate_id (prjResetRecurrence naqshi). 0 qator → hech
--       narsa yozilmaydi va {ok:false, state:'used'|'expired'|'invalid'}.
-- ⚠️ Xatolar RAISE EXCEPTION EMAS, {ok:false, error:'...'} bilan qaytadi —
--    sahifa foydalanuvchiga tushunarli o'zbekcha xabar ko'rsatsin.
--    (Yagona istisno: nomzod qatori topilmasa — u holda TRANZAKSIYA
--     QAYTARILISHI kerak, aks holda token yoqilib, ma'lumot esa yozilmasdi.)
-- ⚠️ Funksiya FAQAT ikkita jadvalga yozadi: hr_apply_tokens (da'vo) va
--    hr_candidates (nomzod qatori). Boshqa hech qayerga.
CREATE OR REPLACE FUNCTION public.hr_apply_submit(p_token uuid, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_cand  uuid;
  v_ws    uuid;
  v_used  timestamptz;
  v_exp   timestamptz;
  v_ua    text;
  v_pref  text;      -- 'apply/<token>/' — fayl yo'llari SHU bilan boshlanishi shart
  v_tmp   text;
  -- ── OQ RO'YXAT (faqat shular o'qiladi) ────────────────────────────────
  v_full   text; v_birth  date; v_gender text; v_pinfl text;
  v_pser   text; v_pby    text; v_pat    date; v_pex   date;
  v_addr   text; v_phone  text; v_pname  text; v_pphone text; v_email text;
  v_ph     text; v_pf     text; v_pb     text;
  v_ppf    text; v_ppb    text; v_ctr    text;
  v_cver   text; v_cons   text;
BEGIN
  IF p_token IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'state', 'invalid');
  END IF;
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ma''lumot yuborilmadi.');
  END IF;

  -- 🔴 lower(): p_token::text Postgres'da doim kichik harfli, MIJOZ yuborgan
  --    yo'l esa KATTA harfli bo'lishi mumkin (havola qo'lda ko'chirilgan yoki
  --    uuid'ni uppercase qiladigan tizim). Storage policy'si ((...))::uuid
  --    bilan normallashtirgani uchun bunday fayl OMBORGA MUVAFFAQIYATLI
  --    tushardi, keyin shu prefiks solishtiruvi uni rad etib odamni abadiy
  --    tiqilib qoldirardi. Solishtiruv katta-kichik harfga SEZGIR EMAS
  --    (mijoz tomonida ham token kichik harfga keltiriladi — ikki qatlam).
  v_pref := 'apply/' || lower(p_token::text) || '/';

  -- ── 1) OQ RO'YXATNI O'QISH (nomma-nom) ──────────────────────────────
  v_full   := nullif(btrim(p_payload->>'full_name'), '');
  v_gender := nullif(btrim(lower(p_payload->>'gender')), '');
  v_pinfl  := nullif(regexp_replace(coalesce(p_payload->>'pinfl', ''), '[^0-9]', '', 'g'), '');
  v_pser   := nullif(upper(regexp_replace(coalesce(p_payload->>'passport_serial', ''), '[^A-Za-z0-9]', '', 'g')), '');
  v_pby    := nullif(btrim(p_payload->>'passport_issued_by'), '');
  v_addr   := nullif(btrim(p_payload->>'address'), '');
  v_phone  := nullif(btrim(p_payload->>'phone'), '');
  v_pname  := nullif(btrim(p_payload->>'parent_name'), '');
  v_pphone := nullif(btrim(p_payload->>'parent_phone'), '');
  v_email  := nullif(btrim(lower(p_payload->>'email')), '');
  v_ph     := nullif(btrim(p_payload->>'photo_path'), '');
  v_pf     := nullif(btrim(p_payload->>'passport_front_path'), '');
  v_pb     := nullif(btrim(p_payload->>'passport_back_path'), '');
  v_ppf    := nullif(btrim(p_payload->>'parent_passport_front_path'), '');
  v_ppb    := nullif(btrim(p_payload->>'parent_passport_back_path'), '');
  -- ⚠️ contract_path IXTIYORIY (D10): nomzod sahifasida shartnoma maydoni yo'q,
  --    lekin kelsa qabul qilinadi va prefiksi baribir tekshiriladi.
  v_ctr    := nullif(btrim(p_payload->>'contract_path'), '');
  -- 🔴 `referred_by` ATAYLAB O'QILMAYDI (D10 — faqat HR to'ldiradi).
  --    Mijoz uni yuborsa e'tiborsiz qoladi; oxirgi tekshiruv bloki uning
  --    qayta qo'shilishini taqiqlaydi (status/want_* bilan bir qatorda).
  v_cver   := nullif(btrim(p_payload->>'consent_version'), '');
  -- 🔴 Rozilikning O'ZI (checkbox) — brief 64-qator. Avval faqat
  --    consent_version kelardi, u esa checkbox holatidan QAT'I NAZAR doim
  --    yuborilardi → consent_at = now() faqat MIJOZ validatsiyasiga suyanardi.
  --    Endi shart serverda: 'true' bo'lmasa qator ham, consent_at ham yozilmaydi.
  v_cons   := lower(nullif(btrim(p_payload->>'consent'), ''));

  -- Sanalar: noto'g'ri matn cast'da xato beradi → ushlab, tushunarli javob
  BEGIN
    v_birth := nullif(btrim(p_payload->>'birth_date'), '')::date;
    v_pat   := nullif(btrim(p_payload->>'passport_issued_at'), '')::date;
    v_pex   := nullif(btrim(p_payload->>'passport_expires_at'), '')::date;
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Sana formati noto''g''ri (YYYY-MM-DD).');
  END;

  -- ── 2) VALIDATSIYA (tokenni da'vo qilishdan OLDIN — 2-qoida) ────────
  IF v_full IS NULL OR char_length(v_full) < 3 OR char_length(v_full) > 200 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'F.I.O. to''liq kiritilishi kerak.');
  END IF;
  IF v_birth IS NULL OR v_birth >= current_date OR v_birth < date '1900-01-01' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Tug''ilgan sana noto''g''ri.');
  END IF;
  IF v_gender IS NOT NULL AND v_gender NOT IN ('m', 'f') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Jinsi noto''g''ri.');
  END IF;
  IF v_pinfl IS NULL OR v_pinfl !~ '^[0-9]{14}$' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'JSHSHIR (PINFL) 14 ta raqamdan iborat bo''lishi kerak.');
  END IF;
  IF v_pser IS NULL OR v_pser !~ '^[A-Z]{2}[0-9]{7}$' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Passport seriyasi noto''g''ri (namuna: AA1234567).');
  END IF;
  IF v_pby IS NOT NULL AND char_length(v_pby) > 300 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Passport kim tomonidan berilgani juda uzun.');
  END IF;
  IF v_pat IS NOT NULL AND (v_pat > current_date OR v_pat < date '1900-01-01') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Passport berilgan sana noto''g''ri.');
  END IF;
  IF v_pat IS NOT NULL AND v_pex IS NOT NULL AND v_pex <= v_pat THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Passport amal qilish muddati berilgan sanadan keyin bo''lishi kerak.');
  END IF;
  IF v_addr IS NULL OR char_length(v_addr) < 5 OR char_length(v_addr) > 500 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Yashash manzili to''liq kiritilishi kerak.');
  END IF;
  IF v_pname IS NULL OR char_length(v_pname) < 3 OR char_length(v_pname) > 200 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ota/ona F.I.O. kiritilishi kerak.');
  END IF;

  -- Telefonlar: faqat raqamlar bo'yicha tekshiriladi (format erkin)
  IF v_phone IS NULL
     OR char_length(regexp_replace(v_phone, '[^0-9]', '', 'g')) NOT BETWEEN 7 AND 15
     OR char_length(v_phone) > 30 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Telefon raqami noto''g''ri.');
  END IF;
  IF v_pphone IS NULL
     OR char_length(regexp_replace(v_pphone, '[^0-9]', '', 'g')) NOT BETWEEN 7 AND 15
     OR char_length(v_pphone) > 30 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ota/ona telefon raqami noto''g''ri.');
  END IF;

  IF v_email IS NULL
     OR char_length(v_email) > 200
     OR v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Email manzili noto''g''ri.');
  END IF;

  -- Rozilik (D7 / brief 64-qator): SERVERDA tekshiriladi.
  -- 🔴 Ikki shart ham majburiy: belgilangan checkbox (consent = true) VA
  --    versiya. Faqat versiya bo'lsa, mijoz kodidagi bitta xato (yoki qo'lda
  --    yuborilgan so'rov) rozilikni chetlab o'tardi va consent_at yolg'on
  --    yozilardi.
  IF v_cons IS DISTINCT FROM 'true' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Rozilik tasdiqlanmagan.');
  END IF;
  IF v_cver IS NULL OR char_length(v_cver) > 40 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Shaxsiy ma''lumotlarga rozilik tasdiqlanmagan.');
  END IF;

  -- 🔴 FAYL YO'LLARI — 5 TASI MAJBURIY, har biri aynan shu tokenning
  --    papkasida bo'lishi shart (apply/<token>/...). Aks holda mijoz boshqa
  --    yo'lni ko'rsatib qatorga begona path yozdirardi.
  FOREACH v_tmp IN ARRAY ARRAY[v_ph, v_pf, v_pb, v_ppf, v_ppb] LOOP
    IF v_tmp IS NULL
       OR char_length(v_tmp) > 400
       OR lower(left(v_tmp, char_length(v_pref))) <> v_pref THEN
      RETURN jsonb_build_object('ok', false,
        'error', 'Hujjatlar to''liq yuklanmadi. Sahifani yangilab, qaytadan urinib ko''ring.');
    END IF;
  END LOOP;

  -- 🔴 SHARTNOMA (D10): nomzod uchun IXTIYORIY — sahifasida bu maydon yo'q,
  --    uni HR yuklaydi. LEKIN kelsa prefiks tekshiruvi BARIBIR qo'llanadi:
  --    "bo'lsa tekshir, bo'lmasa o'tkaz" — begona yo'l yozdirilmasin.
  IF v_ctr IS NOT NULL
     AND (char_length(v_ctr) > 400
          OR lower(left(v_ctr, char_length(v_pref))) <> v_pref) THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'Shartnoma fayli qabul qilinmadi. Sahifani yangilab, qaytadan urinib ko''ring.');
  END IF;

  -- ── 3) User-Agent (audit) ───────────────────────────────────────────
  BEGIN
    v_ua := current_setting('request.headers', true)::jsonb ->> 'user-agent';
  EXCEPTION WHEN others THEN
    v_ua := NULL;
  END;
  v_ua := left(coalesce(v_ua, nullif(btrim(coalesce(p_payload->>'_ua', '')), ''), ''), 300);

  -- ── 4) ATOMIK DA'VO (3-qoida) ───────────────────────────────────────
  UPDATE public.hr_apply_tokens
     SET used_at = now(),
         used_ua = v_ua
   WHERE token = p_token
     AND used_at IS NULL
     AND expires_at > now()
  RETURNING candidate_id, workspace_id INTO v_cand, v_ws;

  IF NOT FOUND THEN
    -- Sababni aniqlaymiz (hech narsa yozilmadi)
    SELECT t.used_at, t.expires_at INTO v_used, v_exp
      FROM public.hr_apply_tokens t WHERE t.token = p_token;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'state', 'invalid');
    ELSIF v_used IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'state', 'used');
    ELSE
      RETURN jsonb_build_object('ok', false, 'state', 'expired');
    END IF;
  END IF;

  -- ── 5) NOMZOD QATORI ────────────────────────────────────────────────
  UPDATE public.hr_candidates SET
      full_name                  = v_full,
      birth_date                 = v_birth,
      -- ⚠️ IXTIYORIY maydonlar COALESCE bilan: nomzod bo'sh qoldirsa HR
      --    OLDIN kiritgan qiymat O'CHIB KETMASIN (referred_by dagi naqsh).
      --    Majburiy maydonlar (F.I.O., PINFL, passport seriyasi, manzil,
      --    telefonlar, email, fayllar) validatsiyadan o'tgani uchun hech
      --    qachon NULL emas — ular to'g'ridan yoziladi.
      gender                     = COALESCE(v_gender, gender),
      pinfl                      = v_pinfl,
      passport_serial            = v_pser,
      passport_issued_by         = COALESCE(v_pby, passport_issued_by),
      passport_issued_at         = COALESCE(v_pat, passport_issued_at),
      passport_expires_at        = COALESCE(v_pex, passport_expires_at),
      address                    = v_addr,
      phone                      = v_phone,
      parent_name                = v_pname,
      parent_phone               = v_pphone,
      email                      = v_email,
      photo_path                 = v_ph,
      passport_front_path        = v_pf,
      passport_back_path         = v_pb,
      parent_passport_front_path = v_ppf,
      parent_passport_back_path  = v_ppb,
      -- 🔴 D10: shartnomani HR OLDIN yuklagan bo'lishi mumkin — nomzod
      --    yubormasa (v_ctr NULL) o'sha qiymat O'CHIB KETMASIN.
      contract_path              = COALESCE(v_ctr, contract_path),
      -- ⚠️ `referred_by` va `position_id` bu yerda UMUMAN yozilmaydi (D10) —
      --    ular HR maydonlari, nomzod yuborishi ularga ta'sir qilmaydi.
      consent_at                 = now(),
      consent_version            = v_cver,
      status                     = 'pending',
      submitted_at               = now()
   WHERE id = v_cand
     AND workspace_id = v_ws;

  IF NOT FOUND THEN
    -- Bu holat bo'lishi mumkin emas (token → candidate FK CASCADE).
    -- Baribir jimgina o'tkazmaymiz: EXCEPTION butun statement'ni, ya'ni
    -- yuqoridagi token da'vosini ham QAYTARADI (token yonib ketmaydi).
    RAISE EXCEPTION 'hr_apply_submit: nomzod qatori topilmadi (candidate=%)', v_cand;
  END IF;

  RETURN jsonb_build_object('ok', true, 'state', 'submitted');
END;
$fn$;

COMMENT ON FUNCTION public.hr_apply_submit(uuid, jsonb) IS
  'Public apply formasini qabul qiladi. SECURITY DEFINER — anon hr_candidates ga TO''G''RIDAN yoza olmaydi (D2). Tanasida 3 majburiy qoida: (1) p_payload dan faqat oq ro''yxatdagi maydonlar ->> bilan o''qiladi (status/workspace_id/want_*/position_id/branch_folder_id/hired_by_user_id/taskfix_user_id/kassa_*/consent_at/referred_by QABUL QILINMAYDI); (2) validatsiya token da''vosidan OLDIN; (3) UPDATE hr_apply_tokens ... WHERE used_at IS NULL AND expires_at > now() — atomik, ikki marta yuborish imkonsiz. Faqat 2 jadvalga yozadi.';

REVOKE ALL ON FUNCTION public.hr_apply_submit(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hr_apply_submit(uuid, jsonb) TO anon, authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- 7) STORAGE bucket `hr-docs` (PRIVATE)
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO storage.buckets (id, name, public)
VALUES ('hr-docs', 'hr-docs', false)
ON CONFLICT (id) DO NOTHING;

-- Fayl hajmi chegarasi: anon write-only yuklay oladi (token bilan), shuning
-- uchun cheksiz hajm suiiste'mol yo'li bo'lardi. Faqat BELGILANMAGAN bo'lsa
-- qo'yiladi — admin qo'lda o'zgartirgan bo'lsa bosilmaydi.
-- ⚠️ allowed_mime_types ATAYLAB qo'yilmaydi: shartnoma pdf/docx/rasm bo'lishi
--    mumkin, ro'yxat tor bo'lsa HR yuklashi to'silardi.
DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'storage' AND table_name = 'buckets'
                AND column_name = 'file_size_limit') THEN
    EXECUTE 'UPDATE storage.buckets SET file_size_limit = 10485760
              WHERE id = ''hr-docs'' AND file_size_limit IS NULL';
  END IF;
END $do$;


-- ════════════════════════════════════════════════════════════════════════════
-- 8) STORAGE POLICY'LARI (D2) — eng muhim xavfsizlik qismi
-- ════════════════════════════════════════════════════════════════════════════
-- YO'L SXEMASI (boshqasi qabul qilinmaydi):
--   apply/<token>/<fayl>            ← anon (nomzod) YOZADI, o'qiy OLMAYDI
--   ws/<workspace_id>/<...>/<fayl>  ← HR yozadi/o'qiydi
--
-- 🔴 anon: FAQAT INSERT. SELECT/UPDATE/DELETE policy YO'Q → write-only.
--    Ya'ni haqiqiy token bilan ham boshqa nomzodning (yoki o'zining) faylini
--    o'qib/o'chirib bo'lmaydi.
--
-- ⚠️ ::uuid CAST HECH QACHON QOROVULSIZ QILINMAYDI. Postgres AND'da hisoblash
--    tartibini KAFOLATLAMAYDI, ya'ni buzuq nomli obyekt (apply/xyz/a.jpg)
--    cast xatosi berib BUTUN so'rovni yiqitardi. Shuning uchun CASE + uuid
--    regex — 41_staff_import_data.sql dagi aynan o'sha naqsh.
--
-- ⚠️ HR `apply/<token>/...` fayllarini QANDAY o'qiydi: policy ichida
--    `EXISTS (SELECT 1 FROM public.hr_apply_tokens ...)`. Bu subquery
--    CHAQIRUVCHI rol huquqi bilan baholanadi, ya'ni hr_apply_tokens ning
--    O'Z RLS'i qo'llanadi → qatorni faqat o'sha workspace'ning
--    is_ws_manager / hr_is_editor foydalanuvchisi ko'radi. Demak shartning
--    o'zi workspace bilan chegaralaydi (yo'lda workspace_id yo'q bo'lsa ham).
--    anon esa hr_apply_tokens ga umuman ruxsatsiz → bu shox unga hech qachon
--    ochilmaydi. Rekursiya yo'q: hr_apply_tokens policy'lari storage.objects
--    ga murojaat qilmaydi.
DO $do$
DECLARE
  v_re   text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_seg1 text := '(storage.foldername(name))[1]';
  v_seg2 text := '(storage.foldername(name))[2]';
  v_hr   boolean;
  v_wsx  text;   -- ws/<uuid> shoxi
  v_apx  text;   -- apply/<token> shoxi (authenticated uchun)
  v_cond text;
BEGIN
  v_hr := EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'hr_is_editor' AND p.pronargs = 2
  );

  -- ws/<workspace_id>/... — HR papkasi
  v_cond := 'is_ws_manager(((' || v_seg2 || '))::uuid, (SELECT auth.uid()))';
  IF v_hr THEN
    v_cond := v_cond || ' OR hr_is_editor(((' || v_seg2 || '))::uuid, (SELECT auth.uid()))';
  END IF;

  v_wsx := 'CASE WHEN ' || v_seg1 || ' = ''ws'' AND ' || v_seg2 || ' ~ ''' || v_re || ''''
        || ' THEN (' || v_cond || ') ELSE false END';

  -- apply/<token>/... — nomzod yuklagan fayllar (HR o'qiydi)
  v_apx := 'CASE WHEN ' || v_seg1 || ' = ''apply'' AND ' || v_seg2 || ' ~ ''' || v_re || ''''
        || ' THEN EXISTS (SELECT 1 FROM public.hr_apply_tokens tk'
        || ' WHERE tk.token = ((' || v_seg2 || '))::uuid) ELSE false END';

  -- ── anon: FAQAT INSERT, faqat apply/<OCHIQ token>/... ──────────────
  EXECUTE 'DROP POLICY IF EXISTS "hrdocs_anon_insert" ON storage.objects';
  EXECUTE 'CREATE POLICY "hrdocs_anon_insert" ON storage.objects
             AS PERMISSIVE FOR INSERT TO anon
             WITH CHECK (
               bucket_id = ''hr-docs''
               AND ' || v_seg1 || ' = ''apply''
               AND CASE WHEN ' || v_seg2 || ' ~ ''' || v_re || '''
                        THEN public.hr_token_open(((' || v_seg2 || '))::uuid)
                        ELSE false END
             )';

  -- 🔴 anon uchun SELECT / UPDATE / DELETE policy ATAYLAB YO'Q.
  --    Eski (avvalgi run) qoldig'i bo'lsa tozalanadi:
  EXECUTE 'DROP POLICY IF EXISTS "hrdocs_anon_select" ON storage.objects';
  EXECUTE 'DROP POLICY IF EXISTS "hrdocs_anon_update" ON storage.objects';
  EXECUTE 'DROP POLICY IF EXISTS "hrdocs_anon_delete" ON storage.objects';

  -- ── authenticated: HR papkasi + o'z workspace'idagi apply fayllari ──
  EXECUTE 'DROP POLICY IF EXISTS "hrdocs_auth_select" ON storage.objects';
  EXECUTE 'CREATE POLICY "hrdocs_auth_select" ON storage.objects
             AS PERMISSIVE FOR SELECT TO authenticated
             USING ( bucket_id = ''hr-docs'' AND ((' || v_wsx || ') OR (' || v_apx || ')) )';

  -- INSERT faqat ws/... ga: HR nomzod papkasiga fayl qo'shmaydi
  EXECUTE 'DROP POLICY IF EXISTS "hrdocs_auth_insert" ON storage.objects';
  EXECUTE 'CREATE POLICY "hrdocs_auth_insert" ON storage.objects
             AS PERMISSIVE FOR INSERT TO authenticated
             WITH CHECK ( bucket_id = ''hr-docs'' AND (' || v_wsx || ') )';

  EXECUTE 'DROP POLICY IF EXISTS "hrdocs_auth_update" ON storage.objects';
  EXECUTE 'CREATE POLICY "hrdocs_auth_update" ON storage.objects
             AS PERMISSIVE FOR UPDATE TO authenticated
             USING      ( bucket_id = ''hr-docs'' AND ((' || v_wsx || ') OR (' || v_apx || ')) )
             WITH CHECK ( bucket_id = ''hr-docs'' AND ((' || v_wsx || ') OR (' || v_apx || ')) )';

  EXECUTE 'DROP POLICY IF EXISTS "hrdocs_auth_delete" ON storage.objects';
  EXECUTE 'CREATE POLICY "hrdocs_auth_delete" ON storage.objects
             AS PERMISSIVE FOR DELETE TO authenticated
             USING ( bucket_id = ''hr-docs'' AND ((' || v_wsx || ') OR (' || v_apx || ')) )';

EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE EXCEPTION 'storage.objects ga policy yaratish huquqi yo''q (%). Supabase SQL Editor''da `postgres` roli bilan ishga tushiring yoki policy''larni Dashboard → Storage → Policies orqali qo''ying. HECH NARSA o''rnatilmadi.', SQLERRM;
END $do$;


-- ════════════════════════════════════════════════════════════════════════════
-- 9) TEKSHIRUV — JIMGINA O'TMASIN
-- ════════════════════════════════════════════════════════════════════════════
DO $chk$
DECLARE
  v_cnt  int;
  v_txt  text;
  v_src  text;
  v_norm text;   -- izohsiz + bo'shliqlar normallashtirilgan + UPPER
  v_flat text;   -- v_norm, bo'shliqsiz va qo'shtirnoqsiz (naqsh qidirish uchun)
  t      text;
  r      record;
BEGIN
  -- ── 9.a) Ikkala jadval bor va RLS yoqilgan ────────────────────────
  FOREACH t IN ARRAY ARRAY['hr_candidates','hr_apply_tokens'] LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE EXCEPTION '%: jadval yaratilmadi', t;
    END IF;
    SELECT count(*) INTO v_cnt FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = t AND c.relrowsecurity;
    IF v_cnt = 0 THEN
      RAISE EXCEPTION '%: RLS yoqilmadi — passport/JSHSHIR hammaga ochiq qolardi!', t;
    END IF;
  END LOOP;

  -- ── 9.b) Ustunlar to'liqmi (jadval avval boshqa sxema bilan yaratilgan
  --         bo'lsa CREATE TABLE IF NOT EXISTS jimgina o'tib ketardi) ─────
  SELECT count(*) INTO v_cnt FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'hr_candidates'
     AND column_name IN ('id','workspace_id','status','full_name','birth_date','gender',
                         'pinfl','passport_serial','passport_issued_by','passport_issued_at',
                         'passport_expires_at','address','phone','parent_name','parent_phone',
                         'email','photo_path','passport_front_path','passport_back_path',
                         'parent_passport_front_path','parent_passport_back_path','contract_path',
                         'position_id','branch_folder_id','hired_by_user_id',
                         'taskfix_user_id','referred_by',
                         'start_date','notes','want_taskfix_invite','want_kassa',
                         'taskfix_invited_at','kassa_created_at','kassa_error',
                         'consent_at','consent_version','created_by','created_at',
                         'updated_at','submitted_at');
  IF v_cnt <> 40 THEN
    RAISE EXCEPTION 'hr_candidates ustunlari to''liq emas (% / 40) — jadval avval boshqa sxema bilan yaratilganmi? Qo''lda tekshiring.', v_cnt;
  END IF;

  SELECT count(*) INTO v_cnt FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'hr_apply_tokens'
     AND column_name IN ('token','workspace_id','candidate_id','created_by',
                         'created_at','expires_at','used_at','used_ua');
  IF v_cnt <> 8 THEN
    RAISE EXCEPTION 'hr_apply_tokens ustunlari to''liq emas (% / 8)', v_cnt;
  END IF;

  -- ── 9.c) CHECK'lar (conrelid bilan skoplangan — conname global unikal emas)
  SELECT count(*) INTO v_cnt FROM pg_constraint
   WHERE contype = 'c' AND conrelid = 'public.hr_candidates'::regclass
     AND conname IN ('hr_candidates_status_chk','hr_candidates_gender_chk',
                     'hr_candidates_pinfl_chk','hr_candidates_passport_chk');
  IF v_cnt <> 4 THEN
    RAISE EXCEPTION 'hr_candidates CHECK''lari to''liq emas (% / 4)', v_cnt;
  END IF;

  -- ── 9.d) Indekslar ────────────────────────────────────────────────
  FOREACH t IN ARRAY ARRAY['hr_candidates_ws_status_idx','hr_apply_tokens_cand_idx'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = t) THEN
      RAISE EXCEPTION '% indeksi yaratilmadi', t;
    END IF;
  END LOOP;

  -- ── 9.e) Har jadvalda 4 tadan policy, HAMMASI faqat authenticated ──
  FOREACH t IN ARRAY ARRAY['hr_candidates','hr_apply_tokens'] LOOP
    SELECT count(*) INTO v_cnt FROM pg_policies
     WHERE schemaname = 'public' AND tablename = t;
    IF v_cnt < 4 THEN
      RAISE EXCEPTION '%: policy''lar to''liq emas (% ta, 4 kutilgan)', t, v_cnt;
    END IF;

    -- 🔴 anon (yoki public) uchun policy BO'LMASLIGI SHART
    SELECT string_agg(policyname || ' (' || cmd || ')', ', ') INTO v_txt
      FROM pg_policies
     WHERE schemaname = 'public' AND tablename = t
       AND roles::text[] && ARRAY['anon','public'];
    IF v_txt IS NOT NULL THEN
      RAISE EXCEPTION '%: anon/public uchun policy topildi: % — shaxsiy ma''lumot ochilib ketardi. To''xtatildi.', t, v_txt;
    END IF;

    -- Shart haqiqatan workspace bilan cheklaydimi? (kimdir USING(true) qilib
    -- qayta yozsa shu yerda to'xtaydi)
    FOR r IN SELECT policyname, coalesce(qual, '') || ' ' || coalesce(with_check, '') AS expr
               FROM pg_policies WHERE schemaname = 'public' AND tablename = t
    LOOP
      IF strpos(upper(r.expr), 'IS_WS_MANAGER(') = 0 THEN
        RAISE EXCEPTION '%.% policy''sida is_ws_manager(...) yo''q — shart: %. To''xtatildi.', t, r.policyname, r.expr;
      END IF;
    END LOOP;
  END LOOP;

  -- ── 9.f) 3 funksiya bor va SECURITY DEFINER ───────────────────────
  FOREACH t IN ARRAY ARRAY['hr_token_open','hr_apply_peek','hr_apply_submit'] LOOP
    SELECT count(*) INTO v_cnt FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = t AND p.prosecdef;
    IF v_cnt = 0 THEN
      RAISE EXCEPTION '%() yaratilmadi yoki SECURITY DEFINER emas', t;
    END IF;
  END LOOP;

  -- anon uchtala funksiyani ham chaqira olishi SHART (apply sahifasi + storage policy)
  FOREACH t IN ARRAY ARRAY['public.hr_token_open(uuid)','public.hr_apply_peek(uuid)',
                           'public.hr_apply_submit(uuid, jsonb)'] LOOP
    IF NOT has_function_privilege('anon', t, 'EXECUTE') THEN
      RAISE EXCEPTION 'anon roli % ni chaqira olmaydi — apply sahifasi ishlamas edi.', t;
    END IF;
  END LOOP;

  -- ── 9.g) hr_apply_peek() ORTIQCHA MA'LUMOT QAYTARMASLIGI ──────────
  SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'hr_apply_peek' AND p.pronargs = 1
   LIMIT 1;
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'hr_apply_peek(uuid) tanasi o''qilmadi';
  END IF;
  IF strpos(upper(v_src), 'HR_CANDIDATES') > 0 THEN
    RAISE EXCEPTION 'hr_apply_peek() KODIDA hr_candidates ga murojaat bor — nomzod ma''lumoti sizib chiqardi (brief 44-qator). To''xtatildi.';
  END IF;

  -- ── 9.h) hr_apply_submit() tanasidagi MAJBURIY qorovullar ─────────
  -- Izohlar avval tozalanadi (TASKFIX_HR_EDITORS.sql 4.b2 naqshi): tanadagi
  -- ogohlantirish izohlarida ham shu matnlar bor — kod o'chirilib izoh
  -- qoldirilgan holat sezilmay qolmasin.
  SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'hr_apply_submit' AND p.pronargs = 2
   LIMIT 1;
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'hr_apply_submit(uuid, jsonb) tanasi o''qilmadi';
  END IF;

  v_norm := upper(regexp_replace(v_src, '\s+', ' ', 'g'));
  v_flat := replace(replace(v_norm, '''', ''), ' ', '');

  -- 🔴 ATOMIK DA'VO (butun ifoda — yakka kalit so'z yetarli emas)
  IF strpos(v_flat, 'WHERETOKEN=P_TOKENANDUSED_ATISNULLANDEXPIRES_AT>NOW()') = 0 THEN
    RAISE EXCEPTION 'hr_apply_submit() KODIDA atomik da''vo (WHERE token = p_token AND used_at IS NULL AND expires_at > now()) topilmadi — bir martalik havola ikki marta ishlatilishi mumkin bo''lardi. To''xtatildi.';
  END IF;
  IF strpos(v_flat, 'SETUSED_AT=NOW()') = 0 THEN
    RAISE EXCEPTION 'hr_apply_submit() KODIDA "SET used_at = now()" topilmadi — token yopilmasdi. To''xtatildi.';
  END IF;
  IF strpos(v_flat, 'STATUS=PENDING') = 0 THEN
    RAISE EXCEPTION 'hr_apply_submit() KODIDA status = ''pending'' yozilmayapti (D8). To''xtatildi.';
  END IF;
  IF strpos(v_flat, 'CONSENT_AT=NOW()') = 0 THEN
    RAISE EXCEPTION 'hr_apply_submit() KODIDA consent_at = now() yo''q — rozilik lahzasi yozilmasdi (D7). To''xtatildi.';
  END IF;
  -- 🔴 ROZILIK SERVERDA TEKSHIRILADIMI (brief 64-qator). Faqat consent_version
  --    ga suyanish YETARLI EMAS: u checkbox holatidan qat'i nazar yuboriladi.
  IF strpos(v_flat, 'P_PAYLOAD->>CONSENT)') = 0
     OR strpos(v_flat, 'V_CONSISDISTINCTFROMTRUE') = 0 THEN
    RAISE EXCEPTION 'hr_apply_submit() KODIDA rozilik tekshirilmayapti (p_payload->>''consent'' <> ''true'' bo''lsa rad etilishi shart) — consent_at faqat mijoz validatsiyasiga suyanardi (brief 64-qator). To''xtatildi.';
  END IF;
  IF strpos(v_flat, 'SUBMITTED_AT=NOW()') = 0 THEN
    RAISE EXCEPTION 'hr_apply_submit() KODIDA submitted_at = now() yo''q. To''xtatildi.';
  END IF;

  -- 🔴 OQ RO'YXAT BUZILMAGANMI: quyidagi kalitlar p_payload dan HECH QACHON
  --    o'qilmasligi kerak. Kimdir keyin qo'shsa — skript qayta run qilinganda
  --    SHU YERDA qichqiradi.
  --    ⚠️ 'TASKFIX_' — prefiks: taskfix_invited_at ham, taskfix_user_id ham.
  --    ⚠️ 'REFERRED_BY' — D10: "kim taklif qildi" faqat HR maydoni.
  FOREACH t IN ARRAY ARRAY['STATUS','WORKSPACE_ID','WANT_','POSITION_ID','BRANCH_FOLDER_ID',
                           'HIRED_BY_USER_ID','TASKFIX_','KASSA_','CONSENT_AT',
                           'SUBMITTED_AT','CREATED_BY','REFERRED_BY','ID'] LOOP
    IF strpos(v_flat, 'P_PAYLOAD->>' || t) > 0 OR strpos(v_flat, 'P_PAYLOAD->' || t) > 0 THEN
      RAISE EXCEPTION 'hr_apply_submit() KODIDA p_payload dan "%" o''qilmoqda — bu maydon MIJOZDAN qabul qilinmasligi kerak (D2 oq ro''yxati). To''xtatildi.', lower(t);
    END IF;
  END LOOP;
  IF strpos(v_flat, 'JSONB_POPULATE_RECORD') > 0 OR strpos(v_flat, 'JSONB_TO_RECORD') > 0 THEN
    RAISE EXCEPTION 'hr_apply_submit() butun jsonb ni qatorga yozmoqchi (jsonb_populate_record/to_record) — oq ro''yxat chetlab o''tilgan. To''xtatildi.';
  END IF;

  -- 🔴 OQ RO'YXAT SONI: p_payload dan o'qiladigan kalitlar soni aynan 22
  --    bo'lishi shart = 21 ta nomzod maydoni + 1 ta `_ua` (audit metadata).
  --    Taqiqlangan ro'yxat FAQAT bilingan xavfli nomlarni tutadi; bu son esa
  --    KUTILMAGAN yangi kalit qo'shilishini ham ushlaydi (masalan mijoz
  --    yuboradigan yangi ustun jimgina oq ro'yxatga kirib ketmasin).
  --    ⚠️ Ataylab yangi maydon qo'shsangiz: shu sonni ham yangilang.
  v_cnt := array_length(string_to_array(v_flat, 'P_PAYLOAD->>'), 1) - 1;
  IF v_cnt <> 22 THEN
    RAISE EXCEPTION 'hr_apply_submit() oq ro''yxatida % ta kalit bor, 22 kutilgan (21 maydon + _ua). Kimdir maydon qo''shgan yoki olib tashlagan — D2/D10 oq ro''yxatini qayta ko''rib chiqing. To''xtatildi.', v_cnt;
  END IF;

  -- ── 9.i) BUCKET bor va PRIVATE ────────────────────────────────────
  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'hr-docs') THEN
    RAISE EXCEPTION 'hr-docs bucket yaratilmadi';
  END IF;
  IF EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'hr-docs' AND public IS TRUE) THEN
    RAISE EXCEPTION 'hr-docs bucket PUBLIC bo''lib qolgan — passport rasmlari internetga ochiq bo''lardi! Dashboard → Storage → hr-docs → Private qiling va skriptni qayta ishga tushiring. HECH NARSA o''rnatilmadi.';
  END IF;

  -- ── 9.j) Storage policy'lari ──────────────────────────────────────
  FOREACH t IN ARRAY ARRAY['hrdocs_anon_insert','hrdocs_auth_select','hrdocs_auth_insert',
                           'hrdocs_auth_update','hrdocs_auth_delete'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = t) THEN
      RAISE EXCEPTION 'storage.objects da % policy''si yaratilmadi', t;
    END IF;
  END LOOP;

  -- anon INSERT policy'si haqiqatan token bilan cheklaydimi?
  SELECT upper(coalesce(with_check, '')) INTO v_txt
    FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects'
     AND policyname = 'hrdocs_anon_insert' AND cmd = 'INSERT';
  IF v_txt IS NULL THEN
    RAISE EXCEPTION 'hrdocs_anon_insert policy''si INSERT emas yoki WITH CHECK bo''sh';
  END IF;
  IF strpos(v_txt, 'HR_TOKEN_OPEN') = 0
     OR strpos(v_txt, 'APPLY') = 0
     OR strpos(v_txt, 'HR-DOCS') = 0 THEN
    RAISE EXCEPTION 'hrdocs_anon_insert sharti kutilganidek emas (hr_token_open + apply/ + hr-docs): % — anon ixtiyoriy joyga fayl yuklay olardi. To''xtatildi.', v_txt;
  END IF;

  -- 🔴 ENG MUHIM TEKSHIRUV: anon (yoki public) uchun hr-docs bo'yicha
  --    INSERT'dan BOSHQA policy BO'LMASLIGI SHART. Kimdir keyinroq SELECT
  --    qo'shib qo'ysa — nomzodlarning passport rasmlari o'qiladigan bo'lardi.
  SELECT string_agg(policyname || ' (' || cmd || ')', ', ') INTO v_txt
    FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects'
     AND roles::text[] && ARRAY['anon','public']
     AND cmd <> 'INSERT'
     AND upper(coalesce(qual, '') || ' ' || coalesce(with_check, '')) LIKE '%HR-DOCS%';
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'hr-docs uchun anon/public rolida INSERT''dan boshqa policy topildi: % — bucket write-only bo''lishi SHART (D2). To''xtatildi.', v_txt;
  END IF;

  -- ── 9.j2) DIAGNOSTIKA: bucket bilan CHEGARALANMAGAN storage policy'lari ──
  -- 🔴 SKRIPTDAN TASHQARIDAGI YAGONA REAL SIZISH YO'LI.
  --    Yuqoridagi tekshiruvlar faqat anon/public rolidagi va matnida 'hr-docs'
  --    bo'lgan policy'larni ko'radi. Agar bazada Dashboard orqali qo'yilgan,
  --    BUCKET bilan chegaralanmagan PERMISSIVE policy bo'lsa (masalan
  --    "Allow authenticated read" USING (true)), u HAR BUCKETGA, jumladan
  --    hr-docs ga ham qo'llanadi → istalgan workspace'dagi istalgan
  --    foydalanuvchi passport rasmiga signed URL ola oladi.
  -- ⚠️ ATAYLAB RAISE EXCEPTION EMAS: bu policy begona modulniki bo'lishi
  --    mumkin, uni bilmasdan o'chirish yoki skriptni bloklash noto'g'ri
  --    bo'lardi. Lekin JIMGINA ham o'tmaydi — RUN natijasida nomma-nom
  --    ko'rinadi va qaror odamda qoladi.
  v_cnt := 0;
  FOR r IN SELECT policyname,
                  cmd,
                  roles::text AS rls,
                  coalesce(qual, '') || ' ' || coalesce(with_check, '') AS expr
             FROM pg_policies
            WHERE schemaname = 'storage'
              AND tablename  = 'objects'
              AND permissive = 'PERMISSIVE'
              AND strpos(upper(coalesce(qual, '') || ' ' || coalesce(with_check, '')), 'BUCKET_ID') = 0
            ORDER BY policyname
  LOOP
    v_cnt := v_cnt + 1;
    RAISE WARNING '⚠️ storage.objects policy "%" (%, rol: %) shartida bucket_id YO''Q → u hr-docs ga ham qo''llanadi. Shart: %',
      r.policyname, r.cmd, r.rls, left(btrim(r.expr), 200);
  END LOOP;
  IF v_cnt > 0 THEN
    RAISE WARNING '⚠️ Yuqorida % ta bucket bilan CHEGARALANMAGAN storage policy''si bor. Bu skript ularga TEGMADI. NIMA QILISH KERAK: Dashboard → Storage → Policies da har biriga `bucket_id = ''<o''sha modul bucketi>''` shartini qo''shing (yoki keraksiz bo''lsa o''chiring). Aks holda SELECT shoxi orqali nomzodlarning passport/JSHSHIR rasmlari begona foydalanuvchiga ochiladi, INSERT shoxi orqali esa hr-docs ga begona fayl yuklanadi.', v_cnt;
  ELSE
    RAISE NOTICE '  storage.objects : bucket bilan chegaralanmagan PERMISSIVE policy topilmadi ✓';
  END IF;

  -- ── 9.k) Eski tizim butunmi? (bu fayl hech nimani buzmaganiga ishonch)
  FOREACH t IN ARRAY ARRAY['workspaces','positions','org_folders','org_people','tasks'] LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE EXCEPTION 'Mavjud jadval % yo''qolgan — TO''XTANG!', t;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'employee-photos') THEN
    RAISE NOTICE '⚠️ employee-photos bucket topilmadi (41-migratsiya ishga tushmaganmi?) — bu fayl unga tegmagan.';
  END IF;

  -- ── HISOBOT ───────────────────────────────────────────────────────
  SELECT count(*) INTO v_cnt FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'hr_is_editor' AND p.pronargs = 2;

  RAISE NOTICE '─────────────────────────────────────────────';
  RAISE NOTICE 'TASKFIX_HR_RECRUITING.sql — TAYYOR';
  RAISE NOTICE '  hr_candidates    : 40 ustun, 4 CHECK, RLS + 4 policy (authenticated)';
  RAISE NOTICE '  D10              : shartnoma nomzod uchun ixtiyoriy, referred_by/lavozim = HR';
  RAISE NOTICE '  hr_apply_tokens  : 8 ustun, RLS + 4 policy (authenticated)';
  RAISE NOTICE '  funksiyalar      : hr_token_open / hr_apply_peek / hr_apply_submit (SECURITY DEFINER)';
  RAISE NOTICE '  bucket hr-docs   : PRIVATE, anon = FAQAT INSERT (apply/<token>/...)';
  RAISE NOTICE '  storage policy   : 5 ta (1 anon INSERT + 4 authenticated)';
  IF v_cnt = 0 THEN
    RAISE NOTICE '  ⚠️ hr_is_editor(): YO''Q → faqat owner/admin ishlata oladi.';
    RAISE NOTICE '     TASKFIX_HR_EDITORS.sql ni ishga tushirib, SHU faylni QAYTA run qiling.';
  ELSE
    RAISE NOTICE '  hr_is_editor()   : bor → HR muharriri ham ishlata oladi';
  END IF;
  RAISE NOTICE '─────────────────────────────────────────────';
END $chk$;

COMMIT;

-- ============================================================================
-- KEYIN NIMA BO'LADI
--   • 2-bosqich: `hr-apply.html` (public forma) + `index.html` da "Hodim ishga
--     olish" ro'yxati/formasi va link generatsiyasi.
--   • 3-bosqich: BOX amallari (TaskFix invitation + kassa) — D6 bo'yicha
--     ALOHIDA va IDEMPOTENT (optimistik da'vo:
--     UPDATE ... SET taskfix_invited_at = now() WHERE id = ? AND
--     taskfix_invited_at IS NULL RETURNING id → 0 qator = jim chiqish).
--
-- MIJOZ TOMONI UCHUN QISQA ESLATMA (kod bu faylda YO'Q):
--   const { data, error } = await sb.rpc('hr_apply_peek',   { p_token: t });
--   const { data, error } = await sb.rpc('hr_apply_submit', { p_token: t, p_payload: {...} });
--   ⚠️ `{ error }` DOIM tekshiriladi (supabase-js throw QILMAYDI — 6-qoida),
--      va `data.ok === false` bo'lsa `data.error` / `data.state` ko'rsatiladi
--      (RPC muvaffaqiyatli qaytgani "saqlandi" degani EMAS).
--   ⚠️ Fayl yuklash: sb.storage.from('hr-docs').upload('apply/' + t + '/' + nom, file)
--      Preview MAHALLIY (URL.createObjectURL) — o'qish policy'si YO'Q.
--
-- ── QAYTARISH (rollback) ────────────────────────────────────────────────────
--   DROP POLICY IF EXISTS "hrdocs_anon_insert"  ON storage.objects;
--   DROP POLICY IF EXISTS "hrdocs_auth_select"  ON storage.objects;
--   DROP POLICY IF EXISTS "hrdocs_auth_insert"  ON storage.objects;
--   DROP POLICY IF EXISTS "hrdocs_auth_update"  ON storage.objects;
--   DROP POLICY IF EXISTS "hrdocs_auth_delete"  ON storage.objects;
--   DROP FUNCTION IF EXISTS public.hr_apply_submit(uuid, jsonb);
--   DROP FUNCTION IF EXISTS public.hr_apply_peek(uuid);
--   DROP FUNCTION IF EXISTS public.hr_token_open(uuid);
--   DROP TABLE    IF EXISTS public.hr_apply_tokens CASCADE;
--   DROP TABLE    IF EXISTS public.hr_candidates   CASCADE;
--   -- Bucket va undagi fayllar ATAYLAB avtomat o'chirilmaydi (passport
--   -- hujjatlari!). Kerak bo'lsa qo'lda:
--   --   DELETE FROM storage.objects WHERE bucket_id = 'hr-docs';
--   --   DELETE FROM storage.buckets WHERE id = 'hr-docs';
--   -- ⚠️ public.org_touch() O'CHIRILMAYDI — u TASKFIX_HR.sql niki.
-- ============================================================================
