-- ============================================================
-- 45_staff_phone_lookup.sql
-- Telefon bo'yicha qidirish — import dublikat identitet yaratmasin.
--
-- MUAMMO (o'lchangan, taxmin emas):
--   Import mavjud odamni FAQAT sintetik email bo'yicha qidiradi
--   (auth_user_id_by_email, 40:109). Sintetik email telefondan hosil
--   bo'ladi: '998930702425@staff.taskfix.org'. Haqiqiy emaili bor odam
--   ('feruzbek2295002@gmail.com') hech qachon topilmaydi → unga IKKINCHI
--   akkaunt yaratiladi.
--
-- ⚠️ NEGA BU FAYL O'ZI YETARLI EMAS:
--   Odamning haqiqiy telefoni auth.users.phone da EMAS — u yerda bo'lganida
--   createUser "already registered" berardi va import xato bilan to'xtardi.
--   Bermagan. Haqiqiy telefon public.profiles.phone da, va u ERKIN MATN
--   (setProfPhone 3483, edtPhone 10351, Jamoa inline tahriri 9836 — hammasi
--   faqat .trim() qiladi).
--
--   Shuning uchun ASOSIY moslashtirish MIJOZ preflight'ida, profiles.phone
--   bo'yicha bo'lishi KERAK (u service_role talab qilmaydi — EF'ning o'z
--   qoidasi, index.ts:10-15).
--
--   ⛔ OGOHLANTIRISH — U MOSLASHTIRISH HALI YOZILMAGAN (2026-07-17 holati).
--      hrImportPreflight() da 1-6 bosqich bor, telefon bo'yicha mavjud
--      foydalanuvchini topish bosqichi YO'Q. Ya'ni bugun qayta import
--      qilinsa — dublikat YANA yaratiladi. Bu fayl o'zi buni to'smaydi.
--
--   Bu yerdagi funksiyalar hozircha ikki TOR vazifa uchun:
--
--     1) cleanup_duplicate_staff.sql juftlikni SHU normalizatsiya bilan topadi
--     2) EF createUser "telefon band" desa, xato matni kim bilan to'qnashganini
--        aytsin ("qo'lda tekshiring" o'rniga)
--
--   ⚠️ auth_user_id_by_phone() AVTOMATIK ADOPT uchun EMAS. Adopt qarori ism
--   tekshiruvini ham talab qiladi (kelishilgan: telefon mos + ism mos emas →
--   bloker, jimgina bog'lamaydi). Bu funksiya ism haqida hech nima bilmaydi.
--
-- Tartib: 38 → 39 → 40 → 41 → 45. (Bu fayl HALI ISHGA TUSHIRILMAGAN.)
--
-- Band raqamlar: 42 = lavozimlar seed (ishga tushirilgan), 43 = ish jadvali
-- (monthly_off_*, hali yozilmagan), 44 = storage RLS (ishga tushirilgan).
-- ⚠️ 42 va 44 REPODA YO'Q — ular bazada bor, lekin fayli saqlanmagan.
-- ============================================================

-- ── 0) Oldindan tekshiruv ───────────────────────────────────
-- 40 bo'lmasa auth_user_id_by_email ham yo'q — demak import infratuzilmasi
-- umuman qo'yilmagan va bu fayl mantiqsiz.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'auth_user_id_by_email' AND n.nspname = 'public'
  ) THEN
    RAISE EXCEPTION 'auth_user_id_by_email() topilmadi. Avval 40_staff_import.sql ni ishga tushiring.';
  END IF;
END $$;

-- ── 1) Telefonni normallashtirish ───────────────────────────
-- index.html:10805-10813 (hrImportNormPhone) ning AYNAN nusxasi:
--   • raqam bo'lmagan hamma belgi tashlanadi
--   • 9 raqam           → '998' qo'shiladi   (901234567 → milliy)
--   • 12 raqam, '998'   → o'zi
--   • 11 raqam, '98'    → '9' qo'shiladi     (998 dan bitta 9 tushib qolgan)
--   • so'ng E.164 shakli tekshiriladi (JS: /^\+[1-9]\d{7,14}$/)
--
-- Shakl tekshiruvidan o'tmasa NULL qaytadi — ATAYLAB. Shunda taqqoslash
-- (norm(a) = norm(b)) axlat qiymatlarda NULL beradi, ya'ni MOS KELMAYDI.
-- '123' va '123' ni bir odam deb hisoblab qo'ymaymiz.
--
-- ⚠️ Bu mantiq ikki joyda yashaydi (JS va SQL). Birini o'zgartirsangiz —
-- ikkinchisini ham. Aks holda mijoz bir odamni topadi, tozalash skripti boshqasini.
CREATE OR REPLACE FUNCTION norm_phone_digits(p TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN d2 ~ '^[1-9][0-9]{7,14}$' THEN d2 ELSE NULL END
  FROM (
    SELECT CASE
      WHEN length(d) = 9                          THEN '998' || d
      WHEN length(d) = 12 AND left(d, 3) = '998'  THEN d
      WHEN length(d) = 11 AND left(d, 2) = '98'   THEN '9' || d
      ELSE d
    END AS d2
    -- '[^0-9]' — '\D' emas: bir xil ishlaydi, lekin qochirish qoidalariga
    -- (standard_conforming_strings) umuman bog'liq emas.
    FROM (SELECT regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') AS d) t1
  ) t2;
$$;

COMMENT ON FUNCTION norm_phone_digits(TEXT) IS
  'Telefon → E.164 raqamlari (+ siz). index.html:10800 hrImportNormPhone bilan bir xil bo''lishi SHART.';

-- ── 2) auth.users da telefon bo'yicha qidirish ──────────────
-- FAQAT auth.users.phone ni ko'radi. profiles.phone ni QASDDAN ko'rmaydi:
-- bu funksiya EF uchun, EF esa createUser to'qnashuvini tushuntirishi kerak,
-- to'qnashuv esa aynan auth.users.phone unikalligidan kelib chiqadi.
--
-- Indeks yo'q — har qatorda funksiya hisoblanadi. auth.users kichik
-- (yuzlab qator), va bu import'da qator boshiga ko'pi bilan bir marta,
-- faqat XATO yo'lida chaqiriladi. Optimallashtirish kerak emas.
CREATE OR REPLACE FUNCTION auth_user_id_by_phone(p_phone TEXT)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth
AS $$
  SELECT u.id FROM auth.users u
  WHERE norm_phone_digits(p_phone) IS NOT NULL
    AND norm_phone_digits(u.phone) = norm_phone_digits(p_phone)
  LIMIT 1;
$$;

-- XAVFSIZLIK: 40:119-124 bilan bir xil sabab — bu telefon bo'yicha ro'yxatni
-- tekshirish (enumeration) vositasi bo'lib qolmasin.
REVOKE ALL ON FUNCTION auth_user_id_by_phone(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION auth_user_id_by_phone(TEXT) FROM anon;
REVOKE ALL ON FUNCTION auth_user_id_by_phone(TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION auth_user_id_by_phone(TEXT) TO service_role;

-- norm_phone_digits — sof matn funksiyasi, hech qanday ma'lumotga tegmaydi.
-- Cheklash KERAK EMAS: tozalash skripti (postgres roli) va kelajakdagi
-- so'rovlar uni erkin chaqira olsin.

-- ── 3) Tekshiruv ────────────────────────────────────────────
-- Dastlabki uch qator ham 998930702425 chiqishi kerak — ya'ni erkin matn holida
-- yozilgan telefon manbadagi E.164 bilan mos tushadi. Aynan shu Feruzbekni topadi.
-- Oxirgi ikkitasi NULL bo'lsin: axlat qiymat hech kim bilan mos kelmasin.
SELECT
  norm_phone_digits('+998930702425')   AS e164,
  norm_phone_digits('93 070 24 25')    AS milliy_probel,
  norm_phone_digits('+998 93 070-24-25') AS aralash,
  norm_phone_digits('123')             AS axlat_null_bolsin,
  norm_phone_digits(NULL)              AS null_null_bolsin;
