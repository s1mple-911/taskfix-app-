-- 47_harajat_kassa.sql
-- Hodim uchun "Harajat kassa kerakmi" bayrog'i (Aros Provodka integratsiyasi).
-- Faqat owner/admin o'zgartiradi — mavjud employee_details RLS yetarli,
-- yangi policy kerak emas.
-- Idempotent.

ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS harajat_kassa BOOLEAN NOT NULL DEFAULT false;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employee_details' AND column_name = 'harajat_kassa'
  ) THEN
    RAISE EXCEPTION '47 BAJARILMADI: harajat_kassa ustuni qo''shilmadi.';
  END IF;
  RAISE NOTICE '47 OK: employee_details.harajat_kassa (BOOLEAN, default false).';
END $$;
