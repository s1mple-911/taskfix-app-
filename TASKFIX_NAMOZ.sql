-- ============================================================================
-- TASKFIX_NAMOZ.sql — Namoz vaqtlari (Planner) · 2026-08-08 (yang. 2026-08-09)
-- ============================================================================
-- ADDITIVE + IDEMPOTENT: mavjud jadval/ustunlarga TEGMAYDI. Qo'shadi:
--   1) public.profiles  → namoz_enabled (toggle), namoz_region (viloyat),
--                         namoz_lat/namoz_lon (ANIQ joylashuv — shahar aniqligi)
--   2) public.namoz_times → kunlik kesh (region + geo + sana → 5 vaqt)
--
-- ⚠️ QAYTA ISHGA TUSHIRISH XAVFSIZ VA KERAK: 2026-08-09 da koordinata
--    ustunlari va `namoz_times.geo` qo'shildi. Fayl avvalgi tahrirda
--    bajarilgan bo'lsa ham, quyidagi bloklar yetishmaganini qo'shadi va
--    birlamchi kalitni (region, geo, date) ga ko'chiradi.
--
-- ⚠️ BU FAYL ISHGA TUSHMASA — ilova YIQILMAYDI: planner avvalgidek ishlaydi,
--    "Muslim" toggle'i esa "SQL ishga tushirilmagan" deb ochiq aytadi.
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

-- ── 1b) ANIQ JOYLASHUV (2026-08-09) ─────────────────────────────────────────
-- Viloyat markazi 1–2 daqiqa xato beradi (Qarshi'dagi odam Qashqadaryo
-- markazining vaqtini olardi). aladhan koordinata bilan ishlaydi, shuning
-- uchun foydalanuvchining O'Z koordinatasi saqlanadi.
--   • NULL = koordinata yo'q → viloyat markazi ishlatiladi (avvalgi xatti-harakat);
--   • viloyat ustuni QOLADI — ko'rsatish uchun va islomapi (viloyat bilan
--     ishlaydigan zaxira manba) uchun kerak.
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS namoz_lat double precision;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS namoz_lon double precision;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_namoz_geo_ck') THEN
    ALTER TABLE public.profiles ADD CONSTRAINT profiles_namoz_geo_ck CHECK (
      -- Ikkovi ham bo'sh yoki ikkovi ham to'la va mantiqiy oraliqda
      (namoz_lat IS NULL) = (namoz_lon IS NULL)
      AND (namoz_lat IS NULL OR (namoz_lat BETWEEN -90 AND 90 AND namoz_lon BETWEEN -180 AND 180))
    );
  END IF;
END $$;

COMMENT ON COLUMN public.profiles.namoz_enabled IS 'Planner''da namoz vaqtlari ko''rsatilsinmi ("Muslim" toggle). TASKFIX_NAMOZ.sql';
COMMENT ON COLUMN public.profiles.namoz_region  IS 'Viloyat slug''i (14 qiymat). NULL = hali tanlanmagan. Ko''rsatish + islomapi uchun.';
COMMENT ON COLUMN public.profiles.namoz_lat     IS 'Foydalanuvchining aniq kengligi (shahar aniqligi). NULL = viloyat markazi ishlatiladi.';
COMMENT ON COLUMN public.profiles.namoz_lon     IS 'Foydalanuvchining aniq uzunligi. namoz_lat bilan birga to''ladi yoki ikkovi ham NULL.';

-- ── 2) Kunlik kesh ──────────────────────────────────────────────────────────
-- Bitta (viloyat, sana) = bitta qator. Bir odam olib kelsa, qolganlarga
-- API'ga chiqish shart emas.
--
-- ⚠️ `sunrise` (quyosh chiqishi) NAMOZ EMAS — saqlanadi, lekin planner'da
--    blok qilinmaydi (brifda ham shunday).
-- ⚠️ `geo` (2026-08-09): '' = viloyat markazi bo'yicha (islomapi), aks holda
--    yaxlitlangan koordinata "38.85,65.80" (aladhan, shahar aniqligi).
--    Kalitning bir qismi — aks holda Qarshi'dagi odamning vaqti Qashqadaryo
--    markazidagi odamga (va aksincha) berilib ketardi.
--    0.05° ≈ 5.5 km ≈ 12 soniya farq — bir shahar aholisi bitta keshni
--    baham ko'radi, lekin qo'shni shahar aralashmaydi.
CREATE TABLE IF NOT EXISTS public.namoz_times (
  region      text NOT NULL,
  geo         text NOT NULL DEFAULT '',
  date        date NOT NULL,
  fajr        text NOT NULL,   -- bomdod
  sunrise     text,            -- quyosh (namoz emas, ma'lumot uchun)
  dhuhr       text NOT NULL,   -- peshin
  asr         text NOT NULL,   -- asr
  maghrib     text NOT NULL,   -- shom
  isha        text NOT NULL,   -- xufton
  source      text NOT NULL DEFAULT 'unknown',
  fetched_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (region, geo, date)
);

-- Fayl AVVALGI tahrirda (geo'siz) ishga tushirilgan bo'lsa — ustunni qo'shib,
-- kalitni qayta quramiz. Yangi o'rnatishda bu blok hech nima qilmaydi.
-- ⚠️ Dublikat xavfi yo'q: eski kalit (region, date) edi, geo esa '' bo'lib
--    to'ladi → (region, '', date) baribir yagona.
DO $$
BEGIN
  ALTER TABLE public.namoz_times ADD COLUMN IF NOT EXISTS geo text NOT NULL DEFAULT '';

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
     WHERE c.conrelid = 'public.namoz_times'::regclass AND c.contype = 'p' AND a.attname = 'geo'
  ) THEN
    ALTER TABLE public.namoz_times DROP CONSTRAINT IF EXISTS namoz_times_pkey;
    ALTER TABLE public.namoz_times ADD PRIMARY KEY (region, geo, date);
    RAISE NOTICE 'namoz_times: birlamchi kalit (region, geo, date) ga ko''chirildi.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'namoz_times_geo_ck') THEN
    ALTER TABLE public.namoz_times ADD CONSTRAINT namoz_times_geo_ck
      CHECK (geo = '' OR geo ~ '^-?[0-9]{1,3}(\.[0-9]{1,4})?,-?[0-9]{1,3}(\.[0-9]{1,4})?$');
  END IF;
END $$;

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

  -- Aniq joylashuv (2026-08-09)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'profiles'
                    AND column_name IN ('namoz_lat', 'namoz_lon')
                  HAVING count(*) = 2) THEN
    RAISE EXCEPTION 'TEKSHIRUV: profiles.namoz_lat/namoz_lon yaratilmadi.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_namoz_geo_ck') THEN
    RAISE EXCEPTION 'TEKSHIRUV: profiles_namoz_geo_ck qo''shilmadi.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'namoz_times_geo_ck') THEN
    RAISE EXCEPTION 'TEKSHIRUV: namoz_times_geo_ck qo''shilmadi.';
  END IF;
  -- Birlamchi kalit geo ni qamrab olishi SHART (aks holda qo'shni shaharlar
  -- bir-birining vaqtini olib ketardi)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
     WHERE c.conrelid = 'public.namoz_times'::regclass AND c.contype = 'p' AND a.attname = 'geo'
  ) THEN
    RAISE EXCEPTION 'TEKSHIRUV: namoz_times birlamchi kaliti geo ni qamramadi.';
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

  -- Bir viloyat, ikki xil geo — IKKALASI ham yotishi kerak (qo'shni shaharlar)
  INSERT INTO public.namoz_times (region, geo, date, fajr, dhuhr, asr, maghrib, isha, source)
  VALUES ('qashqadaryo', '38.85,65.80', DATE '1990-01-05', '05:31', '12:31', '15:31', '17:31', '19:01', 'selftest'),
         ('qashqadaryo', '38.75,66.05', DATE '1990-01-05', '05:30', '12:30', '15:30', '17:30', '19:00', 'selftest');
  IF (SELECT count(*) FROM public.namoz_times
       WHERE region = 'qashqadaryo' AND date = DATE '1990-01-05') <> 2 THEN
    RAISE EXCEPTION 'TIRIK TEST: geo kalitning bir qismi emas — qo''shni shaharlar bir-birini bosdi.';
  END IF;

  -- Buzuq geo RAD ETILISHI kerak
  v_ok := false;
  BEGIN
    INSERT INTO public.namoz_times (region, geo, date, fajr, dhuhr, asr, maghrib, isha, source)
    VALUES ('toshkent', 'qarshi', DATE '1990-01-06', '05:30', '12:30', '15:30', '17:30', '19:00', 'selftest');
  EXCEPTION WHEN check_violation THEN v_ok := true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TIRIK TEST: buzuq geo qiymati o''tib ketdi.'; END IF;

  -- Yarim to'ldirilgan koordinata RAD ETILISHI kerak
  v_ok := false;
  BEGIN
    UPDATE public.profiles SET namoz_lat = 41.3, namoz_lon = NULL
     WHERE id = (SELECT id FROM public.profiles LIMIT 1);
  EXCEPTION WHEN check_violation THEN v_ok := true;
  END;
  IF NOT v_ok AND EXISTS (SELECT 1 FROM public.profiles) THEN
    RAISE EXCEPTION 'TIRIK TEST: yarim to''ldirilgan koordinata o''tib ketdi.';
  END IF;

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
  RAISE NOTICE 'TAYYOR: Planner → "Muslim" toggle''ini yoqing.';
END $$;

COMMIT;

-- ============================================================================
-- QAYTARISH (kerak bo'lsa):
--   DROP TABLE IF EXISTS public.namoz_times;
--   ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_namoz_region_ck;
--   ALTER TABLE public.profiles DROP COLUMN IF EXISTS namoz_enabled,
--                               DROP COLUMN IF EXISTS namoz_region;
-- ============================================================================
