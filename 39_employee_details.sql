-- ============================================================
-- 39_employee_details.sql
-- Jamoa (HR) moduli — hodim kadrlar ma'lumoti.
--
-- MUHIM: fayl saqlanmaydi. Shartnoma, rasm, hujjatlar — faqat
--        Google Drive havolalari (matn URL).
--
-- Tartib: 35 → 38 → 39. Bu fayl 38_employee_links.sql dan KEYIN.
-- ============================================================

-- ── 0) Oldindan tekshiruv ───────────────────────────────────
-- is_ws_manager() 35-migratsiyada yaratilgan. Bo'lmasa, quyidagi
-- barcha RLS policy'lar xato beradi — shuning uchun darrov to'xtaymiz.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'is_ws_manager' AND n.nspname = 'public'
  ) THEN
    RAISE EXCEPTION 'is_ws_manager() topilmadi. Avval 35_fix_projects_rls.sql ni ishga tushiring, keyin 38 va 39 ni.';
  END IF;
END $$;

-- ── 1) Yordamchi: is_ws_member ──────────────────────────────
-- is_ws_manager owner/admin uchun. Oddiy a'zo ham lavozim/rol
-- NOMLARINI o'qiy olishi kerak (o'z sahifasida ko'rsatish uchun).
-- SECURITY DEFINER — RLS'ni chetlab o'tadi, shuning uchun
-- workspace_members policy'lariga murojaat qilmaydi → rekursiya YO'Q.
CREATE OR REPLACE FUNCTION is_ws_member(p_ws UUID, p_user UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM workspace_members
    WHERE workspace_id = p_ws AND user_id = p_user
  );
$$;

-- ── 2) Lavozimlar (localStorage'dan DB'ga ko'chiriladi) ─────
-- "positions" — umumiy nom. Agar u allaqachon BOSHQA sxema bilan mavjud
-- bo'lsa, CREATE TABLE IF NOT EXISTS jimgina o'tkazib yuboradi va keyingi
-- policy'lar tushunarsiz xato beradi. Shuning uchun oldindan tekshiramiz.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'positions') THEN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'positions' AND column_name = 'workspace_id')
    OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'positions' AND column_name = 'name') THEN
      RAISE EXCEPTION 'public.positions jadvali mavjud, lekin kutilgan ustunlar (workspace_id, name) yo''q. Qo''lda tekshiring — bu boshqa jadval bo''lishi mumkin.';
    END IF;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS positions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id  UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (workspace_id, name)
);

CREATE INDEX IF NOT EXISTS positions_ws_idx ON positions (workspace_id);

ALTER TABLE positions ENABLE ROW LEVEL SECURITY;

-- KO'RISH: workspace'ning har qanday a'zosi
DROP POLICY IF EXISTS "positions_select" ON positions;
CREATE POLICY "positions_select" ON positions FOR SELECT TO authenticated
  USING ( is_ws_member(workspace_id, auth.uid()) );

-- YOZISH: faqat owner/admin
DROP POLICY IF EXISTS "positions_write" ON positions;
CREATE POLICY "positions_write" ON positions FOR ALL TO authenticated
  USING ( is_ws_manager(workspace_id, auth.uid()) )
  WITH CHECK ( is_ws_manager(workspace_id, auth.uid()) );

-- ── 3) Hodim rollari (DEVELOPER, CEO, ROP …) ────────────────
-- DIQQAT: bu TaskFix'ning workspace_members.role (owner/admin/member)
-- dan BUTUNLAY ALOHIDA. U ruxsat beradi, bu — lavozim darajasi.
CREATE TABLE IF NOT EXISTS employee_roles (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id  UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  code          TEXT NOT NULL,   -- DEVELOPER, CEO, ROP — import shu bo'yicha moslashtiradi
  label         TEXT NOT NULL,   -- UI'da ko'rinadigan nom
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (workspace_id, code)
);

CREATE INDEX IF NOT EXISTS employee_roles_ws_idx ON employee_roles (workspace_id);

ALTER TABLE employee_roles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "emp_roles_select" ON employee_roles;
CREATE POLICY "emp_roles_select" ON employee_roles FOR SELECT TO authenticated
  USING ( is_ws_member(workspace_id, auth.uid()) );

DROP POLICY IF EXISTS "emp_roles_write" ON employee_roles;
CREATE POLICY "emp_roles_write" ON employee_roles FOR ALL TO authenticated
  USING ( is_ws_manager(workspace_id, auth.uid()) )
  WITH CHECK ( is_ws_manager(workspace_id, auth.uid()) );

-- ── 4) Hodim kadrlar ma'lumoti (1:1 workspace a'zosi bilan) ──
CREATE TABLE IF NOT EXISTS employee_details (
  workspace_id     UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id          UUID NOT NULL,

  first_name       TEXT,
  last_name        TEXT,
  photo_url        TEXT,          -- Google Drive havolasi (fayl EMAS)

  address          TEXT,
  no_address       BOOLEAN NOT NULL DEFAULT false,
  address_extra    TEXT,          -- "Qo'shimcha manzil"

  contract_url     TEXT,          -- Google Docs/Drive havolasi
  contract_start   DATE,
  contract_end     DATE,

  role_id          UUID REFERENCES employee_roles(id) ON DELETE SET NULL,
  position_id      UUID REFERENCES positions(id) ON DELETE SET NULL,

  work_type        TEXT,          -- offline | online | hybrid
  radius           INT,           -- metr

  schedule_type    TEXT,          -- weekly | monthly | flexible
  weekend_days     INT[] NOT NULL DEFAULT '{}',   -- 0=Yakshanba … 6=Shanba
  work_start       TIME,
  work_end         TIME,

  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (workspace_id, user_id)
);

-- TEXT + CHECK (ENUM EMAS — 30/32-migratsiyalardagi saboq).
-- NULL ruxsat: import paytida qiymat noma'lum bo'lishi mumkin.
ALTER TABLE employee_details DROP CONSTRAINT IF EXISTS employee_details_work_type_chk;
ALTER TABLE employee_details ADD CONSTRAINT employee_details_work_type_chk
  CHECK (work_type IS NULL OR work_type IN ('offline', 'online', 'hybrid'));

ALTER TABLE employee_details DROP CONSTRAINT IF EXISTS employee_details_schedule_type_chk;
ALTER TABLE employee_details ADD CONSTRAINT employee_details_schedule_type_chk
  CHECK (schedule_type IS NULL OR schedule_type IN ('weekly', 'monthly', 'flexible'));

ALTER TABLE employee_details ENABLE ROW LEVEL SECURITY;

-- KO'RISH: hodim — faqat o'zinikini; owner/admin — hammasini
DROP POLICY IF EXISTS "emp_details_select" ON employee_details;
CREATE POLICY "emp_details_select" ON employee_details FOR SELECT TO authenticated
  USING ( user_id = auth.uid() OR is_ws_manager(workspace_id, auth.uid()) );

-- YOZISH: faqat owner/admin (hodim o'zinikini ham TAHRIRLAY OLMAYDI)
DROP POLICY IF EXISTS "emp_details_write" ON employee_details;
CREATE POLICY "emp_details_write" ON employee_details FOR ALL TO authenticated
  USING ( is_ws_manager(workspace_id, auth.uid()) )
  WITH CHECK ( is_ws_manager(workspace_id, auth.uid()) );

-- updated_at avtomatik
CREATE OR REPLACE FUNCTION employee_details_touch()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS employee_details_touch_trg ON employee_details;
CREATE TRIGGER employee_details_touch_trg
  BEFORE UPDATE ON employee_details
  FOR EACH ROW EXECUTE FUNCTION employee_details_touch();

-- ── 5) Hodim filiallari (ko'p-ko'p) ─────────────────────────
-- Bo'limlar uchun alohida jadval KERAK EMAS — mavjud
-- department_members ishlatiladi.
CREATE TABLE IF NOT EXISTS employee_branches (
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL,
  branch_id    UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  PRIMARY KEY (workspace_id, user_id, branch_id)
);

CREATE INDEX IF NOT EXISTS employee_branches_ws_user_idx ON employee_branches (workspace_id, user_id);
CREATE INDEX IF NOT EXISTS employee_branches_branch_idx ON employee_branches (branch_id);

ALTER TABLE employee_branches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "emp_branches_select" ON employee_branches;
CREATE POLICY "emp_branches_select" ON employee_branches FOR SELECT TO authenticated
  USING ( user_id = auth.uid() OR is_ws_manager(workspace_id, auth.uid()) );

DROP POLICY IF EXISTS "emp_branches_write" ON employee_branches;
CREATE POLICY "emp_branches_write" ON employee_branches FOR ALL TO authenticated
  USING ( is_ws_manager(workspace_id, auth.uid()) )
  WITH CHECK ( is_ws_manager(workspace_id, auth.uid()) );

-- ── 6) Tekshiruv ────────────────────────────────────────────
-- Ishga tushgach quyidagi 4 qator chiqishi kerak:
--   employee_branches | employee_details | employee_roles | positions
SELECT tablename
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('positions', 'employee_roles', 'employee_details', 'employee_branches')
ORDER BY tablename;
