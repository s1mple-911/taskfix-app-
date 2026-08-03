-- ============================================================================
-- TASKFIX_EMAIL_SETTINGS.sql — 1: Email bildirishnomalari sozlamasi
-- ============================================================================
-- ADDITIVE + IDEMPOTENT: mavjud jadvallarga TEGMAYDI, faqat yangi jadval
-- (public.workspace_settings) qo'shadi. Qayta ishga tushirsa ham buzmaydi.
--
-- MUAMMO: har amalda email ketardi (biriktirish, qabul qiluvchi, bajarildi)
--         → juda ko'p xat, xodimlar bezovta.
-- YECHIM: har workspace uchun HAR ACTION alohida yoqiladi/o'chiriladi.
--         Sozlamani faqat owner/admin o'zgartiradi, HAMMA a'zo o'qiydi
--         (chunki emailni yuborayotgan mijoz — o'sha a'zoning brauzeri —
--         yuborishdan OLDIN shu sozlamani tekshiradi).
--
-- ⚠️ DEFAULT — HAMMASI O'CHIQ (false). Ya'ni bu fayl ishga tushgandan
--    keyin ilova HECH QANDAY bildirishnoma emaili yubormaydi:
--      • biriktirildi (assign)      → email KETMAYDI   ⬅ O'ZGARISH
--      • qabul qiluvchi tayinlandi  → email KETMAYDI   ⬅ O'ZGARISH
--      • holat o'zgardi / bajarildi → email KETMAYDI   ⬅ O'ZGARISH
--      • vazifa yaratildi / izoh / deadline → o'chiq (baribir yuboruvchi yo'q)
--    Admin kerakli amalni ilovada YOQADI: Sozlamalar →
--    "Email bildirishnomalari" (faqat owner/admin).
--
-- ⚠️ BU FAYL ISHGA TUSHMASA — ilova YIQILMAYDI. Mijoz jadvalni topa
--    olmasa "hammasi yoniq" deb hisoblaydi, ya'ni AVVALGI xatti-harakat
--    saqlanadi (jimgina email o'chib qolmaydi), Sozlamalar bo'limi esa
--    "SQL ishga tushirilmagan" deb ochiq aytadi.
--
-- ESLATMA: TEXT + CHECK qoidasi bu yerda kerak emas (hammasi boolean).
-- ============================================================================

BEGIN;

-- ── 0) Oldindan tekshiruv ───────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'public' AND c.relname = 'workspaces') THEN
    RAISE EXCEPTION 'public.workspaces topilmadi — noto''g''ri baza?';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE p.proname = 'is_ws_member' AND n.nspname = 'public'
  ) THEN
    RAISE EXCEPTION 'is_ws_member() topilmadi. Avval 39_employee_details.sql ni ishga tushiring.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE p.proname = 'is_ws_manager' AND n.nspname = 'public'
  ) THEN
    RAISE EXCEPTION 'is_ws_manager() topilmadi. Avval 35_fix_projects_rls.sql ni ishga tushiring.';
  END IF;
END $$;

-- ── 1) Jadval ───────────────────────────────────────────────────────────────
-- Bitta workspace = bitta qator (PK = workspace_id). JSON emas, ustun —
-- shunda RLS/indeks oddiy, xato yozuv (typo kalit) mumkin emas.
CREATE TABLE IF NOT EXISTS public.workspace_settings (
  workspace_id          uuid PRIMARY KEY REFERENCES public.workspaces(id) ON DELETE CASCADE,

  -- ⚠️ HAMMASI DEFAULT false — admin ilovadan o'zi yoqadi.
  -- Ilova HOZIR shu 3 tasini ishlatadi (index.html → emailNotify):
  email_on_assign       boolean NOT NULL DEFAULT false,  -- 'task_assigned'
  email_on_acceptor     boolean NOT NULL DEFAULT false,  -- 'task_acceptor'
  email_on_status       boolean NOT NULL DEFAULT false,  -- 'task_completed' (holat o'zgardi)

  -- Zaxira: hozir mijozda email yuboruvchi yo'q (Telegram/ilova ichida bor).
  -- Sozlama baribir saqlanadi va n8n webhook payload'iga qo'shiladi.
  email_on_task_create  boolean NOT NULL DEFAULT false,
  email_on_comment      boolean NOT NULL DEFAULT false,
  email_on_deadline     boolean NOT NULL DEFAULT false,

  updated_at            timestamptz NOT NULL DEFAULT now(),
  updated_by            uuid
);

-- Qayta ishga tushirilganda (jadval avval boshqa/kamroq ustun bilan
-- yaratilgan bo'lsa) — yetishmayotganini qo'shamiz.
ALTER TABLE public.workspace_settings ADD COLUMN IF NOT EXISTS email_on_assign      boolean NOT NULL DEFAULT false;
ALTER TABLE public.workspace_settings ADD COLUMN IF NOT EXISTS email_on_acceptor    boolean NOT NULL DEFAULT false;
ALTER TABLE public.workspace_settings ADD COLUMN IF NOT EXISTS email_on_status      boolean NOT NULL DEFAULT false;
ALTER TABLE public.workspace_settings ADD COLUMN IF NOT EXISTS email_on_task_create boolean NOT NULL DEFAULT false;
ALTER TABLE public.workspace_settings ADD COLUMN IF NOT EXISTS email_on_comment     boolean NOT NULL DEFAULT false;
ALTER TABLE public.workspace_settings ADD COLUMN IF NOT EXISTS email_on_deadline    boolean NOT NULL DEFAULT false;
ALTER TABLE public.workspace_settings ADD COLUMN IF NOT EXISTS updated_at           timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.workspace_settings ADD COLUMN IF NOT EXISTS updated_by           uuid;

-- Ustun avval boshqa default bilan yaratilgan bo'lsa — default'ni ham
-- tuzatamiz (ADD COLUMN IF NOT EXISTS mavjud ustunga tegmaydi).
ALTER TABLE public.workspace_settings ALTER COLUMN email_on_assign      SET DEFAULT false;
ALTER TABLE public.workspace_settings ALTER COLUMN email_on_acceptor    SET DEFAULT false;
ALTER TABLE public.workspace_settings ALTER COLUMN email_on_status      SET DEFAULT false;
ALTER TABLE public.workspace_settings ALTER COLUMN email_on_task_create SET DEFAULT false;
ALTER TABLE public.workspace_settings ALTER COLUMN email_on_comment     SET DEFAULT false;
ALTER TABLE public.workspace_settings ALTER COLUMN email_on_deadline    SET DEFAULT false;

COMMENT ON TABLE  public.workspace_settings IS
  'Workspace darajasidagi sozlamalar. Hozircha: qaysi amalda email bildirishnoma ketishi. Yozish — faqat owner/admin, o''qish — hamma a''zo (mijoz email yuborishdan oldin tekshiradi).';
COMMENT ON COLUMN public.workspace_settings.email_on_assign      IS 'Vazifa biriktirilganda bajaruvchiga email (emailNotify ''task_assigned'')';
COMMENT ON COLUMN public.workspace_settings.email_on_acceptor    IS 'Qabul qiluvchi tayinlanganda unga email (emailNotify ''task_acceptor'')';
COMMENT ON COLUMN public.workspace_settings.email_on_status      IS 'Holat o''zgarganda / bajarilganda email (emailNotify ''task_completed'')';
COMMENT ON COLUMN public.workspace_settings.email_on_task_create IS 'Vazifa yaratilganda email — zaxira bayroq (mijozda yuboruvchi yo''q, n8n payload''ida uzatiladi)';
COMMENT ON COLUMN public.workspace_settings.email_on_comment     IS 'Izoh qo''shilganda email — zaxira bayroq (hozir Telegram + ilova ichida xabar bor)';
COMMENT ON COLUMN public.workspace_settings.email_on_deadline    IS 'Deadline yaqinlashdi/o''tdi email — zaxira bayroq (yuboruvchi cron hali yo''q)';

-- ── 2) updated_at ni avtomat yangilash ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.workspace_settings_touch()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS workspace_settings_touch_trg ON public.workspace_settings;
CREATE TRIGGER workspace_settings_touch_trg
  BEFORE UPDATE ON public.workspace_settings
  FOR EACH ROW EXECUTE FUNCTION public.workspace_settings_touch();

-- ── 3) RLS ──────────────────────────────────────────────────────────────────
-- KO'RISH: workspace'ning HAR QANDAY a'zosi.
--   Sabab: emailni yuborayotgan kod mijozda ishlaydi (oddiy a'zo vazifa
--   biriktirsa — uning brauzeri yuboradi). O'qiy olmasa "yoniq" deb
--   hisoblaydi va o'chiq sozlama ishlamay qolardi.
-- YOZISH: faqat owner/admin (is_ws_manager).
-- ⚠️ workspace_members inline subquery YOZILMAYDI (42P17 rekursiya).
ALTER TABLE public.workspace_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ws_settings_select" ON public.workspace_settings;
CREATE POLICY "ws_settings_select" ON public.workspace_settings FOR SELECT TO authenticated
  USING ( is_ws_member(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS "ws_settings_insert" ON public.workspace_settings;
CREATE POLICY "ws_settings_insert" ON public.workspace_settings FOR INSERT TO authenticated
  WITH CHECK ( is_ws_manager(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS "ws_settings_update" ON public.workspace_settings;
CREATE POLICY "ws_settings_update" ON public.workspace_settings FOR UPDATE TO authenticated
  USING      ( is_ws_manager(workspace_id, (SELECT auth.uid())) )
  WITH CHECK ( is_ws_manager(workspace_id, (SELECT auth.uid())) );

-- DELETE policy YO'Q → hech kim o'chira olmaydi. Workspace o'chsa
-- FK CASCADE bilan ketadi — bu normal.

-- ── 4) Mavjud workspace'lar uchun qator ─────────────────────────────────────
-- Qator bo'lmasa ham ilova ishlaydi (mijoz default'ni ishlatadi), lekin
-- qator bo'lgani yaxshi: admin Sozlamalarni ochganda darrov ko'radi.
INSERT INTO public.workspace_settings (workspace_id)
SELECT w.id FROM public.workspaces w
ON CONFLICT (workspace_id) DO NOTHING;

-- Agar bu fayl AVVALGI (ba'zi bayroqlari true bo'lgan) versiyada allaqachon
-- ishga tushirilgan bo'lsa — o'sha qatorlarni ham o'chiramiz.
-- ⚠️ `updated_by IS NULL` sharti MUHIM: ilovadagi emailSetSave() saqlaganda
--    DOIM updated_by yozadi. Ya'ni admin UI'dan bir marta saqlagan bo'lsa,
--    bu skriptni qayta ishga tushirish uning tanlovini O'CHIRMAYDI.
UPDATE public.workspace_settings SET
  email_on_assign      = false,
  email_on_acceptor    = false,
  email_on_status      = false,
  email_on_task_create = false,
  email_on_comment     = false,
  email_on_deadline    = false
WHERE updated_by IS NULL
  AND (email_on_assign OR email_on_acceptor OR email_on_status
       OR email_on_task_create OR email_on_comment OR email_on_deadline);

-- ── 5) Tekshiruv — jimgina o'tmasin ─────────────────────────────────────────
DO $$
DECLARE v_cnt int; v_ws int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'public' AND c.relname = 'workspace_settings') THEN
    RAISE EXCEPTION 'workspace_settings yaratilmadi';
  END IF;

  IF (SELECT count(*) FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'workspace_settings'
         AND column_name IN ('workspace_id','email_on_assign','email_on_acceptor','email_on_status',
                             'email_on_task_create','email_on_comment','email_on_deadline',
                             'updated_at','updated_by')) <> 9 THEN
    RAISE EXCEPTION 'workspace_settings ustunlari to''liq emas — qo''lda tekshiring.';
  END IF;

  SELECT count(*) INTO v_cnt FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'workspace_settings' AND c.relrowsecurity;
  IF v_cnt = 0 THEN
    RAISE EXCEPTION 'workspace_settings da RLS yoqilmadi';
  END IF;

  SELECT count(*) INTO v_cnt FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'workspace_settings';
  IF v_cnt < 3 THEN
    RAISE EXCEPTION 'workspace_settings policy''lari to''liq emas (% ta, 3 kutilgan)', v_cnt;
  END IF;

  -- Har workspace uchun qator borligini tekshiramiz
  SELECT count(*) INTO v_ws  FROM public.workspaces;
  SELECT count(*) INTO v_cnt FROM public.workspace_settings;
  IF v_cnt < v_ws THEN
    RAISE EXCEPTION 'workspace_settings qatorlari yetishmaydi: % ta workspace, % ta qator', v_ws, v_cnt;
  END IF;

  RAISE NOTICE '✅ workspace_settings tayyor: % ta workspace, RLS yoqiq, % ta policy.', v_ws, v_cnt;

  -- Yoqilgan bayroq qolganini ochiq aytamiz (admin UI'dan yoqqan bo'lishi
  -- mumkin — bu normal; lekin jimgina o'tib ketmasin).
  SELECT count(*) INTO v_cnt FROM public.workspace_settings
   WHERE email_on_assign OR email_on_acceptor OR email_on_status
      OR email_on_task_create OR email_on_comment OR email_on_deadline;
  IF v_cnt = 0 THEN
    RAISE NOTICE '   Default: HAMMASI O''CHIQ — hech qanday email yuborilmaydi.';
    RAISE NOTICE '   Yoqish: ilovada Sozlamalar → "Email bildirishnomalari" (owner/admin).';
  ELSE
    RAISE NOTICE '   % ta workspace''da bildirishnoma YOQILGAN (UI''dan saqlangan — tegilmadi).', v_cnt;
  END IF;
END $$;

COMMIT;

-- ============================================================================
-- YOQISH — ilovadan (tavsiya) yoki SQL bilan
-- ============================================================================
-- Odatdagi yo'l: ilovada Sozlamalar → "Email bildirishnomalari"
-- (faqat owner/admin) — kerakli amalni yoqib, "Saqlash".
--
-- SQL bilan yoqmoqchi bo'lsangiz (masalan faqat biriktirish emaili):
--
--   UPDATE public.workspace_settings
--      SET email_on_assign = true
--    WHERE workspace_id = '<workspace uuid>';
--
-- Hammasini yoqish (avvalgi xatti-harakat):
--
--   UPDATE public.workspace_settings SET
--     email_on_assign = true, email_on_acceptor = true, email_on_status = true,
--     email_on_task_create = true, email_on_comment = true, email_on_deadline = true
--   WHERE workspace_id = '<workspace uuid>';
--
-- ⚠️ SQL bilan yozsangiz updated_by NULL qoladi — ya'ni bu skriptni QAYTA
--    ishga tushirsangiz yuqoridagi tozalash UPDATE'i uni o'chirib qo'yadi.
--    Shu bois yoqishni ilovadan qilgan ma'qul (u updated_by yozadi).
-- ============================================================================

-- ============================================================================
-- QAYTARISH (rollback)
-- ============================================================================
--   DROP TABLE IF EXISTS public.workspace_settings;
--   DROP FUNCTION IF EXISTS public.workspace_settings_touch();
-- Jadval yo'q bo'lsa ilova "hammasi yoniq" rejimiga qaytadi (eski holat).
-- ============================================================================

-- ============================================================================
-- EMAIL ZANJIRI (arxitektura — kim kimni chaqiradi)
-- ============================================================================
--   index.html → emailNotify(type, task_id, recipient_user_id)
--              → sb.functions.invoke('send-email', ...)   [Edge Function]
--              → Resend API
--
-- Boshqa email yo'li YO'Q: 'send-email' EF butun ilovada FAQAT emailNotify
-- ichidan chaqiriladi. Shuning uchun tekshiruv aynan o'sha yagona nuqtaga
-- qo'yildi (index.html → emailAllowed) — o'chiq bo'lsa invoke UMUMAN
-- bo'lmaydi, ya'ni email butunlay ketmaydi.
--
-- ⚠️ n8n: notifyN8n() 'task.created' va 'task.status_changed' hodisalarini
--    foydalanuvchining o'z webhook'iga yuboradi. Agar o'sha n8n workflow
--    email yuborsa — biz uni to'sa olmaymiz. Shu sababli payload'ga
--    `email_settings` obyekti QO'SHILDI; n8n workflow'da IF node bilan
--    masalan `{{ $json.email_settings.email_on_status }}` ni tekshiring.
-- ============================================================================
