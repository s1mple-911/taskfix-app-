-- ============================================================================
-- TASKFIX_LOYIHA_V2.sql — LOYIHA V2: multiselect takrorlanish, mas'ul odam,
--                         dam olish + CHECKLIST (task_subtasks) kengaytmasi
-- ============================================================================
-- Asilbek RUN qiladi (Supabase SQL Editor, postgres roli).
-- ADDITIVE + IDEMPOTENT: mavjud ustun / policy / ma'lumot O'CHIRILMAYDI va
-- O'ZGARTIRILMAYDI. Faqat YANGI obyektlar qo'shiladi. Qayta RUN xavfsiz.
--
-- ── NIMA QO'SHILADI ─────────────────────────────────────────────────────────
--   1) public.projects ga 4 ustun:
--        recur_weekdays   smallint[]  — takrorlanish HAFTA KUNLARI (multiselect)
--                                       0=Yakshanba … 6=Shanba (JS getDay(),
--                                       mavjud recur_weekday bilan BIR XIL)
--        recur_monthdays  smallint[]  — takrorlanish OY KUNLARI (multiselect) 1..31
--        responsible_id   uuid        — loyihaga MAS'UL odam (NULLABLE)
--        respect_dayoff   boolean NOT NULL DEFAULT false
--      + 2 CHECK (IMMUTABLE yordamchi public.tf_smallint_set_ok orqali)
--      + responsible_id uchun FK (nishon DINAMIK topiladi)
--
--   2) public.task_subtasks (CHECKLIST) ga 7 ustun — YANGI JADVAL YARATILMAYDI:
--        assigned_to uuid       (FK, ON DELETE SET NULL) — punkt kimga biriktirilgan
--        assigned_by uuid       (FK) — 🔴 KIM biriktirgan. QIYMATNI FAQAT
--                                 TRIGGER YOZADI (mijoz yuborgani e'tiborsiz).
--        file_url    text  — public URL (task_attachments.file_url naqshi)
--        file_name   text
--        file_size   bigint
--        done_at     timestamptz   — trigger yozadi
--        done_by     uuid          — trigger yozadi (FK YO'Q — pastda sabab)
--      + qisman indeks idx_task_subtasks_assigned
--
--   3) public.task_subtasks_guard() + task_subtasks_guard_trg
--      🔴 BEFORE INSERT OR UPDATE — ikki vazifa:
--         (a) assigned_by ni O'ZI yozadi (auth.uid()), mijozdan olmaydi;
--         (b) USTUN darajasidagi cheklov: vazifa egasi/ws-admini BO'LMAGAN
--             odam task_id / workspace_id / title / sort_order / assigned_to /
--             assigned_by ni o'zgartira olmaydi (42501, o'zbekcha matn).
--             Unga faqat bajarish maydonlari ochiq: is_completed, file_*.
--             done_at / done_by ni ham TRIGGER yozadi (soxtalashtirib bo'lmaydi).
--
--   4) public.can_see_task_via_checklist(p_task, p_user) — SECURITY DEFINER
--      + POLICY tasks_select_checklist_assignee (PERMISSIVE SELECT, additive)
--      + kerak bo'lsagina: task_subtasks ga 2 ta PERMISSIVE policy
--        (skript avval mavjudlarini O'QIYDI va ortiqcha bo'lsa QO'SHMAYDI)
--
-- ── 🔴 ESKI XATTI-HARAKAT BIR ZARRA O'ZGARMAYDI ─────────────────────────────
--   `recur_weekdays` / `recur_monthdays` NULL bo'lganda mijoz ESKI bitta
--   qiymatli `recur_weekday` / `recur_monthday` ustunlarini ishlatadi
--   (rcxAnchor / rcxNext mantiqi — TASKFIX_RECUR_TIME.sql). Yangi ustunlar
--   BARCHA mavjud loyihalarda NULL bo'lib tug'iladi.
--   ⚠️ Ikkalasi ham to'lgan bo'lsa MIJOZ ustuvorlikni o'zi hal qiladi — SQL
--      hech narsani majburlamaydi va eski ustunlarni TOZALAMAYDI.
--   `respect_dayoff` DEFAULT false = "hozirgi xatti-harakat".
--   `responsible_id` NULL = mas'ul belgilanmagan (ixtiyoriy maydon).
--
-- ── 🔴 STORAGE — YANGI POLICY KERAK EMAS ────────────────────────────────────
--   Checklist punktiga biriktirilgan fayl MAVJUD `attachments` bucket'iga,
--   MAVJUD yo'l naqshi bilan yuklanadi:
--        <workspace_id>/<task_id>/<timestamp>_<fayl nomi>
--   (index.html: _uploadAttachmentCore). Yangi bucket ham, yangi Storage
--   policy'si ham QO'SHILMAYDI.
--   ⚠️ 🔴 OCHIQ AYTILADI: `attachments` bucket PUBLIC — mijoz `getPublicUrl()`
--      ishlatadi, ya'ni HAVOLANI BILGAN HAR KIM (kirmagan odam ham) faylni
--      yuklab oladi. Bu YANGI xavf emas (mavjud `task_attachments` allaqachon
--      shunday ishlaydi), lekin checklist fayllari ham AYNI shu holatda
--      bo'ladi. Maxfiy hujjat kerak bo'lsa — private bucket + signed URL
--      (hr-docs naqshi), bu ALOHIDA qaror va bu fayl uni QILMAYDI.
--   ⚠️ Checklist fayli o'chirilganda mijoz Storage'dan ham o'chirishi kerak
--      (tartib: avval Storage, keyin qator — task_attachments naqshi).
--
-- ── 🔴 ASOSIY RLS ISHI ──────────────────────────────────────────────────────
--   Checklist punkti menga biriktirilgan bo'lsa, men o'sha VAZIFANI (tasks
--   qatorini) O'QIY olishim kerak. Tahrirlash huquqi BERILMAYDI: yangi policy
--   FAQAT `FOR SELECT`.
--   can_see_task_via_checklist() — SECURITY DEFINER (task_subtasks/tasks ni
--   RLS'siz o'qiydi → `tasks` policy'sidan chaqirilganda 42P17 REKURSIYA
--   BO'LMAYDI; can_see_project() bilan AYNAN bir xil sabab va naqsh).
--   Tanasida UCH MAJBURIY qorovul:
--     1) p_user = (SELECT auth.uid())            — PostgREST /rpc qorovuli
--     2) is_ws_member(t.workspace_id, p_user)    — jamoadan chiqarilgan xodim
--     3) assigned_by HAQIQIY huquqi bor odam bo'lsin  ← 🔴 ENG MUHIMI
--
--   🔴 NEGA 3-QOROVUL (huquq eskalatsiyasi):
--      Yangi SELECT policy YOZUV huquqini O'QISH huquqiga aylantiradi.
--      `task_subtasks` ga INSERT odatda `is_ws_member` bo'yicha KENG ochiq —
--      ya'ni oddiy a'zo istalgan vazifaga `assigned_to = O'ZIM` deb checklist
--      qatori yozib, o'sha vazifani o'qish huquqini O'ZIGA O'ZI berardi
--      (ws'dagi HAR QANDAY yopiq vazifa ochilib ketardi).
--      Shuning uchun qator faqat BIRIKTIRGAN ODAM huquqli bo'lsa ko'rinish
--      beradi: ws-menejeri YOKI vazifaning assigned_to / created_by /
--      acceptor_id si. O'ziga o'zi yozgan qator HECH NARSA ochmaydi.
--      Qiymatni trigger yozgani uchun uni soxtalashtirib ham bo'lmaydi.
--
-- ── NIMA O'ZGARMAYDI ────────────────────────────────────────────────────────
--   • tasks / task_subtasks / projects ning MAVJUD policy'lari — tegilmaydi.
--   • projects.status, recur_type, recur_time, recur_weekday, recur_monthday,
--     start_at, end_at, recurrence_* — bir belgi ham tegilmaydi.
--   • Hech qanday UPDATE/DELETE qilinmaydi. Skriptdagi "tirik" sinovlar
--     SENTINEL-ROLLBACK bilan bajariladi — bazada BITTA qator ham o'zgarmaydi.
--
-- ── BUSIZ ILOVA QANDAY ISHLAYDI ─────────────────────────────────────────────
--   RUN qilinmasa ilova AVVALGIDEK ishlaydi: mijoz "ustun yo'q" xatosini
--   (42703 / PGRST204) aniqlaydi, so'rovni shu ustunlarsiz qayta yuboradi va
--   sababni foydalanuvchiga OCHIQ aytadi (CLAUDE.md 6-qoida).
--
-- ── RUN TARTIBI ─────────────────────────────────────────────────────────────
--   1) 39_employee_details.sql (yoki 35_fix_projects_rls.sql) → is_ws_member(),
--      is_ws_manager() MAVJUD bo'lishi SHART (CLAUDE.md 8-qoida).
--   2) TASKFIX_LOYIHA_V2.sql  ← SHU FAYL
--   🔴 BOSHQA FAYLLARGA BOG'LIQ EMAS (boshqa ustun/funksiya/policy nomlari).
--
-- ── ⚠️ QACHON RUN QILINADI — ILOVA TO'XTASHI MUMKIN ─────────────────────────
--   🔴 ROSTINI AYTAMIZ: bu "bir necha soniya" emas.
--   • `ALTER TABLE ... ADD CONSTRAINT CHECK` → `projects` ga ACCESS EXCLUSIVE
--     (skript boshidan COMMIT gacha).
--   • `ALTER TABLE ... ADD COLUMN` + trigger → `task_subtasks` ga ACCESS
--     EXCLUSIVE (skript boshidan COMMIT gacha).
--   • `CREATE POLICY ... ON public.tasks` → `tasks` ga ACCESS EXCLUSIVE.
--     ⚠️ Bu qulf policy yaratilgan LAHZADAN COMMIT gacha ushlanadi, ORASIDA
--     esa "keyin" o'lchovi + tirik sinovlar bor: har namunaviy foydalanuvchi
--     uchun `tasks` bo'ylab TO'LIQ skan, har qatorda inline BO'LMAYDIGAN
--     `is_ws_member()` chaqiruvi. 20k vazifa × bir necha foydalanuvchi =
--     yuz minglab funksiya chaqiruvi → O'NLAB SONIYA, katta bazada DAQIQALAR.
--     Shu vaqt ichida vazifa/loyiha/checklist O'QILMAYDI ham, YOZILMAYDI ham —
--     ilova amalda TO'XTAB turadi.
--   ➜ Kechqurun / dam olish kuni ishga tushiring, foydalanuvchilarni
--     ogohlantiring. Sekin bo'lsa `v_max_mgr` / `v_max_mem` ni (9-bo'lim
--     boshidagi SOZLAMALAR) yanada kichraytiring — tekshiruv mantiqi
--     o'zgarmaydi, faqat namuna kichrayadi.
--   ➜ `tasks` qulfini imkon qadar KECH olish uchun barcha struktura
--     tekshiruvlari (ustun/CHECK/indeks/funksiya/trigger/grant) policy'dan
--     OLDIN bajariladi. ALTER TABLE'lar `tasks` ga TEGMAYDI.
--
-- ── ⚠️ QOLGAN XAVF (ochiq aytiladi, yashirilmaydi) ──────────────────────────
--   1) RLS **QATOR** darajasida ishlaydi: checklist punkti biriktirilgan odam
--      vazifaning BUTUN qatorini ko'radi (sarlavha, tavsif, deadline). Faqat
--      "punkt matni" ko'rinishi kerak bo'lsa alohida VIEW / SECURITY DEFINER
--      RPC kerak — bu fayl uni QILMAYDI (ataylab).
--
--   2) 🟡 GIGIENA (tuzatilmagan, ATAYLAB): har ws a'zosi O'ZI KO'RMAYDIGAN
--      vazifaga ham checklist punkti YOZIB QO'YA oladi — mavjud
--      task_subtasks INSERT policy'si odatda `is_ws_member` bo'yicha keng va bu
--      skript uni TORAYTIRMAYDI (mavjud "checklist qo'shish" oqimini
--      buzmaslik uchun). 🔴 O'QISH ESKALATSIYASI BU YERDA YO'Q: 2-qorovul
--      (a'zolik) va 3-qorovul (assigned_by huquqli bo'lsin) uni to'sadi —
--      ya'ni o'ziga o'zi yozgan qator hech qanday vazifani OCHMAYDI.
--      Bu — "begona jadvalga axlat yozish" masalasi, huquq masalasi emas.
--      Kerak bo'lsa alohida qaror bilan INSERT policy'si toraytiriladi.
--
--   3) 🟡 DELEGATSIYA (ATAYLAB shunday): vazifaning `assigned_to` si bo'lgan
--      ODDIY a'zo checklist punktini istalgan BOSHQA ws a'zosiga biriktirib,
--      o'sha vazifani unga OCHIB BERA oladi (3-qorovulda `assigned_by =
--      t.assigned_to` bor). Bu talabning o'zi ("bajaruvchi yordamchi
--      qo'shadi"), lekin natijada "vazifani ko'rish huquqini FAQAT admin
--      beradi" degan eski taxmin ENDI TO'G'RI EMAS. Faqat admin bersin
--      desangiz — 2-bo'limdagi `byexpr` dan `s.assigned_by = t.assigned_to`
--      (va acceptor) shoxlarini olib tashlang, `is_ws_manager` qoldiring.
--
--   4) 🟡 O'CHIRISH (DELETE) qorovulsiz: `task_subtasks_guard_trg` faqat
--      INSERT/UPDATE ni ushlaydi. Punktni kim o'chira olishi butunlay
--      MAVJUD DELETE policy'siga bog'liq — bu skript unga TEGMAYDI
--      (mavjud "punktni o'chirish" oqimi buzilmasin).
--
--   5) ⚠️ CHECK ichida foydalanuvchi funksiyasi (tf_smallint_set_ok)
--      ishlatilgani uchun pg_dump/restore da funksiya jadvaldan OLDIN
--      tiklanishi kerak.
--
-- TEXT/boolean/smallint[] + CHECK (ENUM EMAS) — 30/32-migratsiyalar saboqi.
-- Fayl oxirida QAYTARISH (rollback) bo'limi bor.
-- ============================================================================

-- ⚠️ TRANZAKSIYA — TARTIB MUHIM, O'ZGARTIRMANG:
--    `BEGIN;` va `SET TRANSACTION ...` skriptdagi ENG BIRINCHI ikki buyruq
--    bo'lishi shart (aks holda 25001).
BEGIN;
-- 🔴 REPEATABLE READ — busiz "oldin" va "keyin" sanoqlari BOSHQA sessiyaning
--    yozuvi sababli farq qilib, xavfsizlik tekshiruvi SOXTA "XAVFSIZLIK
--    BUZILDI" bilan yiqilardi.
-- ⚠️ AGAR "25001: SET TRANSACTION ISOLATION LEVEL must be called before any
--    query" chiqsa — quyidagi qatorni izohga oling va qayta RUN qiling.
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- 🔴 search_path BUTUN skript uchun SHU YERDA belgilanadi (oxirida emas):
--    quyidagi DO bloklari ham policy'lardagi `is_ws_member(...)` kabi
--    prefikssiz nomlar ham bir xil qoidada baholansin. Temp jadvallarga
--    doim `pg_temp.` prefiksi bilan murojaat qilinadi.
SET LOCAL search_path = public, extensions;


-- ════════════════════════════════════════════════════════════════════════════
-- 0) DIAGNOSTIKA — FAQAT O'QIYDI. Natijani "Messages"/"Notices" da o'qing.
--    🔴 Mavjud policy'larni KO'RMASDAN yangi policy qo'shilmaydi.
-- ════════════════════════════════════════════════════════════════════════════
DO $diag$
DECLARE
  r   RECORD;
  v_t text;
  v_n int;
BEGIN
  RAISE NOTICE '════════ DIAGNOSTIKA (o''zgarishdan OLDINGI holat) ════════';

  FOREACH v_t IN ARRAY ARRAY['tasks','task_subtasks','projects'] LOOP
    IF to_regclass('public.' || v_t) IS NULL THEN
      RAISE WARNING 'public.% jadvali YO''Q', v_t;
      CONTINUE;
    END IF;
    SELECT count(*) INTO v_n
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = v_t AND c.relrowsecurity;
    RAISE NOTICE '── public.% : RLS %', v_t,
      CASE WHEN v_n > 0 THEN 'YOQILGAN' ELSE '❗ O''CHIQ' END;
  END LOOP;

  FOR r IN
    SELECT tablename, policyname, cmd, permissive,
           array_to_string(roles, ',') AS roles, qual, with_check
      FROM pg_policies
     WHERE schemaname = 'public' AND tablename IN ('tasks','task_subtasks')
     ORDER BY tablename, cmd, policyname
  LOOP
    RAISE NOTICE '   [%] % (% · % · %)  USING: %  CHECK: %',
      r.tablename, r.policyname, r.cmd, r.permissive, r.roles,
      coalesce(r.qual, '—'), coalesce(r.with_check, '—');
  END LOOP;

  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='public' AND tablename IN ('tasks','task_subtasks')
     AND permissive = 'RESTRICTIVE';
  IF v_n > 0 THEN
    RAISE WARNING '⚠️ % ta RESTRICTIVE policy bor — ular AND bilan qo''llanadi va yangi PERMISSIVE policy ularni YENGA OLMAYDI.', v_n;
  ELSE
    RAISE NOTICE '   RESTRICTIVE policy yo''q — yangi PERMISSIVE policy to''liq kuchga kiradi.';
  END IF;

  RAISE NOTICE '════════ DIAGNOSTIKA TUGADI ════════';
END $diag$;


-- ════════════════════════════════════════════════════════════════════════════
-- 1) OLD SHARTLAR — noto'g'ri/yarim bazada ishga tushmasin
--    ⚠️ Trigger STATIK yozilgan (dinamik emas — o'qilishi oson bo'lsin),
--       shuning uchun u tegadigan HAR USTUN shu yerda TASDIQLANADI.
--       Ustun yo'q bo'lsa trigger ishga tushganda 42703 bilan yiqilardi.
-- ════════════════════════════════════════════════════════════════════════════
DO $pre$
DECLARE
  v_c   text;
  v_def text;
  v_idn text;
BEGIN
  IF to_regclass('public.projects') IS NULL THEN
    RAISE EXCEPTION 'public.projects topilmadi — bu TaskFix bazasi emasmi?';
  END IF;
  IF to_regclass('public.tasks') IS NULL THEN
    RAISE EXCEPTION 'public.tasks topilmadi — bu TaskFix bazasi emasmi?';
  END IF;
  IF to_regclass('public.task_subtasks') IS NULL THEN
    RAISE EXCEPTION 'public.task_subtasks topilmadi — checklist moduli MAVJUD jadvalni kengaytiradi, yangi jadval yaratmaydi. To''xtatildi.';
  END IF;

  -- tasks: RLS va trigger tayanadigan ustunlar
  FOREACH v_c IN ARRAY ARRAY['workspace_id','assigned_to','created_by'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='tasks' AND column_name=v_c) THEN
      RAISE EXCEPTION 'public.tasks.% ustuni yo''q — checklist qorovullari aynan shu ustunlarga tayanadi. To''xtatildi.', v_c;
    END IF;
  END LOOP;

  -- task_subtasks: trigger nomma-nom tegadigan ustunlar
  FOREACH v_c IN ARRAY ARRAY['id','task_id','workspace_id','title','sort_order','is_completed'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='task_subtasks' AND column_name=v_c) THEN
      RAISE EXCEPTION 'public.task_subtasks.% ustuni yo''q — bu skriptdagi trigger unga nomma-nom murojaat qiladi (ustun darajasidagi qorovul). Sxema kutilganidan boshqa. To''xtatildi.', v_c;
    END IF;
  END LOOP;

  -- F9: id o'zi to'lanadimi? (tirik sinov qator yozadi — 23502 ga urilmasin)
  SELECT column_default, is_identity INTO v_def, v_idn
    FROM information_schema.columns
   WHERE table_schema='public' AND table_name='task_subtasks' AND column_name='id';
  IF v_def IS NULL AND coalesce(v_idn,'NO') <> 'YES' THEN
    RAISE WARNING '⚠️ public.task_subtasks.id da DEFAULT ham, IDENTITY ham yo''q — qiymatni mijoz yuborishi kerak. Skriptdagi TIRIK sinov qator yozadi, shuning uchun u o''tkazib yuboriladi (sabab yakuniy hisobotda ko''rinadi). Migratsiyaning qolgan qismi normal bajariladi.';
  END IF;

  -- 🔴 CLAUDE.md 8-qoida: policy ichida workspace_members inline subquery
  --    YOZILMAYDI (42P17) — shu sababli bu ikki funksiya SHART.
  -- 🔴 IMZO ham tekshiriladi, faqat NOM emas: policy'lar va funksiyalar
  --    aynan (uuid, uuid) imzosini chaqiradi. Boshqa imzoli nusxa bo'lsa
  --    xato faqat RUN paytida, xom 42883 matni bilan chiqardi.
  IF to_regprocedure('public.is_ws_member(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'is_ws_member(uuid, uuid) topilmadi (nomi bor, imzosi boshqa bo''lishi mumkin). Avval 39_employee_details.sql (yoki 35_fix_projects_rls.sql) ni ishga tushiring.';
  END IF;
  IF to_regprocedure('public.is_ws_manager(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'is_ws_manager(uuid, uuid) topilmadi (nomi bor, imzosi boshqa bo''lishi mumkin). Avval 35_fix_projects_rls.sql / 39_employee_details.sql ni ishga tushiring.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    RAISE EXCEPTION '`authenticated` roli topilmadi — bu Supabase bazasi emasmi?';
  END IF;

  -- 🔴 N1: ANON YOZUV YO'LI BO'LMASLIGI SHART.
  --    Butun modul "assigned_by ni SERVER yozadi" invariantiga tayanadi.
  --    Trigger JWT'siz chaqiruvda assigned_by ni NULL qiladi — ya'ni anon
  --    yozgan qator hech narsa OCHMAYDI. Lekin anon uchun ochiq INSERT/UPDATE
  --    yo'li bo'lsa checklist jadvaliga begona qator to'kib tashlash mumkin.
  --    ⚠️ Supabase odatda anon ga JADVAL darajasida grant beradi va RLS bilan
  --       to'sadi — shuning uchun YAKKA grant XATO EMAS. EXCEPTION faqat
  --       grant VA mos policy IKKALASI ham bo'lganda.
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    IF (has_table_privilege('anon', 'public.task_subtasks', 'INSERT')
        OR has_table_privilege('anon', 'public.task_subtasks', 'UPDATE')) THEN
      -- 🔴 IKKI XIL HOLAT — ular BIR XIL EMAS:
      --    (a) policy'da ANIQ 'anon' ko'rsatilgan → haqiqiy yo'l → EXCEPTION.
      --    (b) policy TO bandisiz yaratilgan (roles = {public}) → eski
      --        migratsiyalarda ODATIY holat. Amalda anon u orqali o'ta
      --        olmaydi (shart odatda auth.uid() ga tayanadi, anon'da u NULL),
      --        shuning uchun MIGRATSIYA TO'XTAMAYDI — faqat WARNING.
      --        Avval {public} ham EXCEPTION berardi va skript soxta
      --        "XAVFSIZ EMAS" bilan yiqilardi.
      IF EXISTS (
        SELECT 1 FROM pg_policies
         WHERE schemaname='public' AND tablename='task_subtasks'
           AND cmd IN ('INSERT','UPDATE','ALL')
           AND roles @> ARRAY['anon']::name[]
      ) THEN
        RAISE EXCEPTION 'XAVFSIZ EMAS: anon roli public.task_subtasks ga YOZA oladi — grant BOR va policy''da ANIQ "anon" ko''rsatilgan. Checklist moduli "assigned_by ni server yozadi" invariantiga tayanadi va kirmagan foydalanuvchi jadvalga qator to''kib tashlashi mumkin. Avval o''sha policy''ni TO authenticated bilan cheklang, keyin bu skriptni qayta ishga tushiring.';
      ELSIF EXISTS (
        SELECT 1 FROM pg_policies
         WHERE schemaname='public' AND tablename='task_subtasks'
           AND cmd IN ('INSERT','UPDATE','ALL')
           AND roles @> ARRAY['public']::name[]
      ) THEN
        RAISE WARNING '⚠️ task_subtasks da TO bandisiz (roles = {public}) INSERT/UPDATE policy bor va anon da jadval granti mavjud. Amalda anon u orqali o''ta olmaydi (policy sharti odatda auth.uid() ga tayanadi, anon''da esa u NULL) — shuning uchun migratsiya TO''XTAMAYDI. Baribir o''sha policy''ga TO authenticated qo''shish TAVSIYA etiladi (himoya bitta shartga emas, ikki qatlamga tayansin).';
      ELSE
        RAISE NOTICE 'ℹ️ anon da task_subtasks uchun jadval-darajasidagi grant bor, lekin mos policy YO''Q — RLS to''sadi (Supabase sukut holati, normal).';
      END IF;
    END IF;
  END IF;
END $pre$;


-- ════════════════════════════════════════════════════════════════════════════
-- 2) FK NISHONI + QOROVUL IFODALARI — TAXMIN QILMAYMIZ, KATALOGDAN O'QIYMIZ
--    🔴 Eng ishonchli yo'l: `tasks.assigned_to` QAYSI jadvalga FK bo'lsa,
--       yangi "odam" ustunlari ham AYNAN o'shanga bog'lanadi (repoda 1–37
--       migratsiyalar yo'q, nishonni qattiq yozib qo'yib bo'lmaydi).
--    🔴 `byexpr` / `ownexpr` — 3-qorovul ifodalari BIR MARTA quriladi va
--       funksiya, trigger VA o'lchov so'rovi AYNAN o'shani ishlatadi. Busiz
--       ular vaqt o'tib bir-biridan farq qilib ketardi va "kutilgan son"
--       tekshiruvi soxta xato berardi.
-- ════════════════════════════════════════════════════════════════════════════
DROP TABLE IF EXISTS pg_temp.v2_ref;
CREATE TEMP TABLE pg_temp.v2_ref (k text PRIMARY KEY, ref text, izoh text);

DO $ref$
DECLARE
  v_t   text;
  v_c   text;
  v_acc boolean;
  v_by  text;
  v_own text;
BEGIN
  -- ── 2.a) FK nishoni ───────────────────────────────────────────────────────
  -- ⚠️ ORDER BY conname — bir nechta mos FK bo'lsa tanlov DETERMINISTIK
  --    bo'lsin (aks holda qayta RUN da boshqa nishon tanlanishi mumkin edi).
  SELECT c.confrelid::regclass::text, af.attname
    INTO v_t, v_c
    FROM pg_constraint c
    JOIN pg_attribute a  ON a.attrelid  = c.conrelid  AND a.attnum  = c.conkey[1]
    JOIN pg_attribute af ON af.attrelid = c.confrelid AND af.attnum = c.confkey[1]
   WHERE c.conrelid = 'public.tasks'::regclass
     AND c.contype  = 'f'
     AND array_length(c.conkey, 1) = 1
     AND a.attname  = 'assigned_to'
   ORDER BY c.conname
   LIMIT 1;

  IF v_t IS NOT NULL THEN
    -- ⚠️ quote_ident: g'alati ustun nomi (bosh harf / probel / kalit so'z)
    --    bo'lsa ALTER TABLE buzilmasin. v_t regclass'dan kelgani uchun
    --    allaqachon to'g'ri qo'shtirnoqlangan.
    v_c := quote_ident(v_c);
    INSERT INTO pg_temp.v2_ref VALUES
      ('user', v_t || '(' || v_c || ')', 'tasks.assigned_to FK dan olindi');
    RAISE NOTICE 'FK nishoni: % (tasks.assigned_to bilan BIR XIL)', v_t || '(' || v_c || ')';
  ELSIF to_regclass('public.profiles') IS NOT NULL THEN
    INSERT INTO pg_temp.v2_ref VALUES
      ('user', 'public.profiles(id)', 'tasks.assigned_to da FK yo''q — public.profiles(id) ishlatildi');
    RAISE NOTICE 'tasks.assigned_to da FK topilmadi — nishon: public.profiles(id)';
  ELSIF to_regclass('auth.users') IS NOT NULL THEN
    INSERT INTO pg_temp.v2_ref VALUES
      ('user', 'auth.users(id)', 'profiles topilmadi — auth.users(id) ishlatildi');
    RAISE NOTICE 'public.profiles topilmadi — nishon: auth.users(id)';
  ELSE
    INSERT INTO pg_temp.v2_ref VALUES
      ('user', NULL, 'mos jadval topilmadi — ustunlar FK''SIZ qo''shildi');
    RAISE NOTICE 'ℹ️ FK nishoni topilmadi — ustunlar FK''SIZ qo''shiladi.';
  END IF;

  -- ── 2.b) acceptor_id bormi? ───────────────────────────────────────────────
  v_acc := EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='tasks'
                      AND column_name='acceptor_id');

  -- 🔴 3-QOROVUL IFODASI (huquq eskalatsiyasiga qarshi):
  --    checklist qatorini BIRIKTIRGAN odam haqiqiy huquqqa ega bo'lsin.
  v_by := 's.assigned_by IS NOT NULL AND ('
       || 'public.is_ws_manager(t.workspace_id, s.assigned_by)'
       || ' OR s.assigned_by = t.assigned_to'
       || ' OR s.assigned_by = t.created_by'
       || CASE WHEN v_acc THEN ' OR s.assigned_by = t.acceptor_id' ELSE '' END
       || ')';

  -- Trigger uchun: "tahrirlayotgan odam vazifa egasimi yoki ws-menejerimi?"
  v_own := 'public.is_ws_manager(t.workspace_id, v_uid)'
        || ' OR v_uid = t.assigned_to'
        || ' OR v_uid = t.created_by'
        || CASE WHEN v_acc THEN ' OR v_uid = t.acceptor_id' ELSE '' END;

  INSERT INTO pg_temp.v2_ref VALUES ('byexpr',  v_by,  '3-qorovul: kim biriktirgan');
  INSERT INTO pg_temp.v2_ref VALUES ('ownexpr', v_own, 'trigger: vazifa egasi / ws-menejeri');
  INSERT INTO pg_temp.v2_ref VALUES ('acceptor',
    CASE WHEN v_acc THEN 'bor' ELSE 'yo''q' END,
    'tasks.acceptor_id ustuni — bor bo''lsa qorovullarga qo''shildi');

  RAISE NOTICE '3-qorovul ifodasi: %', v_by;
  IF NOT v_acc THEN
    RAISE NOTICE 'ℹ️ tasks.acceptor_id ustuni yo''q — qorovullar assigned_to + created_by bilan quriladi.';
  END IF;
END $ref$;


-- ════════════════════════════════════════════════════════════════════════════
-- 3) YORDAMCHI FUNKSIYA — smallint[] to'plamini tekshirish
--    🔴 IMMUTABLE bo'lishi SHART: CHECK cheklovi faqat IMMUTABLE funksiyani
--       qabul qiladi. Ayni paytda CHECK ichida SUBQUERY yozib bo'lmaydi —
--       `unnest` + `count(DISTINCT)` aynan shuning uchun funksiya ichida.
--    Qoidalar: NULL → to'g'ri (belgilanmagan) · bo'sh massiv → XATO ·
--    element NULL → XATO · [lo,hi] dan tashqarida → XATO · TAKROR → XATO.
--    ⚠️ Bo'sh massiv ataylab RAD ETILADI: yagona "tanlanmagan" holat — NULL.
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.tf_smallint_set_ok(a smallint[], lo int, hi int)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $body$
  SELECT a IS NULL
      OR (
           array_ndims(a) = 1
           AND cardinality(a) > 0
           AND NOT EXISTS (
                 SELECT 1 FROM unnest(a) AS x
                  WHERE x IS NULL OR x < lo OR x > hi
               )
           AND cardinality(a) = (SELECT count(DISTINCT x) FROM unnest(a) AS x)
         );
$body$;

COMMENT ON FUNCTION public.tf_smallint_set_ok(smallint[], int, int) IS
  'CHECK yordamchisi: smallint[] to''plami to''g''rimi? NULL=to''g''ri (belgilanmagan); bo''sh massiv, NULL element, [lo,hi] dan tashqari qiymat va TAKROR — rad etiladi. IMMUTABLE (CHECK talabi).';


-- ════════════════════════════════════════════════════════════════════════════
-- 4) public.projects — 4 YANGI USTUN
--    🔴 Hammasi NULL / false bilan tug'iladi = ESKI XATTI-HARAKAT.
-- ════════════════════════════════════════════════════════════════════════════
ALTER TABLE public.projects ADD COLUMN IF NOT EXISTS recur_weekdays  smallint[];
ALTER TABLE public.projects ADD COLUMN IF NOT EXISTS recur_monthdays smallint[];
ALTER TABLE public.projects ADD COLUMN IF NOT EXISTS responsible_id  uuid;
ALTER TABLE public.projects ADD COLUMN IF NOT EXISTS respect_dayoff  boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.projects.recur_weekdays IS
  'Haftalik takrorlanish KUNLARI (multiselect): 0=Yakshanba … 6=Shanba, JS getDay(). NULL = belgilanmagan → mijoz ESKI bitta qiymatli recur_weekday ni ishlatadi. Bo''sh massiv RAD ETILADI.';
COMMENT ON COLUMN public.projects.recur_monthdays IS
  'Oylik takrorlanish KUNLARI (multiselect) 1..31. NULL = belgilanmagan → mijoz ESKI recur_monthday ni ishlatadi. Bo''sh massiv RAD ETILADI.';
COMMENT ON COLUMN public.projects.responsible_id IS
  'Loyihaga MAS''UL odam (ixtiyoriy). NULL = belgilanmagan. HUQUQ BERMAYDI — faqat ko''rsatish/filtr uchun.';
COMMENT ON COLUMN public.projects.respect_dayoff IS
  'true → muddat hisobida bajaruvchining DAM OLISH kuni hisobga olinadi (mijoz mantiqi, dof* moduli). DEFAULT false = hozirgi xatti-harakat.';

-- ── 4.1) CHECK'lar (conrelid bilan SKOPLANGAN, conname global unique EMAS) ──
DO $chk$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'projects_recur_weekdays_chk'
                    AND conrelid = 'public.projects'::regclass) THEN
    ALTER TABLE public.projects
      ADD CONSTRAINT projects_recur_weekdays_chk
      CHECK (recur_weekdays IS NULL OR public.tf_smallint_set_ok(recur_weekdays, 0, 6));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'projects_recur_monthdays_chk'
                    AND conrelid = 'public.projects'::regclass) THEN
    ALTER TABLE public.projects
      ADD CONSTRAINT projects_recur_monthdays_chk
      CHECK (recur_monthdays IS NULL OR public.tf_smallint_set_ok(recur_monthdays, 1, 31));
  END IF;
END $chk$;

-- ── 4.2) responsible_id FK ──────────────────────────────────────────────────
DO $fk1$
DECLARE
  v_ref text;
BEGIN
  SELECT ref INTO v_ref FROM pg_temp.v2_ref WHERE k = 'user';
  IF v_ref IS NULL THEN
    RAISE NOTICE 'ℹ️ projects.responsible_id FK''SIZ qoldirildi (mos nishon topilmadi).';
  ELSIF EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'projects_responsible_fk'
                   AND conrelid = 'public.projects'::regclass) THEN
    RAISE NOTICE 'projects_responsible_fk allaqachon bor — tegilmadi.';
  ELSE
    EXECUTE format(
      'ALTER TABLE public.projects ADD CONSTRAINT projects_responsible_fk '
      'FOREIGN KEY (responsible_id) REFERENCES %s ON DELETE SET NULL', v_ref);
    RAISE NOTICE '✅ projects_responsible_fk → %', v_ref;
  END IF;
END $fk1$;


-- ════════════════════════════════════════════════════════════════════════════
-- 5) public.task_subtasks — CHECKLIST kengaytmasi
--    🔴 YANGI JADVAL YARATILMAYDI: mavjud jadval kengaytiriladi, ya'ni
--       mavjud ma'lumot, RLS holati va MAVJUD policy'lar SAQLANADI.
-- ════════════════════════════════════════════════════════════════════════════
ALTER TABLE public.task_subtasks ADD COLUMN IF NOT EXISTS assigned_to uuid;
ALTER TABLE public.task_subtasks ADD COLUMN IF NOT EXISTS assigned_by uuid;
ALTER TABLE public.task_subtasks ADD COLUMN IF NOT EXISTS file_url    text;
ALTER TABLE public.task_subtasks ADD COLUMN IF NOT EXISTS file_name   text;
ALTER TABLE public.task_subtasks ADD COLUMN IF NOT EXISTS file_size   bigint;
ALTER TABLE public.task_subtasks ADD COLUMN IF NOT EXISTS done_at     timestamptz;
ALTER TABLE public.task_subtasks ADD COLUMN IF NOT EXISTS done_by     uuid;

COMMENT ON COLUMN public.task_subtasks.assigned_to IS
  'Checklist punkti kimga biriktirilgan. NULL = umumiy (eski qatorlar). Bu ustun tufayli odam VAZIFANI ham ko''ra oladi (policy tasks_select_checklist_assignee) — lekin FAQAT O''QISH va faqat assigned_by huquqli bo''lsa.';
COMMENT ON COLUMN public.task_subtasks.assigned_by IS
  '🔴 KIM biriktirgan. QIYMATNI FAQAT task_subtasks_guard_trg TRIGGER''i yozadi — mijoz yuborgan qiymat E''TIBORGA OLINMAYDI. Huquq eskalatsiyasining oldini oladi: o''ziga o''zi yozgan checklist qatori vazifani OCHMAYDI (can_see_task_via_checklist 3-qorovuli).';
COMMENT ON COLUMN public.task_subtasks.file_url IS
  'Punktga biriktirilgan fayl (public URL). Fayl MAVJUD `attachments` bucket''ida, MAVJUD yo''l naqshi bilan: <workspace_id>/<task_id>/<ts>_<nom>. Yangi Storage policy''si KERAK EMAS. ⚠️ Bucket PUBLIC — havolani bilgan har kim yuklab oladi (task_attachments bilan bir xil).';
COMMENT ON COLUMN public.task_subtasks.file_name IS 'Fayl nomi (ko''rsatish uchun) — task_attachments.file_name naqshi.';
COMMENT ON COLUMN public.task_subtasks.file_size IS 'Fayl hajmi (bayt) — task_attachments.file_size naqshi.';
COMMENT ON COLUMN public.task_subtasks.done_at IS 'Punkt qachon bajarildi. TRIGGER yozadi (is_completed false→true). Mavjud is_completed ustuniga TEGILMAGAN.';
COMMENT ON COLUMN public.task_subtasks.done_by IS
  'Punktni kim bajardi. TRIGGER yozadi (soxtalashtirib bo''lmasin). ⚠️ FK ATAYLAB YO''Q: bu AUDIT maydoni — odam o''chirilsa ham yozuv qolishi kerak (ON DELETE SET NULL uni jimgina yo''qotardi).';

-- ── 5.1) assigned_to / assigned_by FK (nishon 2-bo'limdan) ──────────────────
DO $fk2$
DECLARE
  v_ref text;
  r     RECORD;
BEGIN
  SELECT ref INTO v_ref FROM pg_temp.v2_ref WHERE k = 'user';

  IF v_ref IS NULL THEN
    RAISE NOTICE 'ℹ️ task_subtasks.assigned_to / assigned_by FK''SIZ qoldirildi (mos nishon topilmadi).';
    RETURN;
  END IF;

  FOR r IN SELECT * FROM (VALUES
      ('task_subtasks_assigned_fk',    'assigned_to'),
      ('task_subtasks_assigned_by_fk', 'assigned_by')
    ) AS x(con, col)
  LOOP
    IF EXISTS (SELECT 1 FROM pg_constraint
                WHERE conname = r.con AND conrelid = 'public.task_subtasks'::regclass) THEN
      RAISE NOTICE '% allaqachon bor — tegilmadi.', r.con;
    ELSE
      EXECUTE format(
        'ALTER TABLE public.task_subtasks ADD CONSTRAINT %I '
        'FOREIGN KEY (%I) REFERENCES %s ON DELETE SET NULL', r.con, r.col, v_ref);
      RAISE NOTICE '✅ % → %', r.con, v_ref;
    END IF;
  END LOOP;
END $fk2$;

-- ── 5.2) Qisman indeks ──────────────────────────────────────────────────────
-- ⚠️ QISMAN (`WHERE assigned_to IS NOT NULL`): punktlarning katta qismi
--    biriktirilmagan — ular indeksga umuman kirmaydi. Yangi policy ham doim
--    `assigned_to = auth.uid()` bilan keladi.
CREATE INDEX IF NOT EXISTS idx_task_subtasks_assigned
  ON public.task_subtasks (assigned_to)
  WHERE assigned_to IS NOT NULL;


-- ════════════════════════════════════════════════════════════════════════════
-- 6) 🔴 TRIGGER — assigned_by ni FAQAT SERVER yozadi + USTUN darajasidagi qorovul
--
--    NEGA POLICY YETMAYDI:
--      • `assigned_by` ni policy bilan "faqat auth.uid() bo'lsin" deb
--        mahkamlash mumkin (WITH CHECK), lekin u holda mijoz uni YUBORISHI
--        shart bo'lardi va har eski chaqiruv (mavjud addSubtask) buzilardi.
--        Trigger esa qiymatni O'ZI qo'yadi — mijoz kodi umuman o'zgarmaydi.
--      • RLS QATOR darajasida ishlaydi: "faqat is_completed ni o'zgartir"
--        degan qoidani policy bilan IFODALAB BO'LMAYDI. Ustun darajasidagi
--        GRANT ham mo'rt (ustunlar ro'yxati vaqt bilan o'zgaradi va REVOKE
--        butun jadvalga ta'sir qiladi).
--      Yagona to'g'ri, ADDITIV va aniq nishonli yechim — BEFORE trigger.
--
--    ⚠️ SECURITY INVOKER (ataylab): `current_user` server tomonini aniqlash
--       uchun kerak. SECURITY DEFINER bo'lsa `current_user` doim `postgres`
--       bo'lib qolardi va trigger HECH QACHON ishlamasdi.
--    ⚠️ Trigger `tasks` ni CHAQIRUVCHI huquqi bilan o'qiydi: qator ko'rinmasa
--       v_priv NULL → false, ya'ni XAVFSIZ tomonga og'adi (cheklov qattiqroq).
-- ════════════════════════════════════════════════════════════════════════════
DO $trg$
DECLARE
  v_own   text;
  v_guard text;
  v_white text[];
BEGIN
  SELECT ref INTO v_own FROM pg_temp.v2_ref WHERE k = 'ownexpr';
  IF v_own IS NULL THEN
    RAISE EXCEPTION 'ownexpr ifodasi qurilmagan — 2-bo''lim bajarilmadimi?';
  END IF;

  -- 🔴 OQ RO'YXAT — YAGONA MANBA.
  --    Ro'yxat FAQAT shu yerda yoziladi; qorovul generatsiyasi ham, pastdagi
  --    NOTICE ham AYNAN shu massivni o'qiydi. Avval u ikki joyda takrorlangan
  --    edi — biri o'zgarsa NOTICE jimgina yolg'on chiqarardi.
  v_white := ARRAY['is_completed','file_url','file_name','file_size',
                   'done_at','done_by','assigned_by'];

  -- 🔴 updated_at — MAVJUD bo'lsa oq ro'yxatga QO'SHILADI.
  --    Sabab: Supabase'da keng tarqalgan handle_updated_at / set_updated_at
  --    BEFORE UPDATE trigger'i BIZNING qorovuldan OLDIN ishlab NEW.updated_at
  --    ni yozib qo'yadi. U himoyalangan ro'yxatda qolsa bajaruvchining HAR
  --    "bajarildi" bosishi 42501 bilan yiqilardi — modul jimgina o'lardi.
  --    Audit vaqt belgisini bajaruvchi yozishi zararsiz (u ma'no tashimaydi).
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='task_subtasks'
                AND column_name='updated_at') THEN
    v_white := v_white || 'updated_at'::text;
    RAISE NOTICE 'ℹ️ task_subtasks.updated_at topildi — oq ro''yxatga qo''shildi (boshqa BEFORE UPDATE trigger''i uni yozishi mumkin).';
  END IF;

  -- 🔴 Himoyalanadigan ustunlar KATALOGDAN o'qiladi, ya'ni jadvalga ERTAGA
  --    qo'shiladigan ustun ham AVTOMAT himoyalanadi.
  SELECT string_agg(
           '    IF NEW.' || quote_ident(column_name) ||
           ' IS DISTINCT FROM OLD.' || quote_ident(column_name) || ' THEN' || chr(10) ||
           '      RAISE EXCEPTION ' ||
           quote_literal('Checklist punktining "' || column_name ||
                         '" maydonini faqat vazifa egasi (bajaruvchi / yaratuvchi / qabul qiluvchi) yoki workspace admini o''zgartira oladi.') ||
           chr(10) || '        USING ERRCODE = ' || quote_literal('42501') || ';' || chr(10) ||
           '    END IF;',
           chr(10) ORDER BY ordinal_position)
    INTO v_guard
    FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name   = 'task_subtasks'
     AND column_name::text <> ALL (v_white);
  IF v_guard IS NULL THEN
    -- Bo'lishi mumkin emas (task_id/title bor), lekin bo'sh blok yozib
    -- qo'yish sintaksis xatosi berardi.
    v_guard := '    NULL;';
  END IF;

  EXECUTE format($tf$
CREATE OR REPLACE FUNCTION public.task_subtasks_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $tb$
DECLARE
  v_uid  uuid;
  v_priv boolean;
BEGIN
  -- Server tomoni (SQL Editor / service_role): trigger ARALASHMAYDI — u
  -- allaqachon to'liq huquqli va assigned_by ni o'zi to'g'ri yozadi
  -- (wm_planner_flag_guard naqshi). Shu shox tufayli SQL/EF orqali
  -- assigned_by ni qo'lda berish mumkin.
  --
  -- 🔴 "v_uid IS NULL OR" SHARTI ATAYLAB OLIB TASHLANGAN — QAYTA QO'SHMANG.
  --    U turganda butun qorovul chetlab o'tilardi: JWT'siz istalgan yozuv
  --    yo'lida (anon policy, tashqi ulanish) trigger umuman ishlamas,
  --    MIJOZ YUBORGAN assigned_by esa o'z holicha qolardi →
  --    can_see_task_via_checklist() uni "menejer biriktirgan" deb qabul
  --    qilib, huquq eskalatsiyasi yo'li ochilardi.
  --    Endi bunday chaqiruvda pastdagi 1-bo'lim assigned_by ni NULL qiladi
  --    (v_uid NULL) va 3-qorovuldagi "assigned_by IS NOT NULL" uni to'sadi.
  --    ⚠️ Server tomonini aniqlash IKKI QATLAM: aniq rollar ro'yxati VA
  --       superuser/bypassrls bayrog'i. Ikkinchisi busiz skript boshqa
  --       superuser (migratsiya vositasi) ostida ishga tushirilsa trigger
  --       uni "mijoz" deb bilib, harnessning assigned_by qiymatini NULL
  --       qilardi va (a) sinovi SOXTA yiqilardi. bypassrls/superuser roli
  --       allaqachon hamma narsani o'qiy/yoza oladi — yangi xavf yo'q.
  v_uid := (SELECT auth.uid());
  IF current_user IN ('postgres', 'supabase_admin', 'service_role')
     OR (SELECT coalesce(bool_or(r.rolsuper OR r.rolbypassrls), false)
           FROM pg_roles r WHERE r.rolname = current_user) THEN
    RETURN NEW;
  END IF;

  -- ── 1) assigned_by MIJOZDAN QABUL QILINMAYDI ──────────────────────────────
  -- 🔴 MAJBURIY: busiz foydalanuvchi assigned_by ga menejer uuid'sini yozib
  --    can_see_task_via_checklist() ning 3-qorovulini chetlab o'tardi.
  IF TG_OP = 'INSERT' THEN
    IF NEW.assigned_to IS NULL THEN
      NEW.assigned_by := NULL;
    ELSE
      NEW.assigned_by := v_uid;
    END IF;
  ELSE
    IF NEW.assigned_to IS DISTINCT FROM OLD.assigned_to THEN
      IF NEW.assigned_to IS NULL THEN
        NEW.assigned_by := NULL;
      ELSE
        NEW.assigned_by := v_uid;
      END IF;
    ELSE
      NEW.assigned_by := OLD.assigned_by;
    END IF;
  END IF;

  -- ── 2) Kim tahrirlayapti: ws-menejeri yoki VAZIFA egasi? ──────────────────
  SELECT (%s) INTO v_priv FROM public.tasks t WHERE t.id = NEW.task_id;
  v_priv := coalesce(v_priv, false);

  -- ── 3) USTUN darajasidagi qorovul (faqat UPDATE, faqat huquqsiz odam) ─────
  -- 🔴 OQ RO'YXAT (qora ro'yxat EMAS): egasi bo'lmagan odamga FAQAT
  --    is_completed / file_url / file_name / file_size / done_at / done_by /
  --    assigned_by o'zgarishi ochiq. QOLGAN HAR QANDAY ustun — bugun bor
  --    va ERTAGA QO'SHILADIGANI ham — YOPIQ.
  --    Qora ro'yxat bo'lganda jadvalga yangi ustun qo'shilishi bilan teshik
  --    ochilardi (created_at, created_by, priority… — hech kim triggerni
  --    yangilashni eslamasdi). Ro'yxat KATALOGDAN o'qib generatsiya qilinadi.
  -- ⚠️ done_at / done_by oq ro'yxatda, chunki ularni pastdagi 4-bo'lim
  --    BARIBIR qayta yozadi (mijoz qiymati saqlanmaydi).
  -- ⚠️ assigned_by ham oq ro'yxatda: uni yuqoridagi 1-bo'lim TO'LIQ
  --    boshqaradi (assigned_to o'zgarmasa OLD qiymat qaytariladi), ya'ni bu
  --    yerda uni tekshirish O'LIK KOD bo'lardi va tekshiruvlar tartibiga
  --    bog'liq soxta xato berishi mumkin edi.
  -- 🔴 JIMGINA QAYTARILMAYDI — ochiq xato (CLAUDE.md 6-qoida).
  -- ⚠️ DELETE qorovuli YO'Q (ataylab, mavjud oqim buzilmasin): punktni
  --    o'chirish butunlay MAVJUD task_subtasks DELETE policy'siga tayanadi —
  --    bu skript unga TEGMAYDI.
  IF TG_OP = 'UPDATE' AND NOT v_priv THEN
%s
  END IF;

  -- ── 4) done_at / done_by — HAR DOIM TRIGGER yozadi ────────────────────────
  -- Mijoz yuborgan qiymat e'tiborga olinmaydi (audit soxtalashtirilmasin).
  IF TG_OP = 'INSERT' THEN
    IF coalesce(NEW.is_completed, false) THEN
      NEW.done_by := v_uid;
      NEW.done_at := now();
    ELSE
      NEW.done_by := NULL;
      NEW.done_at := NULL;
    END IF;
  ELSE
    IF coalesce(NEW.is_completed, false) AND NOT coalesce(OLD.is_completed, false) THEN
      NEW.done_by := v_uid;
      NEW.done_at := now();
    ELSIF NOT coalesce(NEW.is_completed, false) AND coalesce(OLD.is_completed, false) THEN
      NEW.done_by := NULL;
      NEW.done_at := NULL;
    ELSE
      NEW.done_by := OLD.done_by;
      NEW.done_at := OLD.done_at;
    END IF;
  END IF;

  RETURN NEW;
END
$tb$
  $tf$, v_own, v_guard);

  RAISE NOTICE 'task_subtasks_guard() yaratildi (egalik ifodasi: %)', v_own;
  RAISE NOTICE 'Oq ro''yxat (egasi bo''lmagan odam ham yoza oladi): %',
    array_to_string(v_white, ', ');
  RAISE NOTICE 'Himoyalangan ustunlar (qolgan HAMMASI): %',
    (SELECT string_agg(column_name, ', ' ORDER BY ordinal_position)
       FROM information_schema.columns
      WHERE table_schema='public' AND table_name='task_subtasks'
        AND column_name::text <> ALL (v_white));
END $trg$;

COMMENT ON FUNCTION public.task_subtasks_guard() IS
  'Checklist qorovuli. (1) assigned_by ni FAQAT server yozadi (auth.uid()) — huquq eskalatsiyasi oldi olinadi; (2) vazifa egasi/ws-admini bo''lmagan odam task_id/workspace_id/title/sort_order/assigned_to/assigned_by ni o''zgartira olmaydi (42501); (3) done_at/done_by ni trigger o''zi yozadi. SECURITY INVOKER (current_user bilan server tomonini ajratish uchun).';

DROP TRIGGER IF EXISTS task_subtasks_guard_trg ON public.task_subtasks;
CREATE TRIGGER task_subtasks_guard_trg
  BEFORE INSERT OR UPDATE ON public.task_subtasks
  FOR EACH ROW EXECUTE FUNCTION public.task_subtasks_guard();

-- ── 6.1) 🔴 BOSHQA BEFORE UPDATE TRIGGERLARI — sanab, ogohlantiramiz ────────
--    Ular BIZNING qorovuldan OLDIN ishlashi mumkin (nom bo'yicha alifbo
--    tartibida) va HIMOYALANGAN ustunni yozib qo'ysa, huquqsiz odamning har
--    yozuvi 42501 ga urilardi. Eng ko'p uchraydigani — updated_at trigger'i
--    (u yuqorida oq ro'yxatga qo'shildi). Qolganini KO'RSATAMIZ, jimgina
--    o'tkazmaymiz. Pastdagi TIRIK sinov ("bajaruvchi is_completed ni
--    o'zgartira oladimi") buni AMALDA ham tekshiradi.
DO $othr$
DECLARE
  v_list text;
BEGIN
  SELECT string_agg(t.tgname || ' → ' || p.proname || '()', ', ' ORDER BY t.tgname)
    INTO v_list
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
   WHERE t.tgrelid = 'public.task_subtasks'::regclass
     AND NOT t.tgisinternal
     AND t.tgname <> 'task_subtasks_guard_trg'
     AND (t.tgtype & 2) <> 0    -- BEFORE
     AND (t.tgtype & 16) <> 0;  -- UPDATE

  INSERT INTO pg_temp.v2_ref VALUES ('othertrg', v_list,
    'task_subtasks dagi boshqa BEFORE UPDATE triggerlari');

  IF v_list IS NULL THEN
    RAISE NOTICE 'ℹ️ task_subtasks da boshqa BEFORE UPDATE trigger''i yo''q — qorovul bilan to''qnashuv ehtimoli yo''q.';
  ELSE
    RAISE WARNING '⚠️ task_subtasks da BOSHQA BEFORE UPDATE trigger(lar)i bor: %. Ular bizning qorovuldan OLDIN ishlashi va HIMOYALANGAN ustunni yozib qo''yishi mumkin — u holda huquqsiz odamning har yozuvi 42501 ga urilardi. Qaysi ustunni yozishini tekshiring: agar u faqat updated_at bo''lsa muammo yo''q (oq ro''yxatda). Pastdagi tirik sinov buni amalda ham o''lchaydi.', v_list;
  END IF;
END $othr$;


-- ════════════════════════════════════════════════════════════════════════════
-- 7) can_see_task_via_checklist() — YAGONA ruxsat nuqtasi
--    🔴 SECURITY DEFINER: task_subtasks/tasks ni RLS'siz o'qiydi → `tasks`
--       policy'sidan chaqirilganda 42P17 REKURSIYA bo'lmaydi (can_see_project()
--       ayni shu naqsh bilan `tasks` ni o'qiydi va tasks policy'sidan
--       chaqiriladi).
--    ⚠️ p_task TIPI `tasks.id` DAN DINAMIK olinadi (HISTORY/VIEWS naqshi).
-- ════════════════════════════════════════════════════════════════════════════

-- Eski, boshqa imzoli nusxa qolgan bo'lsa — tozalanadi.
-- ⚠️ Biror policy o'sha nusxaga bog'liq bo'lsa DROP xato beradi va butun
--    tranzaksiya qaytadi (jimgina buzilmaydi).
DO $drop$
DECLARE
  r        RECORD;
  v_idtype text;
BEGIN
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_idtype
    FROM pg_attribute a
   WHERE a.attrelid = 'public.tasks'::regclass
     AND a.attname = 'id' AND a.attnum > 0 AND NOT a.attisdropped;

  FOR r IN
    SELECT p.oid, pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='can_see_task_via_checklist'
  LOOP
    IF lower(btrim(r.args)) IS DISTINCT FROM lower('p_task ' || v_idtype || ', p_user uuid') THEN
      RAISE NOTICE 'Eski imzo o''chirilmoqda: can_see_task_via_checklist(%)', r.args;
      EXECUTE format('DROP FUNCTION public.can_see_task_via_checklist(%s)', r.args);
    END IF;
  END LOOP;
END $drop$;

DO $fn$
DECLARE
  v_idtype text;
  v_by     text;
BEGIN
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_idtype
    FROM pg_attribute a
   WHERE a.attrelid = 'public.tasks'::regclass
     AND a.attname = 'id' AND a.attnum > 0 AND NOT a.attisdropped;
  IF v_idtype IS NULL THEN
    RAISE EXCEPTION 'public.tasks.id ustuni topilmadi — funksiya imzosi qurilmadi.';
  END IF;

  SELECT ref INTO v_by FROM pg_temp.v2_ref WHERE k = 'byexpr';
  IF v_by IS NULL THEN
    RAISE EXCEPTION 'byexpr ifodasi qurilmagan — 2-bo''lim bajarilmadimi?';
  END IF;

  RAISE NOTICE 'can_see_task_via_checklist(p_task %) — tip tasks.id dan olindi', v_idtype;

  EXECUTE format($f$
    CREATE OR REPLACE FUNCTION public.can_see_task_via_checklist(p_task %s, p_user uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $fb$
      -- 🔴 QOROVUL 1 — `p_user = (SELECT auth.uid())`. MAJBURIY QATOR,
      --    OLIB TASHLAMANG. Funksiya `authenticated` ga EXECUTE bilan ochiq,
      --    ya'ni uni PostgREST orqali TO'G'RIDAN chaqirish mumkin:
      --        POST /rest/v1/rpc/can_see_task_via_checklist {p_task, p_user}
      --    Bu qatorsiz istalgan foydalanuvchi ixtiyoriy p_user yuborib
      --    "falon odamga falon vazifada checklist punkti biriktirilganmi?"
      --    savoliga javob ola olardi (SECURITY DEFINER RLS'ni chetlab o'tadi).
      -- 🔴 QOROVUL 2 — `is_ws_member(t.workspace_id, p_user)`. MAJBURIY.
      --    Jamoadan chiqarilgan odam huquqni SAQLAB QOLMASIN: rmxDoRemove
      --    xodimni faqat workspace_members dan chiqaradi, task_subtasks
      --    qatoridagi assigned_to o'sha uid'da QOLADI.
      -- 🔴 QOROVUL 3 — assigned_by HAQIQIY huquqqa ega bo'lsin (pastdagi
      --    qavs ichida: ws-menejeri YOKI vazifaning assigned_to /
      --    created_by / acceptor_id si). MAJBURIY — HUQUQ ESKALATSIYASI:
      --    busiz oddiy a'zo istalgan vazifaga "assigned_to = O'ZIM" deb
      --    checklist qatori yozib, o'sha vazifani o'qish huquqini O'ZIGA
      --    O'ZI berardi. assigned_by ni task_subtasks_guard_trg trigger'i
      --    yozgani uchun uni soxtalashtirib ham bo'lmaydi.
      SELECT p_task IS NOT NULL
         AND p_user IS NOT NULL
         AND p_user = (SELECT auth.uid())
         AND EXISTS (
               SELECT 1
                 FROM public.task_subtasks s
                 JOIN public.tasks t ON t.id = s.task_id
                WHERE s.task_id     = p_task
                  AND s.assigned_to = p_user
                  AND public.is_ws_member(t.workspace_id, p_user)
                  AND (%s)
             );
    $fb$
  $f$, v_idtype, v_by);

  EXECUTE format(
    'COMMENT ON FUNCTION public.can_see_task_via_checklist(%s, uuid) IS %L',
    v_idtype,
    'p_user shu vazifani CHECKLIST punkti orqali ko''ra oladimi? SECURITY DEFINER — task_subtasks/tasks ni RLS''siz o''qiydi (42P17 rekursiya bo''lmasin, can_see_project naqshi). Tanasida UCH MAJBURIY qorovul: p_user = auth.uid() (PostgREST /rpc), is_ws_member(task.workspace_id, p_user) (jamoadan chiqarilgan xodim) va assigned_by huquqli odam bo''lishi (huquq eskalatsiyasi). FAQAT O''QISH huquqi beradi.');

  -- 🔴 REVOKE ... FROM PUBLIC YETARLI EMAS: Supabase'da
  --    `ALTER DEFAULT PRIVILEGES ... GRANT ALL ON FUNCTIONS TO anon,
  --     authenticated` o'rnatilgan bo'lishi mumkin — u holda YANGI funksiya
  --    `anon` ga TO'G'RIDAN grant oladi va PUBLIC dan REVOKE unga ta'sir
  --    qilmaydi. Shuning uchun aniq `FROM anon` REVOKE qilinadi.
  EXECUTE format('REVOKE ALL ON FUNCTION public.can_see_task_via_checklist(%s, uuid) FROM PUBLIC', v_idtype);
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    EXECUTE format('REVOKE ALL ON FUNCTION public.can_see_task_via_checklist(%s, uuid) FROM anon', v_idtype);
  END IF;
  EXECUTE format('REVOKE ALL ON FUNCTION public.can_see_task_via_checklist(%s, uuid) FROM authenticated', v_idtype);
  -- EXECUTE authenticated'ga SHART: RLS ifodasi CHAQIRUVCHI huquqi bilan
  -- baholanadi (can_see_project / can_view_planner naqshi).
  EXECUTE format('GRANT EXECUTE ON FUNCTION public.can_see_task_via_checklist(%s, uuid) TO authenticated', v_idtype);
END $fn$;


-- ════════════════════════════════════════════════════════════════════════════
-- 8) GRANT — yangi ustunlar mijozga ko'rinsin/yozilsin
--    ⚠️ Supabase odatda `authenticated` ga JADVAL darajasida to'liq huquq
--    beradi — u holda yangi ustunlar avtomatik qamrab olinadi va bu bo'lim
--    hech narsa qilmaydi. Lekin kimdir USTUN darajasida grant yozgan bo'lsa,
--    YANGI ustun ro'yxatga KIRMAYDI va mijoz "column does not exist" emas,
--    "permission denied" oladi — sabab tushunarsiz bo'lardi.
--    ⚠️ assigned_by ga UPDATE/INSERT grant BERILMAYDI: uni trigger yozadi,
--       mijoz uchun u faqat O'QISH maydoni.
-- ════════════════════════════════════════════════════════════════════════════
DO $cols$
BEGIN
  -- projects
  IF NOT has_column_privilege('authenticated', 'public.projects', 'responsible_id', 'SELECT') THEN
    EXECUTE 'GRANT SELECT (recur_weekdays, recur_monthdays, responsible_id, respect_dayoff) ON public.projects TO authenticated';
    RAISE NOTICE 'GRANT SELECT(projects yangi ustunlari) — ustun darajasidagi grant aniqlandi';
  END IF;
  IF NOT has_column_privilege('authenticated', 'public.projects', 'responsible_id', 'UPDATE') THEN
    EXECUTE 'GRANT UPDATE (recur_weekdays, recur_monthdays, responsible_id, respect_dayoff) ON public.projects TO authenticated';
    RAISE NOTICE 'GRANT UPDATE(projects yangi ustunlari) — ustun darajasidagi grant aniqlandi';
  END IF;
  IF NOT has_column_privilege('authenticated', 'public.projects', 'responsible_id', 'INSERT') THEN
    EXECUTE 'GRANT INSERT (recur_weekdays, recur_monthdays, responsible_id, respect_dayoff) ON public.projects TO authenticated';
    RAISE NOTICE 'GRANT INSERT(projects yangi ustunlari) — ustun darajasidagi grant aniqlandi';
  END IF;

  -- task_subtasks
  IF NOT has_column_privilege('authenticated', 'public.task_subtasks', 'assigned_to', 'SELECT') THEN
    EXECUTE 'GRANT SELECT (assigned_to, assigned_by, file_url, file_name, file_size, done_at, done_by) ON public.task_subtasks TO authenticated';
    RAISE NOTICE 'GRANT SELECT(task_subtasks yangi ustunlari) — ustun darajasidagi grant aniqlandi';
  END IF;
  IF NOT has_column_privilege('authenticated', 'public.task_subtasks', 'assigned_to', 'UPDATE') THEN
    EXECUTE 'GRANT UPDATE (assigned_to, file_url, file_name, file_size) ON public.task_subtasks TO authenticated';
    RAISE NOTICE 'GRANT UPDATE(task_subtasks yangi ustunlari) — ustun darajasidagi grant aniqlandi';
  END IF;
  IF NOT has_column_privilege('authenticated', 'public.task_subtasks', 'assigned_to', 'INSERT') THEN
    EXECUTE 'GRANT INSERT (assigned_to, file_url, file_name, file_size) ON public.task_subtasks TO authenticated';
    RAISE NOTICE 'GRANT INSERT(task_subtasks yangi ustunlari) — ustun darajasidagi grant aniqlandi';
  END IF;
END $cols$;


-- ── O'lchov/natija jadvallari ───────────────────────────────────────────────
--    ⚠️ TRANZAKSIYA ICHIDA yaratiladi: skript yiqilsa ular ham qaytadi va
--       oxiridagi SELECT'lar bajarilmaydi. Xato holatida hamma raqam
--       "Messages" bo'limidagi NOTICE/EXCEPTION matnida bo'ladi.
DROP TABLE IF EXISTS pg_temp.v2_u;
CREATE TEMP TABLE pg_temp.v2_u (
  uid    uuid PRIMARY KEY,
  turi   text   NOT NULL,               -- 'menejer' | 'checklist' | 'nazorat'
  s_ids  text[] NOT NULL DEFAULT '{}',  -- yangi policy OCHADIGAN vazifa id'lari
  s_n    bigint NOT NULL DEFAULT 0,
  s_cut  boolean NOT NULL DEFAULT false
);
DROP TABLE IF EXISTS pg_temp.v2_snap;
CREATE TEMP TABLE pg_temp.v2_snap (
  faza text, uid uuid,
  n_tsk bigint,   -- ko'rinadigan JAMI vazifa
  n_s   bigint,   -- ulardan s_ids ichidagilari
  n_sub bigint    -- ko'rinadigan task_subtasks qatori
);
DROP TABLE IF EXISTS pg_temp.v2_res;
CREATE TEMP TABLE pg_temp.v2_res (ord int, bosqich text, nom text, qiymat text, izoh text);


-- ════════════════════════════════════════════════════════════════════════════
-- 9) ASOSIY BLOK — struktura → o'lchov → policy → o'lchov → tirik sinov
--    🔴 TARTIB ATAYLAB SHUNDAY: `tasks` ga ACCESS EXCLUSIVE qulf FAQAT
--       9.5 dagi CREATE POLICY da olinadi. Undan OLDIN bajarilishi mumkin
--       bo'lgan hamma narsa (struktura tekshiruvi, namuna, o'lchov, "oldin"
--       snapshot) qulfsiz bajariladi — ilova imkon qadar kam to'xtaydi.
-- ════════════════════════════════════════════════════════════════════════════
DO $main$
DECLARE
  -- ══════════ SOZLAMALAR ══════════
  -- 🔴 KICHIK TUTILGAN (2/3): har namunaviy foydalanuvchi uchun `tasks` bo'ylab
  --    to'liq skan bajariladi va uning bir qismi `tasks` ACCESS EXCLUSIVE
  --    qulfi OSTIDA o'tadi. Bu sonlarni oshirish = ilovaning uzoqroq to'xtashi.
  --    Skript sekin ishlasa AVVAL SHU IKKI SONNI kamaytiring (1/1 gacha) —
  --    tekshiruv mantiqi o'zgarmaydi, faqat namuna kichrayadi.
  v_max_mgr  CONSTANT int := 1;     -- namunaga olinadigan menejer soni
  v_max_mem  CONSTANT int := 1;     -- har toifadan oddiy a'zo soni
  v_max_ids  CONSTANT int := 5000;  -- bitta foydalanuvchi uchun id massivi chegarasi

  u             RECORD;
  r             RECORD;
  v_n           bigint;
  v_i           int;
  v_txt         text;
  v_src         text;
  v_norm        text;
  v_qual        text;
  v_idtype      text;
  v_by          text;
  v_own_p       text;
  v_tsk_rls     boolean;
  v_sub_rls     boolean;
  v_sub_has_ws  boolean;
  v_tsk_sel     int;
  v_restr       int;
  v_restr_note  text := '';
  v_pol_added   boolean := false;
  v_pol_reason  text;
  v_ssel_added  boolean := false;
  v_ssel_note   text;
  v_supd_added  boolean := false;
  v_supd_note   text;
  v_c_tsk       bigint;
  v_c_s         bigint;
  v_c_sub       bigint;
  v_exp         bigint;
  v_gain        bigint := 0;

  -- tirik sinov uchun
  v_imp_ok      boolean := false;
  v_id_auto     boolean := true;
  v_m1_owns     boolean := false;
  v_ws          uuid;
  v_mgr         uuid;
  v_m1          uuid;
  v_m2          uuid;
  v_out         uuid;
  v_task_id     text;
  v_base_m1     int := -1;
  v_base_m2     int := -1;
  v_base_out    int := -1;
  v_bad_cols    text;
  v_ins_cols    text;
  v_ins_vals    text;
  v_ins_cols_f  text;   -- (f) sinovi uchun: assigned_by YO'Q
  v_ins_vals_f  text;
  v_probe       text;
  v_p_f1        text;
  v_p_c1        text;
  v_p_se        text;
  v_p_f2        text;
  v_p_c2        text;
  v_p_fx        text;
  v_p_upd       text;
  v_p_fo        text;
  v_p_co        text;
  v_p_esc       text;
  v_p_tog       text;
  v_t_tog       text := 'o''tkazib yuborildi';
  v_t_see       text := 'o''tkazib yuborildi';
  v_t_seesub    text := 'o''tkazib yuborildi';
  v_t_deny      text := 'o''tkazib yuborildi';
  v_t_out       text := 'o''tkazib yuborildi';
  v_t_move      text := 'o''tkazib yuborildi';
  v_t_rpc       text := 'o''tkazib yuborildi';
  v_t_esc       text := 'o''tkazib yuborildi';
  v_skip_why    text := 'bazada mos ma''lumot topilmadi';
BEGIN

SELECT format_type(a.atttypid, a.atttypmod) INTO v_idtype
  FROM pg_attribute a
 WHERE a.attrelid = 'public.tasks'::regclass
   AND a.attname = 'id' AND a.attnum > 0 AND NOT a.attisdropped;
SELECT ref INTO v_by FROM pg_temp.v2_ref WHERE k = 'byexpr';
SELECT replace(ref, 'v_uid', '$1') INTO v_own_p FROM pg_temp.v2_ref WHERE k = 'ownexpr';

-- ══════════════════════════════════════════════════════════════════════════
-- 9.1) Holat: RLS, policy'lar
-- ══════════════════════════════════════════════════════════════════════════
SELECT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                WHERE n.nspname='public' AND c.relname='tasks' AND c.relrowsecurity) INTO v_tsk_rls;
SELECT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                WHERE n.nspname='public' AND c.relname='task_subtasks' AND c.relrowsecurity) INTO v_sub_rls;
SELECT count(*) INTO v_tsk_sel FROM pg_policies
 WHERE schemaname='public' AND tablename='tasks' AND permissive='PERMISSIVE' AND cmd IN ('SELECT','ALL');
SELECT count(*) INTO v_restr FROM pg_policies
 WHERE schemaname='public' AND tablename IN ('tasks','task_subtasks') AND permissive='RESTRICTIVE';
IF v_restr > 0 THEN
  v_restr_note := ' ⚠️ DIQQAT: bu jadvallarda ' || v_restr || ' ta RESTRICTIVE policy bor — ular AND bilan qo''llanadi va yangi PERMISSIVE policy ularni yenga olmaydi.';
  RAISE WARNING '%', v_restr_note;
END IF;
v_sub_has_ws := EXISTS (SELECT 1 FROM information_schema.columns
                         WHERE table_schema='public' AND table_name='task_subtasks'
                           AND column_name='workspace_id');

-- ══════════════════════════════════════════════════════════════════════════
-- 9.2) STRUKTURA TEKSHIRUVI — 🔴 `tasks` QULFIDAN OLDIN
--      "bor deb o'ylash" emas, katalogdan O'QISH.
-- ══════════════════════════════════════════════════════════════════════════
-- (a) projects ustunlari
FOREACH v_txt IN ARRAY ARRAY['recur_weekdays','recur_monthdays','responsible_id','respect_dayoff'] LOOP
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='projects' AND column_name=v_txt) THEN
    RAISE EXCEPTION 'projects.% ustuni yaratilmadi — HAMMASI QAYTARILDI.', v_txt;
  END IF;
END LOOP;
IF (SELECT data_type FROM information_schema.columns
     WHERE table_schema='public' AND table_name='projects' AND column_name='recur_weekdays') <> 'ARRAY' THEN
  RAISE EXCEPTION 'projects.recur_weekdays massiv EMAS — eski/boshqa sxema aniqlandi. HAMMASI QAYTARILDI.';
END IF;
IF (SELECT data_type FROM information_schema.columns
     WHERE table_schema='public' AND table_name='projects' AND column_name='respect_dayoff') <> 'boolean' THEN
  RAISE EXCEPTION 'projects.respect_dayoff boolean EMAS. HAMMASI QAYTARILDI.';
END IF;

-- (b) task_subtasks ustunlari
FOREACH v_txt IN ARRAY ARRAY['assigned_to','assigned_by','file_url','file_name','file_size','done_at','done_by'] LOOP
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='task_subtasks' AND column_name=v_txt) THEN
    RAISE EXCEPTION 'task_subtasks.% ustuni yaratilmadi — HAMMASI QAYTARILDI.', v_txt;
  END IF;
END LOOP;

-- (c) CHECK'lar — 🔴 conrelid bilan SKOPLANGAN (conname global unique EMAS)
FOREACH v_txt IN ARRAY ARRAY['projects_recur_weekdays_chk','projects_recur_monthdays_chk'] LOOP
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'public.projects'::regclass AND contype='c' AND conname = v_txt) THEN
    RAISE EXCEPTION 'CHECK % public.projects da topilmadi — HAMMASI QAYTARILDI.', v_txt;
  END IF;
END LOOP;
SELECT pg_get_constraintdef(oid) INTO v_txt FROM pg_constraint
 WHERE conrelid='public.projects'::regclass AND conname='projects_recur_weekdays_chk';
IF v_txt !~ 'tf_smallint_set_ok' THEN
  RAISE EXCEPTION 'projects_recur_weekdays_chk ichida tf_smallint_set_ok() yo''q: % — HAMMASI QAYTARILDI.', v_txt;
END IF;

-- (c2) CHECK mantiqi TIRIK sinaladi (sentinel-rollback bilan):
--      takror kun RAD ETILISHI shart.
BEGIN
  EXECUTE 'UPDATE public.projects SET recur_weekdays = ARRAY[1,1]::smallint[] WHERE id = (SELECT id FROM public.projects LIMIT 1)';
  GET DIAGNOSTICS v_i = ROW_COUNT;
  RAISE EXCEPTION 'V2_CHK:%', v_i USING ERRCODE = '22000';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'V2_CHK:%' THEN
    v_i := replace(SQLERRM, 'V2_CHK:', '')::int;
    IF v_i > 0 THEN
      RAISE EXCEPTION 'TEKSHIRUV: recur_weekdays = [1,1] (TAKROR) qabul qilindi — tf_smallint_set_ok() takrorni to''smayapti. HAMMASI QAYTARILDI.';
    END IF;
    RAISE NOTICE 'ℹ️ CHECK tirik sinovi: bazada loyiha yo''q (0 qator) — o''tkazib yuborildi.';
  ELSIF SQLSTATE = '23514' THEN
    RAISE NOTICE '✅ CHECK tirik sinovi: takror qiymat ([1,1]) RAD ETILDI (23514).';
  ELSE
    -- ⚠️ ATAYLAB EXCEPTION EMAS: bu UPDATE mavjud begona trigger/cheklovga ham
    --    urilishi mumkin — sinovning noaniq tugashi MIGRATSIYANI to'xtatmasin.
    --    Yozuv baribir bo'lmadi (subtranzaksiya qaytdi), CHECK esa yuqorida
    --    katalogdan tasdiqlangan. Sabab jimgina yutilmaydi.
    RAISE WARNING '⚠️ CHECK tirik sinovi noaniq tugadi (%): %. Cheklovning O''ZI katalogda mavjud; kerak bo''lsa qo''lda sinang.', SQLSTATE, SQLERRM;
  END IF;
END;

-- (d) Indeks
IF NOT EXISTS (SELECT 1 FROM pg_indexes
                WHERE schemaname='public' AND tablename='task_subtasks'
                  AND indexname='idx_task_subtasks_assigned') THEN
  RAISE EXCEPTION 'idx_task_subtasks_assigned indeksi yaratilmadi — HAMMASI QAYTARILDI.';
END IF;

-- (e) Funksiya bor va SECURITY DEFINER
IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                WHERE n.nspname='public' AND p.proname='can_see_task_via_checklist' AND p.prosecdef) THEN
  RAISE EXCEPTION 'can_see_task_via_checklist() yaratilmadi yoki SECURITY DEFINER emas (busiz policy zanjirida 42P17 rekursiya chiqardi). HAMMASI QAYTARILDI.';
END IF;

-- (e2) 🔴 Funksiya TANASIDAGI UCH MAJBURIY QOROVUL
--   IZOHLAR AVVAL TOZALANADI (HR_EDITORS 4.b2 / VIEWS 5.i naqshi): tanadagi
--   🔴 ogohlantirish izohlarida aynan shu matnlar bor — xom matnda qidirsak
--   KOD QATORI o'chirilib izoh qoldirilgan holatni sezmasdik.
--   pronargs = 2 — eski overload qolib ketgan bazada noto'g'ri funksiya
--   tekshirilmasin. Naqshlar BIRLASHGAN (yakka kalit so'z YETARLI EMAS).
SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='can_see_task_via_checklist' AND p.pronargs = 2
 LIMIT 1;
IF v_src IS NULL THEN
  RAISE EXCEPTION 'can_see_task_via_checklist(...) tanasi o''qilmadi — funksiya yaratilmadimi? HAMMASI QAYTARILDI.';
END IF;
-- Normallashtirish: bo'shliq/qator uzilishi BITTA probelga, UPPER.
-- strpos() ishlatiladi (LIKE emas): naqshlarda `_` bor va u LIKE'da
-- "istalgan bitta belgi" degani — tekshiruv bo'shashib ketmasin.
v_norm := upper(regexp_replace(v_src, '\s+', ' ', 'g'));
IF strpos(v_norm, 'P_USER = (SELECT AUTH.UID())') = 0 THEN
  RAISE EXCEPTION 'can_see_task_via_checklist() KODIDA 1-QOROVUL `p_user = (SELECT auth.uid())` YO''Q (izoh hisobga olinmaydi) — funksiya PostgREST /rpc orqali begona odam haqida ma''lumot berardi. HAMMASI QAYTARILDI.';
END IF;
IF strpos(v_norm, 'PUBLIC.IS_WS_MEMBER(T.WORKSPACE_ID, P_USER)') = 0 THEN
  RAISE EXCEPTION 'can_see_task_via_checklist() KODIDA 2-QOROVUL `is_ws_member(t.workspace_id, p_user)` YO''Q — jamoadan chiqarilgan xodim eski vazifalarni ko''rib turardi. HAMMASI QAYTARILDI.';
END IF;
IF strpos(v_norm, 'S.ASSIGNED_TO = P_USER') = 0 THEN
  RAISE EXCEPTION 'can_see_task_via_checklist() KODIDA `s.assigned_to = p_user` sharti YO''Q — funksiya biriktirilmagan odamga ham true qaytarardi. HAMMASI QAYTARILDI.';
END IF;
-- 🔴 3-QOROVUL (huquq eskalatsiyasi) — IKKI bo'lak alohida talab qilinadi
IF strpos(v_norm, 'S.ASSIGNED_BY IS NOT NULL') = 0
   OR strpos(v_norm, 'PUBLIC.IS_WS_MANAGER(T.WORKSPACE_ID, S.ASSIGNED_BY)') = 0 THEN
  RAISE EXCEPTION 'can_see_task_via_checklist() KODIDA 3-QOROVUL YO''Q (assigned_by tekshiruvi). Busiz HUQUQ ESKALATSIYASI: oddiy a''zo istalgan vazifaga "assigned_to = o''zim" deb checklist qatori yozib, o''sha vazifani o''qish huquqini O''ZIGA O''ZI berardi. HAMMASI QAYTARILDI.';
END IF;

-- (f) Huquqlar: authenticated EXECUTE qila oladi, anon YO'Q
IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon')
   AND has_function_privilege('anon',
        format('public.can_see_task_via_checklist(%s,uuid)', v_idtype), 'EXECUTE') THEN
  RAISE EXCEPTION 'can_see_task_via_checklist() `anon` ga EXECUTE bilan ochiq qolgan (ALTER DEFAULT PRIVILEGES) — REVOKE ishlamadi. HAMMASI QAYTARILDI.';
END IF;
IF NOT has_function_privilege('authenticated',
      format('public.can_see_task_via_checklist(%s,uuid)', v_idtype), 'EXECUTE') THEN
  RAISE EXCEPTION 'can_see_task_via_checklist() `authenticated` ga EXECUTE bermayapti — RLS ifodasi chaqiruvchi huquqi bilan baholanadi, policy ishlamasdi. HAMMASI QAYTARILDI.';
END IF;

-- (g) 🔴 TRIGGER joyidami va tanasi haqiqiy qorovulmi?
IF NOT EXISTS (SELECT 1 FROM pg_trigger
                WHERE tgrelid='public.task_subtasks'::regclass
                  AND tgname='task_subtasks_guard_trg' AND NOT tgisinternal) THEN
  RAISE EXCEPTION 'task_subtasks_guard_trg trigger''i yo''q — assigned_by ni mijoz soxtalashtirib, 3-qorovulni chetlab o''tardi. HAMMASI QAYTARILDI.';
END IF;
SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='task_subtasks_guard' LIMIT 1;
IF v_src IS NULL THEN
  RAISE EXCEPTION 'task_subtasks_guard() tanasi o''qilmadi. HAMMASI QAYTARILDI.';
END IF;
v_norm := upper(regexp_replace(v_src, '\s+', ' ', 'g'));
IF strpos(v_norm, 'NEW.ASSIGNED_BY := V_UID') = 0 THEN
  RAISE EXCEPTION 'task_subtasks_guard() KODIDA `NEW.assigned_by := v_uid` YO''Q — qiymatni mijoz yozadigan bo''lib qolardi (3-qorovul ma''nosiz). HAMMASI QAYTARILDI.';
END IF;
IF strpos(v_norm, 'PUBLIC.IS_WS_MANAGER(') = 0 THEN
  RAISE EXCEPTION 'task_subtasks_guard() KODIDA is_ws_manager() yo''q — ustun darajasidagi qorovul kimning egalik huquqini tekshirardi? HAMMASI QAYTARILDI.';
END IF;
IF strpos(v_norm, 'NEW.TITLE IS DISTINCT FROM OLD.TITLE') = 0
   OR strpos(v_norm, 'NEW.TASK_ID IS DISTINCT FROM OLD.TASK_ID') = 0 THEN
  RAISE EXCEPTION 'task_subtasks_guard() KODIDA ustun darajasidagi qorovul (title / task_id) YO''Q — bajaruvchi punktni boshqa vazifaga ko''chirib yoki matnini almashtirib yuborardi. HAMMASI QAYTARILDI.';
END IF;

RAISE NOTICE '✅ STRUKTURA: ustunlar, CHECK''lar, indeks, funksiya (3 qorovul), trigger va grantlar tekshirildi (tasks qulfisiz).';

-- ══════════════════════════════════════════════════════════════════════════
-- 9.3) NAMUNA — kim qaysi toifada
--    🔴 Toifa `is_ws_manager()` orqali aniqlanadi, `role` USTUNI orqali emas.
--    ⚠️ Shartlar KESILGAN namunaga emas, HAQIQIY ma'lumotga qaraydi — aks
--       holda LIMIT dan tashqarida qolgan menejer "nazorat" deb belgilanib,
--       tekshiruv SOXTA "XAVFSIZLIK BUZILDI" bilan yiqilardi.
-- ══════════════════════════════════════════════════════════════════════════
INSERT INTO pg_temp.v2_u (uid, turi)
SELECT DISTINCT wm.user_id, 'menejer'
  FROM public.workspace_members wm
 WHERE public.is_ws_manager(wm.workspace_id, wm.user_id)
 ORDER BY wm.user_id
 LIMIT v_max_mgr;

INSERT INTO pg_temp.v2_u (uid, turi)
SELECT DISTINCT s.assigned_to, 'checklist'
  FROM public.task_subtasks s
 WHERE s.assigned_to IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM public.workspace_members w2
                    WHERE w2.user_id = s.assigned_to
                      AND public.is_ws_manager(w2.workspace_id, w2.user_id))
   AND NOT EXISTS (SELECT 1 FROM pg_temp.v2_u a WHERE a.uid = s.assigned_to)
 ORDER BY s.assigned_to
 LIMIT v_max_mem;

INSERT INTO pg_temp.v2_u (uid, turi)
SELECT DISTINCT wm.user_id, 'nazorat'
  FROM public.workspace_members wm
 WHERE NOT EXISTS (SELECT 1 FROM public.workspace_members w2
                    WHERE w2.user_id = wm.user_id
                      AND public.is_ws_manager(w2.workspace_id, w2.user_id))
   AND NOT EXISTS (SELECT 1 FROM public.task_subtasks s3
                    WHERE s3.assigned_to = wm.user_id)
   AND NOT EXISTS (SELECT 1 FROM pg_temp.v2_u a WHERE a.uid = wm.user_id)
 ORDER BY wm.user_id
 LIMIT v_max_mem;

-- Har foydalanuvchi uchun: yangi policy AYNAN qaysi qatorlarni ochadi?
-- ⚠️ can_see_task_via_checklist() BU YERDA CHAQIRILMAYDI — u auth.uid() ga
--    bog'liq va postgres roli ostida doim false qaytaradi. Shuning uchun
--    mantiq qo'lda ko'chirilgan, LEKIN 3-qorovul ifodasi (`byexpr`) FUNKSIYA
--    BILAN BIR XIL MANBADAN olinadi — ular farq qila olmaydi.
EXECUTE format($q$
  UPDATE pg_temp.v2_u a
     SET s_n = (SELECT count(*) FROM public.tasks t
                 WHERE public.is_ws_member(t.workspace_id, a.uid)
                   AND EXISTS (SELECT 1 FROM public.task_subtasks s
                                WHERE s.task_id = t.id
                                  AND s.assigned_to = a.uid
                                  AND (%s))),
         s_ids = coalesce((SELECT array_agg(q.id) FROM (
                   SELECT t.id::text AS id FROM public.tasks t
                    WHERE public.is_ws_member(t.workspace_id, a.uid)
                      AND EXISTS (SELECT 1 FROM public.task_subtasks s
                                   WHERE s.task_id = t.id
                                     AND s.assigned_to = a.uid
                                     AND (%s))
                    ORDER BY t.id LIMIT %s) q), '{}'::text[])
$q$, v_by, v_by, v_max_ids);

UPDATE pg_temp.v2_u SET s_cut = (s_n > v_max_ids);

SELECT count(*) INTO v_n FROM pg_temp.v2_u;
RAISE NOTICE 'Namuna: % ta foydalanuvchi (% menejer / % checklist / % nazorat)',
  v_n,
  (SELECT count(*) FROM pg_temp.v2_u WHERE turi='menejer'),
  (SELECT count(*) FROM pg_temp.v2_u WHERE turi='checklist'),
  (SELECT count(*) FROM pg_temp.v2_u WHERE turi='nazorat');

SELECT count(*) INTO v_n FROM public.task_subtasks WHERE assigned_to IS NOT NULL;
IF v_n = 0 THEN
  RAISE NOTICE 'ℹ️ Bazada hali BITTA ham biriktirilgan checklist punkti yo''q (assigned_to — YANGI ustun). Demak yangi policy hozircha 0 ta qator ochadi va sanoqlar AYNAN o''zgarmasligi SHART. Bu KUTILGAN natija, xato emas — mijoz bu ustunlarni keyingi bosqichda ulaydi. Semantikani pastdagi TIRIK sinovlar tekshiradi.';
END IF;

-- ══════════════════════════════════════════════════════════════════════════
-- 9.4) SNAPSHOT — OLDIN (authenticated roli ostida, HAQIQIY RLS bilan)
--    ⚠️ Sanoqlar avval O'ZGARUVCHIGA yig'iladi, temp jadvalga esa FAQAT
--       `RESET ROLE` dan KEYIN yoziladi (authenticated ostida temp jadvalga
--       yozish huquqi yo'q — SCALE/PLANNER naqshi).
--    🔴 Har impersonatsiyadan keyin `request.jwt.claims` TOZALANADI.
-- ══════════════════════════════════════════════════════════════════════════
FOR u IN SELECT * FROM pg_temp.v2_u ORDER BY uid LOOP
  BEGIN
    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', u.uid::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    EXECUTE 'SELECT count(*) FROM public.tasks' INTO v_c_tsk;
    EXECUTE 'SELECT count(*) FROM public.tasks WHERE id = ANY ($1::text[]::' || v_idtype || '[])' INTO v_c_s USING u.s_ids;
    EXECUTE 'SELECT count(*) FROM public.task_subtasks' INTO v_c_sub;

    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO pg_temp.v2_snap (faza, uid, n_tsk, n_s, n_sub)
    VALUES ('oldin', u.uid, v_c_tsk, v_c_s, v_c_sub);
  EXCEPTION WHEN OTHERS THEN
    BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM set_config('request.jwt.claims', '', true);
    IF SQLSTATE = '42P17' THEN
      RAISE EXCEPTION 'REKURSIYA (42P17) O''ZGARISHDAN OLDIN ham bor edi: %. Bu skript sababi EMAS — mavjud policy''lardagi halqani avval tuzating.', SQLERRM;
    END IF;
    RAISE EXCEPTION 'OLDIN-snapshot xatosi (% / %): %', u.uid, SQLSTATE, SQLERRM;
  END;
END LOOP;
RAISE NOTICE 'OLDIN-snapshot olindi (% ta foydalanuvchi)', (SELECT count(*) FROM pg_temp.v2_snap WHERE faza='oldin');

-- ══════════════════════════════════════════════════════════════════════════
-- 9.5) POLICY: tasks — checklist bajaruvchisi VAZIFANI KO'RSIN
--    🔴 SHU YERDAN BOSHLAB `tasks` ACCESS EXCLUSIVE qulf ostida (COMMIT gacha).
--    🔴 FAQAT `FOR SELECT` — tahrirlash huquqi BERILMAYDI.
--    🔴 `is_ws_member(workspace_id, auth.uid())` policy ICHIDA HAM bor
--       (funksiya ichidagi tekshiruv ustiga ikkinchi qatlam).
-- ══════════════════════════════════════════════════════════════════════════
IF NOT v_tsk_rls THEN
  v_pol_reason := 'public.tasks da RLS O''CHIQ — policy baholanmaydi, qo''shish soxta xavfsizlik tuyg''usi berardi';
  RAISE WARNING '%', v_pol_reason;
ELSIF v_tsk_sel = 0 THEN
  v_pol_reason := 'public.tasks da PERMISSIVE SELECT policy UMUMAN YO''Q — yolg''iz "checklist" policy''si asosiy ko''rish qoidasi o''rnini bosib qolardi. Avval asosiy tasks SELECT policy''sini tiklang.';
  RAISE WARNING '%', v_pol_reason;
ELSE
  DROP POLICY IF EXISTS tasks_select_checklist_assignee ON public.tasks;
  EXECUTE $p$
    CREATE POLICY tasks_select_checklist_assignee ON public.tasks
      AS PERMISSIVE FOR SELECT TO authenticated
      USING ( is_ws_member(workspace_id, (SELECT auth.uid()))
              AND can_see_task_via_checklist(id, (SELECT auth.uid())) )
  $p$;
  v_pol_added  := true;
  v_pol_reason := 'is_ws_member + can_see_task_via_checklist (FAQAT SELECT, 3 qorovul)';
  RAISE NOTICE '✅ tasks_select_checklist_assignee policy qo''shildi';
END IF;

-- ══════════════════════════════════════════════════════════════════════════
-- 9.6) POLICY: task_subtasks — FAQAT KERAK BO'LSA
--    ⚠️ Avval MAVJUD policy'lar O'QILADI: ular allaqachon is_ws_member
--       bo'yicha ochiq bo'lsa yangi policy ORTIQCHA — QO'SHILMAYDI.
--    🔴 F1: yangi policy'larda `is_ws_member(workspace_id, …)` MAJBURIY.
--       Faqat `assigned_to = auth.uid()` bo'lsa jamoadan CHIQARILGAN xodim
--       eski checklist qatorlarini o'qib/yozib turardi (rmxDoRemove
--       assigned_to ni tozalamaydi — yuqoridagi 5-bo'lim izohi).
-- ══════════════════════════════════════════════════════════════════════════
IF NOT v_sub_rls THEN
  v_ssel_note := 'task_subtasks da RLS o''chiq — policy baholanmaydi';
  v_supd_note := v_ssel_note;
  RAISE WARNING 'public.task_subtasks da RLS O''CHIQ — yangi policy qo''shilmadi (baribir baholanmasdi).';
ELSIF NOT v_sub_has_ws THEN
  v_ssel_note := 'task_subtasks.workspace_id ustuni yo''q — ws qorovulisiz policy qo''shilmaydi (jamoadan chiqarilgan xodim yo''li ochiq qolardi)';
  v_supd_note := v_ssel_note;
  RAISE WARNING '⚠️ public.task_subtasks.workspace_id ustuni yo''q — yangi checklist policy''lari QO''SHILMADI: ularda is_ws_member(workspace_id, …) qorovuli MAJBURIY.';
ELSE
  -- (a) SELECT
  SELECT string_agg(coalesce(qual, ''), '  ##  ') INTO v_qual
    FROM pg_policies
   WHERE schemaname='public' AND tablename='task_subtasks'
     AND permissive='PERMISSIVE' AND cmd IN ('SELECT','ALL');

  IF EXISTS (SELECT 1 FROM pg_policies
              WHERE schemaname='public' AND tablename='task_subtasks'
                AND policyname='task_subtasks_select_assignee') THEN
    -- ⚠️ QAYTA RUN: policy allaqachon BIZNIKI. Pastdagi heuristika uni
    --    "begona mavjud policy" deb o'qib "QO'SHILMADI" deb yozardi —
    --    mantiq to'g'ri, lekin hisobot chalg'itardi. Qayta yaratamiz
    --    (idempotent; shart o'zgarmagani uchun ko'rinish ham o'zgarmaydi).
    DROP POLICY IF EXISTS task_subtasks_select_assignee ON public.task_subtasks;
    EXECUTE $sp0$
      CREATE POLICY task_subtasks_select_assignee ON public.task_subtasks
        AS PERMISSIVE FOR SELECT TO authenticated
        USING ( assigned_to = (SELECT auth.uid())
                AND is_ws_member(workspace_id, (SELECT auth.uid())) )
    $sp0$;
    v_ssel_added := true;
    v_ssel_note  := 'QAYTA RUN — policy allaqachon bizniki edi, o''zgarishsiz qayta yaratildi';
    RAISE NOTICE 'ℹ️ task_subtasks SELECT: %', v_ssel_note;
  ELSIF v_qual IS NOT NULL AND v_qual ~* 'is_ws_member' THEN
    v_ssel_note := 'MAVJUD (begona) PERMISSIVE SELECT policy allaqachon is_ws_member bo''yicha ochiq — yangi policy QO''SHILMADI (ortiqcha policy = ortiqcha xavf). ⚠️ Bu HEURISTIKA: o''sha shart qo''shimcha cheklovga ega bo''lishi mumkin — pastdagi (e) tirik sinovi buni HAQIQATDA o''lchaydi.';
    RAISE NOTICE 'ℹ️ task_subtasks SELECT: %', v_ssel_note;
  ELSE
    DROP POLICY IF EXISTS task_subtasks_select_assignee ON public.task_subtasks;
    EXECUTE $sp$
      CREATE POLICY task_subtasks_select_assignee ON public.task_subtasks
        AS PERMISSIVE FOR SELECT TO authenticated
        USING ( assigned_to = (SELECT auth.uid())
                AND is_ws_member(workspace_id, (SELECT auth.uid())) )
    $sp$;
    v_ssel_added := true;
    v_ssel_note  := 'mavjud policy''lar checklist bajaruvchisini qamramas edi → additive PERMISSIVE SELECT qo''shildi (assigned_to = men VA is_ws_member)';
    RAISE NOTICE '✅ task_subtasks_select_assignee policy qo''shildi';
  END IF;

  -- (b) UPDATE
  SELECT string_agg(coalesce(qual, '') || ' | ' || coalesce(with_check, ''), '  ##  ') INTO v_qual
    FROM pg_policies
   WHERE schemaname='public' AND tablename='task_subtasks'
     AND permissive='PERMISSIVE' AND cmd IN ('UPDATE','ALL');

  IF EXISTS (SELECT 1 FROM pg_policies
              WHERE schemaname='public' AND tablename='task_subtasks'
                AND policyname='task_subtasks_update_assignee') THEN
    -- ⚠️ QAYTA RUN — yuqoridagi (SELECT) izohi bilan bir xil sabab.
    DROP POLICY IF EXISTS task_subtasks_update_assignee ON public.task_subtasks;
    EXECUTE $up0$
      CREATE POLICY task_subtasks_update_assignee ON public.task_subtasks
        AS PERMISSIVE FOR UPDATE TO authenticated
        USING      ( assigned_to = (SELECT auth.uid())
                     AND is_ws_member(workspace_id, (SELECT auth.uid())) )
        WITH CHECK ( assigned_to = (SELECT auth.uid())
                     AND is_ws_member(workspace_id, (SELECT auth.uid())) )
    $up0$;
    v_supd_added := true;
    v_supd_note  := 'QAYTA RUN — policy allaqachon bizniki edi, o''zgarishsiz qayta yaratildi';
    RAISE NOTICE 'ℹ️ task_subtasks UPDATE: %', v_supd_note;
  ELSIF v_qual IS NOT NULL AND v_qual ~* 'is_ws_member' THEN
    v_supd_note := 'MAVJUD (begona) PERMISSIVE UPDATE policy allaqachon is_ws_member bo''yicha ochiq — yangi policy QO''SHILMADI. ⚠️ Punktni ws a''zosi ham yangilay oladi (mavjud xatti-harakat) — LEKIN endi task_subtasks_guard_trg trigger''i ustun darajasida to''sadi (title/task_id/assigned_to/... faqat vazifa egasiga).';
    RAISE NOTICE 'ℹ️ task_subtasks UPDATE: %', v_supd_note;
  ELSE
    DROP POLICY IF EXISTS task_subtasks_update_assignee ON public.task_subtasks;
    -- 🔴 WITH CHECK ham `assigned_to = auth.uid()` + ws: bajaruvchi punktni
    --    O'ZIDAN BOSHQASIGA o'tkaza olmasin (USING yolg'iz bo'lsa u qatorni
    --    ko'rib, assigned_to ni boshqa odamga yozib yuborardi).
    --    ⚠️ Ustun darajasidagi asosiy qorovul TRIGGER da (policy buni
    --       ifodalay olmaydi) — bu ikkisi bir-birini to'ldiradi.
    EXECUTE $up$
      CREATE POLICY task_subtasks_update_assignee ON public.task_subtasks
        AS PERMISSIVE FOR UPDATE TO authenticated
        USING      ( assigned_to = (SELECT auth.uid())
                     AND is_ws_member(workspace_id, (SELECT auth.uid())) )
        WITH CHECK ( assigned_to = (SELECT auth.uid())
                     AND is_ws_member(workspace_id, (SELECT auth.uid())) )
    $up$;
    v_supd_added := true;
    v_supd_note  := 'additive PERMISSIVE UPDATE qo''shildi (USING + WITH CHECK: assigned_to = men VA is_ws_member)';
    RAISE NOTICE '✅ task_subtasks_update_assignee policy qo''shildi';
  END IF;
END IF;

-- ══════════════════════════════════════════════════════════════════════════
-- 9.7) SNAPSHOT — KEYIN (aynan shu so'rovlar, aynan shu foydalanuvchilar)
--    Bu ayni paytda REKURSIYA (42P17) testi hamdir.
-- ══════════════════════════════════════════════════════════════════════════
FOR u IN SELECT * FROM pg_temp.v2_u ORDER BY uid LOOP
  BEGIN
    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', u.uid::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    EXECUTE 'SELECT count(*) FROM public.tasks' INTO v_c_tsk;
    EXECUTE 'SELECT count(*) FROM public.tasks WHERE id = ANY ($1::text[]::' || v_idtype || '[])' INTO v_c_s USING u.s_ids;
    EXECUTE 'SELECT count(*) FROM public.task_subtasks' INTO v_c_sub;

    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    INSERT INTO pg_temp.v2_snap (faza, uid, n_tsk, n_s, n_sub)
    VALUES ('keyin', u.uid, v_c_tsk, v_c_s, v_c_sub);
  EXCEPTION WHEN OTHERS THEN
    BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM set_config('request.jwt.claims', '', true);
    IF SQLSTATE = '42P17' THEN
      RAISE EXCEPTION 'REKURSIYA (42P17) YANGI POLICY SABABLI: %. Demak can_see_task_via_checklist() SECURITY DEFINER bo''lishiga qaramay task_subtasks/tasks RLS''i baholanyapti (funksiya egasi jadval egasi emas / FORCE ROW LEVEL SECURITY yoqilgan). HAMMASI QAYTARILDI.', SQLERRM;
    END IF;
    RAISE EXCEPTION 'KEYIN-snapshot xatosi (% / %): % — HAMMASI QAYTARILDI', u.uid, SQLSTATE, SQLERRM;
  END;
END LOOP;

-- ══════════════════════════════════════════════════════════════════════════
-- 9.8) 🔴 XAVFSIZLIK TEKSHIRUVI — kutilgan sondan bitta ham farq bo'lmasin
--    Kutilgan = oldingi_jami − oldin_ko'ringan_S + S_hajmi.
--    BIRINCHI RUN da S BO'SH (assigned_by/assigned_to yangi ustunlar) →
--    kutilgan = oldingi_jami, ya'ni son AYNAN O'ZGARMASLIGI shart.
-- ══════════════════════════════════════════════════════════════════════════
FOR u IN
  SELECT a.uid, a.turi, a.s_n, a.s_cut, cardinality(a.s_ids) AS s_len,
         o.n_tsk AS o_tsk, o.n_s AS o_s, o.n_sub AS o_sub,
         k.n_tsk AS k_tsk, k.n_s AS k_s, k.n_sub AS k_sub
    FROM pg_temp.v2_u a
    JOIN pg_temp.v2_snap o ON o.uid = a.uid AND o.faza='oldin'
    JOIN pg_temp.v2_snap k ON k.uid = a.uid AND k.faza='keyin'
   ORDER BY a.uid
LOOP
  -- (a) KAMAYISH — hech qachon bo'lmasligi kerak (PERMISSIVE qo'shildi)
  IF u.k_tsk < u.o_tsk THEN
    RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (tasks KAMAYDI): foydalanuvchi % — oldin %, keyin %. PERMISSIVE policy kirish huquqini TORAYTIRA OLMAYDI, demak boshqa nimadir buzilgan.% HAMMASI QAYTARILDI.',
      u.uid, u.o_tsk, u.k_tsk, v_restr_note;
  END IF;

  -- (b) ANIQ SON — to'plam kesilmagan bo'lsa
  --     🔴 F6: xato matni YO'NALISHNI ayirib beradi (ortiqcha ochildi /
  --        kam ochildi) — sabab qidirish yo'nalishi darrov ma'lum bo'lsin.
  IF NOT u.s_cut THEN
    v_exp := CASE WHEN v_pol_added THEN u.o_tsk - u.o_s + u.s_len ELSE u.o_tsk END;
    IF u.k_tsk > v_exp THEN
      RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (tasks — ORTIQCHA OCHILDI): foydalanuvchi % (%) — oldin %, kutilgan %, keyin % (ortiqcha % ta). Policy kutilganidan KO''PROQ qator ochdi: qorovullardan biri ishlamayapti (eng ehtimoli — 3-qorovul assigned_by).% HAMMASI QAYTARILDI.',
        u.uid, u.turi, u.o_tsk, v_exp, u.k_tsk, (u.k_tsk - v_exp), v_restr_note;
    ELSIF u.k_tsk < v_exp THEN
      RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (tasks — KAM OCHILDI): foydalanuvchi % (%) — oldin %, kutilgan %, keyin % (yetishmayapti % ta). Policy kutilganidan KAMROQ qator ochdi: RESTRICTIVE policy to''sayotgan bo''lishi yoki o''lchov mantiqi funksiyadan farq qilishi mumkin.% HAMMASI QAYTARILDI.',
        u.uid, u.turi, u.o_tsk, v_exp, u.k_tsk, (v_exp - u.k_tsk), v_restr_note;
    END IF;

    -- 🔴 F7: RESTRICTIVE policy bor bazada bu tekshiruv EXCEPTION EMAS —
    --    RESTRICTIVE AND bilan qo'llanadi va yangi PERMISSIVE policy ochishi
    --    kerak bo'lgan qatorni QONUNIY ravishda to'sib qo'yishi mumkin.
    --    Bu XAVFSIZ yo'nalish (kamroq ko'rinadi), shuning uchun butun
    --    migratsiya yiqilmaydi — lekin jimgina ham o'tmaydi.
    IF v_pol_added AND u.k_s IS DISTINCT FROM u.s_len THEN
      IF v_restr > 0 THEN
        RAISE WARNING '⚠️ foydalanuvchi % ga ochilishi kerak bo''lgan % ta checklist vazifasidan atigi % tasi ko''rinmoqda. Bazada % ta RESTRICTIVE policy bor — ehtimol o''sha to''sayapti (XAVFSIZ yo''nalish). Modul ishlaydi, lekin checklist bajaruvchisi ba''zi vazifalarni ko''rmasligi mumkin — qo''lda tekshiring.',
          u.uid, u.s_len, u.k_s, v_restr;
      ELSE
        RAISE EXCEPTION 'TEKSHIRUV (tasks): foydalanuvchi % ga ochilishi kerak bo''lgan % ta checklist vazifasidan atigi % tasi ko''rinmoqda — policy KUTILGANDAY ISHLAMADI (can_see_task_via_checklist mantiqi bilan o''lchov mantiqi mos kelmadi). HAMMASI QAYTARILDI.',
          u.uid, u.s_len, u.k_s;
      END IF;
    END IF;
  ELSE
    RAISE NOTICE 'ℹ️ % : to''plam % ta (chegara % dan katta) — aniq formula o''tkazib yuborildi, faqat "kamaymadi" tekshirildi.', u.uid, u.s_n, v_max_ids;
  END IF;

  -- (c) 🔴 SIZISH — "nazorat" (menejer emas, checklist punkti yo'q)
  --     foydalanuvchiga BITTA ham qo'shimcha vazifa ochilmasligi SHART.
  IF u.turi = 'nazorat' AND u.k_tsk IS DISTINCT FROM u.o_tsk THEN
    RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (SIZISH): checklist punkti YO''Q foydalanuvchi % uchun ko''rinadigan vazifalar soni % → % ga o''zgardi. HAMMASI QAYTARILDI.',
      u.uid, u.o_tsk, u.k_tsk;
  END IF;

  -- (d) task_subtasks: SELECT policy QO'SHILMAGAN bo'lsa ko'rinish
  --     O'ZGARMASLIGI shart. Qo'shilgan bo'lsa faqat KAMAYMASLIGI.
  IF NOT v_ssel_added AND u.k_sub IS DISTINCT FROM u.o_sub THEN
    RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (task_subtasks): foydalanuvchi % uchun ko''rinadigan checklist qatori % → % ga o''zgardi, holbuki bu skript unga SELECT policy QO''SHMAGAN. HAMMASI QAYTARILDI.',
      u.uid, u.o_sub, u.k_sub;
  END IF;
  IF v_ssel_added AND u.k_sub < u.o_sub THEN
    RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (task_subtasks KAMAYDI): foydalanuvchi % — % → %. HAMMASI QAYTARILDI.',
      u.uid, u.o_sub, u.k_sub;
  END IF;

  v_gain := v_gain + (u.k_tsk - u.o_tsk);
END LOOP;

RAISE NOTICE '✅ XAVFSIZLIK (sanoq): barcha sanoqlar kutilganday. Yangi ko''ringan jami: % ta vazifa qatori (faqat checklist orqali).', v_gain;

-- ══════════════════════════════════════════════════════════════════════════
-- 9.9) TIRIK SINOV — SENTINEL-ROLLBACK bilan
--    🔴 Sanoq o'lchovi birinchi RUN da bo'sh chiqadi (assigned_to/assigned_by
--       yangi ustunlar), shuning uchun ASOSIY kafolat aynan shu bo'lim.
--    ⚠️ Yozuv qiladigan sinovlar ichki blokda ataylab EXCEPTION bilan
--       tugatiladi → subtranzaksiya qaytadi va bazada BITTA qator ham
--       o'zgarmaydi.
--    Sinovlar: (a) biriktirilgan KO'RADI · (e) o'z punktini KO'RADIMI ·
--    (b) begona a'zo KO'RMAYDI · (d) punktni o'tkaza OLMAYDI ·
--    (c) jamoadan chiqarilgan KO'RMAYDI · (f) 🔴 o'ziga o'zi yozib
--    huquq OLA OLMAYDI (eskalatsiya) · PostgREST qorovuli.
-- ══════════════════════════════════════════════════════════════════════════
-- (0) Harness sanity: set_config('request.jwt.claims') haqiqatan auth.uid()
--     ga ta'sir qiladimi? (Eski auth.uid() 'request.jwt.claim.sub' ni o'qishi
--     mumkin — u holda impersonatsiya ISHLAMAYDI va sinovlar SOXTA "true"
--     bermasligi uchun umuman o'tkazib yuboriladi.)
SELECT uid INTO v_m1 FROM pg_temp.v2_u ORDER BY uid LIMIT 1;
IF v_m1 IS NOT NULL THEN
  BEGIN
    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', v_m1::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE 'SELECT (SELECT auth.uid())::text' INTO v_txt;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    v_imp_ok := (v_txt IS NOT DISTINCT FROM v_m1::text);
  EXCEPTION WHEN OTHERS THEN
    BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM set_config('request.jwt.claims', '', true);
    v_imp_ok := false;
  END;
END IF;
v_m1 := NULL;

IF NOT v_imp_ok THEN
  v_skip_why := 'impersonatsiya harnessi ishlamadi (auth.uid() request.jwt.claims dan o''qimayapti)';
  RAISE WARNING '⚠️ % — TIRIK sinovlar o''tkazib yuborildi. Struktura tekshiruvlari baribir bajarildi. Prodga chiqarishdan oldin QO''LDA sinang: (1) biriktirilgan xodim vazifani ko''radi; (2) biriktirilmagani KO''RMAYDI; (3) o''ziga o''zi checklist yozgan odam vazifani KO''RMAYDI.', v_skip_why;
END IF;

-- (0b) F9: task_subtasks.id o'zi to'lanadimi? Yo'q bo'lsa sinov qator yoza
--      olmaydi (23502) — sababni OLDINDAN aniqlaymiz, "noma'lum xato" emas.
SELECT (column_default IS NOT NULL OR is_identity = 'YES') INTO v_id_auto
  FROM information_schema.columns
 WHERE table_schema='public' AND table_name='task_subtasks' AND column_name='id';
IF v_imp_ok AND NOT coalesce(v_id_auto, false) THEN
  v_imp_ok   := false;
  v_skip_why := 'task_subtasks.id da DEFAULT/IDENTITY yo''q — sinov qatorining id sini skript o''ylab topa olmaydi (taxmin bilan yozmaymiz)';
  RAISE WARNING '⚠️ TIRIK sinov o''tkazib yuborildi — %.', v_skip_why;
END IF;

-- Sinov uchun (ws, menejer, a'zo1, a'zo2) to'rtligini topamiz.
-- ⚠️ BOSQICHMA-BOSQICH, uch tomonlama JOIN bilan EMAS: `wa × wb × wc` dekart
--    ko'paytmasi 126 a'zoli workspace'da ~2 million qator bo'lib, har qatorda
--    is_ws_manager() chaqirilardi (skript daqiqalab qotib qolardi).
IF v_imp_ok THEN
  SELECT wa.workspace_id, wa.user_id INTO v_ws, v_mgr
    FROM public.workspace_members wa
   WHERE public.is_ws_manager(wa.workspace_id, wa.user_id)
     AND EXISTS (SELECT 1 FROM public.workspace_members wb
                  WHERE wb.workspace_id = wa.workspace_id
                    AND wb.user_id <> wa.user_id
                    AND NOT public.is_ws_manager(wb.workspace_id, wb.user_id))
     AND EXISTS (SELECT 1 FROM public.tasks t WHERE t.workspace_id = wa.workspace_id)
   ORDER BY wa.workspace_id, wa.user_id
   LIMIT 1;

  IF v_ws IS NOT NULL THEN
    SELECT wb.user_id INTO v_m1
      FROM public.workspace_members wb
     WHERE wb.workspace_id = v_ws
       AND wb.user_id <> v_mgr
       AND NOT public.is_ws_manager(v_ws, wb.user_id)
     ORDER BY wb.user_id LIMIT 1;

    SELECT wc.user_id INTO v_m2
      FROM public.workspace_members wc
     WHERE wc.workspace_id = v_ws
       AND wc.user_id <> v_mgr
       AND wc.user_id IS DISTINCT FROM v_m1
       AND NOT public.is_ws_manager(v_ws, wc.user_id)
     ORDER BY wc.user_id LIMIT 1;

    IF v_m1 IS NULL OR v_m2 IS NULL THEN
      v_ws := NULL;
      v_skip_why := 'bitta workspace''da menejer + 2 ta oddiy a''zo topilmadi';
    END IF;
  ELSE
    v_skip_why := 'menejer + oddiy a''zo + vazifasi bor workspace topilmadi';
  END IF;

  -- Jamoadan TASHQARIDAGI odam (c-sinov uchun): boshqa ws a'zosi, v_ws da YO'Q
  IF v_ws IS NOT NULL THEN
    SELECT w2.user_id INTO v_out
      FROM public.workspace_members w2
     WHERE w2.workspace_id <> v_ws
       AND NOT EXISTS (SELECT 1 FROM public.workspace_members w3
                        WHERE w3.workspace_id = v_ws AND w3.user_id = w2.user_id)
     ORDER BY w2.user_id LIMIT 1;
  END IF;

  -- Sinov vazifasi: iloji bo'lsa m1 ga HOZIR KO'RINMAYDIGAN vazifa tanlanadi
  -- (shunda "checklist punkti vazifani OCHDI" ni HAQIQATAN ko'rsatish mumkin).
  IF v_ws IS NOT NULL THEN
    FOR r IN
      SELECT t.id::text AS id FROM public.tasks t
       WHERE t.workspace_id = v_ws
         AND NOT EXISTS (SELECT 1 FROM public.task_subtasks s
                          WHERE s.task_id = t.id AND s.assigned_to = v_m1)
       ORDER BY t.id DESC LIMIT 3   -- 🔴 3 (25 EMAS): har iteratsiya tasks bo'ylab so'rov qiladi
    LOOP
      BEGIN
        PERFORM set_config('request.jwt.claims',
                 json_build_object('sub', v_m1::text, 'role', 'authenticated')::text, true);
        EXECUTE 'SET LOCAL ROLE authenticated';
        -- ⚠️ id::text = $1 EMAS: chap tomonga cast qo'yilsa PK indeksi
        --    ISHLAMAY, har chaqiruv to'liq skan bo'lardi (RLS har qatorda
        --    funksiya chaqiradi). Cast O'NG tomonda.
        EXECUTE 'SELECT count(*) FROM public.tasks WHERE id = $1::text::' || v_idtype INTO v_i USING r.id;
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
      EXCEPTION WHEN OTHERS THEN
        BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
        PERFORM set_config('request.jwt.claims', '', true);
        RAISE EXCEPTION 'Sinov vazifasini tanlashda xato (%): %', SQLSTATE, SQLERRM;
      END;
      IF v_task_id IS NULL THEN
        v_task_id := r.id;   -- zaxira: hech bo'lmasa birinchisi
        v_base_m1 := v_i;
      END IF;
      IF v_i = 0 THEN
        v_task_id := r.id;   -- ideal: hozir KO'RINMAYDIGAN vazifa
        v_base_m1 := 0;
        EXIT;
      END IF;
    END LOOP;

    IF v_task_id IS NULL THEN
      v_ws := NULL;
      v_skip_why := 'sinov uchun vazifa topilmadi';
    ELSIF v_base_m1 > 0 THEN
      RAISE NOTICE 'ℹ️ Sinov vazifasi a''zoga ALLAQACHON ko''rinadi (mavjud tasks SELECT policy''si ws a''zosiga hamma vazifani ochadi). Demak yangi policy bu bazada QO''SHIMCHA qator ochmaydi — u faqat vazifasi yopiq bo''lgan sxemalarda ma''noli. Funksiya semantikasi baribir tekshiriladi.';
    END IF;
  END IF;

  -- (f) sinovi ma'noli bo'lishi uchun: m1 shu vazifaning EGASI BO'LMASLIGI
  --     shart (aks holda u vazifani qonuniy ravishda ko'radi va "eskalatsiya
  --     bo'lmadi" degan xulosa yolg'on bo'lardi).
  IF v_ws IS NOT NULL THEN
    EXECUTE 'SELECT coalesce((' || v_own_p || '), false) FROM public.tasks t WHERE t.id::text = $2'
      INTO v_m1_owns USING v_m1, v_task_id;
    v_m1_owns := coalesce(v_m1_owns, false);
  END IF;

  -- m2 va tashqi odam uchun BAZAVIY ko'rinish (keyin solishtiramiz)
  IF v_ws IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', v_m2::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE 'SELECT count(*) FROM public.tasks WHERE id = $1::text::' || v_idtype INTO v_base_m2 USING v_task_id;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);

    IF v_out IS NOT NULL THEN
      PERFORM set_config('request.jwt.claims',
               json_build_object('sub', v_out::text, 'role', 'authenticated')::text, true);
      EXECUTE 'SET LOCAL ROLE authenticated';
      EXECUTE 'SELECT count(*) FROM public.tasks WHERE id = $1::text::' || v_idtype INTO v_base_out USING v_task_id;
      EXECUTE 'RESET ROLE';
      PERFORM set_config('request.jwt.claims', '', true);
    END IF;
  END IF;

  -- INSERT uchun ustun ro'yxati: BILMAYDIGAN majburiy ustun bo'lsa sinov
  -- o'tkazib yuboriladi (taxmin bilan qator yozilmaydi).
  IF v_ws IS NOT NULL THEN
    SELECT string_agg(column_name, ', ') INTO v_bad_cols
      FROM information_schema.columns
     WHERE table_schema='public' AND table_name='task_subtasks'
       AND is_nullable='NO' AND column_default IS NULL AND is_identity='NO'
       AND column_name NOT IN ('id','workspace_id','task_id','title','assigned_to','assigned_by','sort_order');
    IF v_bad_cols IS NOT NULL THEN
      v_ws := NULL;
      v_skip_why := 'task_subtasks da noma''lum majburiy ustun(lar) bor: ' || v_bad_cols;
      RAISE WARNING '⚠️ TIRIK sinov o''tkazib yuborildi — %. Sinov qatorini taxmin bilan to''ldirmaymiz.', v_skip_why;
    END IF;
  END IF;
END IF;

-- ── Asosiy tirik sinov (sentinel-rollback) ──────────────────────────────────
IF v_imp_ok AND v_ws IS NOT NULL THEN
  -- INSERT ifodasini mavjud ustunlardan quramiz.
  -- ⚠️ `assigned_by` ATAYLAB v_mgr bilan yuboriladi: postgres roli ostida
  --    trigger aralashmaydi (server tomoni), ya'ni qator "menejer biriktirgan"
  --    bo'lib tug'iladi — 3-qorovul uchun QONUNIY holat.
  --    (f) sinovida AYNI SHU satr `authenticated` ostida qayta ishlatiladi va
  --    trigger assigned_by ni majburan qayta yozadi — shu bilan "mijoz
  --    yuborgan qiymat e'tiborga olinmaydi" ham TIRIK isbotlanadi.
  v_ins_cols := 'task_id';
  v_ins_vals := quote_literal(v_task_id) || '::' || v_idtype;

  IF v_sub_has_ws THEN
    v_ins_cols := v_ins_cols || ', workspace_id';
    v_ins_vals := v_ins_vals || ', ' || quote_literal(v_ws::text) || '::uuid';
  END IF;
  v_ins_cols := v_ins_cols || ', title';
  v_ins_vals := v_ins_vals || ', ' || quote_literal('TASKFIX_LOYIHA_V2 sinov — QAYTARILADI');
  v_ins_cols := v_ins_cols || ', sort_order';
  v_ins_vals := v_ins_vals || ', 0';
  v_ins_cols := v_ins_cols || ', assigned_to, assigned_by';
  v_ins_vals := v_ins_vals || ', ' || quote_literal(v_m1::text) || '::uuid'
                           || ', ' || quote_literal(v_mgr::text) || '::uuid';

  -- 🔴 (f) sinovi uchun ALOHIDA satr — farqlari ATAYLAB:
  --    • assigned_by YUBORILMAYDI. 8-bo'limdagi GRANT unga INSERT huquqi
  --      BERMAYDI (uni trigger yozadi); ustun darajasidagi grant ishlatilgan
  --      bazada yuborilsa 42501 kelib, natija "INSERT to'sildi ✅" deb
  --      yozilardi — holbuki ESKALATSIYA QOROVULI umuman sinalmagan bo'lardi.
  --    • title BOSHQA: (task_id, title) bo'yicha UNIQUE indeks bo'lsa 23505
  --      chiqib, xuddi shu SOXTA "✅" ga olib kelardi.
  v_ins_cols_f := replace(v_ins_cols, ', assigned_to, assigned_by', ', assigned_to');
  v_ins_vals_f := replace(v_ins_vals,
                    ', ' || quote_literal(v_mgr::text) || '::uuid', '');
  v_ins_vals_f := replace(v_ins_vals_f,
                    quote_literal('TASKFIX_LOYIHA_V2 sinov — QAYTARILADI'),
                    quote_literal('TASKFIX_LOYIHA_V2 sinov (f) — QAYTARILADI'));

  BEGIN
    -- 1) Sinov qatori (postgres roli ostida — ma'lumot tayyorlash)
    EXECUTE format('INSERT INTO public.task_subtasks (%s) VALUES (%s) RETURNING id::text',
                   v_ins_cols, v_ins_vals) INTO v_probe;

    -- (a) BIRIKTIRILGAN odam vazifani KO'RADI  +  (e) o'z punktini ko'radimi
    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', v_m1::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE 'SELECT public.can_see_task_via_checklist($1::text::' || v_idtype || ', $2)::text'
      INTO v_p_f1 USING v_task_id, v_m1;
    EXECUTE 'SELECT count(*)::text FROM public.tasks WHERE id = $1::text::' || v_idtype INTO v_p_c1 USING v_task_id;
    EXECUTE 'SELECT count(*)::text FROM public.task_subtasks WHERE id::text = $1' INTO v_p_se USING v_probe;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);

    -- (g) 🔴 BAJARUVCHI "bajarildi" BELGISINI QO'YA OLADIMI?
    --     Bu yagona qamralmagan xavfni yopadi: task_subtasks da BOSHQA
    --     BEFORE UPDATE trigger'i (masalan handle_updated_at) bizning
    --     qorovuldan OLDIN ishlab HIMOYALANGAN ustunni yozib qo'ysa,
    --     bajaruvchining har bosishi 42501 ga urilardi va modul jimgina
    --     o'lardi. Shuning uchun buni TAXMIN QILMAYMIZ — o'lchaymiz.
    --     ⚠️ ALOHIDA ICHKI BLOK: 42501 tashqi handler'ga chiqib ketmasin.
    BEGIN
      PERFORM set_config('request.jwt.claims',
               json_build_object('sub', v_m1::text, 'role', 'authenticated')::text, true);
      EXECUTE 'SET LOCAL ROLE authenticated';
      EXECUTE 'UPDATE public.task_subtasks SET is_completed = NOT coalesce(is_completed, false) WHERE id::text = $1'
        USING v_probe;
      GET DIAGNOSTICS v_i = ROW_COUNT;
      v_p_tog := v_i::text;
      EXECUTE 'RESET ROLE';
      PERFORM set_config('request.jwt.claims', '', true);
    EXCEPTION WHEN OTHERS THEN
      BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
      PERFORM set_config('request.jwt.claims', '', true);
      v_p_tog := 'E' || SQLSTATE;
    END;
    -- ⚠️ Belgi ATAYLAB qaytarilmaydi: butun blok sentinel-rollback bilan
    --    baribir qaytadi, keyingi sinovlarning birortasi ham is_completed ni
    --    o'qimaydi. Qo'lda "qaytarish" esa toggle YIQILGAN holatda qiymatni
    --    teskari tomonga surib qo'yardi (foydasiz murakkablik).

    -- (b) BIRIKTIRILMAGAN begona a'zo KO'RMAYDI + PostgREST qorovuli
    PERFORM set_config('request.jwt.claims',
             json_build_object('sub', v_m2::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE 'SELECT public.can_see_task_via_checklist($1::text::' || v_idtype || ', $2)::text'
      INTO v_p_f2 USING v_task_id, v_m2;
    EXECUTE 'SELECT count(*)::text FROM public.tasks WHERE id = $1::text::' || v_idtype INTO v_p_c2 USING v_task_id;
    -- p_user <> auth.uid() → DOIM false
    EXECUTE 'SELECT public.can_see_task_via_checklist($1::text::' || v_idtype || ', $2)::text'
      INTO v_p_fx USING v_task_id, v_m1;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);

    -- (d) 🔴 Bajaruvchi punktni O'ZIDAN BOSHQASIGA o'tkaza olmasin.
    --     ⚠️ TARTIB MUHIM: bu sinov (b) DAN KEYIN turadi — agar yozuv o'tib
    --        ketsa punkt m2 ga ko'chib qolardi va (b) SOXTA xavfsizlik xatosi
    --        berardi. Sinovdan keyin qator m1 ga QAYTARILADI.
    --     ⚠️ ALOHIDA ICHKI BLOK: trigger/WITH CHECK buzilishi 0 QATOR emas,
    --        42501 XATOSI beradi — u tashqi handler'ga chiqib ketsa butun
    --        tirik sinov "harness yiqildi" deb o'tkazib yuborilardi, holbuki
    --        42501 aynan KUTILGAN natija.
    BEGIN
      PERFORM set_config('request.jwt.claims',
               json_build_object('sub', v_m1::text, 'role', 'authenticated')::text, true);
      EXECUTE 'SET LOCAL ROLE authenticated';
      EXECUTE 'UPDATE public.task_subtasks SET assigned_to = $1 WHERE id::text = $2'
        USING v_m2, v_probe;
      GET DIAGNOSTICS v_i = ROW_COUNT;
      v_p_upd := v_i::text;
      EXECUTE 'RESET ROLE';
      PERFORM set_config('request.jwt.claims', '', true);
    EXCEPTION WHEN OTHERS THEN
      BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
      PERFORM set_config('request.jwt.claims', '', true);
      IF SQLSTATE = '42501' THEN
        v_p_upd := 'X';                 -- trigger yoki RLS to'sdi = KUTILGAN
      ELSE
        v_p_upd := 'E' || SQLSTATE;     -- boshqa xato: yozuv baribir bo'lmadi
      END IF;
    END;

    -- Normalizatsiya: (d) o'tib ketgan bo'lsa qatorni m1 ga QAYTARAMIZ.
    EXECUTE 'UPDATE public.task_subtasks SET assigned_to = $1, assigned_by = $2 WHERE id::text = $3'
      USING v_m1, v_mgr, v_probe;

    -- (c) JAMOADAN CHIQARILGAN odam KO'RMAYDI:
    --     punktni unga biriktiramiz (u v_ws a'zosi EMAS) va tekshiramiz.
    IF v_out IS NOT NULL THEN
      EXECUTE 'UPDATE public.task_subtasks SET assigned_to = $1, assigned_by = $2 WHERE id::text = $3'
        USING v_out, v_mgr, v_probe;
      PERFORM set_config('request.jwt.claims',
               json_build_object('sub', v_out::text, 'role', 'authenticated')::text, true);
      EXECUTE 'SET LOCAL ROLE authenticated';
      EXECUTE 'SELECT public.can_see_task_via_checklist($1::text::' || v_idtype || ', $2)::text'
        INTO v_p_fo USING v_task_id, v_out;
      EXECUTE 'SELECT count(*)::text FROM public.tasks WHERE id = $1::text::' || v_idtype INTO v_p_co USING v_task_id;
      EXECUTE 'RESET ROLE';
      PERFORM set_config('request.jwt.claims', '', true);
    END IF;

    -- (f) 🔴 HUQUQ ESKALATSIYASI SINOVI — eng muhim yangi qorovul.
    --     Avval qonuniy qatorni NEYTRALLAYMIZ (aks holda m1 vazifani
    --     qonuniy ravishda ko'rib turardi va natija yolg'on chiqardi).
    EXECUTE 'UPDATE public.task_subtasks SET assigned_to = NULL, assigned_by = NULL WHERE id::text = $1'
      USING v_probe;

    IF v_m1_owns THEN
      v_p_esc := '-';   -- m1 shu vazifaning egasi: sinov ma'nosiz
    ELSE
      BEGIN
        PERFORM set_config('request.jwt.claims',
                 json_build_object('sub', v_m1::text, 'role', 'authenticated')::text, true);
        EXECUTE 'SET LOCAL ROLE authenticated';
        -- m1 O'ZIGA O'ZI checklist qatori yozadi. assigned_by YUBORILMAYDI —
        -- uni trigger m1 ga qo'yadi va 3-qorovul aynan shuni to'sishi kerak.
        EXECUTE format('INSERT INTO public.task_subtasks (%s) VALUES (%s)',
                       v_ins_cols_f, v_ins_vals_f);
        EXECUTE 'SELECT public.can_see_task_via_checklist($1::text::' || v_idtype || ', $2)::text'
          INTO v_p_esc USING v_task_id, v_m1;
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
      EXCEPTION WHEN OTHERS THEN
        BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
        PERFORM set_config('request.jwt.claims', '', true);
        -- INSERT ning o'zi to'silgan bo'lsa eskalatsiya yo'li ham yopiq.
        v_p_esc := 'I' || SQLSTATE;
      END;
    END IF;

    -- ⚠️ SENTINEL: subtranzaksiyani ataylab qaytaramiz (INSERT/UPDATE'lar
    --    yo'qoladi). Natijalar xato MATNIDA olib chiqiladi.
    RAISE EXCEPTION 'V2_PROBE:%',
      coalesce(v_p_f1,'?') || '|' || coalesce(v_p_c1,'?') || '|' ||
      coalesce(v_p_se,'?') || '|' || coalesce(v_p_f2,'?') || '|' ||
      coalesce(v_p_c2,'?') || '|' || coalesce(v_p_fx,'?') || '|' ||
      coalesce(v_p_upd,'?') || '|' || coalesce(v_p_fo,'-') || '|' ||
      coalesce(v_p_co,'-') || '|' || coalesce(v_p_esc,'?') || '|' ||
      coalesce(v_p_tog,'?')
      USING ERRCODE = '22000';

  EXCEPTION WHEN OTHERS THEN
    BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM set_config('request.jwt.claims', '', true);

    IF SQLERRM NOT LIKE 'V2_PROBE:%' THEN
      -- Harness xatosi — bu XAVFSIZLIK xatosi EMAS, migratsiya to'xtatilmaydi,
      -- lekin jimgina ham yutilmaydi (CLAUDE.md 6-qoida).
      v_skip_why := 'sinov qatorini yozib bo''lmadi (' || SQLSTATE || '): ' || left(SQLERRM, 160);
      RAISE WARNING '⚠️ TIRIK sinov o''tkazib yuborildi — %. Struktura tekshiruvlari bajarildi; prodga chiqishdan oldin QO''LDA sinang.', v_skip_why;
    ELSE
      v_probe := replace(SQLERRM, 'V2_PROBE:', '');
      v_p_f1  := split_part(v_probe, '|', 1);
      v_p_c1  := split_part(v_probe, '|', 2);
      v_p_se  := split_part(v_probe, '|', 3);
      v_p_f2  := split_part(v_probe, '|', 4);
      v_p_c2  := split_part(v_probe, '|', 5);
      v_p_fx  := split_part(v_probe, '|', 6);
      v_p_upd := split_part(v_probe, '|', 7);
      v_p_fo  := split_part(v_probe, '|', 8);
      v_p_co  := split_part(v_probe, '|', 9);
      v_p_esc := split_part(v_probe, '|', 10);
      v_p_tog := split_part(v_probe, '|', 11);

      -- (a) KO'RADI
      IF v_p_f1 IS DISTINCT FROM 'true' THEN
        RAISE EXCEPTION 'TIRIK SINOV YIQILDI (a): menejer biriktirgan checklist punkti egasi uchun can_see_task_via_checklist = % (kutilgan true) — vazifa unga OCHILMAYDI. HAMMASI QAYTARILDI.', coalesce(v_p_f1,'NULL');
      END IF;
      IF v_p_c1::int < 1 THEN
        RAISE EXCEPTION 'TIRIK SINOV YIQILDI (a): funksiya true qaytardi, lekin RLS orqali vazifa qatori KO''RINMADI (% ta). Policy qo''shilmaganmi yoki RESTRICTIVE policy to''syaptimi?% HAMMASI QAYTARILDI.', v_p_c1, v_restr_note;
      END IF;
      v_t_see := CASE WHEN v_base_m1 = 0 THEN '✅ true (0 → 1 qator: policy HAQIQATAN ochdi)'
                      ELSE '✅ true (' || v_p_c1 || ' qator; vazifa avvaldan ko''rinardi)' END;

      -- (g) 🔴 BAJARUVCHI "bajarildi" BELGISINI QO'YA OLADIMI?
      IF left(coalesce(v_p_tog, '?'), 1) = 'E' THEN
        IF substr(v_p_tog, 2) = '42501' THEN
          RAISE EXCEPTION 'TIRIK SINOV YIQILDI (g): bajaruvchi O''Z checklist punktida is_completed ni o''zgartira OLMADI — 42501. Sabab deyarli aniq: task_subtasks dagi BOSHQA BEFORE UPDATE trigger''i (masalan handle_updated_at / set_updated_at) HIMOYALANGAN ustunni yozyapti va bizning qorovul uni "ruxsatsiz o''zgarish" deb rad etyapti. Yuqoridagi "BOSHQA BEFORE UPDATE trigger(lar)i bor" ogohlantirishiga qarang: o''sha trigger yozadigan ustunni oq ro''yxatga qo''shing (6-bo''lim, v_white). HAMMASI QAYTARILDI — modul bu holatda foydalanuvchi uchun ISHLAMASDI.';
        END IF;
        RAISE EXCEPTION 'TIRIK SINOV YIQILDI (g): bajaruvchining is_completed yozuvi % xatosi bilan tugadi. Modul foydalanuvchi uchun ishlamasdi. HAMMASI QAYTARILDI.', substr(v_p_tog, 2);
      ELSIF v_p_tog::int > 0 THEN
        v_t_tog := '✅ ' || v_p_tog || ' qator';
      ELSE
        -- 0 qator = RLS to'sdi (UPDATE policy yo'q). Bu BIZNING qorovul
        -- emas va bu skript mavjud policy'larni toraytirmaydi — shuning
        -- uchun EXCEPTION emas, lekin jimgina ham o'tmaydi.
        v_t_tog := '❗ 0 qator — RLS to''sdi';
        RAISE WARNING '❗ (g) SINOVI: bajaruvchi O''Z checklist punktida is_completed ni yoza olmadi (0 qator — RLS). Bu bizning trigger emas: task_subtasks da unga mos PERMISSIVE UPDATE policy yo''q. Modul foydalanuvchi uchun YARIM ishlaydi (punktni belgilay olmaydi). Yakuniy jadvalning 13-qatoriga qarang — agar policy QO''SHILMAGAN bo''lsa, qo''lda qo''shish kerak bo''lishi mumkin.';
      END IF;

      -- (e) 🔴 F4: bajaruvchi CHECKLIST QATORINING O'ZINI ko'radimi?
      --     EXCEPTION EMAS — bu mavjud task_subtasks policy'lariga bog'liq
      --     va bu skript ularni TORAYTIRMAYDI. Lekin jimgina ham o'tmaydi:
      --     0 bo'lsa modul foydalanuvchi uchun ISHLAMAYDI (vazifa ko'rinadi,
      --     punkt ko'rinmaydi) — buni ochiq aytamiz.
      IF v_p_se::int < 1 THEN
        v_t_seesub := '❗ 0 qator — punkt KO''RINMAYDI';
        RAISE WARNING '❗ (e) SINOVI: checklist punkti biriktirilgan xodim VAZIFANI ko''radi, lekin PUNKTNING O''ZINI ko''rmaydi (task_subtasks SELECT policy''si uni qamramaydi). Modul foydalanuvchi uchun YARIM ishlaydi. Sabab: mavjud policy shartida `is_ws_member` bor deb topildi va yangi SELECT policy QO''SHILMADI, lekin o''sha policy qo''shimcha cheklovga ega ekan. TUZATISH: qo''lda qo''shing — CREATE POLICY task_subtasks_select_assignee ON public.task_subtasks AS PERMISSIVE FOR SELECT TO authenticated USING (assigned_to = (SELECT auth.uid()) AND is_ws_member(workspace_id, (SELECT auth.uid())));';
      ELSE
        v_t_seesub := '✅ ' || v_p_se || ' qator';
      END IF;

      -- (b) 🔴 BEGONA A'ZO KO'RMAYDI
      IF v_p_f2 IS DISTINCT FROM 'false' THEN
        RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (b): checklist punkti biriktirilMAGAN a''zo uchun can_see_task_via_checklist = % (kutilgan false). HAMMASI QAYTARILDI.', coalesce(v_p_f2,'NULL');
      END IF;
      IF v_p_c2::int IS DISTINCT FROM v_base_m2 THEN
        RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (b): begona a''zoga ko''rinadigan qator soni % → % ga o''zgardi (checklist unga biriktirilmagan). HAMMASI QAYTARILDI.', v_base_m2, v_p_c2;
      END IF;
      v_t_deny := '✅ false (qator soni o''zgarmadi: ' || v_base_m2 || ')';

      -- PostgREST qorovuli
      IF v_p_fx IS DISTINCT FROM 'false' THEN
        RAISE EXCEPTION 'XAVFSIZLIK BUZILDI: can_see_task_via_checklist BOSHQA odam (p_user <> auth.uid()) haqida javob berdi = %. Funksiya tanasidagi 1-qorovul buzilgan. HAMMASI QAYTARILDI.', coalesce(v_p_fx,'NULL');
      END IF;
      v_t_rpc := '✅ false';

      -- (d) PUNKTNI O'ZIDAN BOSHQASIGA O'TKAZISH
      --     'X'  = 42501 (trigger yoki RLS to'sdi)  → KUTILGAN
      --     'E…' = boshqa xato — yozuv baribir bo'lmadi
      --     son  = ROW_COUNT (0 = to'silgan, >0 = O'TDI)
      IF v_p_upd = 'X' THEN
        v_t_move := '✅ to''sildi (42501 — trigger/WITH CHECK)';
      ELSIF left(v_p_upd, 1) = 'E' THEN
        v_t_move := '✅ to''sildi (' || substr(v_p_upd, 2) || ')';
        RAISE NOTICE 'ℹ️ (d) sinovi kutilmagan SQLSTATE bilan to''sildi: % — yozuv BO''LMADI, lekin sababni ko''rib chiqing.', substr(v_p_upd, 2);
      ELSIF v_p_upd::int > 0 AND v_m1_owns THEN
        -- 🔴 SOXTA XATO EMAS: sinov a'zosi tasodifan SHU vazifaning egasi
        --    (assigned_to / created_by / acceptor_id) bo'lib qolgan — trigger
        --    unga QONUNIY ravishda ruxsat beradi. TaskFix'da a'zo odatda
        --    hamma vazifani ko'radi, ya'ni tanlangan vazifa eng yangisi
        --    bo'lib qolishi mumkin va bu holat kam uchraydigan emas.
        --    Busiz butun migratsiya to'g'ri ishlayotgan bazada qaytardi.
        v_t_move := '- (sinov a''zosi shu vazifaning EGASI — o''tishi KUTILGAN, ' || v_p_upd || ' qator)';
        RAISE NOTICE 'ℹ️ (d) sinovi hukmsiz qoldi: sinov a''zosi shu vazifaning egasi ekan (trigger unga qonuniy ruxsat berdi). QO''LDA sinang: egasi BO''LMAGAN odam bilan.';
      ELSIF v_p_upd::int > 0 THEN
        RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (d): vazifa EGASI BO''LMAGAN bajaruvchi checklist punktini BOSHQA odamga o''tkaza oldi (% qator). task_subtasks_guard_trg trigger''i ustun darajasidagi qorovulni bajarmadi. HAMMASI QAYTARILDI.', v_p_upd;
      ELSE
        v_t_move := '✅ to''sildi (0 qator — RLS)';
      END IF;

      -- (c) JAMOADAN CHIQARILGAN ODAM
      IF v_p_fo = '-' THEN
        v_t_out := 'o''tkazib yuborildi (boshqa ws da mos foydalanuvchi topilmadi)';
      ELSIF v_p_fo IS DISTINCT FROM 'false' THEN
        RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (c): jamoadan tashqaridagi odamga checklist punkti biriktirilgan bo''lsa ham can_see_task_via_checklist = % (kutilgan false) — 2-qorovul (is_ws_member) ishlamadi. HAMMASI QAYTARILDI.', v_p_fo;
      ELSIF v_p_co::int IS DISTINCT FROM v_base_out THEN
        RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (c): jamoadan tashqaridagi odamga ko''rinadigan qator soni % → % ga o''zgardi. HAMMASI QAYTARILDI.', v_base_out, v_p_co;
      ELSE
        v_t_out := '✅ false (qator soni o''zgarmadi: ' || v_base_out || ')';
      END IF;

      -- (f) 🔴 HUQUQ ESKALATSIYASI — ENG MUHIM SINOV
      IF v_p_esc = '-' THEN
        v_t_esc := 'o''tkazib yuborildi (sinov a''zosi shu vazifaning egasi — sinov ma''nosiz bo''lardi)';
        RAISE NOTICE 'ℹ️ (f) eskalatsiya sinovi o''tkazib yuborildi: tanlangan a''zo shu vazifaning egasi (assigned_to/created_by/acceptor_id). QO''LDA sinang.';
      ELSIF left(v_p_esc, 1) = 'I' THEN
        -- 🔴 "✅" EMAS: INSERT to'silgani eskalatsiya QOROVULI ishlaganini
        --    ISBOTLAMAYDI — u shunchaki sinovni o'tkazib yubordi (grant,
        --    UNIQUE indeks, boshqa cheklov...). Ochiq aytamiz.
        v_t_esc := '❗ sinov O''TKAZILMADI — INSERT ning o''zi to''sildi (' || substr(v_p_esc, 2) || ')';
        RAISE WARNING '❗ (f) ESKALATSIYA SINOVI O''TKAZILMADI: sinov qatorini yozib bo''lmadi (%). Bu qorovul ISHLADI degani EMAS — u shunchaki sinalmadi. Prodga chiqishdan oldin QO''LDA sinang: oddiy a''zo o''ziga checklist punkti yozib, egasi bo''lmagan vazifani ko''ra olmasligi kerak.', substr(v_p_esc, 2);
      ELSIF v_p_esc IS DISTINCT FROM 'false' THEN
        RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (f) — HUQUQ ESKALATSIYASI: oddiy a''zo o''ziga checklist qatori yozib, egasi bo''lmagan vazifani ko''rish huquqini OLDI (can_see_task_via_checklist = %). Demak 3-qorovul (assigned_by) yoki task_subtasks_guard_trg trigger''i ishlamayapti. HAMMASI QAYTARILDI.', v_p_esc;
      ELSE
        v_t_esc := '✅ false (o''ziga o''zi yozgan qator HECH NARSA ochmadi)';
      END IF;
    END IF;
  END;
ELSE
  RAISE NOTICE 'ℹ️ TIRIK sinovlar bajarilmadi — %. Bu XATO emas, lekin prodga chiqishdan oldin QO''LDA sinang.', v_skip_why;
END IF;

-- ══════════════════════════════════════════════════════════════════════════
-- 9.10) POLICY TEKSHIRUVI (struktura-B) — yangi policy'lar kutilgandekmi
-- ══════════════════════════════════════════════════════════════════════════
IF v_pol_added THEN
  SELECT permissive, qual, cmd INTO v_txt, v_qual, v_src FROM pg_policies
   WHERE schemaname='public' AND tablename='tasks' AND policyname='tasks_select_checklist_assignee';
  IF v_txt IS DISTINCT FROM 'PERMISSIVE' THEN
    RAISE EXCEPTION 'tasks_select_checklist_assignee PERMISSIVE emas (%) — RESTRICTIVE policy mavjud kirish huquqini TORAYTIRIB yuborardi. HAMMASI QAYTARILDI.', coalesce(v_txt,'NULL');
  END IF;
  IF v_src IS DISTINCT FROM 'SELECT' THEN
    RAISE EXCEPTION 'tasks_select_checklist_assignee cmd = % (kutilgan SELECT) — checklist bajaruvchisiga YOZUV huquqi berilmasligi kerak edi. HAMMASI QAYTARILDI.', coalesce(v_src,'NULL');
  END IF;
  IF v_qual !~ 'can_see_task_via_checklist' OR v_qual !~ 'is_ws_member' THEN
    RAISE EXCEPTION 'tasks_select_checklist_assignee shartida can_see_task_via_checklist / is_ws_member yo''q (%) — HAMMASI QAYTARILDI.', coalesce(v_qual,'NULL');
  END IF;
END IF;

-- 🔴 F1: biz qo'shgan checklist policy'larida ws qorovuli BO'LISHI SHART
IF v_ssel_added THEN
  SELECT qual INTO v_qual FROM pg_policies
   WHERE schemaname='public' AND tablename='task_subtasks' AND policyname='task_subtasks_select_assignee';
  IF v_qual IS NULL OR v_qual !~ 'is_ws_member' OR v_qual !~ 'assigned_to' THEN
    RAISE EXCEPTION 'task_subtasks_select_assignee shartida is_ws_member / assigned_to yo''q (%) — jamoadan chiqarilgan xodim eski checklist qatorlarini o''qib turardi. HAMMASI QAYTARILDI.', coalesce(v_qual,'NULL');
  END IF;
END IF;
IF v_supd_added THEN
  SELECT qual, with_check INTO v_qual, v_txt FROM pg_policies
   WHERE schemaname='public' AND tablename='task_subtasks' AND policyname='task_subtasks_update_assignee';
  IF v_txt IS NULL OR v_txt !~ 'assigned_to' OR v_txt !~ 'is_ws_member' THEN
    RAISE EXCEPTION 'task_subtasks_update_assignee da WITH CHECK (assigned_to = auth.uid() AND is_ws_member(...)) YO''Q (%) — HAMMASI QAYTARILDI.', coalesce(v_txt,'NULL');
  END IF;
  IF v_qual IS NULL OR v_qual !~ 'is_ws_member' THEN
    RAISE EXCEPTION 'task_subtasks_update_assignee USING shartida is_ws_member yo''q (%) — HAMMASI QAYTARILDI.', coalesce(v_qual,'NULL');
  END IF;
END IF;

-- Mavjud policy'lar joyidami? (biz faqat QO'SHDIK)
-- ⚠️ Shart `< v_tsk_sel`, `< v_tsk_sel + 1` EMAS: QAYTA RUN da policy allaqachon
--    mavjud bo'lgani uchun "oldingi" sanoq uni O'Z ICHIGA OLADI va +1 talab
--    qilinsa skript ikkinchi RUN da SOXTA xato bilan yiqilardi.
SELECT count(*) INTO v_n FROM pg_policies
 WHERE schemaname='public' AND tablename='tasks' AND permissive='PERMISSIVE' AND cmd IN ('SELECT','ALL');
IF v_n < v_tsk_sel THEN
  RAISE EXCEPTION 'tasks da PERMISSIVE SELECT policy soni KAMAYDI (% ← %) — mavjud policy o''chib ketgan. HAMMASI QAYTARILDI.', v_n, v_tsk_sel;
END IF;

RAISE NOTICE '✅ POLICY tekshiruvi tugadi.';

-- ══════════════════════════════════════════════════════════════════════════
-- 9.11) YAKUNIY HISOBOT
-- ══════════════════════════════════════════════════════════════════════════
INSERT INTO pg_temp.v2_res VALUES
  (1,  'ustun', 'projects.recur_weekdays / recur_monthdays', 'bor',
       'smallint[] multiselect. NULL = ESKI recur_weekday/monthday ishlatiladi — mavjud loyihalar xatti-harakati o''zgarmaydi'),
  (2,  'cheklov', 'projects_recur_weekdays_chk / _monthdays_chk', '2 ta',
       'tf_smallint_set_ok(): bo''sh massiv, NULL element, diapazondan tashqari va TAKROR rad etiladi (0..6 / 1..31)'),
  (3,  'ustun', 'projects.responsible_id', 'bor',
       coalesce((SELECT 'FK → ' || ref FROM pg_temp.v2_ref WHERE k='user'), 'FK''SIZ (nishon topilmadi)')),
  (4,  'ustun', 'projects.respect_dayoff', 'bor',
       'boolean NOT NULL DEFAULT false = hozirgi xatti-harakat'),
  (5,  'ustun', 'task_subtasks: assigned_to, file_url, file_name, file_size, done_at, done_by', 'bor',
       'YANGI JADVAL YO''Q — mavjud checklist jadvali kengaytirildi. done_by da FK ATAYLAB yo''q (audit)'),
  (6,  'ustun', '🔴 task_subtasks.assigned_by', 'bor',
       'KIM biriktirgan. Qiymatni FAQAT trigger yozadi — huquq eskalatsiyasining oldini oladi (3-qorovul manbai)'),
  (7,  'trigger', '🔴 task_subtasks_guard_trg', 'bor',
       'assigned_by ni SERVER yozadi (mijoz qiymati e''tiborsiz, 1-bo''lim) + OQ RO''YXAT: egasi bo''lmagan odamga faqat is_completed/file_* ochiq, QOLGAN HAR QANDAY ustun (yangi qo''shilganlari ham) YOPIQ + done_at/done_by ni trigger yozadi. DELETE ga TEGMAYDI (mavjud policy hal qiladi)'),
  (8,  'indeks', 'idx_task_subtasks_assigned', 'bor',
       'task_subtasks(assigned_to) WHERE assigned_to IS NOT NULL — qisman'),
  (9,  'storage', 'attachments bucket', 'TEGILMADI',
       '🔴 Yangi policy KERAK EMAS: fayl mavjud <ws_id>/<task_id>/… yo''liga yuklanadi. ⚠️ Bucket PUBLIC — havolani bilgan har kim yuklab oladi (task_attachments bilan bir xil)'),
  (10, 'funksiya', format('can_see_task_via_checklist(%s, uuid)', v_idtype), 'yaratildi',
       'SECURITY DEFINER · STABLE · faqat authenticated EXECUTE · 3 QOROVUL (auth.uid() + is_ws_member + assigned_by huquqi)'),
  (11, 'policy', 'tasks_select_checklist_assignee',
       CASE WHEN v_pol_added THEN 'qo''shildi' ELSE 'QO''SHILMADI' END, v_pol_reason),
  (12, 'policy', 'task_subtasks_select_assignee',
       CASE WHEN v_ssel_added THEN 'qo''shildi' ELSE 'QO''SHILMADI' END, coalesce(v_ssel_note,'—')),
  (13, 'policy', 'task_subtasks_update_assignee',
       CASE WHEN v_supd_added THEN 'qo''shildi' ELSE 'QO''SHILMADI' END, coalesce(v_supd_note,'—')),
  (14, 'sinov', '(a) biriktirilgan odam VAZIFANI ko''radi', v_t_see,
       'menejer biriktirgan punkt → can_see = true + RLS qatori ochildi'),
  (15, 'sinov', '(e) u PUNKTNING O''ZINI ko''radimi', v_t_seesub,
       '❗ bo''lsa: task_subtasks SELECT policy''si qamramaydi → modul yarim ishlaydi (yuqoridagi WARNING da tuzatish SQL''i bor)'),
  (16, 'sinov', '(b) 🔴 begona a''zo KO''RMAYDI', v_t_deny,
       'eng muhim sinovlardan — qator soni o''zgarmasligi shart'),
  (17, 'sinov', '(c) jamoadan chiqarilgan KO''RMAYDI', v_t_out,
       '2-qorovul: is_ws_member(task.workspace_id, p_user)'),
  (18, 'sinov', '(d) punktni boshqasiga O''TKAZA OLMAYDI', v_t_move,
       'task_subtasks_guard_trg ustun darajasidagi qorovuli (+ WITH CHECK)'),
  (19, 'sinov', '(f) 🔴 O''ZIGA O''ZI YOZIB HUQUQ OLA OLMAYDI', v_t_esc,
       '3-qorovul: assigned_by ws-menejeri yoki vazifa egasi bo''lmasa qator HECH NARSA ochmaydi'),
  (20, 'sinov', 'begona p_user (PostgREST /rpc)', v_t_rpc,
       'p_user <> auth.uid() → false'),
  (21, 'xavfsizlik', 'tekshirilgan foydalanuvchi',
       (SELECT count(*)::text FROM pg_temp.v2_u),
       (SELECT count(*)::text FROM pg_temp.v2_u WHERE turi='nazorat') || ' tasi NAZORAT (ularda son AYNAN o''zgarmasligi shart)'),
  (22, 'xavfsizlik', 'yangi ko''ringan qator', v_gain::text || ' vazifa',
       CASE WHEN v_gain = 0
            THEN '✅ KUTILGAN NATIJA: assigned_to/assigned_by YANGI ustunlar, hali bitta ham biriktirilgan punkt yo''q va mijoz ularni keyingi bosqichda ulaydi. RUN kunida policy 0 qator ochishi TO''G''RI — bu xato emas.'
            ELSE 'checklist punkti biriktirilgan (va assigned_by huquqli) vazifalar' END),
  (23, 'xavfsizlik', 'RESTRICTIVE policy',
       CASE WHEN v_restr > 0 THEN v_restr::text || ' ta' ELSE 'yo''q' END,
       CASE WHEN v_restr > 0 THEN 'AND bilan qo''llanadi — yangi PERMISSIVE policy ularni yenga olmaydi'
            ELSE 'yangi PERMISSIVE policy to''liq kuchga kiradi' END),
  (24, 'eslatma', 'tirik sinov holati',
       CASE WHEN v_imp_ok AND v_t_see LIKE '✅%' THEN 'bajarildi' ELSE 'to''liq emas' END,
       CASE WHEN v_imp_ok AND v_t_see LIKE '✅%'
            THEN 'sentinel-rollback: bitta qator ham QOLMADI. ⚠️ Aniqlik: id ketma-ketligi (sequence) har RUN da bir necha pog''ona siljiydi va projects/task_subtasks da o''lik tuple qoladi (VACUUM tozalaydi) — bular MA''LUMOT emas, xavf yo''q.'
            ELSE v_skip_why END),
  (25, 'sinov', '(g) 🔴 bajaruvchi "bajarildi" ni qo''ya oladi', v_t_tog,
       'boshqa BEFORE UPDATE trigger''i (updated_at) qorovul bilan to''qnashmayaptimi — AMALDA o''lchandi'),
  (26, 'tekshiruv', 'task_subtasks dagi boshqa BEFORE UPDATE triggerlari',
       coalesce((SELECT CASE WHEN ref IS NULL THEN 'yo''q' ELSE 'BOR' END
                   FROM pg_temp.v2_ref WHERE k='othertrg'), 'o''lchanmadi'),
       coalesce((SELECT ref FROM pg_temp.v2_ref WHERE k='othertrg'),
                'to''qnashuv ehtimoli yo''q') ||
       ' — updated_at MAVJUD bo''lsa oq ro''yxatga avtomat qo''shilgan');

RAISE NOTICE '════ TUGADI — pastdagi jadvalga qarang ════';
END
$main$;

COMMIT;

-- ══════════ NATIJA ══════════
SELECT bosqich, nom, qiymat, izoh FROM pg_temp.v2_res ORDER BY ord;

-- Kim nima ko'rdi (oldin → keyin)
SELECT a.turi,
       a.uid,
       a.s_n                         AS ochilishi_kerak,
       o.n_tsk || ' → ' || k.n_tsk   AS vazifalar,
       o.n_s   || ' → ' || k.n_s     AS checklist_vazifalari,
       o.n_sub || ' → ' || k.n_sub   AS checklist_qatorlari
  FROM pg_temp.v2_u a
  JOIN pg_temp.v2_snap o ON o.uid = a.uid AND o.faza='oldin'
  JOIN pg_temp.v2_snap k ON k.uid = a.uid AND k.faza='keyin'
 ORDER BY a.turi, a.uid;


-- ============================================================================
-- QANDAY O'QISH
-- ============================================================================
--  • "(a) ✅" + "(b) ✅ false" + "(f) ✅ false" — ish bitdi.
--  • 🔴 "(f)" — ENG MUHIM QATOR. U "✅ false" bo'lmasa modul QO'YILMASIN:
--    oddiy a'zo o'ziga checklist qatori yozib istalgan vazifani o'qiy oladi.
--  • "yangi ko'ringan qator: 0 vazifa" — RUN kunida BU TO'G'RI (yangi ustunlar
--    hali bo'sh, mijoz ularni keyingi bosqichda ulaydi). Xato emas.
--  • "(e) ❗ 0 qator" — vazifa ko'rinadi, lekin checklist punktining O'ZI
--    ko'rinmaydi: yuqoridagi WARNING da tayyor tuzatish SQL'i bor.
--  • "sinov · o'tkazib yuborildi" — bazada mos ma'lumot topilmadi yoki
--    impersonatsiya harnessi ishlamadi. XATO emas, lekin QO'LDA sinang.
--  • "(d) - (sinov a'zosi shu vazifaning EGASI…)" — hukmsiz: trigger unga
--    QONUNIY ruxsat berdi. Xato emas; egasi BO'LMAGAN odam bilan qo'lda sinang.
--  • "(f) ❗ sinov O'TKAZILMADI" — qorovul ISHLADI degani EMAS, u sinalmadi.
--    Prodga chiqishdan oldin qo'lda sinash SHART.
--  • "nazorat" toifasidagi foydalanuvchida vazifalar soni o'zgargan bo'lsa
--    skript RAISE EXCEPTION bilan to'xtagan va HECH NARSA o'zgarmagan bo'lardi.
--
-- ── 🔴 RUN'DAN KEYIN — MIJOZ TOMONIDA (boshqa agent) ────────────────────────
--   1) Takrorlanish multiselect: `recur_weekdays` / `recur_monthdays` massiv
--      bilan. 🔴 Massiv NULL bo'lsa ESKI `recur_weekday`/`recur_monthday`
--      mantiqi O'ZGARISHSIZ ishlaydi — yangi kod eskisini BOSMASLIGI shart.
--      ⚠️ Bo'sh massiv YUBORILMAYDI (DB CHECK 23514) — "tanlanmagan" = NULL.
--   2) `responsible_id` — mavjud `ss*` qidiruvli tanlagich (CLAUDE.md 7-qoida).
--   3) `respect_dayoff` — toggle; mantiq mijozda (`dof*`).
--   4) Checklist: `assigned_to` + fayl. 🔴 `assigned_by` NI MIJOZ YUBORMAYDI
--      (trigger yozadi) — yuborilsa ham e'tiborga olinmaydi. `done_at`/`done_by`
--      ham trigger tomonidan; mijoz faqat `is_completed` ni o'zgartiradi.
--   5) 🔴 Checklist punktini FAQAT vazifa egasi (bajaruvchi/yaratuvchi/qabul
--      qiluvchi) yoki ws-admini biriktira oladi. Boshqa odam urinsa 42501 va
--      o'zbekcha xato matni keladi — uni `translateErr()` orqali ko'rsating,
--      xom Postgres matni chiqmasin (CLAUDE.md 6-qoida).
--   6) Har so'rovda `{ error }` DOIM tekshiriladi va `.select()` bilan qator
--      soni ham (RLS jimgina to'smasin).
--   7) Ustun yo'q bazada (bu fayl RUN qilinmagan) ilova AVVALGIDEK ishlashi
--      shart: 42703 / PGRST204 → sababni OCHIQ aytadi.
--
-- ============================================================================
-- QAYTARISH (ROLLBACK) — kerak bo'lsa, TARTIB MUHIM
-- ============================================================================
--   -- 1) policy'lar (funksiyaga bog'liq — avval ular)
--   DROP POLICY IF EXISTS tasks_select_checklist_assignee ON public.tasks;
--   DROP POLICY IF EXISTS task_subtasks_select_assignee   ON public.task_subtasks;
--   DROP POLICY IF EXISTS task_subtasks_update_assignee   ON public.task_subtasks;
--   -- 2) trigger + funksiyalar
--   DROP TRIGGER  IF EXISTS task_subtasks_guard_trg ON public.task_subtasks;
--   DROP FUNCTION IF EXISTS public.task_subtasks_guard();
--   -- (imzodagi tip = tasks.id tipi, odatda bigint)
--   -- DROP FUNCTION IF EXISTS public.can_see_task_via_checklist(bigint, uuid);
--   -- 3) indeks (zararsiz, qolsa ham bo'ladi)
--   DROP INDEX IF EXISTS public.idx_task_subtasks_assigned;
--   -- 4) ⚠️ USTUNLAR — faqat MA'LUMOT KERAK EMASLIGIGA ishonch bo'lsa:
--   -- ALTER TABLE public.projects DROP CONSTRAINT IF EXISTS projects_recur_weekdays_chk;
--   -- ALTER TABLE public.projects DROP CONSTRAINT IF EXISTS projects_recur_monthdays_chk;
--   -- ALTER TABLE public.projects DROP CONSTRAINT IF EXISTS projects_responsible_fk;
--   -- ALTER TABLE public.projects DROP COLUMN IF EXISTS recur_weekdays;
--   -- ALTER TABLE public.projects DROP COLUMN IF EXISTS recur_monthdays;
--   -- ALTER TABLE public.projects DROP COLUMN IF EXISTS responsible_id;
--   -- ALTER TABLE public.projects DROP COLUMN IF EXISTS respect_dayoff;
--   -- ALTER TABLE public.task_subtasks DROP CONSTRAINT IF EXISTS task_subtasks_assigned_fk;
--   -- ALTER TABLE public.task_subtasks DROP CONSTRAINT IF EXISTS task_subtasks_assigned_by_fk;
--   -- ALTER TABLE public.task_subtasks DROP COLUMN IF EXISTS assigned_to;
--   -- ALTER TABLE public.task_subtasks DROP COLUMN IF EXISTS assigned_by;
--   -- ALTER TABLE public.task_subtasks DROP COLUMN IF EXISTS file_url;
--   -- ALTER TABLE public.task_subtasks DROP COLUMN IF EXISTS file_name;
--   -- ALTER TABLE public.task_subtasks DROP COLUMN IF EXISTS file_size;
--   -- ALTER TABLE public.task_subtasks DROP COLUMN IF EXISTS done_at;
--   -- ALTER TABLE public.task_subtasks DROP COLUMN IF EXISTS done_by;
--   -- 5) yordamchi funksiya (CHECK'lar o'chgandan KEYIN)
--   -- DROP FUNCTION IF EXISTS public.tf_smallint_set_ok(smallint[], int, int);
--
-- Rollbackdan keyin holat skriptdan OLDINGIDEK bo'ladi.
-- ============================================================================


-- ============================================================================
-- RUN'DAN KEYINGI TAVSIYA — hech narsani o'zgartirmaydi, faqat xabar beradi.
-- (Tranzaksiyadan TASHQARIDA: COMMIT allaqachon bo'lgan.)
-- ============================================================================
DO $post$
BEGIN
  RAISE NOTICE '════════ RUN''DAN KEYIN NIMA QILINADI ════════';

  RAISE NOTICE '1) TEZLIKNI O''LCHANG (N4). Yangi PERMISSIVE SELECT policy OR shoxi bilan qo''shildi: PostgreSQL avvalgi shoxlar false bergan qatorlarda can_see_task_via_checklist() ni CHAQIRISHI mumkin. Katta ro''yxatlarda bu sezilarli bo''lishi mumkin. O''lchash: EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM public.tasks WHERE workspace_id = ''<ws-uuid>'' ORDER BY created_at DESC LIMIT 500;  — ilovadagi asosiy ro''yxat so''rovi bilan bir xil shaklda, authenticated roli ostida.';

  RAISE NOTICE '2) REGRESSIYA BO''LSA — butun migratsiyani qaytarish SHART EMAS. Faqat policy''ni olib tashlash yetadi (ustunlar, trigger va funksiya joyida qoladi, ilova ishlayveradi, checklist orqali ko''rish yopiladi):  DROP POLICY IF EXISTS tasks_select_checklist_assignee ON public.tasks;';

  RAISE NOTICE '3) 🔴 QO''LDA SINANG — BIRIKTIRILMAGAN PUNKTGA ODAM QO''SHISH. Agar skript task_subtasks_update_assignee policy''sini QO''SHGAN bo''lsa (yakuniy jadvalning 13-qatoriga qarang), uning WITH CHECK (assigned_to = auth.uid()) sharti sababli "assigned_to IS NULL bo''lgan punktga odam biriktirish" oqimi TO''SILISHI mumkin: eski qator NULL bo''lgani uchun USING ham, yangi qator boshqa odam bo''lgani uchun WITH CHECK ham o''tmaydi. Vazifa EGASI uchun bu oqim MAVJUD (begona) UPDATE policy''si orqali ishlaydi — u yo''q bo''lsa qo''shimcha policy kerak bo''ladi. Ishga tushirgach ilovadan bir marta sinab ko''ring.';

  RAISE NOTICE '3b) 🔴 ENG TEZ TEKSHIRUV (1 daqiqa): BAJARUVCHI hisobidan bitta checklist punktini BELGILAB, keyin YECHIB ko''ring. Xato chiqmasligi kerak. 42501 ("...maydonini faqat vazifa egasi...") chiqsa — task_subtasks da boshqa BEFORE UPDATE trigger''i himoyalangan ustunni yozyapti: o''sha ustunni 6-bo''limdagi v_white oq ro''yxatiga qo''shib skriptni qayta RUN qiling. Skript buni RUN paytida (g) sinovida ham o''lchagan — yakuniy jadvalning 25-qatoriga qarang.';

  RAISE NOTICE '4) Mijoz tomoni hali bu ustunlarni ULAMAGAN — RUN kunida yangi policy 0 qator ochishi KUTILGAN natija (yakuniy jadval, 22-qator).';

  RAISE NOTICE '════════ TAVSIYA TUGADI ════════';
END $post$;
