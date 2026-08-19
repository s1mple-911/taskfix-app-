-- ============================================================================
-- TASKFIX_HR_DYNAMIC.sql — HR maydon konstruktori (dinamik forma)
-- ============================================================================
-- MANBA: BRIEF_TASKFIX_HR_DYNAMIC.md (1–4 band) + Fable qarori (GIBRID model).
--
-- ── 🔴 ASOSIY ARXITEKTURA QARORI: GIBRID (EAV EMAS) ─────────────────────────
--   Mavjud `hr_candidates` USTUNLARI (full_name, pinfl, passport_serial,
--   photo_path, …) O'Z JOYIDA QOLADI. Ular EAV ga KO'CHIRILMAYDI.
--   Sabab: ko'chirilsa `hrcValidate` (mijoz), `hr_apply_submit` oq ro'yxati,
--   `admin-create-employee` EF integratsiyasi, 6 ta Storage yo'li va
--   BAZADAGI MAVJUD nomzod qatorlari buzilardi — "🔴 Eski buzilmasin" ga zid.
--   Buning o'rniga:
--     • TIZIM maydoni  (hr_fields.is_system = true,  col = mavjud ustun nomi)
--         HR ko'radi, tartibini/nomini/`required`/`fill_by` sini o'zgartiradi,
--         `active=false` bilan YASHIRADI. Lekin O'CHIRA OLMAYDI (DELETE policy)
--         va `key`/`col`/`ftype`/`is_system` ni o'zgartira olmaydi (trigger).
--     • MAXSUS maydon  (is_system = false, col IS NULL)
--         HR noldan qo'shadi; qiymatlari `hr_candidate_values` da.
--
-- ── NIMA QO'SHILADI ─────────────────────────────────────────────────────────
--   1) public.hr_fields            — maydon katalogi (workspace bo'yicha)
--   2) public.hr_candidate_values  — MAXSUS maydon qiymatlari (candidate×field)
--   3) hr_candidates ga 2 ustun    — project_id, project_started_at (4-band)
--   4) public.hr_fields_defaults() — 22 ta tizim maydonining KATALOGI (yagona
--                                    haqiqat manbai: seed ham, trigger ham,
--                                    hr_fields_seed() ham shundan o'qiydi)
--   5) public.hr_fields_seed(uuid) — workspace uchun tizim maydonlarini
--                                    idempotent yaratadi (HR keyin yoqsa)
--   6) public.hr_cand_values_guard()/public.hr_fields_guard() triggerlari
--   7) hr_apply_peek(uuid)         — KENGAYTIRILDI: `fields` massivi qo'shildi
--   8) hr_apply_submit(uuid,jsonb) — KENGAYTIRILDI: dinamik maydon + dinamik
--                                    majburiylik
--   9) RLS: ikkala yangi jadvalda 4 tadan policy (TO authenticated)
--
-- ── NIMA O'ZGARMAYDI (🔴 tegilmaydi) ────────────────────────────────────────
--   • hr_candidates ning MAVJUD ustunlari — na nomi, na turi, na ma'nosi.
--     Nomzod yuborgan qiymat AVVALGIDEK o'sha ustunlarga yoziladi.
--   • hr_apply_submit ning UCHTA QAT'IY QOIDASI (oq ro'yxat / validatsiya
--     da'vodan OLDIN / atomik da'vo) — hammasi joyida, tekshiruv bloki
--     majburlaydi.
--   • Storage: YANGI POLICY QO'SHILMAYDI (8-bo'limga qarang).
--   • hr_settings, org_folders, org_people, positions, tasks, projects,
--     workspace_members — na ustun, na policy, na trigger o'zgaradi.
--   • hr_token_open() — tegilmaydi.
--
-- ── BUSIZ ILOVA QANDAY ISHLAYDI ─────────────────────────────────────────────
--   Bu fayl RUN qilinmasa "Hodim ishga olish" AVVALGIDEK ishlaydi (qat'iy
--   forma). Mijoz `hr_fields` yo'qligini aniqlaydi (PGRST205 / 42P01) va
--   maydon konstruktorini ko'rsatmaydi.
--   RUN qilingandan KEYIN ham: workspace uchun `hr_fields` da BITTA ham qator
--   bo'lmasa — hr_apply_peek `fields: []` qaytaradi va hr_apply_submit ESKI
--   qat'iy majburiy ro'yxatiga tushadi (zaxira yo'l, ataylab).
--
-- ── RUN TARTIBI ─────────────────────────────────────────────────────────────
--   1) 39_employee_details.sql   → positions, is_ws_member(), is_ws_manager()
--   2) TASKFIX_HR.sql            → hr_settings, org_folders, org_touch()
--   3) TASKFIX_HR_EDITORS.sql    → hr_is_editor()          ⚠️ MAJBURIY
--   4) TASKFIX_HR_RECRUITING.sql → hr_candidates, hr_apply_tokens, hr-docs
--   5) TASKFIX_HR_DYNAMIC.sql    ← SHU FAYL
--
--   🔴 EHTIYOT BO'LING: agar keyinchalik TASKFIX_HR_RECRUITING.sql ni QAYTA
--      RUN qilsangiz, u `hr_apply_peek` va `hr_apply_submit` ni O'ZINING eski
--      (dinamiksiz) versiyasi bilan ALMASHTIRADI — apply sahifasidagi maxsus
--      maydonlar JIMGINA yo'qoladi. Shu holatda SHU FAYLNI HAM QAYTA RUN
--      QILING. Ikkalasi ham to'liq idempotent.
--
-- ── STORAGE (yangi policy KERAK EMAS) ───────────────────────────────────────
--   Dinamik fayl maydonlari MAVJUD yo'l sxemasidan foydalanadi:
--     nomzod : apply/<token>/f_<field_id>-<rand>.<ext>
--     HR     : ws/<workspace_id>/<candidate_id>/f_<field_id>-<rand>.<ext>
--   Mavjud policy'lar yo'lning FAQAT 1–2-segmentiga qaraydi
--   ((storage.foldername(name))[1] = 'apply' | 'ws', [2] = uuid), ya'ni
--   fayl NOMI ixtiyoriy bo'lishi mumkin → `f_<field_id>-…` qo'shimcha
--   ruxsatsiz ishlaydi. 9.i tekshiruvi buni policy matnidan tasdiqlaydi.
--
-- TEXT + CHECK ishlatilgan (ENUM emas) — 30/32-migratsiyalardagi saboq.
-- RLS ichida workspace_members inline subquery YO'Q (42P17) — CLAUDE.md 8-qoida.
-- ADDITIVE + IDEMPOTENT: qayta RUN xavfsiz. Fayl oxirida QAYTARISH bo'limi bor.
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

  IF to_regclass('public.hr_candidates') IS NULL OR to_regclass('public.hr_apply_tokens') IS NULL THEN
    RAISE EXCEPTION 'hr_candidates / hr_apply_tokens topilmadi. Avval TASKFIX_HR_RECRUITING.sql ni ishga tushiring (RUN tartibi fayl boshida).';
  END IF;

  IF to_regclass('public.hr_settings') IS NULL THEN
    RAISE EXCEPTION 'public.hr_settings topilmadi. Avval TASKFIX_HR.sql ni ishga tushiring.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'is_ws_manager') THEN
    RAISE EXCEPTION 'is_ws_manager() topilmadi. Avval 39_employee_details.sql ni ishga tushiring.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'is_ws_member') THEN
    RAISE EXCEPTION 'is_ws_member() topilmadi. Avval 39_employee_details.sql ni ishga tushiring.';
  END IF;

  -- 🔴 hr_is_editor() SHU FAYL UCHUN MAJBURIY.
  --    TASKFIX_HR_RECRUITING.sql uni IXTIYORIY deb hisoblaydi (yo'q bo'lsa
  --    policy'lar faqat is_ws_manager bilan yoziladi). Bu yerda esa policy
  --    matni STATIK yozilgan (dinamik EXECUTE yo'q) — funksiya bo'lmasa
  --    CREATE POLICY 42883 bilan yiqilardi. Shuning uchun oldindan,
  --    tushunarli xabar bilan to'xtatamiz.
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'hr_is_editor' AND p.pronargs = 2) THEN
    RAISE EXCEPTION 'hr_is_editor(uuid, uuid) topilmadi — avval TASKFIX_HR_EDITORS.sql ishga tushiring, keyin SHU faylni qayta run qiling. (HR muharriri maydonlarni sozlay olishi uchun shart.) HECH NARSA o''rnatilmadi.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    RAISE EXCEPTION '`authenticated` roli topilmadi — bu Supabase bazasi emasmi?';
  END IF;
END $do$;


-- ════════════════════════════════════════════════════════════════════════════
-- 1) public.hr_fields — maydon katalogi
-- ════════════════════════════════════════════════════════════════════════════
-- 🔴 NOM 3 TILDA USTUNDA SAQLANADI (name_uz/ru/en), i18n.json da EMAS.
--    Sabab: bu ilova UI matni emas, WORKSPACE MA'LUMOTI — HR o'zi kiritadi
--    ("Sudlanganlik hujjati"). CLAUDE.md 10-qoidasi ilova matnlariga tegishli;
--    bu yerda esa til foydalanuvchining SHAXSIY sozlamasi bo'lgani uchun
--    bitta ustunga yozib bo'lmasdi (ru tilida ochgan HR butun workspace'ga
--    rus nomini yozib qo'yardi — `kanColLabel` saboqi).
CREATE TABLE IF NOT EXISTS public.hr_fields (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id  uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,

  -- Barqaror kalit. Tizim maydonida ma'noli ('full_name', 'photo'), maxsus
  -- maydonda mijoz gen_random_uuid() dan hosil qilgan qisqa slug ('f_9c3ab1…').
  key           text NOT NULL,

  -- 🔴 FAQAT is_system da to'ladi: `hr_candidates` USTUNI nomi.
  --    Maxsus maydonda ALBATTA NULL (CHECK majburlaydi).
  col           text,
  is_system     boolean NOT NULL DEFAULT false,

  name_uz       text NOT NULL,
  name_ru       text,
  name_en       text,

  -- TEXT + CHECK (ENUM EMAS). 9 tur — brief 1-band.
  ftype         text NOT NULL,
  required      boolean NOT NULL DEFAULT false,

  -- 'hr' | 'employee' | 'both' — kim to'ldiradi (brief: "Kim to'ldiradi" box).
  fill_by       text NOT NULL DEFAULT 'both',

  -- Faqat ftype='select': [{"value":"a","uz":"…","ru":"…","en":"…"}]
  options       jsonb NOT NULL DEFAULT '[]'::jsonb,

  placeholder_uz text,
  placeholder_ru text,
  placeholder_en text,

  sort_order    int  NOT NULL DEFAULT 0,
  active        boolean NOT NULL DEFAULT true,

  -- Guruhlash uchun ixtiyoriy erkin matn (NULL = "Qo'shimcha").
  section       text,

  created_by    uuid,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz
);

-- Qayta RUN: avvalgi (yarim) versiyada yetishmagan ustunlar qo'shiladi
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS key            text;
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS col            text;
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS is_system      boolean NOT NULL DEFAULT false;
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS name_uz        text;
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS name_ru        text;
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS name_en        text;
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS ftype          text;
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS required       boolean NOT NULL DEFAULT false;
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS fill_by        text NOT NULL DEFAULT 'both';
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS options        jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS placeholder_uz text;
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS placeholder_ru text;
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS placeholder_en text;
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS sort_order     int  NOT NULL DEFAULT 0;
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS active         boolean NOT NULL DEFAULT true;
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS section        text;
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS created_by     uuid;
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS created_at     timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.hr_fields ADD COLUMN IF NOT EXISTS updated_at     timestamptz;

-- ── CHECK'lar (idempotent DROP → ADD; hammasi conrelid bilan skoplangan) ────
ALTER TABLE public.hr_fields DROP CONSTRAINT IF EXISTS hr_fields_ftype_chk;
ALTER TABLE public.hr_fields ADD  CONSTRAINT hr_fields_ftype_chk
  CHECK (ftype IN ('text','textarea','number','date','tel','email','select','checkbox','file'));

ALTER TABLE public.hr_fields DROP CONSTRAINT IF EXISTS hr_fields_fillby_chk;
ALTER TABLE public.hr_fields ADD  CONSTRAINT hr_fields_fillby_chk
  CHECK (fill_by IN ('hr','employee','both'));

-- 🔴 GIBRID MODELNING ASOSIY INVARIANTI: tizim = ustunga bog'langan,
--    maxsus = bog'lanmagan. Ikki holat orasida "yarim" qator bo'lishi mumkin
--    emas (aks holda qiymat qayerga yozilishi noaniq bo'lardi).
ALTER TABLE public.hr_fields DROP CONSTRAINT IF EXISTS hr_fields_syscol_chk;
ALTER TABLE public.hr_fields ADD  CONSTRAINT hr_fields_syscol_chk
  CHECK ((is_system AND col IS NOT NULL) OR (NOT is_system AND col IS NULL));

ALTER TABLE public.hr_fields DROP CONSTRAINT IF EXISTS hr_fields_options_arr_chk;
ALTER TABLE public.hr_fields ADD  CONSTRAINT hr_fields_options_arr_chk
  CHECK (jsonb_typeof(options) = 'array');

-- 🔴 VARIANTSIZ DROPDOWN YARATIB BO'LMASIN.
--    ⚠️ NESTED CASE — ataylab. `ftype <> 'select' OR jsonb_array_length(...)`
--    ko'rinishi XAVFLI: Postgres AND/OR da hisoblash tartibini KAFOLATLAMAYDI,
--    ya'ni options obyekt bo'lsa jsonb_array_length() BUTUN so'rovni xato bilan
--    yiqitardi (41-migratsiya / ::uuid cast saboqi). CASE esa qat'iy gate.
ALTER TABLE public.hr_fields DROP CONSTRAINT IF EXISTS hr_fields_options_chk;
ALTER TABLE public.hr_fields ADD  CONSTRAINT hr_fields_options_chk
  CHECK (
    CASE WHEN ftype = 'select'
         THEN CASE WHEN jsonb_typeof(options) = 'array'
                   THEN jsonb_array_length(options) BETWEEN 1 AND 100
                   ELSE false END
         ELSE true END
  );

ALTER TABLE public.hr_fields DROP CONSTRAINT IF EXISTS hr_fields_name_chk;
ALTER TABLE public.hr_fields ADD  CONSTRAINT hr_fields_name_chk
  CHECK (char_length(name_uz) BETWEEN 1 AND 120);

ALTER TABLE public.hr_fields DROP CONSTRAINT IF EXISTS hr_fields_key_chk;
ALTER TABLE public.hr_fields ADD  CONSTRAINT hr_fields_key_chk
  CHECK (key ~ '^[a-z0-9_]{1,40}$');

-- Har workspace ichida kalit noyob (seed ham shunga tayanadi: ON CONFLICT)
CREATE UNIQUE INDEX IF NOT EXISTS hr_fields_ws_key_uidx
  ON public.hr_fields (workspace_id, key);

-- Asosiy o'qish so'rovi: .eq(workspace_id).eq(active).order(sort_order)
CREATE INDEX IF NOT EXISTS hr_fields_ws_active_sort_idx
  ON public.hr_fields (workspace_id, active, sort_order);

COMMENT ON TABLE public.hr_fields IS
  'HR "Hodim ishga olish" formasining MAYDON KATALOGI (workspace bo''yicha). is_system=true → mavjud hr_candidates USTUNIGA bog''langan (col), o''chirib bo''lmaydi (DELETE policy) va key/col/ftype o''zgarmaydi (hr_fields_guard trigger). is_system=false → maxsus maydon, qiymati hr_candidate_values da. fill_by: hr | employee | both — apply sahifasi FAQAT employee/both ni ko''radi.';
COMMENT ON COLUMN public.hr_fields.col IS
  'hr_candidates USTUNI nomi (faqat is_system). Bu AYNI PAYTDA hr_apply_submit() oq ro''yxatidagi payload kaliti hamdir — mijoz qiymatni payload[col] ga qo''yadi, maxsus maydonni esa payload.fields[<field_id>] ga.';
COMMENT ON COLUMN public.hr_fields.name_uz IS
  'Maydon nomi (o''zbekcha). 🔴 Bu WORKSPACE ma''lumoti, ilova UI matni EMAS — i18n.json ga qo''shilmaydi. ru/en varianti name_ru/name_en da; bo''sh bo''lsa mijoz name_uz ga tushadi.';
COMMENT ON COLUMN public.hr_fields.section IS
  'Guruh sarlavhasi (ixtiyoriy, erkin matn). NULL = "Qo''shimcha". ⚠️ BITTA ustun, ya''ni tarjimasi yo''q — seed uni ATAYLAB to''ldirmaydi (ru/en foydalanuvchi o''zbekcha sarlavha ko''rmasin). HR xohlasa o''zi yozadi.';


-- ════════════════════════════════════════════════════════════════════════════
-- 2) public.hr_candidate_values — MAXSUS maydon qiymatlari
-- ════════════════════════════════════════════════════════════════════════════
-- 🔴 BU YERGA FAQAT `col IS NULL` (maxsus) maydonlar tushadi. Tizim maydoni
--    qiymati AVVALGIDEK hr_candidates USTUNIGA yoziladi — ikki joyda saqlansa
--    haqiqat manbai ikkiga bo'linardi.
CREATE TABLE IF NOT EXISTS public.hr_candidate_values (
  candidate_id  uuid NOT NULL REFERENCES public.hr_candidates(id) ON DELETE CASCADE,
  field_id      uuid NOT NULL REFERENCES public.hr_fields(id)     ON DELETE CASCADE,

  -- 🔴 RLS uchun USTUNDA saqlanadi (policy JOIN qilmasin: har qator uchun
  --    hr_candidates ga subquery = sekin + rekursiya xavfi).
  workspace_id  uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,

  -- Barcha matn/raqam/sana/checkbox qiymati KANONIK MATN ko'rinishida:
  --   sana 'YYYY-MM-DD' · checkbox 'true'/'false' · raqam oddiy son matni
  --   ('12.5', nuqta bilan) · select — options[].value.
  value      text,

  -- 🔴 FAQAT ftype='file': Storage YO'LI (URL EMAS — bucket private,
  --    havola createSignedUrls bilan vaqtincha hosil qilinadi).
  file_path  text,

  updated_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (candidate_id, field_id)
);

ALTER TABLE public.hr_candidate_values ADD COLUMN IF NOT EXISTS value      text;
ALTER TABLE public.hr_candidate_values ADD COLUMN IF NOT EXISTS file_path  text;
ALTER TABLE public.hr_candidate_values ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.hr_candidate_values DROP CONSTRAINT IF EXISTS hr_cand_values_len_chk;
ALTER TABLE public.hr_candidate_values ADD  CONSTRAINT hr_cand_values_len_chk
  CHECK ((value IS NULL OR char_length(value) <= 5000)
     AND (file_path IS NULL OR char_length(file_path) <= 400));

-- FK CASCADE (maydon o'chirilganda) va "shu maydon qayerda ishlatilgan" so'rovi
CREATE INDEX IF NOT EXISTS hr_cand_values_field_idx ON public.hr_candidate_values (field_id);
CREATE INDEX IF NOT EXISTS hr_cand_values_ws_idx    ON public.hr_candidate_values (workspace_id);

COMMENT ON TABLE public.hr_candidate_values IS
  'HR maxsus (is_system=false) maydonlarining qiymatlari. Tizim maydonlari BU YERGA TUSHMAYDI — ular hr_candidates ustunlarida. workspace_id ustunda saqlanadi (RLS JOIN qilmasin) va hr_cand_values_guard trigger''i uni nomzod/maydon bilan MOSligini majburlaydi.';

-- ── 🔴 WORKSPACE MOSLIGI TRIGGERI ──────────────────────────────────────────
-- Busiz bir workspace nomzodiga BOSHQA workspace maydonini ulash mumkin
-- bo'lardi: RLS faqat qatordagi workspace_id ga qaraydi, ya'ni "o'z" ws si
-- yozilgan qator begona candidate_id/field_id ga ishora qilishi mumkin edi.
-- SECURITY DEFINER — tekshiruv RLS ko'rinishiga bog'liq bo'lmasin (aks holda
-- begona qator "topilmadi" bo'lib boshqa xato beradi va sabab chalkashardi).
CREATE OR REPLACE FUNCTION public.hr_cand_values_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_cws uuid;
  v_fws uuid;
BEGIN
  SELECT c.workspace_id INTO v_cws FROM public.hr_candidates c WHERE c.id = NEW.candidate_id;
  IF v_cws IS NULL THEN
    RAISE EXCEPTION 'hr_candidate_values: nomzod topilmadi (candidate=%)', NEW.candidate_id;
  END IF;

  SELECT f.workspace_id INTO v_fws FROM public.hr_fields f WHERE f.id = NEW.field_id;
  IF v_fws IS NULL THEN
    RAISE EXCEPTION 'hr_candidate_values: maydon topilmadi (field=%)', NEW.field_id;
  END IF;

  IF NEW.workspace_id IS NULL THEN
    NEW.workspace_id := v_cws;
  END IF;

  IF NEW.workspace_id <> v_cws OR NEW.workspace_id <> v_fws THEN
    RAISE EXCEPTION 'hr_candidate_values: workspace mos emas (qator=%, nomzod=%, maydon=%)',
      NEW.workspace_id, v_cws, v_fws;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.hr_cand_values_guard() IS
  'hr_candidate_values: qator workspace_id si nomzod VA maydon workspace_id si bilan bir xil bo''lishini majburlaydi (aks holda begona ws maydonini ulash mumkin edi). updated_at ni ham qo''yadi.';

DROP TRIGGER IF EXISTS hr_cand_values_guard_trg ON public.hr_candidate_values;
CREATE TRIGGER hr_cand_values_guard_trg
  BEFORE INSERT OR UPDATE ON public.hr_candidate_values
  FOR EACH ROW EXECUTE FUNCTION public.hr_cand_values_guard();


-- ════════════════════════════════════════════════════════════════════════════
-- 3) hr_candidates ga QO'SHIMCHA 2 USTUN (brief 4-band: loyiha auto-start)
-- ════════════════════════════════════════════════════════════════════════════
-- ⚠️ project_id FK SHARTLI qo'shiladi: `projects` jadvali bo'lmagan (juda eski)
--    bazada butun skript yiqilmasin — maydon konstruktori loyihaga bog'liq emas.
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS project_id         uuid;
ALTER TABLE public.hr_candidates ADD COLUMN IF NOT EXISTS project_started_at timestamptz;

DO $do$
BEGIN
  IF to_regclass('public.projects') IS NULL THEN
    RAISE NOTICE '⚠️ public.projects topilmadi — hr_candidates.project_id FK SIZ qo''shildi (loyiha auto-start ishlamaydi, qolgan hammasi ishlaydi).';
  ELSIF NOT EXISTS (
      SELECT 1 FROM pg_constraint
       WHERE conrelid = 'public.hr_candidates'::regclass
         AND contype  = 'f'
         AND conname  = 'hr_candidates_project_fk') THEN
    EXECUTE 'ALTER TABLE public.hr_candidates
               ADD CONSTRAINT hr_candidates_project_fk
               FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE SET NULL';
  END IF;
END $do$;

COMMENT ON COLUMN public.hr_candidates.project_id IS
  'HR tanlagan loyiha (IXTIYORIY). Nomzod "hired" bo''lganda o''sha loyiha START oladi (brief 4-band). Nomzod bu maydonni HECH QACHON yoza olmaydi — hr_apply_submit() oq ro''yxatida YO''Q.';
COMMENT ON COLUMN public.hr_candidates.project_started_at IS
  '🔴 IDEMPOTENTLIK DA''VOSI: loyiha START qilingan lahza. Mijoz naqshi (hrcClaim): update({project_started_at: now}).eq(id).eq(workspace_id).is(project_started_at, null).select() — 0 qator = boshqa admin ulgurdi, amal QAYTA bajarilmaydi. ⚠️ .eq(col, null) PostgREST''da ISHLAMAYDI, .is() shart.';


-- ════════════════════════════════════════════════════════════════════════════
-- 4) updated_at trigger (hr_fields) — MAVJUD public.org_touch() qayta ishlatiladi
-- ════════════════════════════════════════════════════════════════════════════
-- ⚠️ Yangi funksiya YOZILMAYDI (TASKFIX_HR_RECRUITING.sql naqshi).
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'org_touch') THEN
    RAISE EXCEPTION 'public.org_touch() topilmadi — TASKFIX_HR.sql ishga tushirilmaganmi?';
  END IF;
END $do$;

DROP TRIGGER IF EXISTS hr_fields_touch_trg ON public.hr_fields;
CREATE TRIGGER hr_fields_touch_trg BEFORE UPDATE ON public.hr_fields
  FOR EACH ROW EXECUTE FUNCTION public.org_touch();


-- ════════════════════════════════════════════════════════════════════════════
-- 5) TIZIM MAYDONLARI KATALOGI — YAGONA HAQIQAT MANBAI
-- ════════════════════════════════════════════════════════════════════════════
-- 🔴 Ro'yxat UCH joyda kerak: (a) seed, (b) hr_fields_seed() RPC,
--    (c) hr_fields_guard() trigger'i (is_system qatori KATALOGGA mos bo'lishi
--    shart). Uchtasida qo'lda takrorlansa vaqt o'tib bir-biridan uzoqlashardi
--    — shuning uchun BITTA funksiya.
--
-- name_ru / name_en — mavjud i18n.json dagi `hrc.f_*` / `hrc.doc_*` kalitlaridan
-- olindi (bir xil so'z ilovada va formada boshqacha ko'rinmasin).
--
-- required / fill_by — HOZIRGI mijoz xatti-harakatiga AYNAN mos:
--   • hr_apply_submit() ning qat'iy majburiy ro'yxati → required=true
--   • D10 (contract, referred_by) → fill_by='hr' (nomzod ko'rmaydi)
--   • start_date / notes → HR tomoni, majburiy emas
--
-- sort_order — 10, 20, 30 … (oraliq ATAYLAB: HR orasiga yangi maydon qo'sha olsin)
CREATE OR REPLACE FUNCTION public.hr_fields_defaults()
RETURNS TABLE (
  key        text,
  col        text,
  ftype      text,
  required   boolean,
  fill_by    text,
  name_uz    text,
  name_ru    text,
  name_en    text,
  options    jsonb,
  sort_order int
)
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT * FROM (VALUES
    ('full_name',             'full_name',                  'text',     true,  'both',
     'F.I.O.',                  'Ф.И.О.',                        'Full name',                    '[]'::jsonb,  10),
    ('birth_date',            'birth_date',                 'date',     true,  'both',
     'Tug''ilgan sana',         'Дата рождения',                 'Date of birth',                '[]'::jsonb,  20),
    ('gender',                'gender',                     'select',   false, 'both',
     'Jinsi',                   'Пол',                           'Gender',
     '[{"value":"m","uz":"Erkak","ru":"Мужской","en":"Male"},{"value":"f","uz":"Ayol","ru":"Женский","en":"Female"}]'::jsonb, 30),
    ('pinfl',                 'pinfl',                      'text',     true,  'both',
     'JSHSHIR (PINFL)',         'ПИНФЛ',                         'PINFL (personal ID number)',   '[]'::jsonb,  40),
    ('passport_serial',       'passport_serial',            'text',     true,  'both',
     'Passport seriyasi',       'Серия и номер паспорта',        'Passport number',              '[]'::jsonb,  50),
    ('passport_issued_by',    'passport_issued_by',         'text',     false, 'both',
     'Kim tomonidan berilgan',  'Кем выдан',                     'Issued by',                    '[]'::jsonb,  60),
    ('passport_issued_at',    'passport_issued_at',         'date',     false, 'both',
     'Berilgan sana',           'Дата выдачи',                   'Issue date',                   '[]'::jsonb,  70),
    ('passport_expires_at',   'passport_expires_at',        'date',     false, 'both',
     'Amal qilish muddati',     'Срок действия',                 'Expiry date',                  '[]'::jsonb,  80),
    ('address',               'address',                    'textarea', true,  'both',
     'Yashash manzili',         'Адрес проживания',              'Residential address',          '[]'::jsonb,  90),
    ('phone',                 'phone',                      'tel',      true,  'both',
     'Telefon',                 'Телефон',                       'Phone',                        '[]'::jsonb, 100),
    ('parent_name',           'parent_name',                'text',     true,  'both',
     'Ota/ona F.I.O.',          'Ф.И.О. родителя',               'Parent''s full name',          '[]'::jsonb, 110),
    ('parent_phone',          'parent_phone',               'tel',      true,  'both',
     'Ota/ona telefoni',        'Телефон родителя',              'Parent''s phone',              '[]'::jsonb, 120),
    ('email',                 'email',                      'email',    true,  'both',
     'Email',                   'Email',                         'Email',                        '[]'::jsonb, 130),
    ('photo',                 'photo_path',                 'file',     true,  'both',
     'Hodim fotosi',            'Фото сотрудника',               'Employee photo',               '[]'::jsonb, 140),
    ('passport_front',        'passport_front_path',        'file',     true,  'both',
     'Passport — oldi',         'Паспорт — лицевая сторона',      'Passport — front',             '[]'::jsonb, 150),
    ('passport_back',         'passport_back_path',         'file',     true,  'both',
     'Passport — orqa',         'Паспорт — оборотная сторона',    'Passport — back',              '[]'::jsonb, 160),
    ('parent_passport_front', 'parent_passport_front_path', 'file',     true,  'both',
     'Ota/ona passporti — oldi','Паспорт родителя — лицевая сторона', 'Parent''s passport — front', '[]'::jsonb, 170),
    ('parent_passport_back',  'parent_passport_back_path',  'file',     true,  'both',
     'Ota/ona passporti — orqa','Паспорт родителя — оборотная сторона','Parent''s passport — back', '[]'::jsonb, 180),
    -- 🔴 D10: shartnoma + kim taklif qildi — FAQAT HR (nomzod sahifasida YO'Q)
    ('contract',              'contract_path',              'file',     true,  'hr',
     'Shartnoma',               'Договор',                       'Contract',                     '[]'::jsonb, 190),
    ('referred_by',           'referred_by',                'text',     true,  'hr',
     'Kim tavsiya qildi / qayerdan topildi', 'Кто порекомендовал / откуда найден', 'Referred by / source', '[]'::jsonb, 200),
    ('start_date',            'start_date',                 'date',     false, 'hr',
     'Ish boshlash sanasi',     'Дата начала работы',            'Start date',                   '[]'::jsonb, 210),
    ('notes',                 'notes',                      'textarea', false, 'hr',
     'Izoh',                    'Заметка',                       'Notes',                        '[]'::jsonb, 220)
  ) AS d(key, col, ftype, required, fill_by, name_uz, name_ru, name_en, options, sort_order);
$fn$;

COMMENT ON FUNCTION public.hr_fields_defaults() IS
  'TIZIM maydonlari katalogi (22 ta) — hr_fields seed''i, hr_fields_seed() RPC va hr_fields_guard() trigger''i UCHALASI shundan o''qiydi. Bu yerdagi (key, col) juftligi is_system qatorlari uchun YAGONA ruxsat etilgan kombinatsiya.';

-- 🔴 REVOKE ... FROM PUBLIC YETARLI EMAS: Supabase'da
--    `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO
--     postgres, anon, authenticated, service_role` standart turadi, ya'ni
--    yangi funksiya `anon` ga TO'G'RIDAN grant oladi va PUBLIC dan REVOKE
--    uni olib tashlamaydi. Loyihaning naqshi: TASKFIX_VIEWS.sql,
--    TASKFIX_HR_EDITORS.sql, TASKFIX_LOYIHA_RLS.sql — uchalasi ham aniq
--    `FROM anon` REVOKE qiladi. Busiz 10.k tekshiruvi otilib butun skript
--    ROLLBACK bo'lardi.
REVOKE ALL ON FUNCTION public.hr_fields_defaults() FROM PUBLIC;
DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.hr_fields_defaults() FROM anon';
  END IF;
  EXECUTE 'REVOKE ALL ON FUNCTION public.hr_fields_defaults() FROM authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.hr_fields_defaults() TO authenticated';
END $do$;


-- ── 5.b) hr_fields_guard() — tizim qatorining butunligi ────────────────────
-- 🔴 Tizim maydonida HR o'zgartira oladi: nom (3 til), required, fill_by,
--    options, placeholder, sort_order, active, section.
--    O'zgartira OLMAYDI: key, col, ftype, is_system, workspace_id.
--    Sabab: `col` — hr_apply_submit() oq ro'yxatidagi ustun; uni o'zgartirish
--    qiymatni boshqa ustunga yo'naltirardi, `ftype` esa mijoz validatsiyasi
--    va saqlash formatini belgilaydi (masalan 'file' → 'text' qilinsa
--    passport rasmi yo'li oddiy matn bo'lib qolardi).
-- 🔴 INSERT da is_system=true faqat KATALOGDAGI (key, col) juftligi bilan
--    ruxsat etiladi — aks holda HR ixtiyoriy ustunga (masalan 'status' yoki
--    'consent_at') "tizim maydoni" yasab olardi.
CREATE OR REPLACE FUNCTION public.hr_fields_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  -- 🔴 YOZIB BO'LMAYDIGAN UCH USTUN. hr_apply_submit() ning OQ RO'YXATI
  --    `referred_by`, `start_date` va `notes` ni ATAYLAB o'qimaydi (D10 —
  --    ular faqat HR maydonlari). Agar HR ulardan birini "Nomzod to'ldiradi"
  --    qilib qo'ysa, zanjir shunday buzilardi: hr_apply_peek maydonni
  --    QAYTARARDI → nomzod uni ekranda ko'rib to'ldirardi → submit'da mos
  --    o'zgaruvchi YO'Q → qiymat yozilmasdan JIMGINA yo'qolardi va javob
  --    {ok:true} bo'lardi (6-qoida buzilishi). Ustiga `required` ham
  --    majburlanmasdi. Shuning uchun bu uchtasida fill_by faqat 'hr'.
  --    Ochish kerak bo'lsa — avval submit oq ro'yxatiga qo'shilsin.
  IF NEW.col IS NOT NULL
     AND NEW.col IN ('referred_by','start_date','notes')
     AND NEW.fill_by <> 'hr' THEN
    RAISE EXCEPTION 'hr_fields: "%" maydonini nomzodga ochib bo''lmaydi — u faqat HR tomonidan to''ldiriladi (fill_by = hr)', NEW.key;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.is_system THEN
      IF NOT EXISTS (SELECT 1 FROM public.hr_fields_defaults() d
                      WHERE d.key = NEW.key AND d.col = NEW.col) THEN
        RAISE EXCEPTION 'hr_fields: tizim maydoni (is_system) faqat katalogdagi kalit/ustun juftligi bilan yaratiladi (key=%, col=%)', NEW.key, NEW.col;
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF NEW.workspace_id IS DISTINCT FROM OLD.workspace_id THEN
    RAISE EXCEPTION 'hr_fields: workspace_id o''zgartirilmaydi';
  END IF;
  IF NEW.is_system IS DISTINCT FROM OLD.is_system THEN
    RAISE EXCEPTION 'hr_fields: is_system o''zgartirilmaydi (tizim/maxsus maydon o''rin almashmaydi)';
  END IF;

  IF OLD.is_system THEN
    IF NEW.key IS DISTINCT FROM OLD.key THEN
      RAISE EXCEPTION 'hr_fields: tizim maydonining kaliti (key) o''zgartirilmaydi: %', OLD.key;
    END IF;
    IF NEW.col IS DISTINCT FROM OLD.col THEN
      RAISE EXCEPTION 'hr_fields: tizim maydonining ustuni (col) o''zgartirilmaydi: %', OLD.key;
    END IF;
    IF NEW.ftype IS DISTINCT FROM OLD.ftype THEN
      RAISE EXCEPTION 'hr_fields: tizim maydonining turi (ftype) o''zgartirilmaydi: % (% → %)', OLD.key, OLD.ftype, NEW.ftype;
    END IF;
  ELSE
    IF NEW.col IS NOT NULL THEN
      RAISE EXCEPTION 'hr_fields: maxsus maydonga col berib bo''lmaydi';
    END IF;
  END IF;

  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.hr_fields_guard() IS
  'hr_fields butunligi: tizim qatorining key/col/ftype/is_system o''zgarmaydi, is_system faqat hr_fields_defaults() katalogidagi (key,col) bilan yaratiladi, workspace_id hech qachon o''zgarmaydi. O''chirishni RLS DELETE policy''si (is_system = false) to''sadi.';

DROP TRIGGER IF EXISTS hr_fields_guard_trg ON public.hr_fields;
CREATE TRIGGER hr_fields_guard_trg
  BEFORE INSERT OR UPDATE ON public.hr_fields
  FOR EACH ROW EXECUTE FUNCTION public.hr_fields_guard();


-- ════════════════════════════════════════════════════════════════════════════
-- 6) GRANT + RLS
-- ════════════════════════════════════════════════════════════════════════════
-- 🔴 anon ikkala jadvalga ham UMUMAN tegmaydi: na policy, na GRANT.
--    Nomzod maydon ro'yxatini hr_apply_peek() dan, yozuvni esa
--    hr_apply_submit() dan oladi (ikkalasi ham SECURITY DEFINER).
REVOKE ALL ON TABLE public.hr_fields           FROM anon;
REVOKE ALL ON TABLE public.hr_candidate_values FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_fields           TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_candidate_values TO authenticated;

ALTER TABLE public.hr_fields           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_candidate_values ENABLE ROW LEVEL SECURITY;

-- ── 6.a) hr_fields ─────────────────────────────────────────────────────────
-- SELECT — workspace A'ZOSI (is_ws_member): maydon KATALOGI shaxsiy ma'lumot
--   emas ("Passport seriyasi" degan yorliq), va uni ochiq qo'yish kelajakda
--   HR bo'lmagan ekranlarda ham yorliqni ko'rsatishga imkon beradi.
--   ⚠️ QIYMATLAR esa (hr_candidate_values) FAQAT HR ga ochiq — pastda.
-- INSERT/UPDATE — is_ws_manager OR hr_is_editor (mavjud hr_candidates modeli).
-- DELETE — o'sha shart VA is_system = false 🔴 (tizim maydoni o'chirilmasin).
DROP POLICY IF EXISTS hr_fields_select ON public.hr_fields;
CREATE POLICY hr_fields_select ON public.hr_fields
  AS PERMISSIVE FOR SELECT TO authenticated
  USING ( is_ws_member(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS hr_fields_insert ON public.hr_fields;
CREATE POLICY hr_fields_insert ON public.hr_fields
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ( is_ws_manager(workspace_id, (SELECT auth.uid()))
            OR hr_is_editor(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS hr_fields_update ON public.hr_fields;
CREATE POLICY hr_fields_update ON public.hr_fields
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING      ( is_ws_manager(workspace_id, (SELECT auth.uid()))
            OR hr_is_editor(workspace_id, (SELECT auth.uid())) )
  WITH CHECK ( is_ws_manager(workspace_id, (SELECT auth.uid()))
            OR hr_is_editor(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS hr_fields_delete ON public.hr_fields;
CREATE POLICY hr_fields_delete ON public.hr_fields
  AS PERMISSIVE FOR DELETE TO authenticated
  USING ( is_system = false
      AND ( is_ws_manager(workspace_id, (SELECT auth.uid()))
         OR hr_is_editor(workspace_id, (SELECT auth.uid())) ) );

-- ── 6.b) hr_candidate_values ───────────────────────────────────────────────
-- 🔴 AYNAN hr_candidates MODELI (yangi model o'ylab topilmadi): shaxsiy
--    ma'lumot — oddiy a'zo KO'RMAYDI, faqat is_ws_manager / hr_is_editor.
--    "Sudlanganlik hujjati" yoki "Kredit tarixi" qiymati passportdan kam
--    maxfiy emas.
DROP POLICY IF EXISTS hr_candidate_values_select ON public.hr_candidate_values;
CREATE POLICY hr_candidate_values_select ON public.hr_candidate_values
  AS PERMISSIVE FOR SELECT TO authenticated
  USING ( is_ws_manager(workspace_id, (SELECT auth.uid()))
       OR hr_is_editor(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS hr_candidate_values_insert ON public.hr_candidate_values;
CREATE POLICY hr_candidate_values_insert ON public.hr_candidate_values
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ( is_ws_manager(workspace_id, (SELECT auth.uid()))
            OR hr_is_editor(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS hr_candidate_values_update ON public.hr_candidate_values;
CREATE POLICY hr_candidate_values_update ON public.hr_candidate_values
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING      ( is_ws_manager(workspace_id, (SELECT auth.uid()))
            OR hr_is_editor(workspace_id, (SELECT auth.uid())) )
  WITH CHECK ( is_ws_manager(workspace_id, (SELECT auth.uid()))
            OR hr_is_editor(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS hr_candidate_values_delete ON public.hr_candidate_values;
CREATE POLICY hr_candidate_values_delete ON public.hr_candidate_values
  AS PERMISSIVE FOR DELETE TO authenticated
  USING ( is_ws_manager(workspace_id, (SELECT auth.uid()))
       OR hr_is_editor(workspace_id, (SELECT auth.uid())) );


-- ════════════════════════════════════════════════════════════════════════════
-- 7) SEED — tizim maydonlarini yaratish
-- ════════════════════════════════════════════════════════════════════════════
-- 🔴 QAYSI WORKSPACE'LAR: (a) HR Service YOQILGAN, yoki (b) hr_candidates
--    qatori bor, yoki (c) apply tokeni bor.
--    NEGA HAMMASI EMAS: TaskFix'da HR bilan umuman ishlamaydigan workspace'lar
--    bor — ularga 22 tadan qator yozsak, (1) ular hech qachon so'ramagan
--    "forma sozlamasi" bazada qotib qolardi va katalog kelajakda o'zgarsa
--    eski nusxa saqlanib qolardi, (2) hr_apply_submit ning "hr_fields bo'sh →
--    eski qat'iy mantiq" zaxira yo'li o'sha workspace'lar uchun ma'nosiz
--    yopilardi. HR keyinroq yoqilganda mijoz `hr_fields_seed(ws)` RPC sini
--    chaqiradi (pastda) — natija AYNAN shu seed bilan bir xil.
DO $do$
DECLARE
  v_n int;
BEGIN
  WITH ws AS (
    SELECT w.id
      FROM public.workspaces w
     WHERE EXISTS (SELECT 1 FROM public.hr_settings   s WHERE s.workspace_id = w.id AND s.is_enabled)
        OR EXISTS (SELECT 1 FROM public.hr_candidates c WHERE c.workspace_id = w.id)
        OR EXISTS (SELECT 1 FROM public.hr_apply_tokens t WHERE t.workspace_id = w.id)
        -- 🔴 TO'LDIRISH SHOXI: maydonlari ALLAQACHON bor workspace (masalan
        --    hr_fields_seed() RPC orqali). Katalogga kelajakda yangi tizim
        --    maydoni qo'shilsa, u ham shu yerda "top-up" bo'ladi — aks holda
        --    10.j tekshiruvi (har ws da katalog soni) o'sha ws da yiqilardi.
        OR EXISTS (SELECT 1 FROM public.hr_fields hf WHERE hf.workspace_id = w.id)
  )
  INSERT INTO public.hr_fields
    (workspace_id, key, col, is_system, name_uz, name_ru, name_en,
     ftype, required, fill_by, options, sort_order, section)
  SELECT ws.id, d.key, d.col, true, d.name_uz, d.name_ru, d.name_en,
         d.ftype, d.required, d.fill_by, d.options, d.sort_order,
         NULL::text   -- ⚠️ section ATAYLAB bo'sh: bitta ustun, tarjimasi yo'q
    FROM ws CROSS JOIN public.hr_fields_defaults() d
  ON CONFLICT (workspace_id, key) DO NOTHING;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE 'SEED: % ta tizim maydoni qatori qo''shildi (mavjudlari tegilmadi).', v_n;
END $do$;


-- ── 7.b) hr_fields_seed(uuid) — keyinchalik HR yoqilgan workspace uchun ────
-- 🔴 SECURITY INVOKER (DEFINER EMAS): haqiqiy himoya — hr_fields ning INSERT
--    policy'si. Boshidagi aniq tekshiruv faqat TUSHUNARLI XATO uchun (RLS
--    rad etsa mijoz xom "new row violates row-level security" ni ko'rardi).
-- Idempotent: ON CONFLICT DO NOTHING → qayta chaqirish xavfsiz, 0 qaytaradi.
CREATE OR REPLACE FUNCTION public.hr_fields_seed(p_ws uuid)
RETURNS int
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_n int;
BEGIN
  IF p_ws IS NULL THEN
    RETURN 0;
  END IF;

  IF NOT ( is_ws_manager(p_ws, (SELECT auth.uid()))
        OR hr_is_editor(p_ws, (SELECT auth.uid())) ) THEN
    RAISE EXCEPTION 'Ruxsat yo''q: maydonlarni faqat administrator yoki HR muharriri sozlaydi.';
  END IF;

  INSERT INTO public.hr_fields
    (workspace_id, key, col, is_system, name_uz, name_ru, name_en,
     ftype, required, fill_by, options, sort_order, created_by)
  SELECT p_ws, d.key, d.col, true, d.name_uz, d.name_ru, d.name_en,
         d.ftype, d.required, d.fill_by, d.options, d.sort_order, (SELECT auth.uid())
    FROM public.hr_fields_defaults() d
  ON CONFLICT (workspace_id, key) DO NOTHING;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$fn$;

COMMENT ON FUNCTION public.hr_fields_seed(uuid) IS
  'Workspace uchun TIZIM maydonlarini (hr_fields_defaults) idempotent yaratadi. Mijoz: HR maydon konstruktori ochilganda ro''yxat BO''SH bo''lsa bir marta chaqiradi. SECURITY INVOKER — RLS INSERT policy''si haqiqiy qorovul. Qaytaradi: qo''shilgan qatorlar soni (0 = allaqachon bor).';

-- 🔴 REVOKE ... FROM PUBLIC YETARLI EMAS: Supabase'da
--    `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO
--     postgres, anon, authenticated, service_role` standart turadi, ya'ni
--    yangi funksiya `anon` ga TO'G'RIDAN grant oladi va PUBLIC dan REVOKE
--    uni olib tashlamaydi. Loyihaning naqshi: TASKFIX_VIEWS.sql,
--    TASKFIX_HR_EDITORS.sql, TASKFIX_LOYIHA_RLS.sql — uchalasi ham aniq
--    `FROM anon` REVOKE qiladi. Busiz 10.k tekshiruvi otilib butun skript
--    ROLLBACK bo'lardi.
REVOKE ALL ON FUNCTION public.hr_fields_seed(uuid) FROM PUBLIC;
DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.hr_fields_seed(uuid) FROM anon';
  END IF;
  EXECUTE 'REVOKE ALL ON FUNCTION public.hr_fields_seed(uuid) FROM authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.hr_fields_seed(uuid) TO authenticated';
END $do$;


-- ════════════════════════════════════════════════════════════════════════════
-- 8) hr_apply_peek(uuid) — KENGAYTIRILDI: `fields`
-- ════════════════════════════════════════════════════════════════════════════
-- 🔴 QAT'IY (o'zgartirmang — 9.g tekshiruvi majburlaydi):
--    • FAQAT `active = true` VA `fill_by IN ('employee','both')` qatorlar.
--      HR-only maydon (contract, referred_by, start_date, notes) bu yerdan
--      HECH QACHON chiqmaydi.
--    • `hr_candidates` ga murojaat YO'Q — nomzod ma'lumoti, lavozim, filial,
--      boshqa nomzodlar avvalgidek QAYTMAYDI (brief 44-qator).
--    • hr_fields bo'sh bo'lsa `fields: []` → mijoz ESKI qat'iy formaga tushadi.
-- ⚠️ `col` ATAYLAB qaytariladi: mijoz qiymatni qayerga qo'yishini shundan
--    biladi — col IS NOT NULL → payload[col] (eski oq ro'yxat),
--    col IS NULL → payload.fields[<id>] / payload.files[<id>].
--    Ustun NOMI maxfiy ma'lumot emas (jadval sxemasi PostgREST'da baribir
--    ochiq emas, lekin qiymat sizmaydi).
CREATE OR REPLACE FUNCTION public.hr_apply_peek(p_token uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_ws     uuid;
  v_used   timestamptz;
  v_exp    timestamptz;
  v_name   text;
  v_fields jsonb;
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

  -- ⚠️ ORDER BY jsonb_agg ICHIDA ham takrorlanadi: ichki so'rovning tartibi
  --    agregat uchun KAFOLATLANMAYDI (planner uni erkin o'zgartira oladi).
  SELECT COALESCE(jsonb_agg(j.o ORDER BY j.so, j.k), '[]'::jsonb) INTO v_fields
    FROM (
      SELECT f.sort_order AS so,
             f.key        AS k,
             jsonb_build_object(
               'id',             f.id,
               'key',            f.key,
               'col',            f.col,
               'is_system',      f.is_system,
               'ftype',          f.ftype,
               'required',       f.required,
               'name_uz',        f.name_uz,
               'name_ru',        f.name_ru,
               'name_en',        f.name_en,
               'placeholder_uz', f.placeholder_uz,
               'placeholder_ru', f.placeholder_ru,
               'placeholder_en', f.placeholder_en,
               'options',        f.options,
               'sort_order',     f.sort_order,
               'section',        f.section
             ) AS o
        FROM public.hr_fields f
       WHERE f.workspace_id = v_ws
         AND f.active
         AND f.fill_by IN ('employee','both')
       ORDER BY f.sort_order, f.key
       LIMIT 300
    ) j;

  RETURN jsonb_build_object(
    'ok',           true,
    'state',        'open',
    'company_name', COALESCE(v_name, ''),
    'fields',       v_fields
  );
END;
$fn$;

COMMENT ON FUNCTION public.hr_apply_peek(uuid) IS
  'Apply sahifasi ochilganda holat + DINAMIK MAYDONLAR: {ok, state: open|used|expired|invalid, company_name, fields[]}. fields FAQAT active = true VA fill_by IN (employee, both) qatorlardan (HR-only maydon hech qachon chiqmaydi) va faqat state=open da. 🔴 hr_candidates ga murojaat YO''Q — nomzod ma''lumoti/lavozim/filial qaytmaydi (brief 44-qator).';

REVOKE ALL ON FUNCTION public.hr_apply_peek(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hr_apply_peek(uuid) TO anon, authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- 9) hr_apply_submit(uuid, jsonb) — KENGAYTIRILDI
-- ════════════════════════════════════════════════════════════════════════════
-- 🔴 MAVJUD UCHTA QAT'IY QOIDA BUZILMAGAN (10.h tekshiruvi majburlaydi):
--   (1) OQ RO'YXAT: p_payload dan FAQAT 21 nomzod maydoni + `_ua` NOMMA-NOM
--       `->>` bilan o'qiladi. status / workspace_id / want_* / position_id /
--       branch_folder_id / hired_by_user_id / taskfix_* / kassa_* / consent_at /
--       submitted_at / created_by / referred_by / project_id — QABUL
--       QILINMAYDI. jsonb_populate_record YO'Q.
--   (2) VALIDATSIYA TOKENNI DA'VO QILISHDAN OLDIN.
--   (3) ATOMIK DA'VO: UPDATE … WHERE used_at IS NULL AND expires_at > now().
--
-- ── YANGI (dinamik) ────────────────────────────────────────────────────────
--   • p_payload->'fields' = {"<field_id>": "<qiymat>"}
--     p_payload->'files'  = {"<field_id>": "<storage yo'li>"}
--   • 🔴 SERVER TOMONDA FILTR — MIJOZ KALITLARI EMAS, SERVER RO'YXATI:
--     funksiya `hr_fields` dan (workspace_id = v_ws AND active AND
--     fill_by IN ('employee','both') AND col IS NULL) qatorlarni O'QIYDI va
--     HAR BIRI uchun payload'dan `f.id::text` kalitini qidiradi. Ya'ni
--     noma'lum / o'chirilgan / HR-only / BEGONA WORKSPACE maydon kaliti
--     UMUMAN qaralmaydi — jimgina tashlanadi (xato emas: mijoz eski bo'lishi
--     mumkin). Bu yo'l `::uuid` cast qorovulini ham keraksiz qiladi.
--   • 🔴 TIZIM maydoni (`col IS NOT NULL`) `fields`/`files` orqali QABUL
--     QILINMAYDI — u AVVALGIDEK oq ro'yxat orqali (payload[col]) keladi va
--     hr_candidates USTUNIGA yoziladi. Nega shunday: dinamik SQL ham,
--     `col` ni ustunga xaritalash ham kerak emas → ustunga yozish yo'li
--     BITTA va u allaqachon audit qilingan (eng sodda va eng xavfsiz variant).
--   • 🔴 MAJBURIYLIK DINAMIK: hr_fields.required (active + employee/both).
--     FORMAT tekshiruvlari (PINFL 14 raqam, passport AA1234567, email shakli,
--     sana oralig'i) — QIYMAT BOR BO'LSA hamon qo'llanadi.
--     ZAXIRA: workspace uchun hr_fields da qator YO'Q bo'lsa — HOZIRGI qat'iy
--     majburiy ro'yxat AYNAN saqlanadi (eski xatti-harakat).
--   • ⚠️ TIZIM ustunlari endi COALESCE(yangi, eski) bilan yoziladi: HR maydonni
--     nomzoddan YASHIRSA (active=false / fill_by='hr') qiymat NULL bo'lib
--     keladi va avvalgi to'g'ridan yozuv HR kiritgan ma'lumotni O'CHIRARDI.
--     Qiymat bo'lganda xatti-harakat aynan avvalgidek.
--   • Fayl yo'llari (tizim ham, maxsus ham) avvalgidek `apply/<token>/` bilan
--     boshlanishi SHART.
--   • `consent` sharti va `consent_at` — O'ZGARMAYDI.
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
  -- ── DINAMIK qism ──────────────────────────────────────────────────────
  v_dyn    boolean := false;   -- workspace uchun hr_fields sozlanganmi?
  v_req    text[]  := '{}';    -- MAJBURIY tizim ustunlari
  v_vis    text[]  := '{}';    -- nomzodga KO'RINADIGAN tizim ustunlari
  v_fmap   jsonb;              -- p_payload -> 'fields'
  v_lmap   jsonb;              -- p_payload -> 'files'
  v_acc    jsonb   := '[]'::jsonb;  -- yozishga tayyor maxsus qiymatlar
  v_f      record;             -- hr_fields qatori
  v_w      record;             -- yozuv qatori (v_acc dan)
  v_val    text;
  v_fpath  text;
  v_cnt    int;
BEGIN
  IF p_token IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'state', 'invalid');
  END IF;
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ma''lumot yuborilmadi.');
  END IF;

  -- 🔴 lower(): p_token::text Postgres'da doim kichik harfli, MIJOZ yuborgan
  --    yo'l esa KATTA harfli bo'lishi mumkin. Solishtiruv katta-kichik harfga
  --    SEZGIR EMAS (mijozda ham token kichik harfga keltiriladi — ikki qatlam).
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
  -- ⚠️ contract_path IXTIYORIY (D10): kelsa qabul qilinadi, prefiksi baribir
  --    tekshiriladi. 🔴 `referred_by` ATAYLAB O'QILMAYDI (faqat HR maydoni).
  v_ctr    := nullif(btrim(p_payload->>'contract_path'), '');
  v_cver   := nullif(btrim(p_payload->>'consent_version'), '');
  v_cons   := lower(nullif(btrim(p_payload->>'consent'), ''));

  -- Sanalar: noto'g'ri matn cast'da xato beradi → ushlab, tushunarli javob
  BEGIN
    v_birth := nullif(btrim(p_payload->>'birth_date'), '')::date;
    v_pat   := nullif(btrim(p_payload->>'passport_issued_at'), '')::date;
    v_pex   := nullif(btrim(p_payload->>'passport_expires_at'), '')::date;
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Sana formati noto''g''ri (YYYY-MM-DD).');
  END;

  -- ── 2) TOKENNI "O'QISH" (DA'VO EMAS!) ───────────────────────────────
  -- 🔴 Dinamik majburiylikni tekshirish uchun workspace KERAK, workspace esa
  --    tokenda. Shuning uchun avval FAQAT O'QIYMIZ (hech narsa yozilmaydi),
  --    da'vo esa avvalgidek validatsiyadan KEYIN va ATOMIK bo'ladi (3-qoida).
  --    Busiz xato formatdagi forma tokenni yoqib yuborardi (2-qoida).
  SELECT t.workspace_id, t.candidate_id, t.used_at, t.expires_at
    INTO v_ws, v_cand, v_used, v_exp
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

  -- ── 3) DINAMIK SOZLAMA (yoki ESKI zaxira ro'yxat) ───────────────────
  -- 🔴 "hr_fields da BITTA ham qator bormi?" — dinamik rejimning kaliti.
  --    ⚠️ Shuning uchun mijoz workspace'ga MAXSUS maydon qo'shishdan OLDIN
  --    hr_fields_seed(ws) ni chaqirishi SHART: aks holda tizim ustunlari
  --    (F.I.O., passport, telefon) "nomzodga ko'rinmaydi" deb hisoblanib
  --    jimgina yozilmay qolardi.
  -- 🔴 FAQAT TIZIM qatorlari (col IS NOT NULL) sanaladi. Aks holda
  --    workspace'da FAQAT maxsus maydon bo'lsa (mijoz hr_fields_seed(ws) ni
  --    chaqirmagan) `v_vis` BO'SH bo'lib, F.I.O./PINFL/passport/telefon/email
  --    va 5 ta fayl — hammasi NULL ga aylanardi, COALESCE bo'sh draft'ni
  --    saqlardi va nomzod "yuborildi" degan javobni olardi: BUTUN shaxsiy
  --    ma'lumot jimgina yo'qolardi (6-qoida). Endi bunday holatda tizim
  --    tomoni ESKI qat'iy ro'yxat bilan ishlaydi, maxsus maydonlar esa
  --    mustaqil yoziladi (ular alohida, quyida).
  SELECT count(*) INTO v_cnt FROM public.hr_fields f
   WHERE f.workspace_id = v_ws AND f.col IS NOT NULL;
  v_dyn := (v_cnt > 0);

  IF v_dyn THEN
    SELECT COALESCE(array_agg(f.col) FILTER (WHERE f.required), '{}'::text[]),
           COALESCE(array_agg(f.col), '{}'::text[])
      INTO v_req, v_vis
      FROM public.hr_fields f
     WHERE f.workspace_id = v_ws
       AND f.active
       AND f.fill_by IN ('employee','both')
       AND f.col IS NOT NULL;
  ELSE
    -- 🔴 ZAXIRA = HOZIRGI xatti-harakat, harfma-harf.
    v_req := ARRAY['full_name','birth_date','pinfl','passport_serial','address',
                   'phone','parent_name','parent_phone','email',
                   'photo_path','passport_front_path','passport_back_path',
                   'parent_passport_front_path','parent_passport_back_path'];
    v_vis := ARRAY['full_name','birth_date','gender','pinfl','passport_serial',
                   'passport_issued_by','passport_issued_at','passport_expires_at',
                   'address','phone','parent_name','parent_phone','email',
                   'photo_path','passport_front_path','passport_back_path',
                   'parent_passport_front_path','parent_passport_back_path',
                   'contract_path'];
  END IF;

  -- Nomzodga ko'rinmaydigan tizim maydoni yuborilgan bo'lsa — E'TIBORSIZ.
  -- (Qiymat NULL bo'ladi; pastdagi UPDATE COALESCE bilan eskisini saqlaydi.)
  IF NOT ('full_name'                  = ANY(v_vis)) THEN v_full   := NULL; END IF;
  IF NOT ('birth_date'                 = ANY(v_vis)) THEN v_birth  := NULL; END IF;
  IF NOT ('gender'                     = ANY(v_vis)) THEN v_gender := NULL; END IF;
  IF NOT ('pinfl'                      = ANY(v_vis)) THEN v_pinfl  := NULL; END IF;
  IF NOT ('passport_serial'            = ANY(v_vis)) THEN v_pser   := NULL; END IF;
  IF NOT ('passport_issued_by'         = ANY(v_vis)) THEN v_pby    := NULL; END IF;
  IF NOT ('passport_issued_at'         = ANY(v_vis)) THEN v_pat    := NULL; END IF;
  IF NOT ('passport_expires_at'        = ANY(v_vis)) THEN v_pex    := NULL; END IF;
  IF NOT ('address'                    = ANY(v_vis)) THEN v_addr   := NULL; END IF;
  IF NOT ('phone'                      = ANY(v_vis)) THEN v_phone  := NULL; END IF;
  IF NOT ('parent_name'                = ANY(v_vis)) THEN v_pname  := NULL; END IF;
  IF NOT ('parent_phone'               = ANY(v_vis)) THEN v_pphone := NULL; END IF;
  IF NOT ('email'                      = ANY(v_vis)) THEN v_email  := NULL; END IF;
  IF NOT ('photo_path'                 = ANY(v_vis)) THEN v_ph     := NULL; END IF;
  IF NOT ('passport_front_path'        = ANY(v_vis)) THEN v_pf     := NULL; END IF;
  IF NOT ('passport_back_path'         = ANY(v_vis)) THEN v_pb     := NULL; END IF;
  IF NOT ('parent_passport_front_path' = ANY(v_vis)) THEN v_ppf    := NULL; END IF;
  IF NOT ('parent_passport_back_path'  = ANY(v_vis)) THEN v_ppb    := NULL; END IF;
  -- 🔴 `contract_path` ATAYLAB bu ro'yxatda YO'Q. Katalogda shartnoma
  --    `fill_by='hr'` (D10) — ya'ni u hech qachon `v_vis` ga tushmaydi va
  --    gate qo'yilsa nomzod yuklagan shartnoma JIMGINA yo'qolardi: fayl
  --    Storage'ga tushib, `contract_path` esa NULL qolardi. Fayl hech bir
  --    ustunda bo'lmagani uchun `hrcDocPaths` uni topmasdi va nomzod
  --    o'chirilganda token CASCADE bilan ketib `hrdocs_auth_select` ning
  --    `apply/` shoxi yopilardi — passport papkasidagi fayl ABADIY qulflanardi.
  --    Eski semantika saqlanadi: "kelsa qabul qilinadi, prefiksi tekshiriladi"
  --    (TASKFIX_HR_RECRUITING.sql). HR shartnomani nomzodga ochsa
  --    (`fill_by='both'`) majburiylik pastdagi `v_req` shoxidan ishlaydi.

  -- ── 4) VALIDATSIYA (tokenni da'vo qilishdan OLDIN — 2-qoida) ────────
  -- MAJBURIYLIK — v_req dan (dinamik yoki zaxira)
  IF 'full_name' = ANY(v_req) AND v_full IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'F.I.O. to''liq kiritilishi kerak.');
  END IF;
  IF 'birth_date' = ANY(v_req) AND v_birth IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Tug''ilgan sana noto''g''ri.');
  END IF;
  IF 'pinfl' = ANY(v_req) AND v_pinfl IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'JSHSHIR (PINFL) 14 ta raqamdan iborat bo''lishi kerak.');
  END IF;
  IF 'passport_serial' = ANY(v_req) AND v_pser IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Passport seriyasi noto''g''ri (namuna: AA1234567).');
  END IF;
  IF 'passport_issued_by' = ANY(v_req) AND v_pby IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Passport kim tomonidan berilgani kiritilishi kerak.');
  END IF;
  IF 'passport_issued_at' = ANY(v_req) AND v_pat IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Passport berilgan sana kiritilishi kerak.');
  END IF;
  IF 'passport_expires_at' = ANY(v_req) AND v_pex IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Passport amal qilish muddati kiritilishi kerak.');
  END IF;
  IF 'gender' = ANY(v_req) AND v_gender IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Jinsi tanlanishi kerak.');
  END IF;
  IF 'address' = ANY(v_req) AND v_addr IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Yashash manzili to''liq kiritilishi kerak.');
  END IF;
  IF 'phone' = ANY(v_req) AND v_phone IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Telefon raqami noto''g''ri.');
  END IF;
  IF 'parent_name' = ANY(v_req) AND v_pname IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ota/ona F.I.O. kiritilishi kerak.');
  END IF;
  IF 'parent_phone' = ANY(v_req) AND v_pphone IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ota/ona telefon raqami noto''g''ri.');
  END IF;
  IF 'email' = ANY(v_req) AND v_email IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Email manzili noto''g''ri.');
  END IF;

  -- FORMAT — QIYMAT BOR BO'LSA hamon qo'llanadi (majburiyligidan qat'i nazar)
  IF v_full IS NOT NULL AND (char_length(v_full) < 3 OR char_length(v_full) > 200) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'F.I.O. to''liq kiritilishi kerak.');
  END IF;
  IF v_birth IS NOT NULL AND (v_birth >= current_date OR v_birth < date '1900-01-01') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Tug''ilgan sana noto''g''ri.');
  END IF;
  IF v_gender IS NOT NULL AND v_gender NOT IN ('m', 'f') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Jinsi noto''g''ri.');
  END IF;
  IF v_pinfl IS NOT NULL AND v_pinfl !~ '^[0-9]{14}$' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'JSHSHIR (PINFL) 14 ta raqamdan iborat bo''lishi kerak.');
  END IF;
  IF v_pser IS NOT NULL AND v_pser !~ '^[A-Z]{2}[0-9]{7}$' THEN
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
  IF v_addr IS NOT NULL AND (char_length(v_addr) < 5 OR char_length(v_addr) > 500) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Yashash manzili to''liq kiritilishi kerak.');
  END IF;
  IF v_pname IS NOT NULL AND (char_length(v_pname) < 3 OR char_length(v_pname) > 200) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ota/ona F.I.O. kiritilishi kerak.');
  END IF;

  -- Telefonlar: faqat raqamlar bo'yicha tekshiriladi (format erkin)
  IF v_phone IS NOT NULL
     AND (char_length(regexp_replace(v_phone, '[^0-9]', '', 'g')) NOT BETWEEN 7 AND 15
          OR char_length(v_phone) > 30) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Telefon raqami noto''g''ri.');
  END IF;
  IF v_pphone IS NOT NULL
     AND (char_length(regexp_replace(v_pphone, '[^0-9]', '', 'g')) NOT BETWEEN 7 AND 15
          OR char_length(v_pphone) > 30) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ota/ona telefon raqami noto''g''ri.');
  END IF;

  IF v_email IS NOT NULL
     AND (char_length(v_email) > 200
          OR v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Email manzili noto''g''ri.');
  END IF;

  -- Rozilik (D7 / brief 64-qator): SERVERDA tekshiriladi — O'ZGARMAGAN.
  IF v_cons IS DISTINCT FROM 'true' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Rozilik tasdiqlanmagan.');
  END IF;
  IF v_cver IS NULL OR char_length(v_cver) > 40 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Shaxsiy ma''lumotlarga rozilik tasdiqlanmagan.');
  END IF;

  -- 🔴 TIZIM FAYLLARI: majburiyligi dinamik, PREFIKS tekshiruvi esa DOIMIY —
  --    mijoz boshqa yo'lni ko'rsatib qatorga begona path yozdirmasin.
  IF ('photo_path'                 = ANY(v_req) AND v_ph  IS NULL)
     OR ('passport_front_path'        = ANY(v_req) AND v_pf  IS NULL)
     OR ('passport_back_path'         = ANY(v_req) AND v_pb  IS NULL)
     OR ('parent_passport_front_path' = ANY(v_req) AND v_ppf IS NULL)
     OR ('parent_passport_back_path'  = ANY(v_req) AND v_ppb IS NULL) THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'Hujjatlar to''liq yuklanmadi. Sahifani yangilab, qaytadan urinib ko''ring.');
  END IF;

  FOREACH v_tmp IN ARRAY ARRAY[v_ph, v_pf, v_pb, v_ppf, v_ppb] LOOP
    IF v_tmp IS NOT NULL
       AND (char_length(v_tmp) > 400
            OR lower(left(v_tmp, char_length(v_pref))) <> v_pref) THEN
      RETURN jsonb_build_object('ok', false,
        'error', 'Hujjatlar to''liq yuklanmadi. Sahifani yangilab, qaytadan urinib ko''ring.');
    END IF;
  END LOOP;

  -- 🔴 SHARTNOMA (D10): sukut bo'yicha HR maydoni. Kelsa prefiks tekshiriladi.
  IF 'contract_path' = ANY(v_req) AND v_ctr IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Shartnoma fayli yuklanmadi.');
  END IF;
  IF v_ctr IS NOT NULL
     AND (char_length(v_ctr) > 400
          OR lower(left(v_ctr, char_length(v_pref))) <> v_pref) THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'Shartnoma fayli qabul qilinmadi. Sahifani yangilab, qaytadan urinib ko''ring.');
  END IF;

  -- ── 5) MAXSUS MAYDONLAR — validatsiya (hali YOZILMAYDI) ─────────────
  v_fmap := CASE WHEN jsonb_typeof(p_payload->'fields') = 'object' THEN p_payload->'fields' ELSE '{}'::jsonb END;
  v_lmap := CASE WHEN jsonb_typeof(p_payload->'files')  = 'object' THEN p_payload->'files'  ELSE '{}'::jsonb END;

  FOR v_f IN
    SELECT f.id, f.key, f.ftype, f.required, f.name_uz, f.options
      FROM public.hr_fields f
     WHERE f.workspace_id = v_ws
       AND f.active
       AND f.fill_by IN ('employee','both')
       AND f.col IS NULL
     ORDER BY f.sort_order, f.key
     LIMIT 300
  LOOP
    v_val   := nullif(btrim(coalesce(v_fmap ->> v_f.id::text, '')), '');
    v_fpath := nullif(btrim(coalesce(v_lmap ->> v_f.id::text, '')), '');

    IF v_f.ftype = 'file' THEN
      IF v_f.required AND v_fpath IS NULL THEN
        RETURN jsonb_build_object('ok', false,
          'error', '«' || v_f.name_uz || '» fayli yuklanmadi.');
      END IF;
      IF v_fpath IS NOT NULL
         AND (char_length(v_fpath) > 400
              OR lower(left(v_fpath, char_length(v_pref))) <> v_pref) THEN
        RETURN jsonb_build_object('ok', false,
          'error', '«' || v_f.name_uz || '» fayli qabul qilinmadi. Sahifani yangilab, qaytadan urinib ko''ring.');
      END IF;
      v_val := NULL;   -- fayl maydonida matn qiymati saqlanmaydi

    ELSIF v_f.ftype = 'checkbox' THEN
      IF v_val IS NOT NULL THEN
        v_val := CASE WHEN lower(v_val) IN ('true','1','yes','on','ha') THEN 'true' ELSE 'false' END;
      END IF;
      IF v_f.required AND (v_val IS NULL OR v_val <> 'true') THEN
        RETURN jsonb_build_object('ok', false,
          'error', '«' || v_f.name_uz || '» tasdiqlanishi kerak.');
      END IF;

    ELSE
      IF v_f.required AND v_val IS NULL THEN
        RETURN jsonb_build_object('ok', false,
          'error', '«' || v_f.name_uz || '» to''ldirilishi shart.');
      END IF;

      IF v_val IS NOT NULL THEN
        IF char_length(v_val) > (CASE WHEN v_f.ftype = 'textarea' THEN 5000 ELSE 1000 END) THEN
          RETURN jsonb_build_object('ok', false,
            'error', '«' || v_f.name_uz || '» juda uzun.');
        END IF;

        IF v_f.ftype = 'number' THEN
          v_val := replace(v_val, ',', '.');
          IF v_val !~ '^-?[0-9]+(\.[0-9]+)?$' THEN
            RETURN jsonb_build_object('ok', false,
              'error', '«' || v_f.name_uz || '» — faqat raqam kiritiladi.');
          END IF;

        ELSIF v_f.ftype = 'date' THEN
          BEGIN
            v_val := (v_val::date)::text;   -- kanonik YYYY-MM-DD
          EXCEPTION WHEN others THEN
            RETURN jsonb_build_object('ok', false,
              'error', '«' || v_f.name_uz || '» — sana formati noto''g''ri (YYYY-MM-DD).');
          END;

        ELSIF v_f.ftype = 'email' THEN
          v_val := lower(v_val);
          IF v_val !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$' THEN
            RETURN jsonb_build_object('ok', false,
              'error', '«' || v_f.name_uz || '» — email manzili noto''g''ri.');
          END IF;

        ELSIF v_f.ftype = 'tel' THEN
          IF char_length(regexp_replace(v_val, '[^0-9]', '', 'g')) NOT BETWEEN 7 AND 15
             OR char_length(v_val) > 30 THEN
            RETURN jsonb_build_object('ok', false,
              'error', '«' || v_f.name_uz || '» — telefon raqami noto''g''ri.');
          END IF;

        ELSIF v_f.ftype = 'select' THEN
          -- 🔴 Faqat KATALOGDAGI variant qabul qilinadi (mijoz ixtiyoriy
          --    qiymat yuborib "boshqa" javob yozdirmasin).
          IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_f.options) o
                          WHERE o->>'value' = v_val) THEN
            RETURN jsonb_build_object('ok', false,
              'error', '«' || v_f.name_uz || '» — tanlangan variant noto''g''ri.');
          END IF;
        END IF;
      END IF;
      v_fpath := NULL;   -- fayl bo'lmagan maydonda yo'l saqlanmaydi
    END IF;

    -- ⚠️ Bo'sh javob YOZILMAYDI: HR allaqachon kiritgan qiymat o'chib ketmasin.
    IF v_val IS NOT NULL OR v_fpath IS NOT NULL THEN
      v_acc := v_acc || jsonb_build_array(
                 jsonb_build_object('f', v_f.id, 'v', v_val, 'p', v_fpath));
    END IF;
  END LOOP;

  -- ── 6) User-Agent (audit) ───────────────────────────────────────────
  BEGIN
    v_ua := current_setting('request.headers', true)::jsonb ->> 'user-agent';
  EXCEPTION WHEN others THEN
    v_ua := NULL;
  END;
  v_ua := left(coalesce(v_ua, nullif(btrim(coalesce(p_payload->>'_ua', '')), ''), ''), 300);

  -- ── 7) ATOMIK DA'VO (3-qoida) ───────────────────────────────────────
  UPDATE public.hr_apply_tokens
     SET used_at = now(),
         used_ua = v_ua
   WHERE token = p_token
     AND used_at IS NULL
     AND expires_at > now()
  RETURNING candidate_id, workspace_id INTO v_cand, v_ws;

  IF NOT FOUND THEN
    -- Poyga: yuqoridagi o'qishdan keyin boshqa birov ulgurdi. Hech narsa yozilmadi.
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

  -- ── 8) NOMZOD QATORI (tizim maydonlari) ─────────────────────────────
  -- ⚠️ HAMMASI COALESCE: yashirilgan/yuborilmagan maydon HR kiritgan qiymatni
  --    O'CHIRMASIN. Qiymat bor bo'lganda natija avvalgidek.
  UPDATE public.hr_candidates SET
      full_name                  = COALESCE(v_full,   full_name),
      birth_date                 = COALESCE(v_birth,  birth_date),
      gender                     = COALESCE(v_gender, gender),
      pinfl                      = COALESCE(v_pinfl,  pinfl),
      passport_serial            = COALESCE(v_pser,   passport_serial),
      passport_issued_by         = COALESCE(v_pby,    passport_issued_by),
      passport_issued_at         = COALESCE(v_pat,    passport_issued_at),
      passport_expires_at        = COALESCE(v_pex,    passport_expires_at),
      address                    = COALESCE(v_addr,   address),
      phone                      = COALESCE(v_phone,  phone),
      parent_name                = COALESCE(v_pname,  parent_name),
      parent_phone               = COALESCE(v_pphone, parent_phone),
      email                      = COALESCE(v_email,  email),
      photo_path                 = COALESCE(v_ph,     photo_path),
      passport_front_path        = COALESCE(v_pf,     passport_front_path),
      passport_back_path         = COALESCE(v_pb,     passport_back_path),
      parent_passport_front_path = COALESCE(v_ppf,    parent_passport_front_path),
      parent_passport_back_path  = COALESCE(v_ppb,    parent_passport_back_path),
      contract_path              = COALESCE(v_ctr,    contract_path),
      -- ⚠️ referred_by / position_id / project_id BU YERDA UMUMAN yozilmaydi.
      consent_at                 = now(),
      consent_version            = v_cver,
      status                     = 'pending',
      submitted_at               = now()
   WHERE id = v_cand
     AND workspace_id = v_ws;

  IF NOT FOUND THEN
    -- Bu holat bo'lishi mumkin emas (token → candidate FK CASCADE).
    -- EXCEPTION butun statement'ni, ya'ni token da'vosini ham QAYTARADI.
    RAISE EXCEPTION 'hr_apply_submit: nomzod qatori topilmadi (candidate=%)', v_cand;
  END IF;

  -- ── 9) MAXSUS MAYDON QIYMATLARI ─────────────────────────────────────
  FOR v_w IN SELECT (e->>'f')::uuid AS fid, e->>'v' AS val, e->>'p' AS path
               FROM jsonb_array_elements(v_acc) e
  LOOP
    INSERT INTO public.hr_candidate_values (candidate_id, field_id, workspace_id, value, file_path)
    VALUES (v_cand, v_w.fid, v_ws, v_w.val, v_w.path)
    ON CONFLICT (candidate_id, field_id) DO UPDATE
      SET value     = COALESCE(EXCLUDED.value,     public.hr_candidate_values.value),
          file_path = COALESCE(EXCLUDED.file_path, public.hr_candidate_values.file_path);
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'state', 'submitted');
END;
$fn$;

COMMENT ON FUNCTION public.hr_apply_submit(uuid, jsonb) IS
  'Public apply formasini qabul qiladi (DINAMIK maydonlar bilan). SECURITY DEFINER. 3 majburiy qoida saqlangan: (1) tizim maydonlari p_payload dan FAQAT oq ro''yxat bo''yicha ->> bilan; (2) validatsiya token DA''VOSIDAN OLDIN (token faqat o''qiladi); (3) UPDATE hr_apply_tokens ... WHERE used_at IS NULL AND expires_at > now() — atomik. YANGI: majburiylik hr_fields.required dan (zaxira — eski qat''iy ro''yxat), maxsus maydonlar p_payload->fields/->files dan SERVER ro''yxati bo''yicha filtrlanadi (active + fill_by IN employee/both + col IS NULL) va hr_candidate_values ga yoziladi.';

REVOKE ALL ON FUNCTION public.hr_apply_submit(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hr_apply_submit(uuid, jsonb) TO anon, authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- 10) TEKSHIRUV — JIMGINA O'TMASIN
-- ════════════════════════════════════════════════════════════════════════════
DO $chk$
DECLARE
  v_cnt  int;
  v_exp  int;
  v_txt  text;
  v_src  text;
  v_norm text;   -- izohsiz + bo'shliqlar normallashtirilgan + UPPER
  v_flat text;   -- v_norm, bo'shliqsiz va qo'shtirnoqsiz (naqsh qidirish uchun)
  t      text;
  r      record;
BEGIN
  -- ── 10.a) Ikkala jadval bor va RLS yoqilgan ───────────────────────
  FOREACH t IN ARRAY ARRAY['hr_fields','hr_candidate_values'] LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE EXCEPTION '%: jadval yaratilmadi', t;
    END IF;
    SELECT count(*) INTO v_cnt FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = t AND c.relrowsecurity;
    IF v_cnt = 0 THEN
      RAISE EXCEPTION '%: RLS yoqilmadi — shaxsiy ma''lumot hammaga ochiq qolardi!', t;
    END IF;
  END LOOP;

  -- ── 10.b) Ustunlar to'liqmi ───────────────────────────────────────
  SELECT count(*) INTO v_cnt FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'hr_fields'
     AND column_name IN ('id','workspace_id','key','col','is_system','name_uz','name_ru',
                         'name_en','ftype','required','fill_by','options','placeholder_uz',
                         'placeholder_ru','placeholder_en','sort_order','active','section',
                         'created_by','created_at','updated_at');
  IF v_cnt <> 21 THEN
    RAISE EXCEPTION 'hr_fields ustunlari to''liq emas (% / 21) — jadval avval boshqa sxema bilan yaratilganmi?', v_cnt;
  END IF;

  SELECT count(*) INTO v_cnt FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'hr_candidate_values'
     AND column_name IN ('candidate_id','field_id','workspace_id','value','file_path','updated_at');
  IF v_cnt <> 6 THEN
    RAISE EXCEPTION 'hr_candidate_values ustunlari to''liq emas (% / 6)', v_cnt;
  END IF;

  SELECT count(*) INTO v_cnt FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'hr_candidates'
     AND column_name IN ('project_id','project_started_at');
  IF v_cnt <> 2 THEN
    RAISE EXCEPTION 'hr_candidates ga project_id / project_started_at qo''shilmadi (% / 2)', v_cnt;
  END IF;

  -- ── 10.c) CHECK'lar (conrelid bilan skoplangan) ───────────────────
  SELECT count(*) INTO v_cnt FROM pg_constraint
   WHERE contype = 'c' AND conrelid = 'public.hr_fields'::regclass
     AND conname IN ('hr_fields_ftype_chk','hr_fields_fillby_chk','hr_fields_syscol_chk',
                     'hr_fields_options_arr_chk','hr_fields_options_chk',
                     'hr_fields_name_chk','hr_fields_key_chk');
  IF v_cnt <> 7 THEN
    RAISE EXCEPTION 'hr_fields CHECK''lari to''liq emas (% / 7)', v_cnt;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE contype = 'c' AND conrelid = 'public.hr_candidate_values'::regclass
                    AND conname = 'hr_cand_values_len_chk') THEN
    RAISE EXCEPTION 'hr_cand_values_len_chk CHECK''i yaratilmadi';
  END IF;

  -- ── 10.d) Indekslar ───────────────────────────────────────────────
  FOREACH t IN ARRAY ARRAY['hr_fields_ws_key_uidx','hr_fields_ws_active_sort_idx',
                           'hr_cand_values_field_idx','hr_cand_values_ws_idx'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = t) THEN
      RAISE EXCEPTION '% indeksi yaratilmadi', t;
    END IF;
  END LOOP;

  -- ── 10.e) Triggerlar ──────────────────────────────────────────────
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgrelid = 'public.hr_candidate_values'::regclass
                    AND tgname = 'hr_cand_values_guard_trg' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'hr_cand_values_guard_trg yaratilmadi — begona workspace maydonini ulash mumkin bo''lardi. To''xtatildi.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgrelid = 'public.hr_fields'::regclass
                    AND tgname = 'hr_fields_guard_trg' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'hr_fields_guard_trg yaratilmadi — tizim maydonining col/ftype si o''zgartirilishi mumkin bo''lardi. To''xtatildi.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgrelid = 'public.hr_fields'::regclass
                    AND tgname = 'hr_fields_touch_trg' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'hr_fields_touch_trg yaratilmadi (updated_at)';
  END IF;

  -- ── 10.f) Policy'lar ──────────────────────────────────────────────
  FOREACH t IN ARRAY ARRAY['hr_fields','hr_candidate_values'] LOOP
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
      RAISE EXCEPTION '%: anon/public uchun policy topildi: % — ma''lumot ochilib ketardi. To''xtatildi.', t, v_txt;
    END IF;
  END LOOP;

  -- 🔴 hr_candidate_values SELECT policy'si USING (true) BO'LMASLIGI SHART:
  --    kimdir uni "hammaga ochiq" qilib qayta yozsa, maxsus maydonlardagi
  --    (sudlanganlik, kredit tarixi…) javoblar butun ilovaga ochilardi.
  SELECT coalesce(qual, '') INTO v_txt
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'hr_candidate_values'
     AND cmd = 'SELECT'
   LIMIT 1;
  IF v_txt IS NULL OR btrim(v_txt) = '' THEN
    RAISE EXCEPTION 'hr_candidate_values SELECT policy''si topilmadi';
  END IF;
  IF lower(btrim(v_txt)) IN ('true', '(true)') THEN
    RAISE EXCEPTION 'hr_candidate_values SELECT policy''si USING (true) — shaxsiy javoblar hammaga ochiq bo''lardi. To''xtatildi.';
  END IF;
  IF strpos(upper(v_txt), 'IS_WS_MANAGER(') = 0 THEN
    RAISE EXCEPTION 'hr_candidate_values SELECT policy''sida is_ws_manager(...) yo''q — shart: %. To''xtatildi.', v_txt;
  END IF;

  -- 🔴 hr_fields DELETE policy'sida `is_system` SHARTI BOR (tizim maydoni
  --    o'chirilsa hr_apply_submit oq ro'yxati bilan bog'lanish uzilardi va
  --    forma jimgina "yarim" bo'lib qolardi).
  SELECT coalesce(qual, '') INTO v_txt
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'hr_fields' AND cmd = 'DELETE'
   LIMIT 1;
  IF v_txt IS NULL OR btrim(v_txt) = '' THEN
    RAISE EXCEPTION 'hr_fields DELETE policy''si topilmadi';
  END IF;
  IF v_txt !~* 'is_system' THEN
    RAISE EXCEPTION 'hr_fields DELETE policy''sida is_system sharti YO''Q — HR tizim maydonini o''chirib yuborardi. Shart: %. To''xtatildi.', v_txt;
  END IF;
  IF strpos(upper(v_txt), 'IS_WS_MANAGER(') = 0 THEN
    RAISE EXCEPTION 'hr_fields DELETE policy''sida is_ws_manager(...) yo''q: %. To''xtatildi.', v_txt;
  END IF;

  -- ── 10.g) hr_apply_peek() — dinamik, lekin ORTIQCHA MA'LUMOTSIZ ────
  SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'hr_apply_peek' AND p.pronargs = 1
   LIMIT 1;
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'hr_apply_peek(uuid) tanasi o''qilmadi';
  END IF;
  v_norm := upper(regexp_replace(v_src, '\s+', ' ', 'g'));
  v_flat := replace(replace(v_norm, '''', ''), ' ', '');

  IF strpos(v_norm, 'HR_CANDIDATES') > 0 THEN
    RAISE EXCEPTION 'hr_apply_peek() KODIDA hr_candidates ga murojaat bor — nomzod ma''lumoti sizib chiqardi (brief 44-qator). To''xtatildi.';
  END IF;
  IF strpos(v_flat, 'ANDF.ACTIVEANDF.FILL_BYIN(EMPLOYEE,BOTH)') = 0 THEN
    RAISE EXCEPTION 'hr_apply_peek() KODIDA `AND f.active AND f.fill_by IN (''employee'',''both'')` filtri topilmadi — HR-ONLY maydonlar (shartnoma, kim taklif qildi, izoh) nomzodga ochilib ketardi. To''xtatildi.';
  END IF;
  IF strpos(v_flat, 'F.WORKSPACE_ID=V_WS') = 0 THEN
    RAISE EXCEPTION 'hr_apply_peek() KODIDA maydonlar workspace bo''yicha filtrlanmayapti (f.workspace_id = v_ws) — begona tashkilot maydonlari ko''rinardi. To''xtatildi.';
  END IF;

  -- ── 10.h) hr_apply_submit() tanasidagi MAJBURIY qorovullar ────────
  -- Izohlar avval tozalanadi: tanadagi ogohlantirish izohlarida ham shu
  -- matnlar bor — kod o'chirilib izoh qoldirilgan holat sezilmay qolmasin.
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
  IF strpos(v_flat, 'P_PAYLOAD->>CONSENT)') = 0
     OR strpos(v_flat, 'V_CONSISDISTINCTFROMTRUE') = 0 THEN
    RAISE EXCEPTION 'hr_apply_submit() KODIDA rozilik tekshirilmayapti (p_payload->>''consent'' <> ''true'' bo''lsa rad etilishi shart). To''xtatildi.';
  END IF;
  IF strpos(v_flat, 'SUBMITTED_AT=NOW()') = 0 THEN
    RAISE EXCEPTION 'hr_apply_submit() KODIDA submitted_at = now() yo''q. To''xtatildi.';
  END IF;

  -- 🔴 OQ RO'YXAT BUZILMAGANMI (D2/D10) + project_id ham qo'shildi
  FOREACH t IN ARRAY ARRAY['STATUS','WORKSPACE_ID','WANT_','POSITION_ID','BRANCH_FOLDER_ID',
                           'HIRED_BY_USER_ID','TASKFIX_','KASSA_','CONSENT_AT',
                           'SUBMITTED_AT','CREATED_BY','REFERRED_BY','PROJECT_','ID'] LOOP
    IF strpos(v_flat, 'P_PAYLOAD->>' || t) > 0 OR strpos(v_flat, 'P_PAYLOAD->' || t) > 0 THEN
      RAISE EXCEPTION 'hr_apply_submit() KODIDA p_payload dan "%" o''qilmoqda — bu maydon MIJOZDAN qabul qilinmasligi kerak (oq ro''yxat). To''xtatildi.', lower(t);
    END IF;
  END LOOP;
  IF strpos(v_flat, 'JSONB_POPULATE_RECORD') > 0 OR strpos(v_flat, 'JSONB_TO_RECORD') > 0 THEN
    RAISE EXCEPTION 'hr_apply_submit() butun jsonb ni qatorga yozmoqchi (jsonb_populate_record/to_record) — oq ro''yxat chetlab o''tilgan. To''xtatildi.';
  END IF;

  -- 🔴 OQ RO'YXAT SONI: p_payload dan `->>` bilan o'qiladigan kalitlar AYNAN 22
  --    (21 nomzod maydoni + `_ua`). Dinamik maydonlar `p_payload->'fields'` /
  --    `->'files'` orqali keladi (`->`, obyekt) va bu songa KIRMAYDI.
  v_cnt := array_length(string_to_array(v_flat, 'P_PAYLOAD->>'), 1) - 1;
  IF v_cnt <> 22 THEN
    RAISE EXCEPTION 'hr_apply_submit() oq ro''yxatida % ta kalit bor, 22 kutilgan (21 maydon + _ua). Kimdir maydon qo''shgan yoki olib tashlagan. To''xtatildi.', v_cnt;
  END IF;

  -- 🔴 DINAMIK FILTR: maxsus maydonlar SERVER ro'yxatidan olinadi
  IF strpos(v_norm, 'HR_FIELDS') = 0 THEN
    RAISE EXCEPTION 'hr_apply_submit() KODIDA hr_fields dan o''qish YO''Q — dinamik maydonlar va dinamik majburiylik ishlamasdi. To''xtatildi.';
  END IF;
  IF strpos(v_flat, 'ANDF.ACTIVEANDF.FILL_BYIN(EMPLOYEE,BOTH)') = 0 THEN
    RAISE EXCEPTION 'hr_apply_submit() KODIDA `AND f.active AND f.fill_by IN (''employee'',''both'')` filtri topilmadi — nomzod HR-only yoki o''chirilgan maydonga qiymat yozdira olardi. To''xtatildi.';
  END IF;
  IF strpos(v_flat, 'F.WORKSPACE_ID=V_WS') = 0 THEN
    RAISE EXCEPTION 'hr_apply_submit() KODIDA maydonlar workspace bo''yicha filtrlanmayapti (f.workspace_id = v_ws) — BEGONA tashkilot maydoniga qiymat yozilishi mumkin bo''lardi. To''xtatildi.';
  END IF;
  IF strpos(v_flat, 'ANDF.COLISNULL') = 0 THEN
    RAISE EXCEPTION 'hr_apply_submit() KODIDA `AND f.col IS NULL` yo''q — tizim maydoni fields/files orqali ham yozilib, oq ro''yxat chetlab o''tilardi (GIBRID model buzilardi). To''xtatildi.';
  END IF;
  -- Fayl prefiksi maxsus maydonlarga ham qo'llanadimi?
  IF strpos(v_flat, 'LOWER(LEFT(V_FPATH,CHAR_LENGTH(V_PREF)))<>V_PREF') = 0 THEN
    RAISE EXCEPTION 'hr_apply_submit() KODIDA maxsus fayl maydoni uchun apply/<token>/ prefiks tekshiruvi yo''q — nomzod qatorga begona Storage yo''lini yozdira olardi. To''xtatildi.';
  END IF;

  -- ── 10.h2) hr_fields_guard() — yozib bo'lmaydigan 3 ustun qulfi ───
  -- 🔴 Busiz HR "Kim tavsiya qildi" ni nomzodga ochib qo'yardi va javob
  --    jimgina yo'qolardi (yuqoridagi izohga qarang).
  SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'hr_fields_guard'
   LIMIT 1;
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'hr_fields_guard() tanasi o''qilmadi';
  END IF;
  v_flat := replace(replace(upper(regexp_replace(v_src, '\s+', ' ', 'g')), '''', ''), ' ', '');
  IF strpos(v_flat, 'NEW.COLIN(REFERRED_BY,START_DATE,NOTES)') = 0
     OR strpos(v_flat, 'NEW.FILL_BY<>HR') = 0 THEN
    RAISE EXCEPTION 'hr_fields_guard() KODIDA referred_by/start_date/notes uchun fill_by = hr qulfi topilmadi — HR bu maydonlarni nomzodga ochib qo''ysa javob JIMGINA yo''qolardi. To''xtatildi.';
  END IF;

  -- ── 10.i) STORAGE: yangi policy YO'Q, mavjudlari yo'llarni qoplaydi ─
  -- ⚠️ Bu skript storage.objects ga TEGMAYDI. Faqat dinamik fayllar
  --    ishlashiga ishonch hosil qilamiz: mavjud policy'lar yo'lning 1–2
  --    segmentiga qaraydi (fayl NOMI ixtiyoriy), ya'ni f_<field_id>-… ishlaydi.
  SELECT count(*) INTO v_cnt FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects'
     AND policyname IN ('hrdocs_anon_insert','hrdocs_auth_select','hrdocs_auth_insert',
                        'hrdocs_auth_update','hrdocs_auth_delete');
  IF v_cnt < 5 THEN
    RAISE EXCEPTION 'hr-docs storage policy''lari to''liq emas (% / 5) — TASKFIX_HR_RECRUITING.sql ni ishga tushiring (yoki qayta run qiling). To''xtatildi.', v_cnt;
  END IF;

  SELECT lower(coalesce(with_check, '')) INTO v_txt
    FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects'
     AND policyname = 'hrdocs_anon_insert';
  IF strpos(v_txt, '''apply''') = 0 OR strpos(v_txt, 'hr_token_open') = 0 THEN
    RAISE EXCEPTION 'hrdocs_anon_insert policy''si kutilganidek emas (apply/ + hr_token_open): % — nomzod dinamik faylni yuklay olmasdi (yoki ixtiyoriy joyga yuklardi). To''xtatildi.', v_txt;
  END IF;

  SELECT lower(coalesce(qual, '')) INTO v_txt
    FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects'
     AND policyname = 'hrdocs_auth_select';
  IF strpos(v_txt, '''apply''') = 0 OR strpos(v_txt, '''ws''') = 0 THEN
    RAISE EXCEPTION 'hrdocs_auth_select policy''sida apply/ yoki ws/ shoxi yo''q: % — HR dinamik hujjatni ocholmasdi. TASKFIX_HR_RECRUITING.sql ni qayta run qiling. To''xtatildi.', v_txt;
  END IF;

  -- ── 10.j) SEED to'g'ri bajarildimi ────────────────────────────────
  SELECT count(*) INTO v_exp FROM public.hr_fields_defaults();
  IF v_exp <> 22 THEN
    RAISE EXCEPTION 'hr_fields_defaults() % ta qator qaytardi, 22 kutilgan — katalog o''zgartirilgan. Seed va trigger buni birga ishlatadi, tekshiring.', v_exp;
  END IF;

  FOR r IN SELECT f.workspace_id AS ws, count(*) FILTER (WHERE f.is_system) AS n
             FROM public.hr_fields f
            GROUP BY f.workspace_id
           HAVING count(*) FILTER (WHERE f.is_system) > 0
  LOOP
    IF r.n <> v_exp THEN
      RAISE EXCEPTION 'workspace % da tizim maydonlari soni % (kutilgan %) — seed to''liq bajarilmagan yoki qator qo''lda o''chirilgan. Skriptni qayta run qiling.', r.ws, r.n, v_exp;
    END IF;
  END LOOP;

  -- Tizim qatorlari haqiqatan ustunga bog'langanmi (col mavjud ustunmi)?
  SELECT count(*) INTO v_cnt
    FROM (SELECT DISTINCT f.col FROM public.hr_fields f WHERE f.is_system) x
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns c
                      WHERE c.table_schema = 'public' AND c.table_name = 'hr_candidates'
                        AND c.column_name = x.col);
  IF v_cnt > 0 THEN
    RAISE EXCEPTION '% ta tizim maydonining `col` i hr_candidates da mavjud emas — qiymat hech qayerga yozilmasdi. To''xtatildi.', v_cnt;
  END IF;

  -- ── 10.k) Funksiyalar + huquqlar ──────────────────────────────────
  FOREACH t IN ARRAY ARRAY['hr_fields_defaults','hr_fields_seed','hr_apply_peek',
                           'hr_apply_submit','hr_cand_values_guard','hr_fields_guard'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = 'public' AND p.proname = t) THEN
      RAISE EXCEPTION '%() yaratilmadi', t;
    END IF;
  END LOOP;

  -- 🔴 hr_fields_seed SECURITY DEFINER BO'LMASLIGI kerak (RLS qorovul bo'lsin)
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'hr_fields_seed' AND p.prosecdef) THEN
    RAISE EXCEPTION 'hr_fields_seed() SECURITY DEFINER — u RLS ni chetlab o''tib, istalgan foydalanuvchiga BEGONA workspace''ga qator yozdirardi. To''xtatildi.';
  END IF;

  -- anon apply funksiyalarini chaqira olishi SHART, seed'ni esa YO'Q
  FOREACH t IN ARRAY ARRAY['public.hr_apply_peek(uuid)','public.hr_apply_submit(uuid, jsonb)'] LOOP
    IF NOT has_function_privilege('anon', t, 'EXECUTE') THEN
      RAISE EXCEPTION 'anon roli % ni chaqira olmaydi — apply sahifasi ishlamas edi.', t;
    END IF;
  END LOOP;
  IF has_function_privilege('anon', 'public.hr_fields_seed(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon roli hr_fields_seed() ni chaqira oladi — begona odam maydon yarata olardi. To''xtatildi.';
  END IF;

  -- ── 10.l) Eski tizim butunmi? ─────────────────────────────────────
  FOREACH t IN ARRAY ARRAY['hr_candidates','hr_apply_tokens','hr_settings',
                           'workspaces','positions','org_folders','tasks'] LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE EXCEPTION 'Mavjud jadval % yo''qolgan — TO''XTANG!', t;
    END IF;
  END LOOP;
  SELECT count(*) INTO v_cnt FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'hr_candidates';
  IF v_cnt < 4 THEN
    RAISE EXCEPTION 'hr_candidates policy''lari yo''qolgan (% ta) — TO''XTANG!', v_cnt;
  END IF;

  -- ── HISOBOT ───────────────────────────────────────────────────────
  SELECT count(DISTINCT workspace_id) INTO v_cnt FROM public.hr_fields;
  SELECT count(*) INTO v_exp FROM public.hr_fields;

  RAISE NOTICE '─────────────────────────────────────────────';
  RAISE NOTICE 'TASKFIX_HR_DYNAMIC.sql — TAYYOR';
  RAISE NOTICE '  hr_fields            : 21 ustun, 7 CHECK, RLS + 4 policy';
  RAISE NOTICE '                         (SELECT = ws a''zosi, yozuv = manager/HR muharriri,';
  RAISE NOTICE '                          DELETE = faqat is_system = false)';
  RAISE NOTICE '  hr_candidate_values  : 6 ustun, RLS + 4 policy (faqat manager/HR muharriri)';
  RAISE NOTICE '  hr_candidates        : +project_id, +project_started_at';
  RAISE NOTICE '  katalog              : hr_fields_defaults() — 22 tizim maydoni';
  RAISE NOTICE '  seed                 : % ta workspace, jami % ta maydon qatori', v_cnt, v_exp;
  RAISE NOTICE '  hr_apply_peek()      : + fields[] (faqat active + employee/both)';
  RAISE NOTICE '  hr_apply_submit()    : dinamik majburiylik + maxsus maydonlar';
  RAISE NOTICE '                         (3 qat''iy qoida saqlangan, oq ro''yxat = 22 kalit)';
  RAISE NOTICE '  storage              : YANGI POLICY YO''Q (mavjud yo''llar qoplaydi)';
  RAISE NOTICE '─────────────────────────────────────────────';
  RAISE NOTICE 'MIJOZ UCHUN: maydon ro''yxati bo''sh workspace''da hr_fields_seed(ws) RPC';
  RAISE NOTICE '             chaqiring (idempotent). Qiymat manzili: col IS NOT NULL →';
  RAISE NOTICE '             payload[col], col IS NULL → payload.fields[id]/files[id].';
  RAISE NOTICE '─────────────────────────────────────────────';
END $chk$;

COMMIT;

-- ============================================================================
-- MIJOZ TOMONI UCHUN QISQA ESLATMA (kod bu faylda YO'Q)
--
--   -- HR paneli (index.html)
--   const { data, error } = await sb.from('hr_fields')
--       .select('*').eq('workspace_id', ws).order('sort_order');
--   ⚠️ `{ error }` DOIM tekshiriladi (supabase-js throw QILMAYDI — 6-qoida).
--   Ro'yxat bo'sh bo'lsa: await sb.rpc('hr_fields_seed', { p_ws: ws });
--   🔴 MAXSUS MAYDON QO'SHISHDAN OLDIN seed MAJBURIY. Sabab: hr_apply_submit
--      "hr_fields da qator BORmi?" degan savol bilan dinamik rejimga o'tadi.
--      Agar workspace'da FAQAT maxsus maydonlar bo'lsa (tizim maydonlari
--      seed qilinmagan), tizim ustunlari "nomzodga ko'rinmaydi" deb
--      hisoblanadi va F.I.O./passport/telefon JIMGINA yozilmay qoladi.
--      Shuning uchun mijoz "+ Maydon qo'shish" oqimida ham avval seed'ni
--      chaqiradi (idempotent, 0 qaytarsa hammasi joyida).
--   ⚠️ Tizim maydonini O'CHIRISH tugmasi CHIZILMASIN (is_system) — RLS baribir
--      rad etadi, lekin foydalanuvchi sababsiz xato ko'rmasin. "Yashirish" =
--      active = false.
--
--   -- Nomzod sahifasi (hr-apply.html)
--   const { data } = await sb.rpc('hr_apply_peek', { p_token: t });
--   data.fields → formani chizadi (ro'yxat bo'sh bo'lsa ESKI qat'iy forma).
--   Yuborish:
--     payload[f.col] = qiymat            // f.col !== null  (tizim maydoni)
--     payload.fields[f.id] = qiymat      // f.col === null  (maxsus)
--     payload.files[f.id]  = 'apply/<token>/f_<f.id>-<rand>.<ext>'
--   await sb.rpc('hr_apply_submit', { p_token: t, p_payload: payload });
--   ⚠️ `data.ok === false` bo'lsa `data.error` / `data.state` ko'rsatiladi
--      (RPC muvaffaqiyatli qaytgani "saqlandi" degani EMAS).
--   ⚠️ Preview MAHALLIY (URL.createObjectURL) — anon uchun SELECT policy YO'Q.
--
--   -- HR tomonida maxsus qiymatlarni o'qish
--   sb.from('hr_candidate_values').select('field_id,value,file_path')
--     .eq('candidate_id', id);
--   Fayl: sb.storage.from('hr-docs').createSignedUrls([file_path], 3600);
--   ⚠️ Nomzodni O'CHIRISHDA tartib O'ZGARMAYDI: avval Storage, keyin qator
--      (hrcDelete/hrcDocPaths naqshi) — maxsus fayl yo'llari ham
--      hr_candidate_values.file_path dan yig'iladi, aks holda ular omborda
--      "yetim" qolib, apply/ shoxi yopilgach abadiy qulflanadi.
--
-- ── QAYTARISH (rollback) ────────────────────────────────────────────────────
--   -- ⚠️ hr_apply_peek / hr_apply_submit ESKI (dinamiksiz) versiyaga qaytishi
--   --    uchun TASKFIX_HR_RECRUITING.sql ni QAYTA RUN qiling — u ikkalasini
--   --    CREATE OR REPLACE bilan tiklaydi.
--   DROP TRIGGER  IF EXISTS hr_cand_values_guard_trg ON public.hr_candidate_values;
--   DROP TRIGGER  IF EXISTS hr_fields_guard_trg      ON public.hr_fields;
--   DROP TRIGGER  IF EXISTS hr_fields_touch_trg      ON public.hr_fields;
--   DROP TABLE    IF EXISTS public.hr_candidate_values CASCADE;  -- 🔴 javoblar yo'qoladi
--   DROP TABLE    IF EXISTS public.hr_fields           CASCADE;
--   DROP FUNCTION IF EXISTS public.hr_cand_values_guard();
--   DROP FUNCTION IF EXISTS public.hr_fields_guard();
--   DROP FUNCTION IF EXISTS public.hr_fields_seed(uuid);
--   DROP FUNCTION IF EXISTS public.hr_fields_defaults();
--   ALTER TABLE public.hr_candidates DROP CONSTRAINT IF EXISTS hr_candidates_project_fk;
--   ALTER TABLE public.hr_candidates DROP COLUMN IF EXISTS project_id;
--   ALTER TABLE public.hr_candidates DROP COLUMN IF EXISTS project_started_at;
--   -- ⚠️ hr-docs dagi MAXSUS fayllar avtomat o'chirilmaydi (hujjatlar!).
--   --    Kerak bo'lsa qo'lda topib o'chiring: name LIKE '%/f\_%'
--   -- ⚠️ public.org_touch() O'CHIRILMAYDI — u TASKFIX_HR.sql niki.
-- ============================================================================
