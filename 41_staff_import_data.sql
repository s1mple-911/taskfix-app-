-- ============================================================
-- 41_staff_import_data.sql
-- aros_staff importi uchun MA'LUMOT qatlami.
--
-- 40 — bog'lash (legacy_id_map, staff_import_map).
-- 41 — bog'lash EMAS, ma'lumot: hodim fakti, ish kunlari, rasm.
--
-- DIQQAT: bu yerda legacy_id / legacy_ids USTUNLARI YO'Q.
--         Manba id → TaskFix UUID bog'lash BUTUNLAY 40 dagi
--         legacy_id_map (filial/lavozim/rol/bo'lim) va
--         staff_import_map (hodim) orqali.
--         Quyidagi legacy_* ustunlar — bog'lash emas, hodim haqidagi
--         FAKT (asl ism, manba employment_id). Ular bilan qidirilmaydi.
--
-- Tartib: 35 → 38 → 39 → 40 → 41.
-- ============================================================

-- ── 0) Oldindan tekshiruv ───────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'is_ws_manager' AND n.nspname = 'public'
  ) THEN
    RAISE EXCEPTION 'is_ws_manager() topilmadi. Avval 35, 38, 39, 40-migratsiyalarni ishga tushiring.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'employee_details') THEN
    RAISE EXCEPTION 'employee_details topilmadi. Avval 39_employee_details.sql ni ishga tushiring.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'staff_import_map') THEN
    RAISE EXCEPTION 'staff_import_map topilmadi. Avval 40_staff_import.sql ni ishga tushiring.';
  END IF;
END $$;

-- ── 1a) branches: koordinata ────────────────────────────────
-- Manba filiallarida lat/lng bor, TaskFix'da ustun yo'q edi.
-- external_id ga TEGILMAYDI — u boshqa maqsad uchun (40:28-34).
ALTER TABLE branches ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION;
ALTER TABLE branches ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION;

-- ── 1) employee_details: ma'lumot ustunlari ─────────────────
-- Hech biri kalit emas — hech biri bo'yicha qidirilmaydi, shuning
-- uchun indeks ham yo'q. Hodimni topish: staff_import_map.source_id.
ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS legacy_name_raw      TEXT;
ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS legacy_employment_id INT;
ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS photo_path           TEXT;
ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS hired_at             TIMESTAMPTZ;
ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS lat                  DOUBLE PRECISION;
ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS lng                  DOUBLE PRECISION;

COMMENT ON COLUMN employee_details.legacy_name_raw IS
  'Manbadagi ASL ism — normalizatsiyagacha (kirill homoglif, U+2019 apostrof). Audit uchun.';
COMMENT ON COLUMN employee_details.legacy_employment_id IS
  'aros_staff employment_id. KALIT EMAS (kalit — staff_import_map.source_id = user_id). Manba bilan solishtirish uchun.';
COMMENT ON COLUMN employee_details.photo_path IS
  'employee-photos bucket ichidagi yo''l: {workspace_id}/{user_id}.jpg. photo_url dan USTUN turadi.';
COMMENT ON COLUMN employee_details.hired_at IS
  'aros_staff created_at — hodim manbada yaratilgan payt.';

-- ── 2) Ish jadvali: to'liq kunlar ───────────────────────────
-- Nega naqsh (weekend_days + bitta ish vaqti) EMAS:
-- manbada ish vaqti xilma-xil — 08:30–20:00 (9535 kun), 08:30–19:00
-- (7009), 09:00–21:00 (3057) va h.k. Naqshga aylantirish ma'lumotning
-- katta qismini yo'qotardi. ~40 412 qator import qilinadi.
--
-- employee_details.schedule_type / weekend_days / work_start / work_end
-- QOLADI, lekin ular endi faqat UI'da qisqa ko'rsatish uchun.
-- HAQIQAT MANBAI — shu jadval.
CREATE TABLE IF NOT EXISTS employee_schedule_days (
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL,
  date         DATE NOT NULL,
  day_type     TEXT NOT NULL,   -- on | off
  -- Vaqt 'off' kunda ham bo'lishi mumkin (manbada 4544 ta shunday):
  -- u hodimning odatiy jadvali, day_type esa o'sha kuni ishlash/ishlamasligini
  -- aytadi. Ikkovi bir-birini inkor qilmaydi.
  start_time   TIME,
  end_time     TIME,
  PRIMARY KEY (workspace_id, user_id, date)
);

-- PK (workspace_id, user_id, date) — "hodimning kunlari" so'rovini
-- o'zi qoplaydi. Alohida (workspace_id, user_id) indeksi ORTIQCHA.

-- TEXT + CHECK (ENUM EMAS — 30/32-migratsiyalardagi saboq).
-- Manbada faqat 'on'/'off' kutiladi. Agar uchinchi qiymat chiqsa —
-- import'da EMAS, mijoz preflight'ida ushlanadi (hrImportMapRow
-- day_type'ni tekshiradi va bloker sifatida ko'rsatadi). Shundagina
-- bu CHECK'ni ongli ravishda kengaytiramiz.
ALTER TABLE employee_schedule_days DROP CONSTRAINT IF EXISTS employee_schedule_days_day_type_chk;
ALTER TABLE employee_schedule_days ADD CONSTRAINT employee_schedule_days_day_type_chk
  CHECK (day_type IN ('on', 'off'));

ALTER TABLE employee_schedule_days ENABLE ROW LEVEL SECURITY;

-- KO'RISH: hodim — o'z jadvalini; owner/admin — hammasini.
-- FAQAT is_ws_manager()/is_ws_member() ishlatiladi — policy ichida
-- inline workspace_members subquery YOZMANG (rekursiya → 42P17, 39:28-29).
DROP POLICY IF EXISTS "emp_sched_days_select" ON employee_schedule_days;
CREATE POLICY "emp_sched_days_select" ON employee_schedule_days FOR SELECT TO authenticated
  USING ( user_id = auth.uid() OR is_ws_manager(workspace_id, auth.uid()) );

-- YOZISH: faqat owner/admin (import mijozda owner sifatida yozadi)
DROP POLICY IF EXISTS "emp_sched_days_write" ON employee_schedule_days;
CREATE POLICY "emp_sched_days_write" ON employee_schedule_days FOR ALL TO authenticated
  USING ( is_ws_manager(workspace_id, auth.uid()) )
  WITH CHECK ( is_ws_manager(workspace_id, auth.uid()) );

-- ── 3) Rasm: Storage bucket ─────────────────────────────────
-- DIQQAT — bu 38/39 dagi "fayl saqlanmaydi, faqat havola" qoidasidan
-- ONGLI CHEKINISH.
--
-- Sabab O'LCHANGAN (2026-07-17, 126 URL server tomondan tekshirilgan):
--   • auth KERAK EMAS — 401/403 umuman chiqmadi, 'cors_blocked' faqat
--     brauzer cheklovi edi (<img src> ni CORS to'smaydi)
--   • LEKIN 46/126 URL — 404. O'lik havolalar.
--
-- Havola sifatida qoldirsak: photo_url NULL emas → avatarHtml initsiallarga
-- tushmaydi → 46 ta jimgina siniq rasm ikonkasi.
-- Storage bilan: 404 import paytida ushlanadi → photo_path NULL qoladi →
-- initsiallarga toza tushadi, va hisobotda ko'rinadi.
--
-- Shartnoma va employee_links esa HAVOLA bo'lib qoladi (o'zgarmadi).
INSERT INTO storage.buckets (id, name, public)
VALUES ('employee-photos', 'employee-photos', false)
ON CONFLICT (id) DO NOTHING;

-- Yo'l sxemasi: {workspace_id}/{user_id}.jpg
--
-- YOZISH policy'si ATAYLAB YO'Q: rasmni faqat Edge Function
-- (service_role) yuklaydi, u esa RLS'ni butunlay chetlab o'tadi.
-- Policy bo'lmasa — hech bir authenticated foydalanuvchi yoza olmaydi.
--
-- O'QISH: createSignedUrl() chaqiruvchi JWT bilan ishlaydi, shuning
-- uchun SELECT policy SHART.
--
-- CASE ishlatilgan, AND emas: Postgres AND'da hisoblash tartibini
-- KAFOLATLAMAYDI, ya'ni buzuq nomdagi obyektda ::uuid cast xato berardi.
-- CASE tartibni kafolatlaydi.
DROP POLICY IF EXISTS "employee_photos_select" ON storage.objects;
CREATE POLICY "employee_photos_select" ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'employee-photos'
    AND CASE
          WHEN (storage.foldername(name))[1] ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
          THEN is_ws_manager(((storage.foldername(name))[1])::uuid, auth.uid())
               OR name = (storage.foldername(name))[1] || '/' || auth.uid()::text || '.jpg'
          ELSE false
        END
  );

-- ── 4) Tekshiruv — JIM O'TMAYDI ─────────────────────────────
-- SELECT bilan tekshirish yetarli emas: hech narsa yaratilmasa ham
-- migratsiya "muvaffaqiyatli" ko'rinadi, xato esa keyinroq — import
-- paytida chiqadi. Shuning uchun kutilgan holat bajarilmasa — EXCEPTION.
DO $$
DECLARE
  v_missing TEXT[];
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_tables
                 WHERE schemaname = 'public' AND tablename = 'employee_schedule_days') THEN
    RAISE EXCEPTION '41 BAJARILMADI: employee_schedule_days yaratilmadi.';
  END IF;

  SELECT array_agg(c) INTO v_missing
  FROM unnest(ARRAY['legacy_name_raw', 'legacy_employment_id', 'photo_path',
                    'hired_at', 'lat', 'lng']) AS c
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'employee_details' AND column_name = c
  );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '41 BAJARILMADI: employee_details da ustun yo''q: %', array_to_string(v_missing, ', ');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'employee-photos') THEN
    RAISE EXCEPTION '41 BAJARILMADI: employee-photos bucket yaratilmadi.';
  END IF;

  IF EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'employee-photos' AND public IS TRUE) THEN
    RAISE EXCEPTION '41 XAVFLI: employee-photos PUBLIC bo''lib qolgan — private bo''lishi kerak.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname = 'storage' AND tablename = 'objects'
                   AND policyname = 'employee_photos_select') THEN
    RAISE EXCEPTION '41 BAJARILMADI: storage.objects da employee_photos_select policy yo''q. '
      'Supabase''da storage.objects ga policy yaratish huquqi kerak — dashboard orqali qo''ying.';
  END IF;

  RAISE NOTICE '41 OK: employee_schedule_days, 6 ustun, employee-photos (private) + SELECT policy.';
END $$;

-- Ko'z bilan ko'rish uchun (yuqoridagi blok allaqachon kafolatladi)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'employee_details'
  AND column_name IN ('legacy_name_raw', 'legacy_employment_id', 'photo_path',
                      'hired_at', 'lat', 'lng')
ORDER BY column_name;
