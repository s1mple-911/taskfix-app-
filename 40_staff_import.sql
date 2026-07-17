-- ============================================================
-- 40_staff_import.sql
-- aros_staff → TaskFix import infratuzilmasi.
--
-- Ikki jadval, ikki vazifa:
--   staff_import_map — HODIM: manba yozuvi ↔ auth user (+ rollback)
--   legacy_id_map    — MA'LUMOTNOMA: manbadagi raqamli id ↔ TaskFix UUID
--                      (filial, lavozim, rol, bo'lim)
--
-- Tartib: 35 → 38 → 39 → 40.
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'is_ws_manager' AND n.nspname = 'public'
  ) THEN
    RAISE EXCEPTION 'is_ws_manager() topilmadi. Avval 35, 38, 39-migratsiyalarni ishga tushiring.';
  END IF;
END $$;

-- ── 1) Ma'lumotnoma xaritasi ────────────────────────────────
-- aros_staff'da filial/lavozim/rol RAQAMLI id bilan keladi (masalan
-- branch_id = 42). TaskFix'da esa UUID. Bu jadval ikkisini bog'laydi.
--
-- Nega alohida jadval, ustun emas:
--   • branches.external_id allaqachon bor, lekin u "Aros warehouse_id"
--     uchun — aros_staff.branch_id bilan BIR XIL id maydoni ekani
--     tasdiqlanmagan. Ustunni qayta ishlatish jimgina xato beradi.
--   • positions / employee_roles'da bunday ustun umuman yo'q.
--   • Bitta naqsh — to'rt entity uchun. Import mantig'i bitta.
--   • Domen jadvallari import tafsilotlaridan toza qoladi.
CREATE TABLE IF NOT EXISTS legacy_id_map (
  workspace_id  UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  source_system TEXT NOT NULL DEFAULT 'aros_staff',
  entity_type   TEXT NOT NULL,   -- branch | position | role | department
  legacy_id     TEXT NOT NULL,   -- manbadagi id (raqam ham matn sifatida)
  target_id     UUID NOT NULL,   -- TaskFix ichidagi id
  note          TEXT,
  created_by    UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (workspace_id, source_system, entity_type, legacy_id)
);

-- TEXT + CHECK (ENUM emas — 30/32-migratsiyalardagi saboq)
ALTER TABLE legacy_id_map DROP CONSTRAINT IF EXISTS legacy_id_map_entity_chk;
ALTER TABLE legacy_id_map ADD CONSTRAINT legacy_id_map_entity_chk
  CHECK (entity_type IN ('branch', 'position', 'role', 'department'));

-- Teskari qidiruv: "bu TaskFix filialiga qaysi legacy id'lar bog'langan?"
CREATE INDEX IF NOT EXISTS legacy_id_map_target_idx
  ON legacy_id_map (workspace_id, entity_type, target_id);

-- DIQQAT: (entity_type, target_id) bo'yicha UNIQUE ATAYLAB QO'YILMAGAN —
-- manbada bo'lingan ikki filial TaskFix'da bitta bo'lishi mumkin (birlashtirish).
-- Teskarisi esa PK bilan to'silgan: bitta legacy_id ikki joyga ketolmaydi.

ALTER TABLE legacy_id_map ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "legacy_map_all" ON legacy_id_map;
CREATE POLICY "legacy_map_all" ON legacy_id_map FOR ALL TO authenticated
  USING ( is_ws_manager(workspace_id, auth.uid()) )
  WITH CHECK ( is_ws_manager(workspace_id, auth.uid()) );

-- ── 2) Hodim import xaritasi ────────────────────────────────
-- Idempotentlikning asosiy langari: source_id → user_id.
-- Qayta ishga tushirilganda shu yerdan topilgan hodim QAYTA YARATILMAYDI.
CREATE TABLE IF NOT EXISTS staff_import_map (
  workspace_id      UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  source_system     TEXT NOT NULL DEFAULT 'aros_staff',
  source_id         TEXT NOT NULL,   -- aros_staff PK; bo'lmasa E.164 telefon
  user_id           UUID NOT NULL,
  phone_e164        TEXT,
  -- Rollback uchun: bitta yurgizish = bitta UUID.
  -- created_in_run — FAQAT shu yurgizishda yaratilgan userlarni qaytarish
  -- mumkin. adopted/updated bo'lganlarga tegilmaydi (ular avvaldan bor edi).
  import_run_id     UUID,
  created_in_run    BOOLEAN NOT NULL DEFAULT false,
  first_imported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_imported_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (workspace_id, source_system, source_id)
);

-- Bitta auth user ikki manba yozuviga bog'lanib qolmasin
CREATE UNIQUE INDEX IF NOT EXISTS staff_import_map_user_uniq
  ON staff_import_map (workspace_id, source_system, user_id);

CREATE INDEX IF NOT EXISTS staff_import_map_run_idx
  ON staff_import_map (workspace_id, import_run_id);

ALTER TABLE staff_import_map ENABLE ROW LEVEL SECURITY;

-- Faqat owner/admin. Oddiy hodim import metama'lumotini ko'rmaydi —
-- shuning uchun is_ws_member() bu yerda KERAK EMAS.
DROP POLICY IF EXISTS "staff_import_all" ON staff_import_map;
CREATE POLICY "staff_import_all" ON staff_import_map FOR ALL TO authenticated
  USING ( is_ws_manager(workspace_id, auth.uid()) )
  WITH CHECK ( is_ws_manager(workspace_id, auth.uid()) );

-- ── 3) Yordamchi: email bo'yicha auth user topish ───────────
-- "Adopt" yo'li uchun: user auth.users'da bor, lekin staff_import_map'da yo'q
-- (oldingi yurgizish map yozishdan oldin uzilgan). Shunda uni topib map'ga
-- bog'laymiz — yangi user yaratmaymiz.
--
-- Nega SQL funksiya, listUsers() emas: listUsers barcha userlarni sahifalab
-- yuklaydi — 130 qator uchun 130 marta qilib bo'lmaydi. Bu esa indeksli qidiruv.
CREATE OR REPLACE FUNCTION auth_user_id_by_email(p_email TEXT)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth
AS $$
  SELECT id FROM auth.users WHERE lower(email) = lower(p_email) LIMIT 1;
$$;

-- XAVFSIZLIK: bu funksiya email bo'yicha ro'yxatni tekshirish (enumeration)
-- vositasi bo'lib qolmasin — faqat service_role (Edge Function) chaqira oladi.
REVOKE ALL ON FUNCTION auth_user_id_by_email(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION auth_user_id_by_email(TEXT) FROM anon;
REVOKE ALL ON FUNCTION auth_user_id_by_email(TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION auth_user_id_by_email(TEXT) TO service_role;

-- ── 4) Tekshiruv ────────────────────────────────────────────
-- 2 qator chiqishi kerak: legacy_id_map | staff_import_map
SELECT tablename
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('legacy_id_map', 'staff_import_map')
ORDER BY tablename;
