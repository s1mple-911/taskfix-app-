-- 43_schedule_monthly.sql
-- Oylik (monthly) ish jadvali uchun ikkita ustun: har oyning boshi yoki
-- oxiridan ketma-ket N kun dam. Kalendar YO'Q — naqsh (pattern) sifatida
-- saqlanadi, "Kunlarni saqlash" tugmasi employee_schedule_days'ni shundan
-- qayta hosil qiladi.
--
-- TEXT + CHECK (ENUM EMAS — 30/32-migratsiyalardagi saboq).
-- Idempotent: qayta ishga tushirsa xato bermaydi.

ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS monthly_off_count    INT;
ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS monthly_off_position TEXT;

ALTER TABLE employee_details DROP CONSTRAINT IF EXISTS employee_details_monthly_pos_chk;
ALTER TABLE employee_details ADD CONSTRAINT employee_details_monthly_pos_chk
  CHECK (monthly_off_position IS NULL OR monthly_off_position IN ('start', 'end'));

-- 0..31 oralig'i (bir oyda 31 kundan ko'p dam bo'lmaydi)
ALTER TABLE employee_details DROP CONSTRAINT IF EXISTS employee_details_monthly_count_chk;
ALTER TABLE employee_details ADD CONSTRAINT employee_details_monthly_count_chk
  CHECK (monthly_off_count IS NULL OR (monthly_off_count >= 0 AND monthly_off_count <= 31));

-- Tekshiruv: ikkala ustun ham qo'shilganini tasdiqlaydi (jimgina o'tmasin)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employee_details' AND column_name = 'monthly_off_count'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employee_details' AND column_name = 'monthly_off_position'
  ) THEN
    RAISE EXCEPTION '43 BAJARILMADI: monthly_off ustunlari qo''shilmadi.';
  END IF;
  RAISE NOTICE '43 OK: employee_details.monthly_off_count + monthly_off_position (TEXT+CHECK).';
END $$;
