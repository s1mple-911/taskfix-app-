-- TASKFIX_PROJECT.sql — Loyiha turi (ketma-ket / parallel)
-- Asilbek RUN qiladi. ADDITIVE + IDEMPOTENT: mavjud ma'lumot o'zgarmaydi, prod xavfsiz.
--
-- Nima qiladi:
--   1) public.projects.flow_type ustuni — 'sequential' (ketma-ket) | 'parallel'.
--      Default 'sequential' → MAVJUD barcha loyihalar avvalgidek ketma-ket bo'lib qoladi,
--      hech qanday xatti-harakat o'zgarmaydi.
--   2) Diagnostika (faqat O'QIYDI, hech narsani o'zgartirmaydi): projects.status ustuni
--      qanday qiymatlarni qabul qilishi va RLS yoqilgan-yoqilmaganini xabar qiladi.
--
-- Eslatma: ENUM emas — TEXT + CHECK (30/32-migratsiyalardagi saboq).
-- Ilova ustun bo'lmasa ham ishlaydi (flow_type null/yo'q → ketma-ket deb hisoblanadi),
-- lekin "Loyiha turi" tanlovi saqlanmaydi. Shuning uchun bu fayl ishga tushirilishi kerak.

BEGIN;

-- ─────────────────────────────────────────────────────────────
-- 1) flow_type ustuni
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS flow_type text NOT NULL DEFAULT 'sequential';

-- CHECK — faqat yo'q bo'lsa qo'shamiz (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'projects_flow_type_chk'
      AND conrelid = 'public.projects'::regclass
  ) THEN
    ALTER TABLE public.projects
      ADD CONSTRAINT projects_flow_type_chk
      CHECK (flow_type IN ('sequential','parallel'));
  END IF;
END $$;

COMMENT ON COLUMN public.projects.flow_type IS
  'Loyiha turi: sequential = bosqichlar navbatma-navbat ochiladi (yangi vazifada depends_on_prev default YOQIQ); parallel = hamma vazifa birdan ochiq (default O''CHIQ). Bu faqat YANGI bosqich uchun default — har vazifa o''z depends_on_prev qiymatini saqlaydi.';

-- ─────────────────────────────────────────────────────────────
-- 2) Tekshiruv — jimgina o'tmasin
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'projects' AND column_name = 'flow_type'
  ) THEN
    RAISE EXCEPTION 'projects.flow_type ustuni qo''shilmadi';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'projects_flow_type_chk' AND conrelid = 'public.projects'::regclass
  ) THEN
    RAISE EXCEPTION 'projects_flow_type_chk cheklovi qo''shilmadi';
  END IF;

  IF EXISTS (SELECT 1 FROM public.projects WHERE flow_type IS NULL) THEN
    RAISE EXCEPTION 'projects.flow_type da NULL qiymat bor — default ishlamadi';
  END IF;
END $$;

COMMIT;

-- ─────────────────────────────────────────────────────────────
-- 3) DIAGNOSTIKA — hech narsani o'zgartirmaydi, faqat xabar beradi.
--    Natijani "Messages"/"Notices" bo'limida o'qing.
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_txt text;
  v_cnt int;
BEGIN
  -- 3.1 Loyiha turlari taqsimoti
  SELECT string_agg(flow_type || '=' || c::text, ', ')
    INTO v_txt
    FROM (SELECT flow_type, count(*) c FROM public.projects GROUP BY flow_type) s;
  RAISE NOTICE 'Loyiha turlari: %', coalesce(v_txt, '(loyiha yo''q)');

  -- 3.2 projects.status — ilova 'active' | 'paused' | 'done' yozadi.
  --     Agar status ustunida boshqa qiymatlarga ruxsat bermaydigan CHECK bo'lsa,
  --     "Sozlash"dagi holat tugmalari xato beradi — quyidagi xabarni tekshiring.
  SELECT string_agg(coalesce(status,'(null)') || '=' || c::text, ', ')
    INTO v_txt
    FROM (SELECT status, count(*) c FROM public.projects GROUP BY status) s;
  RAISE NOTICE 'projects.status hozirgi qiymatlari: %', coalesce(v_txt, '(loyiha yo''q)');

  SELECT string_agg(conname || ': ' || pg_get_constraintdef(oid), ' | ')
    INTO v_txt
    FROM pg_constraint
    WHERE conrelid = 'public.projects'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%status%';
  IF v_txt IS NULL THEN
    RAISE NOTICE 'projects.status uchun CHECK yo''q — ilova active/paused/done yozadi, muammo bo''lmaydi.';
  ELSE
    RAISE WARNING 'projects.status CHECK mavjud: % — active/paused/done ruxsat etilganini tekshiring!', v_txt;
  END IF;

  -- 3.3 RLS holati (loyiha ma'lumoti workspace tashqarisiga chiqmasligi kerak)
  SELECT count(*) INTO v_cnt
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'projects' AND c.relrowsecurity;
  IF v_cnt = 0 THEN
    RAISE WARNING 'DIQQAT: public.projects jadvalida RLS YOQILMAGAN!';
  ELSE
    SELECT count(*) INTO v_cnt FROM pg_policies WHERE schemaname='public' AND tablename='projects';
    RAISE NOTICE 'public.projects: RLS yoqilgan, % ta policy.', v_cnt;
  END IF;

  SELECT count(*) INTO v_cnt
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'project_members' AND c.relrowsecurity;
  IF v_cnt = 0 THEN
    RAISE WARNING 'DIQQAT: public.project_members jadvalida RLS YOQILMAGAN!';
  ELSE
    SELECT count(*) INTO v_cnt FROM pg_policies WHERE schemaname='public' AND tablename='project_members';
    RAISE NOTICE 'public.project_members: RLS yoqilgan, % ta policy.', v_cnt;
  END IF;

  -- 3.4 Flow ustunlari joyidami?
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='tasks' AND column_name='depends_on_prev'
  ) THEN
    RAISE WARNING 'tasks.depends_on_prev ustuni yo''q — loyiha flow''i ishlamaydi (34-migratsiya).';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='tasks' AND column_name='is_locked'
  ) THEN
    RAISE WARNING 'tasks.is_locked ustuni yo''q — qulflash ishlamaydi (34-migratsiya).';
  END IF;
END $$;
