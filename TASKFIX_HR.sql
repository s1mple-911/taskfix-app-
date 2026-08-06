-- ============================================================================
-- TASKFIX_HR.sql — HR Service + Org Schema (tashkiliy sxema)
-- ============================================================================
-- ADDITIVE + IDEMPOTENT. Mavjud jadvallarga (tasks, projects, departments,
-- workspace_members, tg_bot_users, org_containers…) TEGMAYDI — faqat 3 ta
-- YANGI jadval qo'shadi. Qayta ishga tushirilsa ham hech narsa buzilmaydi.
--
-- ⚠️ ESKI "Tashkilot tuzilmasi" (org_containers + workspace_members.node_x/y +
--    tg_bot_users.manager_id) O'CHIRILMAYDI va O'ZGARTIRILMAYDI. Yangi Org
--    Schema butunlay alohida jadvallarda yashaydi. Ilovada eski ko'rinish
--    vaqtincha yashirilgan, xolos — kerak bo'lsa qaytariladi.
--
-- NIMA QO'SHILADI
--   1) hr_settings   — HR Service har workspace uchun yoqilgan/o'chirilgan.
--                      DEFAULT: O'CHIQ (admin "Qo'shimcha service" dan yoqadi).
--   2) org_folders   — papka DARAXTI. Papka ichida papka (parent_id).
--                      ⚠️ Papkalarni foydalanuvchi NOLDAN o'zi yaratadi.
--                      TaskFix'dagi mavjud `departments` AVTOMAT tortilmaydi
--                      (2026-08-06 qarori — pastda 5-bo'limga qarang).
--   3) org_people    — sxemadagi O'RINLAR. ⚠️ Bitta xodim BIR NECHA
--                      o'rinda bo'la oladi (ikki bo'limda, bir necha rolda) —
--                      har qatori alohida o'rin. Bo'ysunish SAQLANMAYDI,
--                      daraxtdan hisoblanadi (5b-bo'lim).
--
-- IKKI KO'RINISH, BITTA MANBA: papka ko'rinishi ham, org chart vizuali ham
-- AYNAN shu 2 jadvaldan o'qiydi. Org chart joylashuvi avtomatik hisoblanadi
-- (node_x/node_y saqlanmaydi) — shuning uchun ikki ko'rinish hech qachon
-- bir-biridan ajralib qolmaydi.
--
-- ⚠️ BU FAYL ISHGA TUSHMASA — ilova YIQILMAYDI. HR Service kartasi
--    "SQL ishga tushirilmagan" deb ochiq aytadi, qolgan hamma narsa
--    (vazifa, loyiha, kanban, email, jamoa) avvalgidek ishlaydi.
--
-- TEXT + CHECK ishlatilgan (ENUM emas) — 30/32-migratsiyalardagi saboq.
-- RLS ichida workspace_members inline subquery YO'Q (42P17 rekursiya) —
-- faqat is_ws_member() / is_ws_manager().
-- ============================================================================

BEGIN;

-- ── 0) Oldindan tekshiruv — noto'g'ri bazada ishga tushmasin ────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'public' AND c.relname = 'workspaces') THEN
    RAISE EXCEPTION 'public.workspaces topilmadi — noto''g''ri baza?';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'public' AND c.relname = 'departments') THEN
    RAISE EXCEPTION 'public.departments topilmadi — noto''g''ri baza?';
  END IF;

  -- ⚠️ `departments` ga bu skript UMUMAN tegmaydi (avtomatik sync ham,
  --    FK ham olib tashlandi). Jadval faqat "to'g'ri bazadamizmi?"
  --    tekshiruvi sifatida qaraladi — yuqorida shu bajarildi.
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE p.proname = 'is_ws_member' AND n.nspname = 'public'
  ) THEN
    RAISE EXCEPTION 'is_ws_member() topilmadi. Avval 39_employee_details.sql ni ishga tushiring.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE p.proname = 'is_ws_manager' AND n.nspname = 'public'
  ) THEN
    RAISE EXCEPTION 'is_ws_manager() topilmadi. Avval 35_fix_projects_rls.sql ni ishga tushiring.';
  END IF;
END $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 1) hr_settings — HR Service yoqilganmi?
-- ════════════════════════════════════════════════════════════════════════════
-- Nega alohida jadval, `integrations` emas? `integrations.tool` da CHECK
-- bo'lishi mumkin va uni o'zgartirish MAVJUD Telegram/n8n integratsiyasiga
-- xavf tug'diradi. HR — tashqi xizmat emas, ichki modul: o'z jadvali.
CREATE TABLE IF NOT EXISTS public.hr_settings (
  workspace_id  uuid PRIMARY KEY REFERENCES public.workspaces(id) ON DELETE CASCADE,
  is_enabled    boolean NOT NULL DEFAULT false,   -- ⚠️ DEFAULT: O'CHIQ
  enabled_at    timestamptz,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  updated_by    uuid
);

ALTER TABLE public.hr_settings ADD COLUMN IF NOT EXISTS is_enabled boolean NOT NULL DEFAULT false;
ALTER TABLE public.hr_settings ADD COLUMN IF NOT EXISTS enabled_at timestamptz;
ALTER TABLE public.hr_settings ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.hr_settings ADD COLUMN IF NOT EXISTS updated_by uuid;
ALTER TABLE public.hr_settings ALTER COLUMN is_enabled SET DEFAULT false;

COMMENT ON TABLE public.hr_settings IS
  'HR Service moduli har workspace uchun yoqilgan/o''chirilgan. Yoqilsa chap menyuda "HR" bo''limi va "Org Schema" sahifasi paydo bo''ladi.';


-- ════════════════════════════════════════════════════════════════════════════
-- 2) org_folders — papka daraxti
-- ════════════════════════════════════════════════════════════════════════════
-- Oddiy papka daraxti, boshqa hech nima. Papkalarni foydalanuvchi noldan
-- o'zi yaratadi; TaskFix `departments` bilan HECH QANDAY bog'lanish yo'q.
--
-- ⚠️ Bu daraxt AYNI PAYTDA bo'ysunish sxemasi ham: pastdagi papkadagi hodim
--    yuqoridagi papkadagi hodimga bo'ysunadi (5b-bo'limga qarang).
CREATE TABLE IF NOT EXISTS public.org_folders (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id   uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  parent_id      uuid REFERENCES public.org_folders(id) ON DELETE CASCADE,
  name           text NOT NULL,
  icon           text,                              -- ixtiyoriy: ikonka nomi (ICON_PATHS kaliti)
  sort_order     integer NOT NULL DEFAULT 0,
  created_by     uuid,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

-- Qayta ishga tushirilganda yetishmayotgan ustunlar
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS parent_id  uuid REFERENCES public.org_folders(id) ON DELETE CASCADE;
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS icon       text;
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 0;
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS created_by uuid;
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- CHECK'lar. Idempotent: avval DROP, keyin ADD.
ALTER TABLE public.org_folders DROP CONSTRAINT IF EXISTS org_folders_name_chk;
ALTER TABLE public.org_folders ADD  CONSTRAINT org_folders_name_chk
  CHECK (char_length(btrim(name)) BETWEEN 1 AND 120);

-- O'ziga o'zi ota bo'lmasin (1 bosqichli qorong'i holat — chuqurrog'ini trigger tutadi)
ALTER TABLE public.org_folders DROP CONSTRAINT IF EXISTS org_folders_self_parent_chk;
ALTER TABLE public.org_folders ADD  CONSTRAINT org_folders_self_parent_chk
  CHECK (parent_id IS NULL OR parent_id <> id);

CREATE INDEX IF NOT EXISTS org_folders_ws_parent_idx ON public.org_folders (workspace_id, parent_id, sort_order);

COMMENT ON TABLE public.org_folders IS
  'Org Schema papka daraxti. Papkalar foydalanuvchi tomonidan noldan yaratiladi; TaskFix departments bilan bog''lanish YO''Q. Daraxt ayni paytda bo''ysunish sxemasi.';


-- ════════════════════════════════════════════════════════════════════════════
-- 3) org_people — sxemadagi hodimlar
-- ════════════════════════════════════════════════════════════════════════════
-- Hodim = workspace a'zosi (user_id), bitta papkada turadi (folder_id).
-- ⚠️ `manager_id` YO'Q: kim kimga bo'ysunishi PAPKA JOYLASHUVIDAN kelib
--    chiqadi (5b-bo'limga qarang). Shu sababli bo'ysunish papka daraxtidan
--    hech qachon ayri tushmaydi va sikl bo'lishi mumkin emas.
-- folder_id NULL = papkasiz (hech kimga bo'ysunmaydi, ilovada alohida
--    "Papkasiz xodimlar" bo'limida ko'rinadi).
CREATE TABLE IF NOT EXISTS public.org_people (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id  uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL,
  folder_id     uuid REFERENCES public.org_folders(id) ON DELETE SET NULL,
  title         text,                                -- ko'rsatiladigan lavozim (bo'sh → employee_details dan olinadi)
  sort_order    integer NOT NULL DEFAULT 0,
  created_by    uuid,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.org_people ADD COLUMN IF NOT EXISTS folder_id  uuid REFERENCES public.org_folders(id) ON DELETE SET NULL;
ALTER TABLE public.org_people ADD COLUMN IF NOT EXISTS title      text;
ALTER TABLE public.org_people ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 0;
ALTER TABLE public.org_people ADD COLUMN IF NOT EXISTS created_by uuid;
ALTER TABLE public.org_people ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.org_people ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- ⚠️ 2026-08-06: "bir odam sxemada BIR MARTA" cheklovi OLIB TASHLANDI.
--    Haqiqiy hayotda bir xodim bir necha o'rinda bo'lishi mumkin (ikki
--    bo'limda, yoki bir necha rolda). Endi bir user_id bir necha org_people
--    qatori bo'la oladi — har biri ALOHIDA O'RIN.
DROP INDEX IF EXISTS public.org_people_ws_user_uniq;

-- Lekin BIR XIL O'RINDA ikki marta bo'lmasin (tasodifiy dublikat).
-- "O'rin" = ota tugun: papka ichida / hodim ostida / ildizda.
-- ⚠️ Uchta ALOHIDA qisman indeks kerak, chunki NULL ustunli oddiy UNIQUE
--    indeks ishlamaydi: Postgres'da NULL != NULL, ya'ni folder_id NULL
--    bo'lgan qatorlar cheksiz takrorlanardi.
CREATE UNIQUE INDEX IF NOT EXISTS org_people_uniq_in_folder
  ON public.org_people (workspace_id, user_id, folder_id)
  WHERE folder_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS org_people_uniq_under_person
  ON public.org_people (workspace_id, user_id, parent_person_id)
  WHERE parent_person_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS org_people_uniq_root
  ON public.org_people (workspace_id, user_id)
  WHERE folder_id IS NULL AND parent_person_id IS NULL;

CREATE INDEX IF NOT EXISTS org_people_ws_folder_idx ON public.org_people (workspace_id, folder_id, sort_order);
CREATE INDEX IF NOT EXISTS org_people_ws_user_idx   ON public.org_people (workspace_id, user_id);

COMMENT ON TABLE public.org_people IS
  'Org Schema O''RINLARI (lavozim/joy). Bitta xodim bir necha o''rinda bo''la oladi — har qatori alohida o''rin. folder_id / parent_person_id → o''sha o''rin qayerda turishi. Bo''ysunish saqlanmaydi, daraxtdan hisoblanadi.';


-- ════════════════════════════════════════════════════════════════════════════
-- 3b) HODIM OSTIDA DAVOM ETISH (2026-08-06)
-- ════════════════════════════════════════════════════════════════════════════
-- Endi ISTALGAN tugun pastga davom etadi: hodim ostiga ham papka, ham hodim
-- qo'yiladi. Shuning uchun har ikkala jadvalda "otam kim?" ikki xil bo'lishi
-- mumkin:
--   org_folders : parent_id (papka ostida)  YOKI  parent_person_id (hodim ostida)
--   org_people  : folder_id (papkada)       YOKI  parent_person_id (hodim ostida)
--
-- ⚠️ Nega `parent_kind text` + bitta `parent_id` EMAS? Chunki u holda FK
--    yozib bo'lmaydi — o'chirilgan tugun "osilib" qolardi (eski oc*/
--    org_containers dagi muammo). Ikki alohida FK ustuni bilan baza o'zi
--    butunligini saqlaydi.
--
-- ⚠️ ON DELETE SET NULL (CASCADE emas): rahbar sxemadan olib tashlansa
--    uning ostidagi butun shox O'CHIB KETMASIN — ular ildizga ko'chadi.
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS parent_person_id uuid REFERENCES public.org_people(id) ON DELETE SET NULL;
ALTER TABLE public.org_people  ADD COLUMN IF NOT EXISTS parent_person_id uuid REFERENCES public.org_people(id) ON DELETE SET NULL;

-- Bir vaqtda IKKI ota bo'lmasin (aks holda daraxt ikkilanardi)
ALTER TABLE public.org_folders DROP CONSTRAINT IF EXISTS org_folders_one_parent_chk;
ALTER TABLE public.org_folders ADD  CONSTRAINT org_folders_one_parent_chk
  CHECK (parent_id IS NULL OR parent_person_id IS NULL);

ALTER TABLE public.org_people DROP CONSTRAINT IF EXISTS org_people_one_parent_chk;
ALTER TABLE public.org_people ADD  CONSTRAINT org_people_one_parent_chk
  CHECK (folder_id IS NULL OR parent_person_id IS NULL);

ALTER TABLE public.org_people DROP CONSTRAINT IF EXISTS org_people_self_parent_chk;
ALTER TABLE public.org_people ADD  CONSTRAINT org_people_self_parent_chk
  CHECK (parent_person_id IS NULL OR parent_person_id <> id);

CREATE INDEX IF NOT EXISTS org_folders_pp_idx ON public.org_folders (workspace_id, parent_person_id);
CREATE INDEX IF NOT EXISTS org_people_pp_idx  ON public.org_people  (workspace_id, parent_person_id);

COMMENT ON COLUMN public.org_folders.parent_person_id IS 'Papka SHU HODIM ostida turadi (parent_id bilan bir vaqtda to''ldirilmaydi).';
COMMENT ON COLUMN public.org_people.parent_person_id  IS 'Hodim SHU HODIM ostida turadi, ya''ni unga bo''ysunadi (folder_id bilan bir vaqtda to''ldirilmaydi).';


-- ════════════════════════════════════════════════════════════════════════════
-- 4) Triggerlar — updated_at + SIKL taqiqi
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.org_touch()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS hr_settings_touch_trg ON public.hr_settings;
CREATE TRIGGER hr_settings_touch_trg BEFORE UPDATE ON public.hr_settings
  FOR EACH ROW EXECUTE FUNCTION public.org_touch();

DROP TRIGGER IF EXISTS org_folders_touch_trg ON public.org_folders;
CREATE TRIGGER org_folders_touch_trg BEFORE UPDATE ON public.org_folders
  FOR EACH ROW EXECUTE FUNCTION public.org_touch();

DROP TRIGGER IF EXISTS org_people_touch_trg ON public.org_people;
CREATE TRIGGER org_people_touch_trg BEFORE UPDATE ON public.org_people
  FOR EACH ROW EXECUTE FUNCTION public.org_touch();

-- ── SIKL QO'RIQCHISI (ikki jadval bo'ylab) ─────────────────────────────────
-- Daraxt endi org_folders + org_people bo'ylab yoyilgan: papka hodim ostida,
-- hodim papka ichida yoki boshqa hodim ostida bo'lishi mumkin. Demak sikl ham
-- ARALASH bo'lishi mumkin (papka → hodim → papka → …), va uni bitta jadvalni
-- kuzatib tutib bo'lmaydi.
--
-- ⚠️ Bu YAGONA haqiqiy himoya: sikl paydo bo'lsa daraxt chizuvchi rekursiya
--    cheksiz aylanadi. Mijozda ham tekshiruv bor, lekin unga ishonib bo'lmaydi.
--
-- Berilgan (kind,id) tugunning YANGI otasidan yuqoriga yuriladi; yo'lda
-- o'zimiz uchrasak — sikl.
CREATE OR REPLACE FUNCTION public.org_check_ancestor(
  p_kind text, p_id uuid, p_pkind text, p_pid uuid, p_ws uuid
) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_kind  text := p_pkind;
  v_id    uuid := p_pid;
  v_ws    uuid;
  v_next_folder uuid;
  v_next_person uuid;
  v_steps int := 0;
BEGIN
  WHILE v_id IS NOT NULL LOOP
    IF v_kind = p_kind AND v_id = p_id THEN
      RAISE EXCEPTION 'Tugunni o''zining ichiga ko''chirib bo''lmaydi (sikl)';
    END IF;

    v_steps := v_steps + 1;
    IF v_steps > 200 THEN
      RAISE EXCEPTION 'Daraxt juda chuqur yoki siklda';
    END IF;

    IF v_kind = 'folder' THEN
      SELECT workspace_id, parent_id, parent_person_id
        INTO v_ws, v_next_folder, v_next_person
        FROM public.org_folders WHERE id = v_id;
    ELSE
      SELECT workspace_id, folder_id, parent_person_id
        INTO v_ws, v_next_folder, v_next_person
        FROM public.org_people WHERE id = v_id;
    END IF;

    IF v_ws IS NULL THEN
      RAISE EXCEPTION 'Ota tugun topilmadi';
    END IF;
    IF v_ws <> p_ws THEN
      RAISE EXCEPTION 'Ota tugun boshqa workspace''da';
    END IF;

    IF v_next_person IS NOT NULL THEN
      v_kind := 'person'; v_id := v_next_person;
    ELSIF v_next_folder IS NOT NULL THEN
      v_kind := 'folder'; v_id := v_next_folder;
    ELSE
      v_id := NULL;   -- ildizga yetdik
    END IF;
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.org_folders_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.parent_id IS NOT NULL THEN
    PERFORM public.org_check_ancestor('folder', NEW.id, 'folder', NEW.parent_id, NEW.workspace_id);
  ELSIF NEW.parent_person_id IS NOT NULL THEN
    PERFORM public.org_check_ancestor('folder', NEW.id, 'person', NEW.parent_person_id, NEW.workspace_id);
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS org_folders_guard_trg ON public.org_folders;
CREATE TRIGGER org_folders_guard_trg
  BEFORE INSERT OR UPDATE OF parent_id, parent_person_id, workspace_id ON public.org_folders
  FOR EACH ROW EXECUTE FUNCTION public.org_folders_guard();

CREATE OR REPLACE FUNCTION public.org_people_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.parent_person_id IS NOT NULL THEN
    PERFORM public.org_check_ancestor('person', NEW.id, 'person', NEW.parent_person_id, NEW.workspace_id);
  ELSIF NEW.folder_id IS NOT NULL THEN
    PERFORM public.org_check_ancestor('person', NEW.id, 'folder', NEW.folder_id, NEW.workspace_id);
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS org_people_guard_trg ON public.org_people;
CREATE TRIGGER org_people_guard_trg
  BEFORE INSERT OR UPDATE OF folder_id, parent_person_id, workspace_id ON public.org_people
  FOR EACH ROW EXECUTE FUNCTION public.org_people_guard();


-- ════════════════════════════════════════════════════════════════════════════
-- 5) `departments` bilan AVTOMATIK BOG'LANISH — OLIB TASHLANDI (2026-08-06)
-- ════════════════════════════════════════════════════════════════════════════
-- Avval bu yerda ikkita narsa bor edi:
--   (a) org_sync_departments(ws) — TaskFix'dagi mavjud bo'limlarni Org Schema
--       daraxtiga avtomat papka qilib tortadigan RPC;
--   (b) org_dept_rename_sync — `departments` dagi nom o'zgarsa papka nomini
--       ergashtiradigan trigger.
--
-- QAROR: Org Schema BO'SH boshlanadi — papkalarni foydalanuvchi noldan o'zi
-- yaratadi. Shu sababli ikkalasi ham kerak emas va OLIB TASHLANDI.
--
-- ⚠️ NATIJA: bu skript endi mavjud `public.departments` jadvaliga UMUMAN
--    tegmaydi — na o'qiydi, na yozadi, na trigger osadi. FK ham qolmaydi
--    (org_folders.department_id ustuni 5b da olib tashlanadi).
--
-- Quyidagi DROP'lar — skriptning AVVALGI versiyasi allaqachon ishga
-- tushirilgan bo'lsa tozalash uchun. Bo'lmasa jimgina o'tadi.
DROP TRIGGER  IF EXISTS org_dept_rename_sync_trg ON public.departments;
DROP FUNCTION IF EXISTS public.org_dept_rename_sync();
DROP FUNCTION IF EXISTS public.org_sync_departments(uuid);

-- ⚠️ TOZALASH: avvalgi versiya AVTOMAT yaratgan bo'lim papkalari
--    (kind='department') SHU YERDA O'CHIRILADI — foydalanuvchi so'radi
--    ("Org Schema toza boshlansin"). Ichidagi papkalar CASCADE bilan ketadi,
--    hodimlar esa papkasiz qoladi (ON DELETE SET NULL) — ilovada "Papkasiz
--    xodimlar" bo'limida ko'rinadi, YO'QOLMAYDI.
DO $$
DECLARE v_cnt int := 0;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='org_folders' AND column_name='kind') THEN
    DELETE FROM public.org_folders WHERE kind = 'department';
    GET DIAGNOSTICS v_cnt = ROW_COUNT;
    RAISE NOTICE 'Avtomat yaratilgan bo''lim papkalari o''chirildi: % ta', v_cnt;
  END IF;
END $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 5b) MODEL SODDALASHDI — keraksiz ustunlar olib tashlanadi (2026-08-06)
-- ════════════════════════════════════════════════════════════════════════════
-- PAPKA DARAXTI = BO'YSUNISH SXEMASI. Ya'ni:
--   • bitta papkadagi hodimlar TENG (o'zaro bo'ysunish yo'q);
--   • hammasi YUQORIDAGI papkadagi hodimlarga bo'ysunadi;
--   • yuqoridagi papka bo'sh bo'lsa — undan ham yuqoriga qaraladi;
--   • boshqa ildiz (alohida daraxt) bilan bog'lanish YO'Q.
--
-- Bu ma'lumot papka joylashuvidan HISOBLANADI, saqlanmaydi. Shuning uchun:
--   • org_people.manager_id  — KERAK EMAS (va saqlansa, papka joylashuvi
--                              bilan ziddiyatga tushishi mumkin edi);
--   • org_people.is_head     — hech qachon ishlatilmadi;
--   • org_folders.kind /     — `departments` bilan avtomatik bog'lanish
--     org_folders.department_id  olib tashlangach ma'nosiz qoldi.
--
-- ⚠️ DROP COLUMN — ma'lumot yo'qotadi, lekin bu ustunlarda saqlanadigan
--    ma'noli ma'lumot YO'Q: manager_id endi hisoblanadi, qolgan uchtasini
--    hech kim to'ldirmagan. Idempotent (IF EXISTS).
ALTER TABLE public.org_people  DROP COLUMN IF EXISTS manager_id;
ALTER TABLE public.org_people  DROP COLUMN IF EXISTS is_head;
ALTER TABLE public.org_folders DROP COLUMN IF EXISTS kind;
ALTER TABLE public.org_folders DROP COLUMN IF EXISTS department_id;

-- Ular bilan bog'liq cheklovlar/indekslar ham ketsin
ALTER TABLE public.org_people  DROP CONSTRAINT IF EXISTS org_people_self_mgr_chk;
ALTER TABLE public.org_folders DROP CONSTRAINT IF EXISTS org_folders_kind_chk;
ALTER TABLE public.org_folders DROP CONSTRAINT IF EXISTS org_folders_dept_link_chk;
DROP INDEX IF EXISTS public.org_folders_dept_uniq;
DROP INDEX IF EXISTS public.org_people_ws_mgr_idx;


-- ════════════════════════════════════════════════════════════════════════════
-- 6) RLS
-- ════════════════════════════════════════════════════════════════════════════
-- KO'RISH  — workspace'ning har qanday a'zosi (sxema hamma uchun ochiq).
-- YOZISH   — faqat owner/admin (is_ws_manager).
-- ⚠️ workspace_members inline subquery YO'Q (42P17).
-- ⚠️ auth.uid() (SELECT ...) ichida — har qator uchun qayta hisoblanmasin
--    (TASKFIX_SCALE.sql dagi bilan bir xil naqsh).

ALTER TABLE public.hr_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "hr_settings_select" ON public.hr_settings;
CREATE POLICY "hr_settings_select" ON public.hr_settings FOR SELECT TO authenticated
  USING ( is_ws_member(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS "hr_settings_insert" ON public.hr_settings;
CREATE POLICY "hr_settings_insert" ON public.hr_settings FOR INSERT TO authenticated
  WITH CHECK ( is_ws_manager(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS "hr_settings_update" ON public.hr_settings;
CREATE POLICY "hr_settings_update" ON public.hr_settings FOR UPDATE TO authenticated
  USING      ( is_ws_manager(workspace_id, (SELECT auth.uid())) )
  WITH CHECK ( is_ws_manager(workspace_id, (SELECT auth.uid())) );


ALTER TABLE public.org_folders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "org_folders_select" ON public.org_folders;
CREATE POLICY "org_folders_select" ON public.org_folders FOR SELECT TO authenticated
  USING ( is_ws_member(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS "org_folders_insert" ON public.org_folders;
CREATE POLICY "org_folders_insert" ON public.org_folders FOR INSERT TO authenticated
  WITH CHECK ( is_ws_manager(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS "org_folders_update" ON public.org_folders;
CREATE POLICY "org_folders_update" ON public.org_folders FOR UPDATE TO authenticated
  USING      ( is_ws_manager(workspace_id, (SELECT auth.uid())) )
  WITH CHECK ( is_ws_manager(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS "org_folders_delete" ON public.org_folders;
CREATE POLICY "org_folders_delete" ON public.org_folders FOR DELETE TO authenticated
  USING ( is_ws_manager(workspace_id, (SELECT auth.uid())) );


ALTER TABLE public.org_people ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "org_people_select" ON public.org_people;
CREATE POLICY "org_people_select" ON public.org_people FOR SELECT TO authenticated
  USING ( is_ws_member(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS "org_people_insert" ON public.org_people;
CREATE POLICY "org_people_insert" ON public.org_people FOR INSERT TO authenticated
  WITH CHECK ( is_ws_manager(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS "org_people_update" ON public.org_people;
CREATE POLICY "org_people_update" ON public.org_people FOR UPDATE TO authenticated
  USING      ( is_ws_manager(workspace_id, (SELECT auth.uid())) )
  WITH CHECK ( is_ws_manager(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS "org_people_delete" ON public.org_people;
CREATE POLICY "org_people_delete" ON public.org_people FOR DELETE TO authenticated
  USING ( is_ws_manager(workspace_id, (SELECT auth.uid())) );


-- ════════════════════════════════════════════════════════════════════════════
-- 7) TEKSHIRUV — jimgina o'tmasin
-- ════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE v_cnt int; t text;
BEGIN
  -- 7.1 Jadvallar bor va RLS yoqilgan
  FOREACH t IN ARRAY ARRAY['hr_settings','org_folders','org_people'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = 'public' AND c.relname = t) THEN
      RAISE EXCEPTION '% jadvali yaratilmadi', t;
    END IF;
    SELECT count(*) INTO v_cnt FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = t AND c.relrowsecurity;
    IF v_cnt = 0 THEN RAISE EXCEPTION '% da RLS yoqilmadi', t; END IF;
  END LOOP;

  -- 7.2 Policy soni
  SELECT count(*) INTO v_cnt FROM pg_policies WHERE schemaname='public' AND tablename='hr_settings';
  IF v_cnt < 3 THEN RAISE EXCEPTION 'hr_settings policy''lari to''liq emas (% ta, 3 kutilgan)', v_cnt; END IF;
  SELECT count(*) INTO v_cnt FROM pg_policies WHERE schemaname='public' AND tablename='org_folders';
  IF v_cnt < 4 THEN RAISE EXCEPTION 'org_folders policy''lari to''liq emas (% ta, 4 kutilgan)', v_cnt; END IF;
  SELECT count(*) INTO v_cnt FROM pg_policies WHERE schemaname='public' AND tablename='org_people';
  IF v_cnt < 4 THEN RAISE EXCEPTION 'org_people policy''lari to''liq emas (% ta, 4 kutilgan)', v_cnt; END IF;

  -- 7.3 Sikl qo'riqchilari — ikkala jadvalda ham bo'lishi SHART
  -- (daraxt endi org_folders + org_people bo'ylab yoyilgan → aralash sikl
  --  mumkin, shuning uchun ikkovi ham org_check_ancestor() ni chaqiradi)
  FOREACH t IN ARRAY ARRAY['org_folders_guard_trg','org_people_guard_trg'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = t AND NOT tgisinternal) THEN
      RAISE EXCEPTION '% yaratilmadi', t;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='org_check_ancestor') THEN
    RAISE EXCEPTION 'org_check_ancestor() yaratilmadi';
  END IF;

  -- 7.3b Yangi "hodim ostida" ustunlari
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='org_folders' AND column_name='parent_person_id') THEN
    RAISE EXCEPTION 'org_folders.parent_person_id yaratilmadi';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='org_people' AND column_name='parent_person_id') THEN
    RAISE EXCEPTION 'org_people.parent_person_id yaratilmadi';
  END IF;

  -- 7.4 Avtomatik bog'lanish HAQIQATAN yo'qmi? (teskari tekshiruv)
  -- Skriptning avvalgi versiyasi ishga tushirilgan bo'lsa, yuqoridagi DROP'lar
  -- ularni tozalagan bo'lishi SHART — aks holda bo'limlar yana avtomat
  -- tortilib, "bo'sh boshlansin" talabi jimgina buzilardi.
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname='public' AND p.proname='org_sync_departments') THEN
    RAISE EXCEPTION 'org_sync_departments() hali ham bor — o''chirilmadi!';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'org_dept_rename_sync_trg' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'org_dept_rename_sync_trg hali ham bor — o''chirilmadi!';
  END IF;

  -- 7.4b Model soddaligini tasdiqlaymiz: bo'ysunish/bo'lim ustunlari
  -- QOLMAGAN bo'lishi shart, aks holda ikki xil manba paydo bo'lardi.
  -- (manager_id — eski qo'lda tanlanadigan rahbar; parent_person_id uni
  --  almashtirdi va bo'ysunish endi daraxtdan hisoblanadi)
  FOREACH t IN ARRAY ARRAY['manager_id','is_head'] LOOP
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='org_people' AND column_name=t) THEN
      RAISE EXCEPTION 'org_people.% hali ham bor — olib tashlanmadi!', t;
    END IF;
  END LOOP;
  FOREACH t IN ARRAY ARRAY['kind','department_id'] LOOP
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='org_folders' AND column_name=t) THEN
      RAISE EXCEPTION 'org_folders.% hali ham bor — olib tashlanmadi!', t;
    END IF;
  END LOOP;

  -- 7.4c "Bir odam bir marta" cheklovi OLIB TASHLANGANMI?
  -- (bir xodim bir necha o'rinda bo'la olishi SHART)
  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'org_people_ws_user_uniq') THEN
    RAISE EXCEPTION 'org_people_ws_user_uniq hali ham bor — xodim bir necha o''rinda bo''la olmaydi!';
  END IF;
  FOREACH t IN ARRAY ARRAY['org_people_uniq_in_folder','org_people_uniq_under_person','org_people_uniq_root'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = t) THEN
      RAISE EXCEPTION '% indeksi yaratilmadi (bir o''rinda dublikat oldini oladi)', t;
    END IF;
  END LOOP;

  -- 7.5 ESKI TIZIM BUTUNMI? (bu fayl hech nimani buzmaganiga ishonch)
  FOREACH t IN ARRAY ARRAY['tasks','projects','departments','workspace_members'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = 'public' AND c.relname = t) THEN
      RAISE EXCEPTION 'Eski jadval % yo''qolgan — TO''XTANG!', t;
    END IF;
  END LOOP;

  -- 7.5b `departments` ga TEGILMAGANINI tasdiqlaymiz: bu skript o'rnatgan
  -- hech qanday trigger ham, FK ham u yerda qolmasligi kerak.
  IF EXISTS (
    SELECT 1 FROM pg_trigger tg
      JOIN pg_class c ON c.oid = tg.tgrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'departments'
       AND NOT tg.tgisinternal AND tg.tgname LIKE 'org_%'
  ) THEN
    RAISE EXCEPTION 'departments da org_* trigger qolib ketdi';
  END IF;
END $$;

-- ── 7.6 Sikl triggerlari HAQIQATAN ishlaydimi? ─────────────────────────────
-- Tirik ma'lumot ustida sinaymiz, lekin test qatorlari SAQLANMAYDI:
-- ichki subtranzaksiya ataylab RAISE bilan qaytariladi.
-- Ikki holat: (a) sof papka sikli, (b) ARALASH sikl (papka → hodim → papka).
DO $$
DECLARE
  v_ws uuid; v_u uuid; v_a uuid; v_b uuid; v_p uuid;
  v_ok1 boolean := false; v_ok2 boolean := false;
BEGIN
  SELECT id INTO v_ws FROM public.workspaces LIMIT 1;
  IF v_ws IS NULL THEN
    RAISE NOTICE 'Workspace yo''q — sikl testi o''tkazib yuborildi';
    RETURN;
  END IF;
  SELECT user_id INTO v_u FROM public.workspace_members WHERE workspace_id = v_ws LIMIT 1;

  BEGIN
    INSERT INTO public.org_folders (workspace_id, name) VALUES (v_ws, '__test_a__') RETURNING id INTO v_a;
    INSERT INTO public.org_folders (workspace_id, name, parent_id) VALUES (v_ws, '__test_b__', v_a) RETURNING id INTO v_b;

    -- (a) A → B → A
    BEGIN
      UPDATE public.org_folders SET parent_id = v_b WHERE id = v_a;
    EXCEPTION WHEN others THEN v_ok1 := true;
    END;
    IF NOT v_ok1 THEN
      RAISE EXCEPTION 'PAPKA SIKLI TRIGGERI ISHLAMADI — org_folders_guard tekshiring!';
    END IF;

    -- (b) aralash: papka A ichida hodim P, keyin A ni P ostiga ko'chirmoqchi bo'lamiz
    IF v_u IS NOT NULL THEN
      INSERT INTO public.org_people (workspace_id, user_id, folder_id)
      VALUES (v_ws, v_u, v_a) RETURNING id INTO v_p;
      BEGIN
        UPDATE public.org_folders SET parent_id = NULL, parent_person_id = v_p WHERE id = v_a;
      EXCEPTION WHEN others THEN v_ok2 := true;
      END;
      IF NOT v_ok2 THEN
        RAISE EXCEPTION 'ARALASH SIKL TRIGGERI ISHLAMADI — org_check_ancestor tekshiring!';
      END IF;
    ELSE
      RAISE NOTICE 'Workspace a''zosi yo''q — aralash sikl testi o''tkazib yuborildi';
    END IF;

    RAISE EXCEPTION '__rollback_test__';   -- test qatorlarini qaytaramiz
  EXCEPTION WHEN others THEN
    IF SQLERRM <> '__rollback_test__' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'Sikl triggerlari OK (test qatorlari qaytarildi)';
END $$;

COMMIT;

-- ============================================================================
-- KEYIN NIMA BO'LADI
--   • HR Service DEFAULT O'CHIQ. Admin: "Qo'shimcha service" → HR Service →
--     "Yoqish". Shundan keyin chap menyuda "HR → Org Schema" paydo bo'ladi.
--   • Org Schema birinchi ochilganda BO'SH bo'ladi. Papkalarni "+ Papka"
--     bilan o'zingiz yaratasiz, xodimlarni "+ Xodim" bilan qo'shasiz.
--     TaskFix'dagi mavjud bo'limlar bu yerga AVTOMAT tortilmaydi.
--   • Eski "Jamoa → 🏢 Tashkilot" ko'rinishi (org_containers) ilovada
--     yashirilgan, lekin MA'LUMOTI JOYIDA — hech narsa o'chirilmadi.
--
-- QAYTARISH (kerak bo'lsa):
--   DROP TABLE IF EXISTS public.org_people  CASCADE;
--   DROP TABLE IF EXISTS public.org_folders CASCADE;
--   DROP TABLE IF EXISTS public.hr_settings CASCADE;
--   DROP FUNCTION IF EXISTS public.org_folders_guard() CASCADE;
--   DROP FUNCTION IF EXISTS public.org_people_guard()  CASCADE;
--   DROP FUNCTION IF EXISTS public.org_touch() CASCADE;
-- ============================================================================
