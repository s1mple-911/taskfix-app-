-- ============================================================================
-- TASKFIX_HR_EDITORS.sql — "HR muharriri" ruxsat turi
-- ============================================================================
-- MAQSAD: owner/admin BO'LMAGAN, lekin HR lavozimidagi xodim
--         HR Service → Org Schema (org_folders + org_people) ni TAHRIRLAY olsin.
--         Qolgan hamma joyda u avvalgidek ODDIY A'ZO bo'lib qoladi.
--
-- DIZAYN QARORI: ruxsat lavozim NOMIGA emas, BAYROQQA bog'lanadi —
--   `positions.hr_editor boolean`. Owner "HR" lavozimini bir marta belgilaydi
--   → o'sha lavozimdagi HAR KIM Org Schema'ni tahrirlaydi. Nom bo'yicha
--   moslashtirish ("HR" / "HR menejer" / "Kadrlar bo'limi") mo'rt — ishlatilmaydi.
--
-- NIMA QO'SHILADI
--   1) positions.hr_editor      — boolean NOT NULL DEFAULT false (+ qisman indeks)
--   2) public.hr_is_editor(ws, user) — SECURITY DEFINER yordamchi
--   3) 6 ta YANGI PERMISSIVE policy:
--        org_folders_insert_hr / _update_hr / _delete_hr
--        org_people_insert_hr  / _update_hr / _delete_hr
--
-- 🔴 NIMAGA TEGMAYDI
--   • Mavjud `org_folders_insert|_update|_delete` va `org_people_*` policy'lari
--     DROP ham, ALTER ham QILINMAYDI. PostgreSQL bir jadvaldagi bir necha
--     PERMISSIVE policy'ni OR bilan birlashtiradi → manager huquqi
--     HECH QACHON torayib qolmaydi. Nomlar boshqacha bo'lgani uchun
--     TASKFIX_HR.sql ni QAYTA run qilish ham buni buzmaydi.
--   • SELECT policy'lari — ko'rish allaqachon har a'zoga ochiq, o'zgarish yo'q.
--   • is_ws_manager(), is_ws_member(), workspace_members, hr_settings — tegilmaydi.
--   • `positions` ning o'z RLS'i (positions_write = is_ws_manager) — tegilmaydi,
--     ya'ni `hr_editor` bayrog'ini FAQAT owner/admin qo'ya oladi. HR muharriri
--     o'zini o'zi abadiylashtira OLMAYDI.
--
-- 🔴 NIMAGA XAVFSIZ (o'zini o'zi HR qilib olish mumkin emas)
--   `employee_details` yozuvi (position_id ni o'zgartirish) RLS bo'yicha faqat
--   is_ws_manager'ga ochiq — xodim O'Z qatorini ham tahrirlay olmaydi.
--   Demak lavozim → ruxsat zanjirining IKKALA halqasi ham owner/admin qo'lida.
--
-- ⚠️ BU FAYL ISHGA TUSHMASA — ilova YIQILMAYDI. Mijozda `hr_editor` ustuni
--    `undefined` bo'ladi → hrIsEditor() false → hamma narsa avvalgidek
--    (faqat owner/admin tahrirlaydi). UI buni ochiq aytadi.
--
-- ADDITIVE + IDEMPOTENT. TEXT+CHECK / ENUM emas (bu yerda boolean).
-- RLS ichida workspace_members inline subquery YO'Q (42P17) — CLAUDE.md 8-qoida.
--
-- ── ORQAGA QAYTARISH (kerak bo'lsa) ────────────────────────────────────────
--   DROP POLICY IF EXISTS "org_folders_insert_hr" ON public.org_folders;
--   DROP POLICY IF EXISTS "org_folders_update_hr" ON public.org_folders;
--   DROP POLICY IF EXISTS "org_folders_delete_hr" ON public.org_folders;
--   DROP POLICY IF EXISTS "org_people_insert_hr"  ON public.org_people;
--   DROP POLICY IF EXISTS "org_people_update_hr"  ON public.org_people;
--   DROP POLICY IF EXISTS "org_people_delete_hr"  ON public.org_people;
--   DROP FUNCTION IF EXISTS public.hr_is_editor(uuid, uuid);
--   DROP INDEX  IF EXISTS public.positions_hr_editor_idx;
--   ALTER TABLE public.positions DROP COLUMN IF EXISTS hr_editor;
--   (Ustunni tashlash ma'lumot yo'qotadi — faqat bayroqlar; lavozimlar qoladi.)
-- ============================================================================

BEGIN;

-- ════════════════════════════════════════════════════════════════════════════
-- 0) OLDINDAN TEKSHIRUV — noto'g'ri/yarim bazada ishga tushmasin
-- ════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['positions','employee_details'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = 'public' AND c.relname = t) THEN
      RAISE EXCEPTION 'public.% topilmadi. Avval 39_employee_details.sql ni ishga tushiring.', t;
    END IF;
  END LOOP;

  FOREACH t IN ARRAY ARRAY['org_folders','org_people'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = 'public' AND c.relname = t) THEN
      RAISE EXCEPTION 'public.% topilmadi. Avval TASKFIX_HR.sql ni ishga tushiring.', t;
    END IF;
  END LOOP;

  -- Kutilgan ustunlar (boshqa sxemali "positions" bo'lib qolmasin)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='positions' AND column_name='workspace_id') THEN
    RAISE EXCEPTION 'public.positions.workspace_id yo''q — bu kutilgan jadval emas.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='employee_details' AND column_name='position_id') THEN
    RAISE EXCEPTION 'public.employee_details.position_id yo''q. Avval 39_employee_details.sql ni ishga tushiring.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'is_ws_manager') THEN
    RAISE EXCEPTION 'is_ws_manager() topilmadi. Avval 35_fix_projects_rls.sql ni ishga tushiring.';
  END IF;

  -- hr_is_editor() tanasida ISHLATILADI (jamoadan chiqarilgan xodim huquqni
  -- saqlab qolmasin) — shuning uchun mavjudligi MAJBURIY tekshiriladi.
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'is_ws_member') THEN
    RAISE EXCEPTION 'is_ws_member() topilmadi. Avval 39_employee_details.sql ni ishga tushiring.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    RAISE EXCEPTION '`authenticated` roli topilmadi — bu Supabase bazasi emasmi?';
  END IF;
END $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 1) positions.hr_editor — bayroq
-- ════════════════════════════════════════════════════════════════════════════
ALTER TABLE public.positions
  ADD COLUMN IF NOT EXISTS hr_editor boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.positions.hr_editor IS
  'true = shu lavozimdagi xodim Org Schema (org_folders/org_people) ni tahrirlay oladi, owner/admin bo''lmasa ham. Bayroqni FAQAT owner/admin qo''yadi (positions_write = is_ws_manager). Boshqa hech qanday ruxsatga TA''SIR QILMAYDI.';

-- Qisman indeks: HR lavozimlari odatda 1–2 ta, qolgan yuzlab qator indeksga
-- umuman kirmaydi (indeks kichik, yozuv arzon).
CREATE INDEX IF NOT EXISTS positions_hr_editor_idx
  ON public.positions (workspace_id)
  WHERE hr_editor;


-- ════════════════════════════════════════════════════════════════════════════
-- 2) public.hr_is_editor(ws, user)
--    🔴 SECURITY DEFINER: policy ichidan chaqirilganda employee_details /
--       positions RLS'i qayta baholanmasin (zanjir uzilsin, 42P17 bo'lmasin).
--    🔴 anon/authenticated dan REVOKE → keyin faqat EXECUTE authenticated
--       (can_see_project naqshi). EXECUTE authenticated'ga SHART: RLS ifodasi
--       CHAQIRUVCHI huquqi bilan baholanadi.
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.hr_is_editor(p_ws uuid, p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $body$
  -- 🔴 `p_user = (SELECT auth.uid())` — MAJBURIY QATOR, OLIB TASHLAMANG.
  --    Funksiya `authenticated` ga EXECUTE bilan ochiq, ya'ni uni PostgREST
  --    orqali TO'G'RIDAN-TO'G'RI chaqirish mumkin:
  --        POST /rest/v1/rpc/hr_is_editor {p_ws, p_user}
  --    Bu qatorsiz istalgan foydalanuvchi ixtiyoriy p_ws/p_user yuborib,
  --    o'zi a'zo bo'lmagan workspace'dagi "falon odam HR muharrirmi?"
  --    savoliga javob ola olardi (SECURITY DEFINER RLS'ni chetlab o'tadi).
  --    Policy'lar doim (SELECT auth.uid()) uzatgani uchun bu shart RLS ishiga
  --    umuman ta'sir qilmaydi.
  -- 🔴 `is_ws_member(...)` — MAJBURIY QATOR, OLIB TASHLAMANG.
  --    "Xodimni o'chirish" (rmxDoRemove) uni FAQAT workspace_members'dan
  --    chiqaradi — employee_details qatori BAZADA QOLADI (CASCADE yo'q,
  --    mijoz ham o'chirmaydi). Bu shartsiz jamoadan chiqarilgan odamning
  --    lavozimi hamon hr_editor bo'lib turadi va u amaldagi JWT bilan
  --    to'g'ridan-to'g'ri PostgREST orqali org_folders/org_people ga
  --    INSERT/UPDATE/DELETE qila olardi (SELECT to'silgan — ya'ni ko'rmasdan
  --    o'chira olardi). Mavjud policy'lar is_ws_manager() ishlatgani uchun bu
  --    invariantni saqlardi; yangi policy'lar buni buzmasligi shart.
  --    is_ws_member() ham SECURITY DEFINER — rekursiya bo'lmaydi (8-qoida).
  SELECT p_ws   IS NOT NULL
     AND p_user IS NOT NULL
     AND p_user = (SELECT auth.uid())
     AND is_ws_member(p_ws, p_user)
     AND EXISTS (
           SELECT 1
             FROM public.employee_details d
             JOIN public.positions p
               ON p.id = d.position_id
              AND p.workspace_id = d.workspace_id
            WHERE d.workspace_id = p_ws
              AND d.user_id      = p_user
              AND p.hr_editor
         );
$body$;

COMMENT ON FUNCTION public.hr_is_editor(uuid, uuid) IS
  'Foydalanuvchining shu workspace''dagi lavozimi hr_editor bilan belgilanganmi? SECURITY DEFINER — employee_details/positions RLS''ini chetlab o''tadi, shu sababli org_* policy''laridan chaqirilganda rekursiya bo''lmaydi. FAQAT RLS policy''lari uchun; tanasida p_user = auth.uid() VA is_ws_member(p_ws, p_user) shartlari MAJBURIY (ikkinchisi — jamoadan chiqarilgan xodim huquqni saqlab qolmasligi uchun: rmxDoRemove employee_details qatorini o''chirmaydi).';

REVOKE ALL ON FUNCTION public.hr_is_editor(uuid, uuid) FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.hr_is_editor(uuid, uuid) FROM anon';
  END IF;
  EXECUTE 'REVOKE ALL ON FUNCTION public.hr_is_editor(uuid, uuid) FROM authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.hr_is_editor(uuid, uuid) TO authenticated';
END $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 3) YANGI PERMISSIVE POLICY'LAR (INSERT / UPDATE / DELETE)
--    🔴 Mavjud org_folders_insert|update|delete va org_people_* TEGILMAYDI.
--       Bular ALOHIDA nomli QO'SHIMCHA policy'lar — PostgreSQL ularni OR
--       bilan birlashtiradi (manager huquqi o'zgarishsiz qoladi).
--    SELECT uchun policy KERAK EMAS — ko'rish allaqachon har a'zoga ochiq.
-- ════════════════════════════════════════════════════════════════════════════

-- ── org_folders ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "org_folders_insert_hr" ON public.org_folders;
CREATE POLICY "org_folders_insert_hr" ON public.org_folders
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ( hr_is_editor(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS "org_folders_update_hr" ON public.org_folders;
CREATE POLICY "org_folders_update_hr" ON public.org_folders
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING      ( hr_is_editor(workspace_id, (SELECT auth.uid())) )
  WITH CHECK ( hr_is_editor(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS "org_folders_delete_hr" ON public.org_folders;
CREATE POLICY "org_folders_delete_hr" ON public.org_folders
  AS PERMISSIVE FOR DELETE TO authenticated
  USING ( hr_is_editor(workspace_id, (SELECT auth.uid())) );

-- ── org_people ──────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "org_people_insert_hr" ON public.org_people;
CREATE POLICY "org_people_insert_hr" ON public.org_people
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ( hr_is_editor(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS "org_people_update_hr" ON public.org_people;
CREATE POLICY "org_people_update_hr" ON public.org_people
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING      ( hr_is_editor(workspace_id, (SELECT auth.uid())) )
  WITH CHECK ( hr_is_editor(workspace_id, (SELECT auth.uid())) );

DROP POLICY IF EXISTS "org_people_delete_hr" ON public.org_people;
CREATE POLICY "org_people_delete_hr" ON public.org_people
  AS PERMISSIVE FOR DELETE TO authenticated
  USING ( hr_is_editor(workspace_id, (SELECT auth.uid())) );


-- ════════════════════════════════════════════════════════════════════════════
-- 4) TEKSHIRUV — jimgina o'tmasin
-- ════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_cnt   int;
  v_pos   int;
  v_users int;
  v_src   text;   -- hr_is_editor() tanasi, izohlari tozalangan (4.b2)
  r       record;
BEGIN
  -- 4.a) Ustun bor va boolean
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='positions'
                    AND column_name='hr_editor' AND data_type='boolean') THEN
    RAISE EXCEPTION 'positions.hr_editor yaratilmadi (yoki boolean emas)';
  END IF;

  -- 4.b) Funksiya bor va SECURITY DEFINER
  SELECT count(*) INTO v_cnt
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='hr_is_editor' AND p.prosecdef;
  IF v_cnt = 0 THEN
    RAISE EXCEPTION 'hr_is_editor() yaratilmadi yoki SECURITY DEFINER emas';
  END IF;

  -- 4.b2) 🔴 Funksiya tanasidagi IKKI MAJBURIY qorovul joyidami?
  --   • auth.uid()     — PostgREST /rpc orqali begona so'rov to'silsin
  --   • is_ws_member() — jamoadan chiqarilgan xodim huquqni saqlab qolmasin
  -- Kelajakda kimdir funksiyani tahrirlab bularni olib tashlasa, skript
  -- qayta run qilinganda SHU YERDA to'xtaydi (jimgina tuynuk ochilmasin).
  --
  -- 🔴 IZOHLAR AVVAL TOZALANADI. Tanadagi 🔴 ogohlantirish izohlarida aynan
  --    shu matnlar ("is_ws_member", "auth.uid()") bor — xom matnda qidirsak
  --    KOD QATORI o'chirilib izoh qoldirilgan holatni sezmasdik (odam
  --    "OLIB TASHLAMANG" yozuvini odatda qoldiradi). Shuning uchun `--` dan
  --    satr oxirigacha bo'lgan qism olib tashlanadi va faqat KOD tekshiriladi.
  --    `prosrc` — tananing o'zi (pg_get_functiondef emas: unda izohlardan
  --    tashqari imzo/COMMENT ham bor).
  --    pronargs = 2 — eski overload qolib ketgan bazada noto'g'ri funksiya
  --    tekshirilmasin.
  SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='hr_is_editor' AND p.pronargs = 2
   LIMIT 1;

  IF v_src IS NULL THEN
    RAISE EXCEPTION 'hr_is_editor(uuid, uuid) tanasi o''qilmadi — funksiya yaratilmadimi?';
  END IF;
  IF v_src NOT LIKE '%is_ws_member%' THEN
    RAISE EXCEPTION 'hr_is_editor() KODIDA is_ws_member() yo''q (izoh hisobga olinmaydi) — jamoadan chiqarilgan xodim yozish huquqini saqlab qolardi. To''xtatildi.';
  END IF;
  IF v_src NOT LIKE '%auth.uid()%' THEN
    RAISE EXCEPTION 'hr_is_editor() KODIDA auth.uid() sharti yo''q (izoh hisobga olinmaydi) — begona foydalanuvchi haqida so''rash mumkin bo''lardi. To''xtatildi.';
  END IF;

  -- 4.c) 6 ta YANGI policy bor va PERMISSIVE
  FOR r IN
    SELECT * FROM (VALUES
      ('org_folders','org_folders_insert_hr'),
      ('org_folders','org_folders_update_hr'),
      ('org_folders','org_folders_delete_hr'),
      ('org_people', 'org_people_insert_hr'),
      ('org_people', 'org_people_update_hr'),
      ('org_people', 'org_people_delete_hr')
    ) AS x(tbl, pol)
  LOOP
    SELECT count(*) INTO v_cnt FROM pg_policies
     WHERE schemaname='public' AND tablename=r.tbl AND policyname=r.pol;
    IF v_cnt = 0 THEN
      RAISE EXCEPTION 'Policy % (%.%) yaratilmadi', r.pol, 'public', r.tbl;
    END IF;
    SELECT count(*) INTO v_cnt FROM pg_policies
     WHERE schemaname='public' AND tablename=r.tbl AND policyname=r.pol
       AND permissive = 'PERMISSIVE';
    IF v_cnt = 0 THEN
      RAISE EXCEPTION 'Policy % PERMISSIVE emas — mavjud huquqni toraytirib yuborardi!', r.pol;
    END IF;
  END LOOP;

  -- 4.d) 🔴 ESKI 6 ta policy HAMON joyida (nomma-nom) — biz ularni buzmadik
  FOR r IN
    SELECT * FROM (VALUES
      ('org_folders','org_folders_insert'),
      ('org_folders','org_folders_update'),
      ('org_folders','org_folders_delete'),
      ('org_people', 'org_people_insert'),
      ('org_people', 'org_people_update'),
      ('org_people', 'org_people_delete')
    ) AS x(tbl, pol)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                    WHERE schemaname='public' AND tablename=r.tbl AND policyname=r.pol) THEN
      RAISE EXCEPTION 'Mavjud policy % YO''QOLGAN — manager huquqi buzildi, hammasi qaytariladi!', r.pol;
    END IF;
  END LOOP;

  -- 4.e) Hisobot: nechta lavozim belgilangan va nechta xodim ruxsat oladi.
  --      ⚠️ ISM chiqarilmaydi — faqat son.
  SELECT count(*) INTO v_pos FROM public.positions WHERE hr_editor;
  -- ⚠️ workspace_members bilan JOIN — hr_is_editor() ham a'zolikni tekshiradi,
  --    shuning uchun bu son HAQIQATDA ruxsat oladiganlarni ko'rsatsin
  --    (jamoadan chiqarilgan, lekin employee_details'da qolgan qatorlar emas).
  SELECT count(DISTINCT d.user_id) INTO v_users
    FROM public.employee_details d
    JOIN public.positions p
      ON p.id = d.position_id AND p.workspace_id = d.workspace_id
    JOIN public.workspace_members wm
      ON wm.workspace_id = d.workspace_id AND wm.user_id = d.user_id
   WHERE p.hr_editor;

  RAISE NOTICE '─────────────────────────────────────────────';
  RAISE NOTICE 'TASKFIX_HR_EDITORS.sql — TAYYOR';
  RAISE NOTICE '  positions.hr_editor  : qo''shildi (default false)';
  RAISE NOTICE '  hr_is_editor()       : SECURITY DEFINER, faqat authenticated EXECUTE';
  RAISE NOTICE '  yangi policy         : 6 ta (org_folders + org_people, PERMISSIVE)';
  RAISE NOTICE '  eski policy          : 6 ta, o''zgarishsiz';
  RAISE NOTICE '  HR muharrir lavozimi : % ta', v_pos;
  RAISE NOTICE '  Ruxsat oladigan xodim: % ta', v_users;
  IF v_pos = 0 THEN
    RAISE NOTICE '  ⚠️ Hali bironta lavozim belgilanmagan — hech kimga yangi ruxsat berilmadi.';
    RAISE NOTICE '     Ilovada: Qo''shimcha service → HR Service → "HR muharrir lavozimlari".';
  END IF;
  RAISE NOTICE '─────────────────────────────────────────────';
END $$;

COMMIT;
