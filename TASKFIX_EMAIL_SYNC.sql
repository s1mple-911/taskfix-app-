-- ============================================================================
-- TASKFIX_EMAIL_SYNC.sql — profiles.email ni auth.users.email bilan sinxron
-- ============================================================================
-- MUAMMO: ilova email'ni FAQAT public.profiles.email dan o'qiydi
--         (loadCurrentContext → profiles.select('… , email')), lekin foydalanuvchi
--         yaratilganda auth.users.email profil qatoriga KO'CHMAGAN → ustun NULL →
--         UI'da email bo'sh ko'rinadi (masalan sherdil8882@gmail.com).
--
-- YECHIM — 2 qatlam:
--   (1) BIR MARTALIK BACKFILL — bo'sh (NULL yoki '') profiles.email lar
--       auth.users.email dan to'ldiriladi.
--   (2) TRIGGER — auth.users ga INSERT / email UPDATE bo'lganda profiles.email
--       avtomat yoziladi. Kelajakda bo'sh qolmaydi.
--   (3-qatlam ilovada: mijoz kirganda o'z profilidagi bo'sh email'ni
--       me.email dan to'ldiradi — bu fayl ishga tushmasa ham o'zini davolaydi.)
--
-- ADDITIVE + IDEMPOTENT: jadval/ustun O'CHIRMAYDI, mavjud trigger'larga
-- (handle_new_user va h.k.) TEGMAYDI — o'z nomli ALOHIDA trigger qo'shadi.
-- Qayta ishga tushirsa ham xavfsiz.
--
-- ⚠️ auth.users — himoyalangan sxema. Bu skript Supabase SQL Editor'da
--    (postgres/supabase_admin roli bilan) ishga tushirilishi kerak.
--    auth.users ga hech qanday YOZUV qilinmaydi — faqat SELECT + trigger.
--    Agar "must be owner of relation users" xatosi chiqsa — SQL Editor emas,
--    boshqa (kamroq huquqli) rol bilan ishlatilgan; postgres roli bilan qayta
--    urinib ko'ring. Skript BITTA tranzaksiya: xato bo'lsa hech nima o'zgarmaydi.
--
-- ⚠️ XAVFSIZLIK: SECURITY DEFINER yordamchi funksiya (auth.users ni o'qish/
--    profiles ga yozish uchun kerak) `anon`/`authenticated` dan REVOKE qilinadi
--    — aks holda oddiy foydalanuvchi boshqa odamning email'ini yoza olardi.
--
-- ⚠️ Trigger nomi ATAYLAB `zz_` bilan boshlanadi: Postgres bir xil hodisadagi
--    trigger'larni NOM TARTIBIDA ishga tushiradi. Shunda mavjud
--    `on_auth_user_created` (handle_new_user) BIRINCHI ishlaydi va profil
--    qatorini o'zi yaratadi; biznikisi undan KEYIN faqat email'ni yozadi
--    (aks holda bizning INSERT o'sha trigger'ning INSERT'ini 23505 bilan
--    yiqitib, ro'yxatdan o'tishni buzishi mumkin edi).
-- ============================================================================

BEGIN;

-- ── 0) Oldindan tekshiruv ───────────────────────────────────────────────────
DO $$
DECLARE
  v_typ text;
  v_bad text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'public' AND c.relname = 'profiles') THEN
    RAISE EXCEPTION 'public.profiles topilmadi — noto''g''ri baza?';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'auth' AND c.relname = 'users') THEN
    RAISE EXCEPTION 'auth.users topilmadi — bu Supabase bazasi emasmi?';
  END IF;

  -- profiles.email ustuni bormi va matnmi?
  SELECT data_type INTO v_typ
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'email';
  IF v_typ IS NULL THEN
    RAISE EXCEPTION 'public.profiles.email ustuni yo''q — ilova email''ni shu ustundan o''qiydi. Avval ustunni qo''shing.';
  END IF;
  IF v_typ NOT IN ('text', 'character varying') THEN
    RAISE EXCEPTION 'public.profiles.email turi kutilmagan: % (text/varchar bo''lishi kerak)', v_typ;
  END IF;

  -- auth.users ni o'qiy olamizmi? (huquq yetmasa — darrov va aniq aytamiz)
  BEGIN
    PERFORM 1 FROM auth.users LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE EXCEPTION 'auth.users o''qilmadi (huquq yo''q). Skriptni Supabase SQL Editor''da (postgres roli) ishga tushiring.';
  END;

  -- profiles da NOT NULL + DEFAULT'siz ustunlar bo'lsa, trigger'ning INSERT yo'li
  -- (profil qatori umuman yo'q holat) ishlamaydi — bu HALOKAT emas, ogohlantiramiz.
  SELECT string_agg(column_name, ', ') INTO v_bad
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'profiles'
     AND is_nullable = 'NO' AND column_default IS NULL
     AND column_name NOT IN ('id', 'email');
  IF v_bad IS NOT NULL THEN
    RAISE NOTICE 'ESLATMA: profiles da NOT NULL + defaultsiz ustun(lar) bor: %. Profil qatori YO''Q bo''lsa trigger uni yarata olmaydi — qatorni handle_new_user yoki ilova yaratadi, trigger keyin email''ni yozadi.', v_bad;
  END IF;
END $$;

-- ── 1) Diagnostika (OLDIN) ──────────────────────────────────────────────────
DO $$
DECLARE
  v_total    bigint;
  v_empty    bigint;
  v_fixable  bigint;
  v_noprof   bigint;
  v_trg      text;
BEGIN
  SELECT count(*) INTO v_total FROM public.profiles;
  SELECT count(*) INTO v_empty FROM public.profiles p
   WHERE p.email IS NULL OR btrim(p.email) = '';
  SELECT count(*) INTO v_fixable
    FROM public.profiles p JOIN auth.users u ON u.id = p.id
   WHERE (p.email IS NULL OR btrim(p.email) = '')
     AND u.email IS NOT NULL AND btrim(u.email) <> '';
  SELECT count(*) INTO v_noprof
    FROM auth.users u LEFT JOIN public.profiles p ON p.id = u.id
   WHERE p.id IS NULL;

  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_trg
    FROM pg_trigger t
   WHERE t.tgrelid = 'auth.users'::regclass AND NOT t.tgisinternal;

  RAISE NOTICE '── OLDIN ──────────────────────────────────';
  RAISE NOTICE 'profiles jami:                 %', v_total;
  RAISE NOTICE 'email bo''sh:                   %', v_empty;
  RAISE NOTICE '  shundan auth''dan tuzatiladi: %', v_fixable;
  RAISE NOTICE 'auth.users da bor, profili YO''Q: %  (ilova kirganda o''zi yaratadi)', v_noprof;
  RAISE NOTICE 'auth.users dagi mavjud trigger''lar: %', COALESCE(v_trg, '(yo''q)');
END $$;

-- ── 1b) UNIQUE to'qnashuvi bo'ladimi? ───────────────────────────────────────
-- Agar profiles.email da UNIQUE indeks bo'lsa, backfill ikki xil yo'l bilan
-- yiqilishi mumkin: (a) auth'da bir xil email ikki userda (bo'lmasligi kerak),
-- (b) allaqachon boshqa profilda o'sha email bor. Jimgina yiqilmasin — oldindan
-- aniq xabar beramiz.
DO $$
DECLARE
  v_uniq boolean;
  v_conf bigint;
  v_list text;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_index i
      JOIN pg_class c   ON c.oid = i.indrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY (i.indkey)
     WHERE n.nspname = 'public' AND c.relname = 'profiles'
       AND i.indisunique AND a.attname = 'email'
       AND i.indnatts = 1
  ) INTO v_uniq;

  IF NOT v_uniq THEN
    RAISE NOTICE 'profiles.email da UNIQUE indeks yo''q — to''qnashuv xavfi yo''q.';
    RETURN;
  END IF;

  SELECT count(*), string_agg(DISTINCT lower(u.email), ', ') INTO v_conf, v_list
    FROM public.profiles p
    JOIN auth.users u ON u.id = p.id
    JOIN public.profiles q ON q.id <> p.id AND lower(q.email) = lower(u.email)
   WHERE (p.email IS NULL OR btrim(p.email) = '')
     AND u.email IS NOT NULL AND btrim(u.email) <> '';

  IF v_conf > 0 THEN
    RAISE EXCEPTION 'profiles.email UNIQUE, lekin % ta email boshqa profilda band: %. Avval dublikatlarni birlashtiring (TASKFIX_MERGE_*.sql).', v_conf, v_list;
  END IF;
  RAISE NOTICE 'profiles.email UNIQUE — to''qnashuv topilmadi.';
END $$;

-- ── 2) Yagona choke-point: email yozuvchi yordamchi ─────────────────────────
-- Backfill ham, trigger ham SHU funksiyani chaqiradi — mantiq bitta joyda.
-- SECURITY DEFINER: trigger auth kontekstida ishlaydi, profiles RLS'i to'smasin.
CREATE OR REPLACE FUNCTION public.tf_set_profile_email(p_id uuid, p_email text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Bo'sh email profildagi mavjud qiymatni O'CHIRMASIN (telefon bilan
  -- ro'yxatdan o'tgan foydalanuvchida auth.email NULL bo'lishi mumkin).
  IF p_id IS NULL OR p_email IS NULL OR btrim(p_email) = '' THEN
    RETURN;
  END IF;

  INSERT INTO public.profiles AS pr (id, email)
       VALUES (p_id, lower(btrim(p_email)))
  ON CONFLICT (id) DO UPDATE
     SET email = EXCLUDED.email
   WHERE pr.email IS DISTINCT FROM EXCLUDED.email;
END $$;

-- Oddiy foydalanuvchi CHAQIRA OLMASIN (aks holda begona profilga email yozardi)
REVOKE ALL ON FUNCTION public.tf_set_profile_email(uuid, text) FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.tf_set_profile_email(uuid, text) FROM anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.tf_set_profile_email(uuid, text) FROM authenticated';
  END IF;
END $$;

COMMENT ON FUNCTION public.tf_set_profile_email(uuid, text) IS
  'profiles.email ni yozadi (bo''sh qiymat e''tiborsiz). auth.users trigger''i va backfill shu yerdan o''tadi. TASKFIX_EMAIL_SYNC.sql';

-- ── 3) BIR MARTALIK BACKFILL ────────────────────────────────────────────────
-- Bo'sh (NULL yoki '') email lar auth.users dan to'ldiriladi. Mavjud (to'ldirilgan)
-- email USTIGA YOZILMAYDI — masalan admin-import-staff "connect" bilan
-- almashtirgan haqiqiy email saqlanib qoladi.
DO $$
DECLARE
  v_n bigint;
BEGIN
  WITH upd AS (
    UPDATE public.profiles p
       SET email = lower(btrim(u.email))
      FROM auth.users u
     WHERE u.id = p.id
       AND (p.email IS NULL OR btrim(p.email) = '')
       AND u.email IS NOT NULL AND btrim(u.email) <> ''
    RETURNING p.id
  )
  SELECT count(*) INTO v_n FROM upd;
  RAISE NOTICE 'BACKFILL: % ta profil email''i to''ldirildi.', v_n;
END $$;

-- ── 4) Trigger: auth.users → profiles.email ─────────────────────────────────
-- ⚠️ auth.users dagi trigger XATO BERSA foydalanuvchi yaratish/kirish BUZILADI.
--    Shuning uchun butun tana EXCEPTION bloki ichida: har qanday xato
--    WARNING'ga aylanadi, auth oqimi to'xtamaydi (email keyin backfill/mijoz
--    tomonidan tuzatiladi).
CREATE OR REPLACE FUNCTION public.tf_auth_email_to_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  BEGIN
    PERFORM public.tf_set_profile_email(NEW.id, NEW.email);
  EXCEPTION WHEN OTHERS THEN
    -- Jimgina yutmaymiz — log'da ko'rinadi; lekin auth'ni yiqitmaymiz.
    RAISE WARNING 'tf_auth_email_to_profile(%): %', NEW.id, SQLERRM;
  END;
  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.tf_auth_email_to_profile() IS
  'auth.users trigger''i: yangi user / email o''zgarganda profiles.email ni yangilaydi. TASKFIX_EMAIL_SYNC.sql';

DROP TRIGGER IF EXISTS zz_tf_auth_email_to_profile ON auth.users;
CREATE TRIGGER zz_tf_auth_email_to_profile
AFTER INSERT OR UPDATE OF email ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.tf_auth_email_to_profile();

-- ── 5) TEKSHIRUV (jimgina o'tmasin) ─────────────────────────────────────────
DO $$
DECLARE
  v_left  bigint;
  v_trg   boolean;
  v_enab  char;
BEGIN
  -- 5a) Backfill'dan keyin tuzatilishi kerak bo'lgan qator QOLMASIN
  SELECT count(*) INTO v_left
    FROM public.profiles p JOIN auth.users u ON u.id = p.id
   WHERE (p.email IS NULL OR btrim(p.email) = '')
     AND u.email IS NOT NULL AND btrim(u.email) <> '';
  IF v_left > 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV: backfill''dan keyin ham % ta profil email''i bo''sh qoldi.', v_left;
  END IF;

  -- 5b) Trigger o'rnatildimi va YOQIQmi?
  SELECT true, t.tgenabled INTO v_trg, v_enab
    FROM pg_trigger t
   WHERE t.tgrelid = 'auth.users'::regclass
     AND t.tgname = 'zz_tf_auth_email_to_profile';
  IF NOT COALESCE(v_trg, false) THEN
    RAISE EXCEPTION 'TEKSHIRUV: zz_tf_auth_email_to_profile trigger''i topilmadi.';
  END IF;
  IF v_enab = 'D' THEN
    RAISE EXCEPTION 'TEKSHIRUV: zz_tf_auth_email_to_profile trigger''i O''CHIRILGAN (disabled).';
  END IF;

  -- 5c) SECURITY DEFINER funksiya oddiy foydalanuvchiga OCHIQ QOLMASIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated')
     AND has_function_privilege('authenticated', 'public.tf_set_profile_email(uuid, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'TEKSHIRUV: tf_set_profile_email `authenticated` uchun ochiq qolgan (REVOKE ishlamadi).';
  END IF;
END $$;

-- ── 6) TIRIK TEST — mantiq haqiqatan ishlaydimi? ────────────────────────────
-- auth.users ga YOZMAYMIZ (himoyalangan jadval). O'rniga trigger chaqiradigan
-- AYNAN O'SHA funksiyani sinaymiz: mavjud bitta profil email'ini bo'shatamiz →
-- funksiyani chaqiramiz → tiklandimi? Tranzaksiya ichida, keyin asliga qaytadi.
DO $$
DECLARE
  v_id    uuid;
  v_mail  text;
  v_after text;
BEGIN
  SELECT p.id, p.email INTO v_id, v_mail
    FROM public.profiles p JOIN auth.users u ON u.id = p.id
   WHERE p.email IS NOT NULL AND btrim(p.email) <> ''
   ORDER BY p.id
   LIMIT 1;

  IF v_id IS NULL THEN
    RAISE NOTICE 'TIRIK TEST: sinash uchun email''li profil topilmadi — o''tkazib yuborildi.';
    RETURN;
  END IF;

  UPDATE public.profiles SET email = NULL WHERE id = v_id;
  PERFORM public.tf_set_profile_email(v_id, v_mail);
  SELECT email INTO v_after FROM public.profiles WHERE id = v_id;

  IF v_after IS DISTINCT FROM lower(btrim(v_mail)) THEN
    RAISE EXCEPTION 'TIRIK TEST: email tiklanmadi (kutilgan %, olindi %).', lower(btrim(v_mail)), COALESCE(v_after, 'NULL');
  END IF;

  -- Bo'sh qiymat mavjudini O'CHIRMASLIGI kerak
  PERFORM public.tf_set_profile_email(v_id, NULL);
  PERFORM public.tf_set_profile_email(v_id, '   ');
  SELECT email INTO v_after FROM public.profiles WHERE id = v_id;
  IF v_after IS DISTINCT FROM lower(btrim(v_mail)) THEN
    RAISE EXCEPTION 'TIRIK TEST: bo''sh qiymat mavjud email''ni o''chirib yubordi.';
  END IF;

  -- Asl holatiga qaytaramiz (test qatorining yozuvi AYNAN avvalgidek qoladi)
  UPDATE public.profiles SET email = v_mail WHERE id = v_id;
  RAISE NOTICE 'TIRIK TEST: OK (%).', v_id;
END $$;

-- ── 7) Yakuniy hisobot ──────────────────────────────────────────────────────
DO $$
DECLARE
  v_total bigint;
  v_full  bigint;
  v_empty bigint;
BEGIN
  SELECT count(*) INTO v_total FROM public.profiles;
  SELECT count(*) INTO v_full  FROM public.profiles WHERE email IS NOT NULL AND btrim(email) <> '';
  v_empty := v_total - v_full;
  RAISE NOTICE '── KEYIN ──────────────────────────────────';
  RAISE NOTICE 'profiles jami: %  ·  email bor: %  ·  email bo''sh: %', v_total, v_full, v_empty;
  RAISE NOTICE 'Qolgan bo''shlar — auth.users da ham email yo''q (telefon/TG orqali kirgan) yoki profil qatori keyin yaratiladi.';
  RAISE NOTICE 'TAYYOR: zz_tf_auth_email_to_profile trigger''i yoqildi — bundan keyin email o''z-o''zidan ko''chadi.';
END $$;

COMMIT;

-- ============================================================================
-- QAYTARISH (kerak bo'lsa):
--   DROP TRIGGER IF EXISTS zz_tf_auth_email_to_profile ON auth.users;
--   DROP FUNCTION IF EXISTS public.tf_auth_email_to_profile();
--   DROP FUNCTION IF EXISTS public.tf_set_profile_email(uuid, text);
--   -- Backfill QAYTARILMAYDI (email'lar to'g'ri ma'lumot, o'chirish ma'nosiz).
-- ============================================================================
