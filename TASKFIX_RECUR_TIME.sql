-- ============================================================================
-- TASKFIX_RECUR_TIME.sql — TAKRORLANISH UCHUN ANIQ VAQT
-- ----------------------------------------------------------------------------
-- NIMA QO'SHILADI (ADDITIVE, hech narsa o'chirilmaydi/o'zgartirilmaydi):
--   public.projects → recur_time TEXT, recur_weekday SMALLINT, recur_monthday SMALLINT
--   public.tasks    → recur_type TEXT, recur_time TEXT, recur_weekday SMALLINT,
--                     recur_monthday SMALLINT
--   + 7 ta CHECK cheklovi (TEXT + CHECK — ENUM EMAS, 30/32-migratsiyalardagi saboq)
--
-- NIMA O'ZGARMAYDI:
--   • Mavjud ustunlar (projects.recur_type / recurrence_* / start_at / end_at,
--     tasks.recur_days) — BIR ZARRA tegilmaydi.
--   • RLS policy'lar, trigger'lar, indekslar, GRANT'lar — tegilmaydi.
--   • Mavjud qatorlar: yangi ustunlar NULL bo'lib qoladi. Har CHECK "IS NULL OR ..."
--     shaklida, ya'ni bironta mavjud qator ham buzilmaydi va skript hech qanday
--     UPDATE qilmaydi.
--
-- ILOVA BUSIZ HAM ISHLAYDI: mijoz "ustun yo'q" xatosini (42703 / PGRST204)
-- aniqlaydi, so'rovni shu ustunlarsiz QAYTA yuboradi va sababni foydalanuvchiga
-- aytadi ("takrorlanish vaqti saqlanmadi — TASKFIX_RECUR_TIME.sql ishga
-- tushirilmagan"). Yangi ustunlar NULL bo'lganda mantiq AYNAN hozirgidek:
-- kunlik = 00:00, haftalik = dushanba 00:00, oylik = 1-sana 00:00 (Asia/Tashkent).
--
-- KONVENSIYA:
--   recur_time     'HH:MM' (24 soatlik, Asia/Tashkent)
--   recur_weekday  0 = Yakshanba … 6 = Shanba  (JS getDay() bilan bir xil;
--                  mavjud projects.recurrence_weekday ham SHU konvensiyada)
--   recur_monthday 1..31 (oyda bunday kun bo'lmasa — o'sha oyning oxirgi kuni)
--
-- IDEMPOTENT: qayta RUN qilish xavfsiz (IF NOT EXISTS + pg_constraint tekshiruvi).
-- Boshqa fayllarga bog'liq emas, tartib muhim emas.
-- ============================================================================

BEGIN;

-- ── 0) OLD SHART: jadvallar bormi? ──────────────────────────────────────────
DO $$
BEGIN
  IF to_regclass('public.projects') IS NULL THEN
    RAISE EXCEPTION 'public.projects jadvali topilmadi — bu TaskFix bazasi emasmi?';
  END IF;
  IF to_regclass('public.tasks') IS NULL THEN
    RAISE EXCEPTION 'public.tasks jadvali topilmadi — bu TaskFix bazasi emasmi?';
  END IF;
END $$;

-- ── 1) USTUNLAR ─────────────────────────────────────────────────────────────
ALTER TABLE public.projects ADD COLUMN IF NOT EXISTS recur_time     text;
ALTER TABLE public.projects ADD COLUMN IF NOT EXISTS recur_weekday  smallint;
ALTER TABLE public.projects ADD COLUMN IF NOT EXISTS recur_monthday smallint;

ALTER TABLE public.tasks    ADD COLUMN IF NOT EXISTS recur_type     text;
ALTER TABLE public.tasks    ADD COLUMN IF NOT EXISTS recur_time     text;
ALTER TABLE public.tasks    ADD COLUMN IF NOT EXISTS recur_weekday  smallint;
ALTER TABLE public.tasks    ADD COLUMN IF NOT EXISTS recur_monthday smallint;

COMMENT ON COLUMN public.projects.recur_time     IS 'Takrorlanish soati ''HH:MM'' (Asia/Tashkent). NULL = 00:00 (eski xatti-harakat).';
COMMENT ON COLUMN public.projects.recur_weekday  IS 'Haftalik takrorlanish kuni: 0=Yakshanba … 6=Shanba. NULL = 1 (Dushanba).';
COMMENT ON COLUMN public.projects.recur_monthday IS 'Oylik takrorlanish kuni 1..31. NULL = 1. Oyda bunday kun bo''lmasa — oxirgi kun.';
COMMENT ON COLUMN public.tasks.recur_type        IS 'Vazifa takrorlanishi: none|daily|weekly|monthly. NULL = eski recur_days mantiqi.';
COMMENT ON COLUMN public.tasks.recur_time        IS 'Takrorlanish soati ''HH:MM'' (Asia/Tashkent). NULL = 00:00.';
COMMENT ON COLUMN public.tasks.recur_weekday     IS 'Haftalik takrorlanish kuni: 0=Yakshanba … 6=Shanba. NULL = 1 (Dushanba).';
COMMENT ON COLUMN public.tasks.recur_monthday    IS 'Oylik takrorlanish kuni 1..31. NULL = 1.';

-- ── 2) CHECK CHEKLOVLARI (TEXT + CHECK, ENUM EMAS) ──────────────────────────
-- ⚠️ Har biri "IS NULL OR ..." — mavjud (NULL) qatorlar buzilmaydi.
DO $$
BEGIN
  -- projects.recur_time
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'projects_recur_time_chk'
                   AND conrelid = 'public.projects'::regclass) THEN
    ALTER TABLE public.projects ADD CONSTRAINT projects_recur_time_chk
      CHECK (recur_time IS NULL OR recur_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$');
  END IF;
  -- projects.recur_weekday
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'projects_recur_weekday_chk'
                   AND conrelid = 'public.projects'::regclass) THEN
    ALTER TABLE public.projects ADD CONSTRAINT projects_recur_weekday_chk
      CHECK (recur_weekday IS NULL OR (recur_weekday BETWEEN 0 AND 6));
  END IF;
  -- projects.recur_monthday
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'projects_recur_monthday_chk'
                   AND conrelid = 'public.projects'::regclass) THEN
    ALTER TABLE public.projects ADD CONSTRAINT projects_recur_monthday_chk
      CHECK (recur_monthday IS NULL OR (recur_monthday BETWEEN 1 AND 31));
  END IF;
  -- tasks.recur_type
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tasks_recur_type_chk'
                   AND conrelid = 'public.tasks'::regclass) THEN
    ALTER TABLE public.tasks ADD CONSTRAINT tasks_recur_type_chk
      CHECK (recur_type IS NULL OR recur_type IN ('none','daily','weekly','monthly'));
  END IF;
  -- tasks.recur_time
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tasks_recur_time_chk'
                   AND conrelid = 'public.tasks'::regclass) THEN
    ALTER TABLE public.tasks ADD CONSTRAINT tasks_recur_time_chk
      CHECK (recur_time IS NULL OR recur_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$');
  END IF;
  -- tasks.recur_weekday
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tasks_recur_weekday_chk'
                   AND conrelid = 'public.tasks'::regclass) THEN
    ALTER TABLE public.tasks ADD CONSTRAINT tasks_recur_weekday_chk
      CHECK (recur_weekday IS NULL OR (recur_weekday BETWEEN 0 AND 6));
  END IF;
  -- tasks.recur_monthday
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tasks_recur_monthday_chk'
                   AND conrelid = 'public.tasks'::regclass) THEN
    ALTER TABLE public.tasks ADD CONSTRAINT tasks_recur_monthday_chk
      CHECK (recur_monthday IS NULL OR (recur_monthday BETWEEN 1 AND 31));
  END IF;
END $$;

-- ── 3) TEKSHIRUV — jimgina o'tmasin ─────────────────────────────────────────
DO $$
DECLARE
  v_cols int;
  v_chks int;
  v_miss text;
BEGIN
  -- 7 ustun
  SELECT count(*) INTO v_cols
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND (
      (table_name = 'projects' AND column_name IN ('recur_time','recur_weekday','recur_monthday'))
      OR
      (table_name = 'tasks'    AND column_name IN ('recur_type','recur_time','recur_weekday','recur_monthday'))
    );
  IF v_cols <> 7 THEN
    SELECT string_agg(x, ', ') INTO v_miss FROM (
      SELECT 'projects.' || c AS x FROM unnest(ARRAY['recur_time','recur_weekday','recur_monthday']) c
      WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_schema='public' AND table_name='projects' AND column_name=c)
      UNION ALL
      SELECT 'tasks.' || c FROM unnest(ARRAY['recur_type','recur_time','recur_weekday','recur_monthday']) c
      WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_schema='public' AND table_name='tasks' AND column_name=c)
    ) q;
    RAISE EXCEPTION 'TEKSHIRUV: 7 ustun kutilgandi, % ta topildi. Yetishmayapti: %', v_cols, coalesce(v_miss,'?');
  END IF;

  -- 7 CHECK
  -- ⚠️ `conname` global unikal EMAS — shuning uchun jadval ham tekshiriladi
  --    (TASKFIX_LOYIHA.sql dagi naqsh: conrelid = '...'::regclass).
  SELECT count(*) INTO v_chks
  FROM pg_constraint
  WHERE contype = 'c'
    AND conrelid IN ('public.projects'::regclass, 'public.tasks'::regclass)
    AND conname IN (
      'projects_recur_time_chk','projects_recur_weekday_chk','projects_recur_monthday_chk',
      'tasks_recur_type_chk','tasks_recur_time_chk','tasks_recur_weekday_chk','tasks_recur_monthday_chk'
    );
  IF v_chks <> 7 THEN
    SELECT string_agg(c, ', ') INTO v_miss FROM unnest(ARRAY[
      'projects_recur_time_chk','projects_recur_weekday_chk','projects_recur_monthday_chk',
      'tasks_recur_type_chk','tasks_recur_time_chk','tasks_recur_weekday_chk','tasks_recur_monthday_chk'
    ]) c WHERE NOT EXISTS (SELECT 1 FROM pg_constraint WHERE contype='c' AND conname = c
                            AND conrelid IN ('public.projects'::regclass, 'public.tasks'::regclass));
    RAISE EXCEPTION 'TEKSHIRUV: 7 CHECK kutilgandi, % ta topildi. Yetishmayapti: %', v_chks, coalesce(v_miss,'?');
  END IF;

  RAISE NOTICE 'TASKFIX_RECUR_TIME: OK — 7 ustun + 7 CHECK joyida.';
END $$;

COMMIT;

-- ============================================================================
-- QAYTARISH (kerak bo'lsa — mijoz ularsiz ham ishlaydi):
--   ALTER TABLE public.projects DROP COLUMN IF EXISTS recur_time;
--   ALTER TABLE public.projects DROP COLUMN IF EXISTS recur_weekday;
--   ALTER TABLE public.projects DROP COLUMN IF EXISTS recur_monthday;
--   ALTER TABLE public.tasks    DROP COLUMN IF EXISTS recur_type;
--   ALTER TABLE public.tasks    DROP COLUMN IF EXISTS recur_time;
--   ALTER TABLE public.tasks    DROP COLUMN IF EXISTS recur_weekday;
--   ALTER TABLE public.tasks    DROP COLUMN IF EXISTS recur_monthday;
--   (CHECK'lar ustun bilan birga o'chadi)
-- ============================================================================
