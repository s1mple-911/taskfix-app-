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
--                      Mavjud `departments` bu daraxtga papka bo'lib kiradi
--                      (kind='department' + department_id).
--   3) org_people    — hodim daraxti. Hodim bitta papkada turadi (folder_id)
--                      va o'zidan TEPADAGI hodimga bo'ysunadi (manager_id).
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
-- kind='folder'      → oddiy papka (foydalanuvchi yaratadi)
-- kind='department'  → mavjud `departments` qatorining daraxtdagi aksi.
--                      Nomi departments.name dan o'qiladi (bu yerda ham
--                      nusxa saqlanadi — bo'lim o'chsa CASCADE bilan ketadi).
CREATE TABLE IF NOT EXISTS public.org_folders (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id   uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  parent_id      uuid REFERENCES public.org_folders(id) ON DELETE CASCADE,
  name           text NOT NULL,
  kind           text NOT NULL DEFAULT 'folder',
  department_id  uuid REFERENCES public.departments(id) ON DELETE CASCADE,
  icon           text,                              -- ixtiyoriy: ikonka nomi (ICON_PATHS kaliti)
  sort_order     integer NOT NULL DEFAULT 0,
  created_by     uuid,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

-- Qayta ishga tushirilganda yetishmayotgan ustunlar
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS parent_id     uuid REFERENCES public.org_folders(id) ON DELETE CASCADE;
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS kind          text NOT NULL DEFAULT 'folder';
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS department_id uuid REFERENCES public.departments(id) ON DELETE CASCADE;
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS icon          text;
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS sort_order    integer NOT NULL DEFAULT 0;
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS created_by    uuid;
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS created_at    timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS updated_at    timestamptz NOT NULL DEFAULT now();

-- CHECK'lar (TEXT + CHECK, ENUM emas). Idempotent: avval DROP, keyin ADD.
ALTER TABLE public.org_folders DROP CONSTRAINT IF EXISTS org_folders_kind_chk;
ALTER TABLE public.org_folders ADD  CONSTRAINT org_folders_kind_chk
  CHECK (kind IN ('folder','department'));

ALTER TABLE public.org_folders DROP CONSTRAINT IF EXISTS org_folders_name_chk;
ALTER TABLE public.org_folders ADD  CONSTRAINT org_folders_name_chk
  CHECK (char_length(btrim(name)) BETWEEN 1 AND 120);

-- kind='department' ⟺ department_id bor. Ikkisi doim birga.
ALTER TABLE public.org_folders DROP CONSTRAINT IF EXISTS org_folders_dept_link_chk;
ALTER TABLE public.org_folders ADD  CONSTRAINT org_folders_dept_link_chk
  CHECK ((kind = 'department') = (department_id IS NOT NULL));

-- O'ziga o'zi ota bo'lmasin (1 bosqichli qorong'i holat — chuqurrog'ini trigger tutadi)
ALTER TABLE public.org_folders DROP CONSTRAINT IF EXISTS org_folders_self_parent_chk;
ALTER TABLE public.org_folders ADD  CONSTRAINT org_folders_self_parent_chk
  CHECK (parent_id IS NULL OR parent_id <> id);

-- Bitta bo'lim = bitta papka (dublikat aks yaratilmasin)
CREATE UNIQUE INDEX IF NOT EXISTS org_folders_dept_uniq
  ON public.org_folders (workspace_id, department_id)
  WHERE department_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS org_folders_ws_parent_idx ON public.org_folders (workspace_id, parent_id, sort_order);

COMMENT ON TABLE public.org_folders IS
  'Org Schema papka daraxti. kind=department bo''lsa — mavjud departments qatorining daraxtdagi aksi (nomi shu yerdan ko''chiriladi).';


-- ════════════════════════════════════════════════════════════════════════════
-- 3) org_people — hodim daraxti (bo'ysunish)
-- ════════════════════════════════════════════════════════════════════════════
-- Hodim = workspace a'zosi (user_id). Bitta papkada turadi (folder_id) va
-- o'zidan TEPADAGI hodimga bo'ysunadi (manager_id → org_people.id).
-- manager_id NULL = ildiz (masalan direktor).
CREATE TABLE IF NOT EXISTS public.org_people (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id  uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL,
  folder_id     uuid REFERENCES public.org_folders(id) ON DELETE SET NULL,
  manager_id    uuid REFERENCES public.org_people(id)  ON DELETE SET NULL,
  title         text,                                -- ko'rsatiladigan lavozim (bo'sh → employee_details dan olinadi)
  is_head       boolean NOT NULL DEFAULT false,      -- shu papkaning rahbari
  sort_order    integer NOT NULL DEFAULT 0,
  created_by    uuid,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.org_people ADD COLUMN IF NOT EXISTS folder_id  uuid REFERENCES public.org_folders(id) ON DELETE SET NULL;
ALTER TABLE public.org_people ADD COLUMN IF NOT EXISTS manager_id uuid REFERENCES public.org_people(id)  ON DELETE SET NULL;
ALTER TABLE public.org_people ADD COLUMN IF NOT EXISTS title      text;
ALTER TABLE public.org_people ADD COLUMN IF NOT EXISTS is_head    boolean NOT NULL DEFAULT false;
ALTER TABLE public.org_people ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 0;
ALTER TABLE public.org_people ADD COLUMN IF NOT EXISTS created_by uuid;
ALTER TABLE public.org_people ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.org_people ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.org_people DROP CONSTRAINT IF EXISTS org_people_self_mgr_chk;
ALTER TABLE public.org_people ADD  CONSTRAINT org_people_self_mgr_chk
  CHECK (manager_id IS NULL OR manager_id <> id);

-- Bitta odam daraxtda BIR MARTA
CREATE UNIQUE INDEX IF NOT EXISTS org_people_ws_user_uniq
  ON public.org_people (workspace_id, user_id);

CREATE INDEX IF NOT EXISTS org_people_ws_folder_idx ON public.org_people (workspace_id, folder_id, sort_order);
CREATE INDEX IF NOT EXISTS org_people_ws_mgr_idx    ON public.org_people (workspace_id, manager_id);

COMMENT ON TABLE public.org_people IS
  'Org Schema hodim daraxti. manager_id → o''zidan tepadagi org_people qatori (NULL = ildiz). folder_id → qaysi papkada turishi.';


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

-- ── Papka sikli: A → B → A bo'lmasin ────────────────────────────────────────
-- ⚠️ Mijoz tomonda ham tekshiruv bor, lekin YAGONA HAQIQIY himoya shu yerda:
--    sikl paydo bo'lsa daraxt chizuvchi rekursiya cheksiz aylanadi.
CREATE OR REPLACE FUNCTION public.org_folders_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_cur   uuid;
  v_ws    uuid;
  v_steps int := 0;
BEGIN
  IF NEW.parent_id IS NULL THEN RETURN NEW; END IF;

  -- Ota boshqa workspace'da bo'lmasin
  SELECT workspace_id INTO v_ws FROM public.org_folders WHERE id = NEW.parent_id;
  IF v_ws IS NULL THEN
    RAISE EXCEPTION 'Ota papka topilmadi';
  END IF;
  IF v_ws <> NEW.workspace_id THEN
    RAISE EXCEPTION 'Ota papka boshqa workspace''da';
  END IF;

  -- Yuqoriga yuramiz: yo'lda o'zimiz uchrasak — sikl
  v_cur := NEW.parent_id;
  WHILE v_cur IS NOT NULL LOOP
    IF v_cur = NEW.id THEN
      RAISE EXCEPTION 'Papkani o''zining ichiga ko''chirib bo''lmaydi (sikl)';
    END IF;
    v_steps := v_steps + 1;
    IF v_steps > 100 THEN
      RAISE EXCEPTION 'Papka daraxti juda chuqur yoki siklda';
    END IF;
    SELECT parent_id INTO v_cur FROM public.org_folders WHERE id = v_cur;
  END LOOP;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS org_folders_guard_trg ON public.org_folders;
CREATE TRIGGER org_folders_guard_trg
  BEFORE INSERT OR UPDATE OF parent_id, workspace_id ON public.org_folders
  FOR EACH ROW EXECUTE FUNCTION public.org_folders_guard();

-- ── Bo'ysunish sikli: A boshlig'i B, B boshlig'i A — bo'lmasin ──────────────
CREATE OR REPLACE FUNCTION public.org_people_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_cur   uuid;
  v_ws    uuid;
  v_steps int := 0;
BEGIN
  IF NEW.manager_id IS NULL THEN RETURN NEW; END IF;

  SELECT workspace_id INTO v_ws FROM public.org_people WHERE id = NEW.manager_id;
  IF v_ws IS NULL THEN
    RAISE EXCEPTION 'Rahbar topilmadi';
  END IF;
  IF v_ws <> NEW.workspace_id THEN
    RAISE EXCEPTION 'Rahbar boshqa workspace''da';
  END IF;

  v_cur := NEW.manager_id;
  WHILE v_cur IS NOT NULL LOOP
    IF v_cur = NEW.id THEN
      RAISE EXCEPTION 'Xodimni o''ziga (yoki o''z qo''l ostidagiga) bo''ysundirib bo''lmaydi (sikl)';
    END IF;
    v_steps := v_steps + 1;
    IF v_steps > 100 THEN
      RAISE EXCEPTION 'Bo''ysunish zanjiri juda uzun yoki siklda';
    END IF;
    SELECT manager_id INTO v_cur FROM public.org_people WHERE id = v_cur;
  END LOOP;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS org_people_guard_trg ON public.org_people;
CREATE TRIGGER org_people_guard_trg
  BEFORE INSERT OR UPDATE OF manager_id, workspace_id ON public.org_people
  FOR EACH ROW EXECUTE FUNCTION public.org_people_guard();


-- ════════════════════════════════════════════════════════════════════════════
-- 5) Bo'lim nomi o'zgarsa — papka nomi ham o'zgarsin
-- ════════════════════════════════════════════════════════════════════════════
-- "Bo'limlar ro'yxati" da nom tahrirlansa, Org Schema'dagi aks eskirmasin.
-- SECURITY DEFINER: aks holda RLS tufayli sinxronlash JIMGINA ishlamay
-- qolishi mumkin (trigger chaqiruvchi rolida ishlaydi). Yozuv qat'iy
-- cheklangan: faqat shu bo'limga bog'langan papka nomi.
CREATE OR REPLACE FUNCTION public.org_dept_rename_sync()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.name IS DISTINCT FROM OLD.name THEN
    UPDATE public.org_folders SET name = NEW.name
     WHERE department_id = NEW.id AND name IS DISTINCT FROM NEW.name;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS org_dept_rename_sync_trg ON public.departments;
CREATE TRIGGER org_dept_rename_sync_trg
  AFTER UPDATE OF name ON public.departments
  FOR EACH ROW EXECUTE FUNCTION public.org_dept_rename_sync();


-- ════════════════════════════════════════════════════════════════════════════
-- 6) org_sync_departments() — mavjud bo'limlarni daraxtga tortadi
-- ════════════════════════════════════════════════════════════════════════════
-- Ilova Org Schema'ni ochganda shuni chaqiradi. Papkasi yo'q har bo'lim
-- uchun ildizda papka yaratadi. Mavjudlariga TEGMAYDI (ko'chirilgan bo'lsa
-- joyida qoladi). Yaratilgan qatorlar sonini qaytaradi.
--
-- SECURITY DEFINER — chunki oddiy a'zo ham sxemani KO'RA olishi kerak,
-- lekin unga org_folders'ga INSERT ruxsati yo'q. Ichkarida a'zolik
-- QAT'IY tekshiriladi (is_ws_member) — begona workspace'ga tegib bo'lmaydi.
CREATE OR REPLACE FUNCTION public.org_sync_departments(p_workspace_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_added integer := 0;
BEGIN
  IF p_workspace_id IS NULL THEN
    RAISE EXCEPTION 'workspace_id kerak';
  END IF;
  IF NOT public.is_ws_member(p_workspace_id, auth.uid()) THEN
    RAISE EXCEPTION 'Ruxsat yo''q';
  END IF;

  INSERT INTO public.org_folders (workspace_id, parent_id, name, kind, department_id, sort_order)
  SELECT d.workspace_id, NULL, d.name, 'department', d.id, COALESCE(d.sort_order, 0)
    FROM public.departments d
   WHERE d.workspace_id = p_workspace_id
     AND NOT EXISTS (
       SELECT 1 FROM public.org_folders f
        WHERE f.workspace_id = d.workspace_id AND f.department_id = d.id
     );

  GET DIAGNOSTICS v_added = ROW_COUNT;
  RETURN v_added;
END $$;

REVOKE ALL ON FUNCTION public.org_sync_departments(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.org_sync_departments(uuid) TO authenticated;

COMMENT ON FUNCTION public.org_sync_departments(uuid) IS
  'Papkasi yo''q bo''limlar uchun org_folders qatorini ildizda yaratadi. Mavjud papkalarga tegmaydi. Faqat workspace a''zosi chaqira oladi.';


-- ════════════════════════════════════════════════════════════════════════════
-- 7) RLS
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
-- 8) TEKSHIRUV — jimgina o'tmasin
-- ════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE v_cnt int; t text;
BEGIN
  -- 8.1 Jadvallar bor va RLS yoqilgan
  FOREACH t IN ARRAY ARRAY['hr_settings','org_folders','org_people'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = 'public' AND c.relname = t) THEN
      RAISE EXCEPTION '% jadvali yaratilmadi', t;
    END IF;
    SELECT count(*) INTO v_cnt FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = t AND c.relrowsecurity;
    IF v_cnt = 0 THEN RAISE EXCEPTION '% da RLS yoqilmadi', t; END IF;
  END LOOP;

  -- 8.2 Policy soni
  SELECT count(*) INTO v_cnt FROM pg_policies WHERE schemaname='public' AND tablename='hr_settings';
  IF v_cnt < 3 THEN RAISE EXCEPTION 'hr_settings policy''lari to''liq emas (% ta, 3 kutilgan)', v_cnt; END IF;
  SELECT count(*) INTO v_cnt FROM pg_policies WHERE schemaname='public' AND tablename='org_folders';
  IF v_cnt < 4 THEN RAISE EXCEPTION 'org_folders policy''lari to''liq emas (% ta, 4 kutilgan)', v_cnt; END IF;
  SELECT count(*) INTO v_cnt FROM pg_policies WHERE schemaname='public' AND tablename='org_people';
  IF v_cnt < 4 THEN RAISE EXCEPTION 'org_people policy''lari to''liq emas (% ta, 4 kutilgan)', v_cnt; END IF;

  -- 8.3 Triggerlar
  FOREACH t IN ARRAY ARRAY['org_folders_guard_trg','org_people_guard_trg','org_dept_rename_sync_trg'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = t AND NOT tgisinternal) THEN
      RAISE EXCEPTION '% trigger''i yaratilmadi', t;
    END IF;
  END LOOP;

  -- 8.4 RPC
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='org_sync_departments') THEN
    RAISE EXCEPTION 'org_sync_departments() yaratilmadi';
  END IF;

  -- 8.5 ESKI TIZIM BUTUNMI? (bu fayl hech nimani buzmaganiga ishonch)
  FOREACH t IN ARRAY ARRAY['tasks','projects','departments','workspace_members'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = 'public' AND c.relname = t) THEN
      RAISE EXCEPTION 'Eski jadval % yo''qolgan — TO''XTANG!', t;
    END IF;
  END LOOP;
END $$;

-- ── 8.6 Sikl triggeri HAQIQATAN ishlaydimi? ────────────────────────────────
-- Tirik ma'lumot ustida sinaymiz, lekin test qatorlari SAQLANMAYDI:
-- ichki subtranzaksiya ataylab RAISE bilan qaytariladi.
DO $$
DECLARE v_ws uuid; v_a uuid; v_b uuid; v_ok boolean := false;
BEGIN
  SELECT id INTO v_ws FROM public.workspaces LIMIT 1;
  IF v_ws IS NULL THEN
    RAISE NOTICE 'Workspace yo''q — sikl testi o''tkazib yuborildi';
    RETURN;
  END IF;

  BEGIN
    INSERT INTO public.org_folders (workspace_id, name) VALUES (v_ws, '__test_a__') RETURNING id INTO v_a;
    INSERT INTO public.org_folders (workspace_id, name, parent_id) VALUES (v_ws, '__test_b__', v_a) RETURNING id INTO v_b;

    BEGIN
      UPDATE public.org_folders SET parent_id = v_b WHERE id = v_a;   -- A → B → A = sikl
    EXCEPTION WHEN others THEN
      v_ok := true;   -- trigger to'sdi — shu kerak
    END;

    IF NOT v_ok THEN
      RAISE EXCEPTION 'SIKL TRIGGERI ISHLAMADI — org_folders_guard tekshiring!';
    END IF;

    RAISE EXCEPTION '__rollback_test__';   -- test qatorlarini qaytaramiz
  EXCEPTION WHEN others THEN
    IF SQLERRM <> '__rollback_test__' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'Sikl triggeri OK (test qatorlari qaytarildi)';
END $$;

COMMIT;

-- ============================================================================
-- KEYIN NIMA BO'LADI
--   • HR Service DEFAULT O'CHIQ. Admin: "Qo'shimcha service" → HR Service →
--     "Yoqish". Shundan keyin chap menyuda "HR → Org Schema" paydo bo'ladi.
--   • Org Schema birinchi ochilganda org_sync_departments() chaqiriladi va
--     mavjud bo'limlar ildizda papka bo'lib turadi. Keyin ularni bemalol
--     ko'chirish/ichiga papka qo'shish mumkin.
--   • Eski "Jamoa → 🏢 Tashkilot" ko'rinishi (org_containers) ilovada
--     yashirilgan, lekin MA'LUMOTI JOYIDA — hech narsa o'chirilmadi.
--
-- QAYTARISH (kerak bo'lsa):
--   DROP TABLE IF EXISTS public.org_people  CASCADE;
--   DROP TABLE IF EXISTS public.org_folders CASCADE;
--   DROP TABLE IF EXISTS public.hr_settings CASCADE;
--   DROP FUNCTION IF EXISTS public.org_sync_departments(uuid);
--   DROP FUNCTION IF EXISTS public.org_dept_rename_sync() CASCADE;
--   DROP FUNCTION IF EXISTS public.org_folders_guard() CASCADE;
--   DROP FUNCTION IF EXISTS public.org_people_guard()  CASCADE;
--   DROP FUNCTION IF EXISTS public.org_touch() CASCADE;
-- ============================================================================
