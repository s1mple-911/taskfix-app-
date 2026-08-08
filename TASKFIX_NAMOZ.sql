-- ============================================================================
-- TASKFIX_NAMOZ.sql — Namoz vaqtlari (Planner) · 2026-08-08
-- ============================================================================
-- ADDITIVE + IDEMPOTENT: mavjud jadval/ustunlarga TEGMAYDI. Qo'shadi:
--   1) public.profiles  → namoz_enabled (toggle), namoz_region (viloyat)
--   2) public.namoz_times → kunlik kesh (region + sana → 5 vaqt)
--
-- ⚠️ BU FAYL ISHGA TUSHMASA — ilova YIQILMAYDI: planner avvalgidek ishlaydi,
--    "Musulmon" toggle'i esa "SQL ishga tushirilmagan" deb ochiq aytadi.
--
-- 3-QOIDA: TEXT + CHECK, ENUM emas (30/32-migratsiyalardagi saboq).
-- ============================================================================

BEGIN;

-- ── 0) Oldindan tekshiruv ───────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'public' AND c.relname = 'profiles') THEN
    RAISE EXCEPTION 'public.profiles topilmadi — noto''g''ri baza?';
  END IF;
END $$;

-- ── 1) Foydalanuvchi sozlamasi (profiles) ───────────────────────────────────
-- ⚠️ SHAXSIY sozlama: workspace'ga bog'liq EMAS (bir odam bir necha workspace'da
--    bo'lishi mumkin, namoz vaqti esa undan qat'i nazar bir xil).
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS namoz_enabled boolean NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS namoz_region  text;

-- 12 viloyat + Qoraqalpog'iston + Toshkent shahri = 14.
-- Slug ASCII (URL/kodda muammo bo'lmasin), ko'rinadigan nomi ilovada.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_namoz_region_ck') THEN
    ALTER TABLE public.profiles ADD CONSTRAINT profiles_namoz_region_ck CHECK (
      namoz_region IS NULL OR namoz_region IN (
        'toshkent', 'toshkent_v', 'andijon', 'buxoro', 'fargona', 'jizzax',
        'namangan', 'navoiy', 'qashqadaryo', 'samarqand', 'sirdaryo',
        'surxondaryo', 'xorazm', 'qoraqalpogiston'
      )
    );
  END IF;
END $$;

COMMENT ON COLUMN public.profiles.namoz_enabled IS 'Planner''da namoz vaqtlari ko''rsatilsinmi ("Musulmon" toggle). TASKFIX_NAMOZ.sql';
COMMENT ON COLUMN public.profiles.namoz_region  IS 'Viloyat slug''i (14 qiymat). NULL = hali tanlanmagan.';

-- ── 2) Kunlik kesh ──────────────────────────────────────────────────────────
-- Bitta (viloyat, sana) = bitta qator. Bir odam olib kelsa, qolganlarga
-- API'ga chiqish shart emas.
--
-- ⚠️ `sunrise` (quyosh chiqishi) NAMOZ EMAS — saqlanadi, lekin planner'da
--    blok qilinmaydi (brifda ham shunday).
CREATE TABLE IF NOT EXISTS public.namoz_times (
  region      text NOT NULL,
  date        date NOT NULL,
  fajr        text NOT NULL,   -- bomdod
  sunrise     text,            -- quyosh (namoz emas, ma'lumot uchun)
  dhuhr       text NOT NULL,   -- peshin
  asr         text NOT NULL,   -- asr
  maghrib     text NOT NULL,   -- shom
  isha        text NOT NULL,   -- xufton
  source      text NOT NULL DEFAULT 'unknown',
  fetched_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (region, date)
);

-- Format: HH:MM (24 soat). Buzuq matn keshga tushib, planner'ni chalkashtirmasin.
DO $$
DECLARE
  c text;
  re constant text := '^([01][0-9]|2[0-3]):[0-5][0-9]$';
BEGIN
  FOREACH c IN ARRAY ARRAY['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'namoz_times_' || c || '_ck') THEN
      EXECUTE format('ALTER TABLE public.namoz_times ADD CONSTRAINT %I CHECK (%I ~ %L)',
                     'namoz_times_' || c || '_ck', c, re);
    END IF;
  END LOOP;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'namoz_times_sunrise_ck') THEN
    ALTER TABLE public.namoz_times ADD CONSTRAINT namoz_times_sunrise_ck
      CHECK (sunrise IS NULL OR sunrise ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'namoz_times_region_ck') THEN
    ALTER TABLE public.namoz_times ADD CONSTRAINT namoz_times_region_ck CHECK (
      region IN (
        'toshkent', 'toshkent_v', 'andijon', 'buxoro', 'fargona', 'jizzax',
        'namangan', 'navoiy', 'qashqadaryo', 'samarqand', 'sirdaryo',
        'surxondaryo', 'xorazm', 'qoraqalpogiston'
      )
    );
  END IF;

  -- Tartib: bomdod < peshin < asr < shom < xufton. Bitta qatorda ham
  -- mantiqsiz ma'lumot yotmasin. Matn solishtiruvi 'HH:MM' (nol bilan
  -- to'ldirilgan) uchun to'g'ri ishlaydi.
  -- ⚠️ Bu O'zbekiston kengliklariga bog'liq: xufton yarim tundan keyinga
  --    o'tmaydi. Viloyat ro'yxati cheklangani uchun shart xavfsiz.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'namoz_times_order_ck') THEN
    ALTER TABLE public.namoz_times ADD CONSTRAINT namoz_times_order_ck
      CHECK (fajr < dhuhr AND dhuhr < asr AND asr < maghrib AND maghrib < isha);
  END IF;
END $$;

COMMENT ON TABLE public.namoz_times IS 'Namoz vaqtlari keshi (viloyat + sana). Manba: islomapi.uz, zaxira api.aladhan.com. TASKFIX_NAMOZ.sql';

-- ── 3) RLS ──────────────────────────────────────────────────────────────────
-- O'qish — har kim (vaqtlar ochiq ma'lumot, workspace'ga bog'liq emas).
-- Yozish/yangilash — har `authenticated`: keshni birinchi kelgan foydalanuvchi
-- to'ldiradi (server tomonda kron/EF yo'q).
--
-- 🔴 SHUNING UCHUN MIJOZ KESHGA ISHONMAYDI: `nmzValidTimes()` format, tartib
--    va mantiqiy oynani tekshiradi; o'tmasa qator e'tiborsiz qoldirilib,
--    vaqt API'dan qayta olinadi. CHECK'lar (yuqorida) birinchi to'siq.
ALTER TABLE public.namoz_times ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "namoz_times_select" ON public.namoz_times;
CREATE POLICY "namoz_times_select" ON public.namoz_times FOR SELECT TO authenticated
  USING ( true );

DROP POLICY IF EXISTS "namoz_times_insert" ON public.namoz_times;
CREATE POLICY "namoz_times_insert" ON public.namoz_times FOR INSERT TO authenticated
  WITH CHECK ( true );

DROP POLICY IF EXISTS "namoz_times_update" ON public.namoz_times;
CREATE POLICY "namoz_times_update" ON public.namoz_times FOR UPDATE TO authenticated
  USING ( true ) WITH CHECK ( true );

-- O'chirish policy'si ATAYLAB YO'Q → hech kim o'chira olmaydi (RLS default rad).

-- ── 4) TEKSHIRUV (jimgina o'tmasin) ─────────────────────────────────────────
DO $$
DECLARE
  v_typ text;
BEGIN
  SELECT data_type INTO v_typ FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'namoz_enabled';
  IF v_typ IS DISTINCT FROM 'boolean' THEN
    RAISE EXCEPTION 'TEKSHIRUV: profiles.namoz_enabled yaratilmadi (turi: %).', COALESCE(v_typ, 'YO''Q');
  END IF;

  SELECT data_type INTO v_typ FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'namoz_region';
  IF v_typ NOT IN ('text', 'character varying') THEN
    RAISE EXCEPTION 'TEKSHIRUV: profiles.namoz_region yaratilmadi (turi: %).', COALESCE(v_typ, 'YO''Q');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_namoz_region_ck') THEN
    RAISE EXCEPTION 'TEKSHIRUV: profiles_namoz_region_ck qo''shilmadi.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'public' AND c.relname = 'namoz_times') THEN
    RAISE EXCEPTION 'TEKSHIRUV: public.namoz_times yaratilmadi.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public'
                  AND tablename = 'namoz_times' AND rowsecurity) THEN
    RAISE EXCEPTION 'TEKSHIRUV: namoz_times uchun RLS yoqilmadi.';
  END IF;
  IF (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'namoz_times') <> 3 THEN
    RAISE EXCEPTION 'TEKSHIRUV: namoz_times policy''lari to''liq emas (3 ta bo''lishi kerak).';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
              AND tablename = 'namoz_times' AND cmd = 'DELETE') THEN
    RAISE EXCEPTION 'TEKSHIRUV: namoz_times uchun DELETE policy paydo bo''ldi — o''chirish yopiq bo''lishi kerak.';
  END IF;
END $$;

-- ── 5) TIRIK TEST — CHECK'lar haqiqatan tutadimi? ───────────────────────────
DO $$
DECLARE
  v_ok boolean;
BEGIN
  -- To'g'ri qator o'tishi kerak
  INSERT INTO public.namoz_times (region, date, fajr, sunrise, dhuhr, asr, maghrib, isha, source)
  VALUES ('toshkent', DATE '1990-01-01', '05:30', '07:00', '12:30', '15:30', '17:30', '19:00', 'selftest');
  IF NOT EXISTS (SELECT 1 FROM public.namoz_times WHERE region = 'toshkent' AND date = DATE '1990-01-01') THEN
    RAISE EXCEPTION 'TIRIK TEST: to''g''ri qator yozilmadi.';
  END IF;

  -- Buzuq format RAD ETILISHI kerak
  v_ok := false;
  BEGIN
    INSERT INTO public.namoz_times (region, date, fajr, dhuhr, asr, maghrib, isha)
    VALUES ('toshkent', DATE '1990-01-02', '25:99', '12:30', '15:30', '17:30', '19:00');
  EXCEPTION WHEN check_violation THEN v_ok := true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TIRIK TEST: buzuq vaqt formati o''tib ketdi.'; END IF;

  -- Teskari tartib RAD ETILISHI kerak
  v_ok := false;
  BEGIN
    INSERT INTO public.namoz_times (region, date, fajr, dhuhr, asr, maghrib, isha)
    VALUES ('toshkent', DATE '1990-01-03', '19:00', '12:30', '15:30', '17:30', '05:30');
  EXCEPTION WHEN check_violation THEN v_ok := true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TIRIK TEST: teskari tartib o''tib ketdi.'; END IF;

  -- Noma'lum viloyat RAD ETILISHI kerak
  v_ok := false;
  BEGIN
    INSERT INTO public.namoz_times (region, date, fajr, dhuhr, asr, maghrib, isha)
    VALUES ('parij', DATE '1990-01-04', '05:30', '12:30', '15:30', '17:30', '19:00');
  EXCEPTION WHEN check_violation THEN v_ok := true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TIRIK TEST: noma''lum viloyat o''tib ketdi.'; END IF;

  -- profiles CHECK'i ham tutadimi?
  v_ok := false;
  BEGIN
    UPDATE public.profiles SET namoz_region = 'parij' WHERE id = (SELECT id FROM public.profiles LIMIT 1);
  EXCEPTION WHEN check_violation THEN v_ok := true;
  END;
  IF NOT v_ok AND EXISTS (SELECT 1 FROM public.profiles) THEN
    RAISE EXCEPTION 'TIRIK TEST: profiles.namoz_region noma''lum qiymatni qabul qildi.';
  END IF;

  -- Test qatorini tozalaymiz (skript o'zidan keyin iz qoldirmasin)
  DELETE FROM public.namoz_times WHERE source = 'selftest';
  RAISE NOTICE 'TIRIK TEST: OK.';
END $$;

-- ── 6) Hisobot ──────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_on bigint; v_reg bigint; v_cache bigint;
BEGIN
  SELECT count(*) FILTER (WHERE namoz_enabled), count(*) FILTER (WHERE namoz_region IS NOT NULL)
    INTO v_on, v_reg FROM public.profiles;
  SELECT count(*) INTO v_cache FROM public.namoz_times;
  RAISE NOTICE '───────────────────────────────────────────';
  RAISE NOTICE 'Namoz yoqilgan foydalanuvchi: %  ·  viloyat tanlagan: %', v_on, v_reg;
  RAISE NOTICE 'Keshdagi kun: %', v_cache;
  RAISE NOTICE 'TAYYOR: Planner → "Musulmon" toggle''ini yoqing.';
END $$;

COMMIT;

-- ============================================================================
-- QAYTARISH (kerak bo'lsa):
--   DROP TABLE IF EXISTS public.namoz_times;
--   ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_namoz_region_ck;
--   ALTER TABLE public.profiles DROP COLUMN IF EXISTS namoz_enabled,
--                               DROP COLUMN IF EXISTS namoz_region;
-- ============================================================================
