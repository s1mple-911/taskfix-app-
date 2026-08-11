-- TASKFIX_LOYIHA_START.sql — "Loyiha boshlandi" xabari uchun BIR MARTALIK belgi
-- Asilbek RUN qiladi. ADDITIVE + IDEMPOTENT: mavjud ustun/ma'lumot buzilmaydi.
-- Qayta RUN xavfsiz (pastdagi 3-bandning ogohlantirishini o'qing).
--
-- 🔴 RUN TARTIBI (shu ketma-ketlikda):
--     1) TASKFIX_LOYIHA.sql      — start_at/end_at ustunlari (BUSIZ bu skript to'xtaydi).
--     2) TASKFIX_LOYIHA_RLS.sql  — a'zo loyiha QATORINI o'qiy olsin. Muhim: ilovadagi
--        ko'rsatish darvozasi (taskHiddenByStart) `projects` SELECT RLS'iga bog'liq —
--        a'zo loyiha qatorini ko'rmasa mijozda start_at bo'lmaydi va bosqich
--        o'sha a'zoga ko'rinib qolaveradi.
--     3) TASKFIX_LOYIHA_START.sql — shu fayl (faqat xabar belgisi).
--
-- MUAMMO (2026-08-11): start_at kelajakda bo'lgan loyihaning bosqichi bajaruvchiga
--   darrov ko'rinardi va unga xabar (Telegram/email) ketardi. To'g'ri mantiq:
--   loyiha boshlanmaguncha hamma bosqich yopiq; start_at kelgach — ketma-ket
--   (sequential) yoki birdan (parallel) ochiladi va AYNAN O'SHANDA xabar ketadi.
--
-- NIMA QO'SHILADI (public.projects ga):
--   1) start_notified_at timestamptz — "boshlanish xabari yuborilgan" belgisi.
--      NULL = hali yuborilmagan. Ilova uni OPTIMISTIK DA'VO bilan yozadi:
--        UPDATE projects SET start_notified_at = now()
--         WHERE id = :id AND start_notified_at IS NULL RETURNING id;
--      0 qator qaytsa — boshqa admin ulgurgan, xabar TAKRORLANMAYDI.
--   2) Qisman indeks idx_projects_start_pending — hali xabar yuborilmagan,
--      sanasi bor loyihalar (ro'yxat kichik; kelajakdagi cron/EF uchun ham foydali).
--
-- NIMA O'ZGARMAYDI:
--   • projects.status, start_at, end_at, recur_* — TEGILMAYDI.
--   • tasks jadvali, is_locked, hech qanday trigger/funksiya — TEGILMAYDI.
--   • RLS: yangi jadval yo'q → yangi policy KERAK EMAS (mavjud projects UPDATE
--     policy'si ishlaydi; ilova bu yozuvni faqat owner/admin uchun chaqiradi).
--
-- ILOVA BUSIZ HAM ISHLAYDI: ustun bo'lmasa mijoz buni aniqlaydi (prjNoStartCol)
--   va faqat "loyiha boshlandi" XABARI yuborilmaydi (aks holda loyiha har
--   ochilganda takroriy xabar ketardi). Sabab bir marta console'ga yoziladi.
--   ⚠️ KO'RINISHGA ta'siri YO'Q: bosqichlar `start_at` o'tishi bilan baribir
--   avtomat ko'rinadi — darvoza mijozda vaqt bo'yicha ishlaydi va `is_locked`
--   ga umuman yozmaydi. Bu ustun FAQAT bir martalik xabar uchun.

BEGIN;

-- ─────────────────────────────────────────────────────────────
-- 0) Old shartlar — jadval va start_at ustuni bormi?
--    start_at BO'LMASA bu skriptning ma'nosi yo'q (darvoza sanaga tayanadi).
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'projects'
  ) THEN
    RAISE EXCEPTION 'public.projects jadvali topilmadi — avval loyiha migratsiyasi (34) ishga tushirilishi kerak.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'projects' AND column_name = 'start_at'
  ) THEN
    RAISE EXCEPTION 'public.projects.start_at ustuni yo''q — avval TASKFIX_LOYIHA.sql ishga tushirilsin (bu skript o''sha sanaga tayanadi).';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 1) Ustun
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.projects ADD COLUMN IF NOT EXISTS start_notified_at timestamptz;

COMMENT ON COLUMN public.projects.start_notified_at IS
  'Loyiha boshlanishi (start_at) haqidagi bir martalik xabar QACHON yuborilgani. NULL = hali yuborilmagan. Ilova optimistik da''vo bilan yozadi (WHERE start_notified_at IS NULL) — ikki admin bir vaqtda ochsa ham xabar bir marta ketadi. Bo''ysunish/qulf mantig''iga TA''SIRI YO''Q.';

-- ─────────────────────────────────────────────────────────────
-- 2) Qisman indeks — "xabari kutilayotgan" loyihalar (odatda juda kam qator)
-- ─────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_projects_start_pending
  ON public.projects (start_at)
  WHERE start_notified_at IS NULL AND start_at IS NOT NULL;

-- ─────────────────────────────────────────────────────────────
-- 3) 🔴 BACKFILL — ALLAQACHON BOSHLANGAN loyihalar "xabari yuborilgan" deb
--    belgilanadi. BUSIZ: admin eski loyihani birinchi marta ochganda ilova uni
--    "endi boshlandi" deb o'qib, barcha ochiq bosqich egalariga TAKRORIY
--    (spam) xabar yuborardi. Kelajakda boshlanadigan loyihalarga tegilmaydi —
--    ular o'z vaqtida xabar oladi.
--    ⚠️ Qayta RUN qilish xavfsiz, lekin: 1-run'dan keyin boshlanib, admin hali
--       ochmagan loyiha 2-run'da "yuborilgan" deb belgilanadi va o'sha bitta
--       xabar o'tkazib yuboriladi (qulflar baribir ochiladi, vazifa ko'rinadi).
-- ─────────────────────────────────────────────────────────────
UPDATE public.projects
   SET start_notified_at = COALESCE(start_at, now())
 WHERE start_notified_at IS NULL
   AND start_at IS NOT NULL
   AND start_at <= now();

-- ─────────────────────────────────────────────────────────────
-- 4) Tekshiruv — jimgina o'tmasin
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_cnt int;
BEGIN
  -- 4.1 Ustun bor va turi to'g'ri
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='projects' AND column_name='start_notified_at'
      AND data_type = 'timestamp with time zone'
  ) THEN
    RAISE EXCEPTION 'public.projects.start_notified_at qo''shilmadi yoki timestamptz emas';
  END IF;

  -- 4.2 Indeks
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='projects' AND indexname='idx_projects_start_pending'
  ) THEN
    RAISE EXCEPTION 'idx_projects_start_pending indeksi qo''shilmadi';
  END IF;

  -- 4.3 Backfill to'liq bajarildimi? (boshlangan, lekin belgilanmagan qator qolmasin)
  SELECT count(*) INTO v_cnt
    FROM public.projects
   WHERE start_notified_at IS NULL AND start_at IS NOT NULL AND start_at <= now();
  IF v_cnt > 0 THEN
    RAISE EXCEPTION 'Backfill to''liq emas: % ta boshlangan loyiha belgilanmadi (takroriy xabar xavfi)', v_cnt;
  END IF;

  -- 4.4 Boshqa ustunlarga TEGILMAGANI
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='projects' AND column_name='status'
  ) THEN
    RAISE EXCEPTION 'public.projects.status yo''q — bu skript unga tegmasligi kerak edi, holat noto''g''ri.';
  END IF;

  RAISE NOTICE 'TASKFIX_LOYIHA_START.sql: OK — start_notified_at + qisman indeks + backfill joyida.';
END $$;

COMMIT;

-- ─────────────────────────────────────────────────────────────
-- 5) DIAGNOSTIKA — hech narsani o'zgartirmaydi, faqat xabar beradi.
--    Natijani "Messages"/"Notices" bo'limida o'qing.
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_all int; v_dated int; v_future int; v_marked int; v_locked int;
BEGIN
  SELECT count(*) INTO v_all    FROM public.projects;
  SELECT count(*) INTO v_dated  FROM public.projects WHERE start_at IS NOT NULL;
  SELECT count(*) INTO v_future FROM public.projects WHERE start_at IS NOT NULL AND start_at > now();
  SELECT count(*) INTO v_marked FROM public.projects WHERE start_notified_at IS NOT NULL;
  RAISE NOTICE 'Loyihalar: % ta (boshlanish sanasi bor: %, hali boshlanmagan: %, xabari belgilangan: %)',
    v_all, v_dated, v_future, v_marked;

  -- MA'LUMOT: hali boshlanmagan loyihalarda nechta bosqich bor. 🔴 Ular
  -- QULFLANMAYDI (is_locked sof ketma-ketlik belgisi bo'lib qoladi) — ilova
  -- ularni KO'RSATISH darvozasi bilan yashiradi va start_at o'tishi bilan
  -- ular o'zi ko'rinadi. Bu skript tasks jadvaliga TEGMAYDI.
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='tasks' AND column_name='is_locked') THEN
    SELECT count(*) INTO v_locked
      FROM public.tasks t
      JOIN public.projects p ON p.id = t.project_id
     WHERE p.start_at > now()
       AND coalesce(t.is_locked, false) = false
       AND t.status NOT IN ('completed','cancelled');
    IF v_locked > 0 THEN
      RAISE NOTICE 'Boshlanmagan loyihalarda % ta ochiq (qulflanmagan) bosqich bor — bu NORMAL. Ilovada ular YASHIRIN (taskHiddenByStart) va start_at o''tishi bilan avtomat ko''rinadi.', v_locked;
    ELSE
      RAISE NOTICE 'Boshlanmagan loyihalarda ochiq bosqich yo''q.';
    END IF;
  END IF;
END $$;
