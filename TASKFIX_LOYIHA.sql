-- TASKFIX_LOYIHA.sql — Loyiha muddati (boshlanish / tugash) + takrorlanish turi
-- Asilbek RUN qiladi. ADDITIVE + IDEMPOTENT: mavjud ma'lumot o'zgarmaydi, prod xavfsiz.
-- Qayta RUN qilish xavfsiz — hamma narsa "yo'q bo'lsa qo'sh" mantig'ida.
--
-- NIMA QO'SHILADI (public.projects ga, hammasi NULL bo'lishi mumkin = eski xatti-harakat):
--   1) start_at        timestamptz — loyiha boshlanishi (sana + soat). NULL = belgilanmagan.
--   2) end_at          timestamptz — loyiha tugashi.                    NULL = belgilanmagan.
--   3) recur_type      text        — 'none' | 'daily' | 'weekly' | 'monthly' (TEXT + CHECK, ENUM EMAS).
--                                    Bu bosqichda ilova UNI YOZMAYDI — keyingi bosqich (takrorlanish) uchun.
--   4) recur_parent_id — takrorlanish zanjiri uchun ZAXIRA (o'z-o'ziga FK, ON DELETE SET NULL).
--                        Bu bosqichda ishlatilmaydi.
--   + CHECK  projects_dates_chk     — end_at > start_at (ikkovi ham to'lgan bo'lsa).
--   + CHECK  projects_recur_type_chk
--   + INDEX  idx_projects_ws_start (workspace_id, start_at) — ro'yxat sanaga qarab saralanadi.
--
-- NIMA O'ZGARMAYDI:
--   • public.projects.status ustuniga TEGILMAYDI. U qo'lda hayot sikli bo'lib qoladi
--     ('active' | 'paused' | 'done' — "Sozlash" oynasi yozadi). Ilovadagi 4 status
--     (upcoming / active / ended / overdue) SAQLANMAYDI — start_at/end_at + bosqichlar
--     holatidan HAR CHIZISHDA hisoblanadi (devor soati o'zgargani sayin o'zi to'g'rilanadi,
--     cron kerak emas, mavjud 'paused' qiymati bosilmaydi).
--   • flow_type, recurrence_type/recurrence_days/recurrence_weekday/last_reset_at — tegilmaydi.
--   • RLS: yangi jadval yo'q → yangi policy KERAK EMAS. Mavjud projects policy'lariga tegilmaydi.
--   • Hech qanday trigger/funksiya qo'shilmaydi yoki o'chirilmaydi.
--
-- ILOVA BUSIZ HAM ISHLAYDI: ustunlar yo'q bo'lsa mijoz ularsiz qayta yozadi
-- (prjNoLoyihaCol) va bir marta ogohlantiradi — lekin sana saqlanmaydi.

BEGIN;

-- ─────────────────────────────────────────────────────────────
-- 0) Old shart — jadval bormi?
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'projects'
  ) THEN
    RAISE EXCEPTION 'public.projects jadvali topilmadi — avval loyiha migratsiyasi (34) ishga tushirilishi kerak.';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 1) Sana ustunlari
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.projects ADD COLUMN IF NOT EXISTS start_at timestamptz;
ALTER TABLE public.projects ADD COLUMN IF NOT EXISTS end_at   timestamptz;

-- ─────────────────────────────────────────────────────────────
-- 2) Takrorlanish turi — TEXT + CHECK (ENUM EMAS, 30/32-migratsiyalardagi saboq)
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.projects ADD COLUMN IF NOT EXISTS recur_type text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'projects_recur_type_chk'
      AND conrelid = 'public.projects'::regclass
  ) THEN
    ALTER TABLE public.projects
      ADD CONSTRAINT projects_recur_type_chk
      CHECK (recur_type IS NULL OR recur_type IN ('none','daily','weekly','monthly'));
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 3) recur_parent_id — o'z-o'ziga havola (zanjir). Tur projects.id turidan olinadi
--    (uuid/bigint — qaysi bo'lsa ham to'g'ri ishlasin).
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_idtype text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'projects' AND column_name = 'recur_parent_id'
  ) THEN
    SELECT format_type(a.atttypid, a.atttypmod) INTO v_idtype
      FROM pg_attribute a
      WHERE a.attrelid = 'public.projects'::regclass AND a.attname = 'id' AND a.attnum > 0;
    IF v_idtype IS NULL THEN
      RAISE EXCEPTION 'public.projects.id ustuni topilmadi — recur_parent_id qo''shib bo''lmadi.';
    END IF;
    EXECUTE format('ALTER TABLE public.projects ADD COLUMN recur_parent_id %s', v_idtype);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'projects_recur_parent_fk'
      AND conrelid = 'public.projects'::regclass
  ) THEN
    ALTER TABLE public.projects
      ADD CONSTRAINT projects_recur_parent_fk
      FOREIGN KEY (recur_parent_id) REFERENCES public.projects(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 4) Sana tartibi cheklovi — end_at > start_at (ikkovi ham to'lgan bo'lsa).
--    Yangi ustunlar bo'lgani uchun mavjud qatorlarda ikkovi ham NULL → tekshiruv o'tadi.
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'projects_dates_chk'
      AND conrelid = 'public.projects'::regclass
  ) THEN
    ALTER TABLE public.projects
      ADD CONSTRAINT projects_dates_chk
      CHECK (end_at IS NULL OR start_at IS NULL OR end_at > start_at);
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 5) Indeks — loyihalar ro'yxati boshlanish sanasi bo'yicha saralanadi
-- ─────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_projects_ws_start
  ON public.projects (workspace_id, start_at);

-- ─────────────────────────────────────────────────────────────
-- 6) Izohlar
-- ─────────────────────────────────────────────────────────────
COMMENT ON COLUMN public.projects.start_at IS
  'Loyiha boshlanishi (sana + soat, timestamptz). NULL = belgilanmagan. Ilovadagi "Boshlanmagan" (upcoming) holati shundan hisoblanadi.';
COMMENT ON COLUMN public.projects.end_at IS
  'Loyiha tugashi (sana + soat, timestamptz). NULL = belgilanmagan. "Muddat o''tgan" (overdue) va "Tugagan" (ended) holatlari shundan hisoblanadi.';
COMMENT ON COLUMN public.projects.recur_type IS
  'Takrorlanish turi: none|daily|weekly|monthly. Bu bosqichda ilova YOZMAYDI — keyingi bosqich uchun. Eski recurrence_days/recurrence_weekday ustunlari o''z joyida qoladi.';
COMMENT ON COLUMN public.projects.recur_parent_id IS
  'Takrorlanish zanjiri: nusxa qaysi loyihadan tug''ilgan. ZAXIRA — hozircha ilova ishlatmaydi. Ota o''chsa NULL bo''ladi (ON DELETE SET NULL).';

-- ─────────────────────────────────────────────────────────────
-- 7) Tekshiruv — jimgina o'tmasin
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  c text;
BEGIN
  -- 7.1 Ustunlar
  FOREACH c IN ARRAY ARRAY['start_at','end_at','recur_type','recur_parent_id'] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'projects' AND column_name = c
    ) THEN
      RAISE EXCEPTION 'public.projects.% ustuni qo''shilmadi', c;
    END IF;
  END LOOP;

  -- 7.2 start_at / end_at turi timestamptz bo'lishi shart
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='projects' AND column_name='start_at'
      AND data_type = 'timestamp with time zone'
  ) THEN
    RAISE EXCEPTION 'public.projects.start_at timestamptz emas';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='projects' AND column_name='end_at'
      AND data_type = 'timestamp with time zone'
  ) THEN
    RAISE EXCEPTION 'public.projects.end_at timestamptz emas';
  END IF;

  -- 7.3 Cheklovlar
  FOREACH c IN ARRAY ARRAY['projects_recur_type_chk','projects_dates_chk','projects_recur_parent_fk'] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = c AND conrelid = 'public.projects'::regclass
    ) THEN
      RAISE EXCEPTION '% cheklovi qo''shilmadi', c;
    END IF;
  END LOOP;

  -- 7.4 Indeks
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND tablename = 'projects' AND indexname = 'idx_projects_ws_start'
  ) THEN
    RAISE EXCEPTION 'idx_projects_ws_start indeksi qo''shilmadi';
  END IF;

  -- 7.5 status ustuniga TEGILMAGANI — ilova unga tayanadi
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'projects' AND column_name = 'status'
  ) THEN
    RAISE EXCEPTION 'public.projects.status ustuni yo''q — bu skript unga tegmasligi kerak edi, holat noto''g''ri.';
  END IF;

  RAISE NOTICE 'TASKFIX_LOYIHA.sql: OK — start_at, end_at, recur_type, recur_parent_id + 2 CHECK + FK + indeks joyida.';
END $$;

COMMIT;

-- ─────────────────────────────────────────────────────────────
-- 8) DIAGNOSTIKA — hech narsani o'zgartirmaydi, faqat xabar beradi.
--    Natijani "Messages"/"Notices" bo'limida o'qing.
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_cnt int;
  v_txt text;
BEGIN
  SELECT count(*) INTO v_cnt FROM public.projects;
  RAISE NOTICE 'Loyihalar soni: %', v_cnt;

  SELECT count(*) INTO v_cnt FROM public.projects WHERE start_at IS NOT NULL OR end_at IS NOT NULL;
  RAISE NOTICE 'Muddati belgilangan loyihalar: % (yangi ustunlar — boshida 0 bo''lishi normal)', v_cnt;

  SELECT string_agg(coalesce(status,'(null)') || '=' || c::text, ', ')
    INTO v_txt
    FROM (SELECT status, count(*) c FROM public.projects GROUP BY status) s;
  RAISE NOTICE 'projects.status (TEGILMADI) hozirgi qiymatlari: %', coalesce(v_txt, '(loyiha yo''q)');

  SELECT count(*) INTO v_cnt
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'projects' AND c.relrowsecurity;
  IF v_cnt = 0 THEN
    RAISE WARNING 'DIQQAT: public.projects jadvalida RLS YOQILMAGAN!';
  ELSE
    SELECT count(*) INTO v_cnt FROM pg_policies WHERE schemaname='public' AND tablename='projects';
    RAISE NOTICE 'public.projects: RLS yoqilgan, % ta policy (o''zgartirilmadi).', v_cnt;
  END IF;
END $$;
