-- ============================================================
-- 38_employee_links.sql
-- Hodim hujjatlari — FAYL EMAS, faqat Google Drive (yoki boshqa) LINKLARI.
-- Owner/admin hammasini ko'radi va boshqaradi; hodim FAQAT o'zinikini ko'radi.
--
-- Tartib: 35 → 38.
-- ============================================================

-- ── 0) Oldindan tekshiruv ───────────────────────────────────
-- is_ws_manager() 35-migratsiyada yaratilgan. Bo'lmasa quyidagi
-- CREATE POLICY'lar yiqiladi — LEKIN jadval allaqachon yaratilgan va
-- RLS yoqilgan bo'lardi. Policy'siz + RLS yoqilgan = hech kim o'qiy
-- olmaydi. Shuning uchun jadvalga TEGMASDAN, darrov to'xtaymiz.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'is_ws_manager' AND n.nspname = 'public'
  ) THEN
    RAISE EXCEPTION 'is_ws_manager() topilmadi. Avval 35_fix_projects_rls.sql ni ishga tushiring.';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS employee_links (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id  UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL,              -- kimning hujjati
  title         TEXT NOT NULL,              -- "Shartnoma", "Diplom", ...
  url           TEXT NOT NULL,              -- Google Drive havolasi
  note          TEXT,                       -- ixtiyoriy izoh
  created_by    UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS employee_links_ws_user_idx ON employee_links (workspace_id, user_id);

ALTER TABLE employee_links ENABLE ROW LEVEL SECURITY;

-- KO'RISH: owner/admin — hammasini; hodim — faqat o'zinikini
DROP POLICY IF EXISTS "emp_links_select" ON employee_links;
CREATE POLICY "emp_links_select" ON employee_links FOR SELECT TO authenticated
  USING ( user_id = auth.uid() OR is_ws_manager(workspace_id, auth.uid()) );

-- YOZISH/O'CHIRISH: faqat owner/admin
DROP POLICY IF EXISTS "emp_links_write" ON employee_links;
CREATE POLICY "emp_links_write" ON employee_links FOR ALL TO authenticated
  USING ( is_ws_manager(workspace_id, auth.uid()) )
  WITH CHECK ( is_ws_manager(workspace_id, auth.uid()) );
