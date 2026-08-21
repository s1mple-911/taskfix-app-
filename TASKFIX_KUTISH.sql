-- ============================================================================
-- TASKFIX_KUTISH.sql — "KUTISH" (dependency): loyiha bosqichi TANLANGAN
--                      bosqichlar tugagach ochiladi
-- ============================================================================
-- Asilbek RUN qiladi (Supabase SQL Editor, postgres roli).
-- ADDITIVE + IDEMPOTENT: mavjud jadval / ustun / policy / ma'lumot
-- O'CHIRILMAYDI va O'ZGARTIRILMAYDI. Faqat YANGI obyektlar qo'shiladi.
-- Qayta RUN xavfsiz. Bitta tranzaksiya — bir joyda yiqilsa HAMMASI qaytadi.
--
-- ── NIMA QO'SHILADI ─────────────────────────────────────────────────────────
--   1) public.task_dependencies (YANGI jadval)
--        task_id       -> public.tasks(id)  ON DELETE CASCADE
--        depends_on_id -> public.tasks(id)  ON DELETE CASCADE
--        workspace_id  uuid NOT NULL        (trigger O'ZI to'ldiradi/to'g'rilaydi)
--        created_by    uuid                 (trigger O'ZI yozadi, JWT bo'lsa)
--        created_at    timestamptz NOT NULL DEFAULT now()
--        PRIMARY KEY (task_id, depends_on_id)
--        CHECK (task_id <> depends_on_id)
--        + indeks (depends_on_id) va (workspace_id)
--      🔴 task_id / depends_on_id TIPI QATTIQ YOZILMAGAN — `tasks.id` dan
--         KATALOGDAN (format_type) olinadi (uuid ham, bigint ham bo'lishi
--         mumkin; repoda 1–37 migratsiyalar yo'q, taxmin qilinmaydi).
--
--   2) public.task_dep_would_cycle(p_task, p_dep) — SIKL tekshiruvi
--      recursive CTE (org_check_ancestor naqshi) + CHUQURLIK/HAJM qorovuli.
--
--   3) public.task_dependencies_guard() + task_dependencies_guard_trg
--      BEFORE INSERT OR UPDATE ON task_dependencies:
--        • ikkala bosqich BIR loyihada bo'lsin (project_id teng va NOT NULL)
--        • workspace_id vazifadan olinadi (mijoz yuborganiga ISHONILMAYDI)
--        • created_by ni SERVER yozadi (JWT bor bo'lsa)
--        • o'ziga o'zi bog'lanish rad etiladi
--        • SIKL rad etiladi
--
--   4) public.task_wait_guard() + zz_task_wait_guard_trg
--      🔴 HAQIQIY TO'SIQ. BEFORE UPDATE OF status ON public.tasks:
--      vazifa `status` 'new' dan BOSHQASIGA o'tayotganda kutilayotgan
--      bosqichlar (status NOT IN ('completed','cancelled')) qolgan bo'lsa
--      → RAISE EXCEPTION (o'zbekcha matn, translateErr() uchun).
--      🔴 'cancelled' ga o'tish ISTISNO — bekor qilish HAR DOIM mumkin.
--      🔴 DEP QATORI BO'LMAGAN HAR QANDAY VAZIFA UCHUN TA'SIR NOL
--         (birinchi shart — `EXISTS (task_dependencies WHERE task_id = NEW.id)`,
--         u false bo'lsa funksiya darrov RETURN NEW qiladi). Skript buni
--         TIRIK sinov bilan isbotlaydi ((f) sinovi).
--
--   5) public.can_edit_task_deps(p_task, p_user) — SECURITY DEFINER,
--      RLS INSERT/DELETE policy'lari uchun YAGONA ruxsat nuqtasi.
--
--   6) task_dependencies uchun RLS: SELECT (ws a'zosi) · INSERT/DELETE
--      🔴 ws-menejeri YOKI vazifaning YARATUVCHISI (created_by).
--      `assigned_to` / `acceptor_id` ATAYLAB YO'Q (QA 2026-08-21):
--      bloklangan bosqichning BAJARUVCHISI o'zini bloklab turgan qatorni
--      o'chirib qoidani chetlab o'ta olmasin.
--      `anon` ga HECH NARSA berilmaydi. UPDATE granti ATAYLAB YO'Q —
--      bog'lanish o'zgarmas: o'chiriladi va qaytadan qo'shiladi.
--
-- ── NIMAGA TEGMAYDI ─────────────────────────────────────────────────────────
--   • `tasks` jadvalining USTUNLARIGA — bitta ustun ham qo'shilmaydi/
--     o'zgartirilmaydi. `is_locked`, `depends_on_prev`, `flow_order`,
--     `status` ustunlariga BIR BELGI ham yozilmaydi.
--     🔴 `is_locked` — 34-migratsiya trigger'ining sof KETMA-KETLIK belgisi.
--        Kutish unga YOZILMAYDI (SPEC 3-bo'lim): aks holda "qulf qotib
--        qolgan" ziddiyati paydo bo'lardi va o'sha trigger uni istalgan
--        paytda qaytarib yuborardi.
--   • `tasks` ning MAVJUD policy'lariga va MAVJUD trigger'lariga.
--     Bizning trigger FAQAT `RAISE EXCEPTION` qiladi — hech qanday ustunni
--     O'ZGARTIRMAYDI, ya'ni boshqa BEFORE trigger'larning ishini buza olmaydi.
--     Nomi ATAYLAB `zz_` bilan boshlanadi (`zz_tf_auth_email_to_profile`
--     naqshi): PostgreSQL bir xil turdagi trigger'larni NOM bo'yicha alifbo
--     tartibida ishga tushiradi → bizniki ENG OXIRIDA ishlaydi va NEW ning
--     YAKUNIY qiymatini ko'radi.
--   • Hech qanday UPDATE/DELETE qilinmaydi. Skriptdagi "tirik" sinovlar
--     SENTINEL-ROLLBACK bilan bajariladi — bazada BITTA qator ham qolmaydi.
--
-- ── BUSIZ ILOVA QANDAY ISHLAYDI ─────────────────────────────────────────────
--   RUN qilinmasa ilova AVVALGIDEK ishlaydi. "Kutish" turi mijozda faqat
--   KO'RSATISH darajasida qoladi (`prjTaskOpen`/`prjShouldBeOpen` — SPEC
--   3-bo'lim), ya'ni:
--     • karta "kutmoqda" deb ko'rinadi va tugmalar berilmaydi,
--     • lekin SERVER TOMONDA TO'SIQ BO'LMAYDI — to'g'ridan API/Telegram bot
--       orqali yuborilgan status o'zgarishi o'tib ketaveradi,
--     • `task_dependencies` jadvali yo'qligi uchun mijoz "kutish" ro'yxatini
--       umuman o'qiy olmaydi (42P01) va turni `sequential`/`parallel` deb
--       ko'rsatadi — mavjud xatti-harakat, hech narsa buzilmaydi.
--   Ya'ni bu fayl "ko'rinish"ni "qoida"ga aylantiradi.
--
-- ── BOG'LIQLIK (RUN TARTIBI) ────────────────────────────────────────────────
--   1) 39_employee_details.sql (yoki 35_fix_projects_rls.sql) →
--      is_ws_member(uuid,uuid) va is_ws_manager(uuid,uuid) MAVJUD bo'lishi
--      SHART (CLAUDE.md 8-qoida: policy ichida workspace_members inline
--      subquery YOZILMAYDI — 42P17).
--   2) TASKFIX_KUTISH.sql  ← SHU FAYL
--   🔴 BOSHQA `TASKFIX_*.sql` FAYLLARGA BOG'LIQ EMAS va ular bilan
--      to'qnashmaydi (yangi jadval nomi, yangi funksiya nomlari, yangi
--      trigger nomlari). TASKFIX_LOYIHA.sql / _RLS.sql / _V2.sql / PLANNER
--      istalgan tartibda bo'lishi mumkin.
--
-- ── ⚠️ QACHON RUN QILINADI — ILOVA QISQA VAQT TO'XTAYDI ─────────────────────
--   🔴 ROSTINI AYTAMIZ: `CREATE TRIGGER ... ON public.tasks` `tasks` jadvaliga
--      ACCESS EXCLUSIVE qulf oladi va u qulf COMMIT gacha ushlanadi. Shu vaqt
--      ichida vazifalar O'QILMAYDI ham, YOZILMAYDI ham.
--      Qulfdan KEYIN skript yana tirik sinov o'tkazadi (bir necha o'nlab
--      qator INSERT/UPDATE + bir necha impersonatsiya so'rovi) — odatda bir
--      necha soniya, lekin band bazada uzoqroq bo'lishi mumkin.
--   ➜ Kam trafik vaqtida (kechqurun / dam olish kuni) ishga tushiring.
--   ➜ Qulfni imkon qadar KECH olish uchun tartib ataylab shunday: jadval,
--      funksiyalar, RLS va grant'lar `tasks` ga TEGMAYDI; `tasks` ga yagona
--      murojaat — 5-bo'limdagi CREATE TRIGGER.
--   ⚠️ Trigger `BEFORE UPDATE OF status` — ya'ni SET ro'yxatida `status`
--      bo'lmagan UPDATE'larda (deadline, plan_*, assigned_to…) UMUMAN
--      ishga tushmaydi. Qo'shimcha yuk deyarli nol.
--
-- ── ⚠️ QOLGAN XAVF / OCHIQ QARORLAR (yashirilmaydi) ─────────────────────────
--   1) 🔴 SERVER ROLI UCHUN ISTISNO QO'YILMADI (qaror, sabab bilan):
--      `service_role`, `postgres`, `rolsuper`/`rolbypassrls` uchun ham
--      to'siq AMAL QILADI. Sabab: bu RUXSAT masalasi emas, BIZNES QOIDASI —
--      "kutilayotgan bosqich tugamaguncha keyingisi boshlanmaydi". Agar EF /
--      Telegram bot (`tg-webhook`, `tg-send`) `tasks` ni to'g'ridan yangilab
--      qoidani chetlab o'tsa, foydalanuvchi uchun tizim ZID ishlagan bo'lardi
--      (ilovada bloklangan, botda o'tadi). Shuning uchun xato matni EF
--      loglarida ham tushunarli bo'lsin deb o'zbekcha + HINT ichida
--      `task_id` bilan yoziladi.
--      ➜ AGAR kelajakda "server hamma narsani qila oladi" kerak bo'lsa,
--        `task_wait_guard()` boshiga BITTA qator yetadi (tayyor, izohda).
--        Uni QO'SHMASLIK — ataylab qilingan tanlov.
--   2) 🔴 "'new' DAN CHIQISH" TO'SIQ NUQTASI (SPEC 4-bo'lim, harfma-harf):
--      to'siq FAQAT `OLD.status = 'new'` → `NEW.status <> 'new'` o'tishida
--      ishlaydi. Natijasi:
--        • Vazifa allaqachon 'in_progress' bo'lsa, keyin 'completed' ga
--          o'tishi TO'SILMAYDI (bir marta ochilgan bosqich yopilmaydi).
--        • 🔴 'cancelled' HECH QACHON TO'SILMAYDI (Asilbek qarori):
--          BEKOR QILISH — vazifani BAJARISH emas, u administrativ chiqish
--          yo'li. To'silsa odam TUZOQQA tushardi: bloklangan bosqichni bekor
--          qilish uchun avval bog'lanishni o'chirish kerak bo'lardi, kutilayotgani
--          o'zi ham bloklangan bo'lsa esa butun zanjir qotib qolardi.
--          Bu MIJOZ mantiqi bilan ham mos: `depUnmet` da 'cancelled'
--          "bajarilgan" hisoblanadi, ya'ni bosqich bekor qilinsa unga
--          bog'langanlar OCHILADI — aynan kutilgan xatti-harakat.
--          Sinov: (h) — bloklangan bosqich bekor bo'ladi va shundan keyin
--          unga bog'langan bosqich ochiladi.
--   3) 🟡 VAZIFA KEYINCHALIK BOSHQA LOYIHAGA KO'CHIRILSA (hujjatlashtirildi,
--      TUZATILMAGAN): "bir loyiha" sharti FAQAT bog'lanish YOZILAYOTGANDA
--      tekshiriladi. Bosqich keyin boshqa loyihaga ko'chirilsa (yoki
--      project_id NULL qilinsa) eskirgan qator QOLADI — `tasks` ga
--      qo'shimcha trigger ATAYLAB osilmagan (u yerdagi yagona trigger
--      status qorovuli va u imkon qadar tor).
--      🔴 QOIDA BUZILMAYDI: to'siq baribir ishlaydi (kutish qatori bor →
--      kutilayotgani tugamaguncha status o'zgarmaydi), faqat kutish
--      "loyihalararo" bo'lib qoladi. Mijozda "bosqichni ko'chirish" oqimi
--      bo'lsa u eski qatorlarni O'ZI tozalasin.
--   4) 🟡 IKKI PARALLEL TRANZAKSIYA (nazariy): A→B va B→A bir vaqtda,
--      har biri ikkinchisini KO'RMASDAN yozilsa halqa hosil bo'lishi
--      mumkin (recursive CTE faqat COMMIT bo'lgan qatorlarni ko'radi).
--      `org_check_ancestor` (TASKFIX_HR.sql) da AYNAN shu holat bor —
--      amaliy xavf juda past (bitta loyihaning bosqichlarini AYNI PAYTDA
--      ikki admin bog'lashi kerak). To'liq yechim ADVISORY LOCK yoki
--      SERIALIZABLE bo'lardi — ataylab QILINMADI (har INSERT ga qulf).
--      Halqa hosil bo'lsa ham zarar yo'q: bosqichlar shunchaki ochilmay
--      qoladi va bog'lanishni o'chirish bilan tuzatiladi.
--   5) RLS **QATOR** darajasida: ws a'zosi bog'lanish qatorlarini (qaysi
--      bosqich qaysi bosqichni kutayotganini) KO'RADI. Bu ataylab — kutish
--      grafigi jamoa uchun ochiq ma'lumot.
--   6) Bog'lanish qatorlari VAZIFA TARIXIGA (task_history) tushmaydi —
--      `TH_FIELDS` faqat deadline/assigned_to/status ni kuzatadi. Kim
--      qachon bog'lagani `created_by`/`created_at` da qoladi.
--
-- TEXT + CHECK (ENUM EMAS) — 30/32-migratsiyalar saboqi.
-- Fayl oxirida QAYTARISH (rollback) bo'limi bor.
-- ============================================================================

-- ⚠️ TRANZAKSIYA — TARTIB MUHIM, O'ZGARTIRMANG:
--    `BEGIN;` va `SET TRANSACTION ...` skriptdagi ENG BIRINCHI ikki buyruq
--    bo'lishi shart (aks holda 25001).
BEGIN;
-- 🔴 REPEATABLE READ — tirik sinov "oldin/keyin" holatni solishtiradi;
--    boshqa sessiyaning yozuvi oraga tushib SOXTA xato bermasin.
-- ⚠️ AGAR "25001: SET TRANSACTION ISOLATION LEVEL must be called before any
--    query" chiqsa — quyidagi qatorni izohga oling va qayta RUN qiling.
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- 🔴 search_path BUTUN skript uchun SHU YERDA belgilanadi: policy va
--    funksiyalardagi prefikssiz nomlar bir xil qoidada baholansin.
--    Temp jadvallarga doim `pg_temp.` prefiksi bilan murojaat qilinadi.
SET LOCAL search_path = public, extensions;


-- ════════════════════════════════════════════════════════════════════════════
-- 0) DIAGNOSTIKA — FAQAT O'QIYDI. Natijani "Messages"/"Notices" da o'qing.
--    🔴 `tasks` da MAVJUD trigger'larni KO'RMASDAN yangi trigger qo'shilmaydi.
-- ════════════════════════════════════════════════════════════════════════════
DO $diag$
DECLARE
  r     RECORD;
  v_n   int;
  v_max text;
BEGIN
  RAISE NOTICE '════════ DIAGNOSTIKA (o''zgarishdan OLDINGI holat) ════════';

  IF to_regclass('public.tasks') IS NULL THEN
    RAISE WARNING 'public.tasks jadvali YO''Q — keyingi bo''lim to''xtatadi.';
  ELSE
    SELECT count(*) INTO v_n
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname='public' AND c.relname='tasks' AND c.relrowsecurity;
    RAISE NOTICE '── public.tasks : RLS %',
      CASE WHEN v_n > 0 THEN 'YOQILGAN' ELSE '❗ O''CHIQ' END;

    -- 🔴 MAVJUD BEFORE UPDATE trigger'lari (34-migratsiya, is_locked, updated_at…)
    v_n := 0;
    FOR r IN
      SELECT t.tgname,
             p.proname,
             CASE WHEN (t.tgtype::int & 2) = 2 THEN 'BEFORE' ELSE 'AFTER' END AS qachon,
             CASE WHEN (t.tgtype::int & 1) = 1 THEN 'ROW' ELSE 'STATEMENT' END AS daraja,
             (t.tgtype::int & 4)  = 4  AS ins,
             (t.tgtype::int & 8)  = 8  AS del,
             (t.tgtype::int & 16) = 16 AS upd,
             t.tgenabled
        FROM pg_trigger t
        JOIN pg_proc p ON p.oid = t.tgfoid
       WHERE t.tgrelid = 'public.tasks'::regclass
         AND NOT t.tgisinternal
       ORDER BY t.tgname
    LOOP
      v_n := v_n + 1;
      RAISE NOTICE '   [tasks trigger] % → %() · % % · INS:% UPD:% DEL:% · holat:%',
        r.tgname, r.proname, r.qachon, r.daraja, r.ins, r.upd, r.del, r.tgenabled;
    END LOOP;
    RAISE NOTICE '   JAMI tasks trigger''i: % ta', v_n;

    -- Alifbo tartibi: bizning `zz_task_wait_guard_trg` OXIRIDA ishlashi kerak
    SELECT max(t.tgname) INTO v_max
      FROM pg_trigger t
     WHERE t.tgrelid='public.tasks'::regclass AND NOT t.tgisinternal
       AND (t.tgtype::int & 2) = 2 AND (t.tgtype::int & 1) = 1
       AND (t.tgtype::int & 16) = 16
       AND t.tgname <> 'zz_task_wait_guard_trg';
    IF v_max IS NOT NULL THEN
      RAISE NOTICE '   Eng "katta" nomli BEFORE UPDATE ROW trigger: % (bizniki `zz_task_wait_guard_trg` — % ishlaydi)',
        v_max,
        CASE WHEN v_max < 'zz_task_wait_guard_trg' THEN 'undan KEYIN' ELSE '❗ undan OLDIN' END;
    ELSE
      RAISE NOTICE '   tasks da boshqa BEFORE UPDATE ROW trigger yo''q.';
    END IF;
  END IF;

  IF to_regclass('public.task_dependencies') IS NOT NULL THEN
    RAISE NOTICE 'ℹ️ public.task_dependencies ALLAQACHON bor — skript idempotent: yetishmagan qismlarigina qo''shiladi.';
    FOR r IN
      SELECT policyname, cmd, permissive, array_to_string(roles, ',') AS roles
        FROM pg_policies
       WHERE schemaname='public' AND tablename='task_dependencies'
       ORDER BY cmd, policyname
    LOOP
      RAISE NOTICE '   [task_dependencies policy] % (% · % · %)', r.policyname, r.cmd, r.permissive, r.roles;
    END LOOP;
  ELSE
    RAISE NOTICE 'ℹ️ public.task_dependencies YO''Q — yaratiladi.';
  END IF;

  RAISE NOTICE '════════ DIAGNOSTIKA TUGADI ════════';
END $diag$;


-- ════════════════════════════════════════════════════════════════════════════
-- 1) OLD SHARTLAR — noto'g'ri/yarim bazada ishga tushmasin
--    ⚠️ Trigger va funksiyalar tegadigan HAR USTUN shu yerda TASDIQLANADI:
--       ustun yo'q bo'lsa xato faqat RUN paytida, xom 42703 bilan chiqardi.
-- ════════════════════════════════════════════════════════════════════════════
DO $pre$
DECLARE
  v_c   text;
  v_def text;
  v_idn text;
BEGIN
  IF to_regclass('public.tasks') IS NULL THEN
    RAISE EXCEPTION 'public.tasks topilmadi — bu TaskFix bazasi emasmi? To''xtatildi.';
  END IF;
  IF to_regclass('public.projects') IS NULL THEN
    RAISE EXCEPTION 'public.projects topilmadi — KUTISH faqat loyiha bosqichlari uchun. To''xtatildi.';
  END IF;
  IF to_regclass('public.workspace_members') IS NULL THEN
    RAISE EXCEPTION 'public.workspace_members topilmadi — RLS va tirik sinov unga tayanadi. To''xtatildi.';
  END IF;

  -- Modul MAJBURIY tayanadigan ustunlar
  FOREACH v_c IN ARRAY ARRAY['id','workspace_id','project_id','status','created_by','assigned_to'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='tasks' AND column_name=v_c) THEN
      RAISE EXCEPTION 'public.tasks.% ustuni yo''q — KUTISH qorovullari aynan shu ustunlarga tayanadi. To''xtatildi.', v_c;
    END IF;
  END LOOP;

  -- flow_order — modul O'QIMAYDI (u faqat UI tartibi), shuning uchun
  -- yo'qligi TO'XTATMAYDI. Lekin bosqich tushunchasi undan kelgani uchun
  -- yo'qligi ochiq aytiladi (jimgina o'tmaydi).
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name='flow_order') THEN
    RAISE WARNING '⚠️ public.tasks.flow_order ustuni yo''q. Modul unga TAYANMAYDI (server qoidasi faqat task_dependencies va status bilan ishlaydi), lekin mijozdagi "faqat tepadagi bosqichlar" ro''yxati (SPEC 5.1) flow_order ga tayanadi — u yerda sikl himoyasining BIRINCHI qatlami yo''qoladi. Server qatlami (recursive CTE) o''z joyida qoladi.';
  END IF;

  -- tasks.project_id NULL bo'la oladimi? (oddiy vazifa = project_id NULL)
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='tasks'
                AND column_name='project_id' AND is_nullable='NO') THEN
    RAISE NOTICE 'ℹ️ tasks.project_id NOT NULL — bu bazada har vazifa loyihaga tegishli. Skript buni hisobga oladi (sinovda "loyihasiz vazifa" holati o''tkazib yuboriladi).';
  END IF;

  -- Sinov qator yozadi — tasks.id o'zi to'lanadimi?
  SELECT column_default, is_identity INTO v_def, v_idn
    FROM information_schema.columns
   WHERE table_schema='public' AND table_name='tasks' AND column_name='id';
  IF v_def IS NULL AND coalesce(v_idn,'NO') <> 'YES' THEN
    RAISE WARNING '⚠️ public.tasks.id da DEFAULT ham, IDENTITY ham yo''q — qiymatni mijoz yuboradi. Skriptdagi TIRIK sinov qator yozadi, shuning uchun u O''TKAZIB YUBORILADI (sabab yakuniy hisobotda). Migratsiyaning qolgan qismi normal bajariladi.';
  END IF;

  -- 🔴 CLAUDE.md 8-qoida: policy ichida workspace_members inline subquery
  --    YOZILMAYDI (42P17) — shu sababli bu ikki funksiya SHART.
  -- 🔴 IMZO ham tekshiriladi, faqat NOM emas.
  IF to_regprocedure('public.is_ws_member(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'is_ws_member(uuid, uuid) topilmadi (nomi bor, imzosi boshqa bo''lishi mumkin). Avval 39_employee_details.sql (yoki 35_fix_projects_rls.sql) ni ishga tushiring.';
  END IF;
  IF to_regprocedure('public.is_ws_manager(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'is_ws_manager(uuid, uuid) topilmadi (nomi bor, imzosi boshqa bo''lishi mumkin). Avval 35_fix_projects_rls.sql / 39_employee_details.sql ni ishga tushiring.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    RAISE EXCEPTION '`authenticated` roli topilmadi — bu Supabase bazasi emasmi?';
  END IF;

  -- tasks.id PK bo'lgan YAGONA ustunmi? (FK aynan shunga qo'yiladi)
  IF NOT EXISTS (
    SELECT 1
      FROM pg_index i
      JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
     WHERE i.indrelid = 'public.tasks'::regclass
       AND i.indisprimary
       AND i.indnatts = 1
       AND a.attname = 'id'
  ) THEN
    RAISE EXCEPTION 'public.tasks ning PRIMARY KEY i bitta `id` ustuni EMAS — task_dependencies FK''lari aynan tasks(id) ga qo''yiladi. Sxema kutilganidan boshqa, to''xtatildi.';
  END IF;
END $pre$;


-- ════════════════════════════════════════════════════════════════════════════
-- 2) KATALOGDAN ANIQLASH — TAXMIN QILMAYMIZ
--    🔴 tasks.id TIPI (uuid / bigint / int8 …) — format_type bilan.
--    🔴 workspace_id / created_by FK NISHONLARI `tasks` dagi AYNI ustunlarning
--       FK'sidan olinadi (repoda 1–37 migratsiyalar yo'q).
--    🔴 `ownexpr` — "vazifa egasi" ifodasi BIR MARTA quriladi va funksiya ham,
--       tekshiruv ham AYNAN o'shani ishlatadi.
-- ════════════════════════════════════════════════════════════════════════════
DROP TABLE IF EXISTS pg_temp.kut_ref;
CREATE TEMP TABLE pg_temp.kut_ref (k text PRIMARY KEY, v text, izoh text);

DO $ref$
DECLARE
  v_idtype  text;
  v_projtyp text;
  v_acc     boolean;
  v_own     text;
  v_ws_ref  text;
  v_usr_ref text;
  v_t       text;
  v_c       text;
BEGIN
  -- ── 2.a) tasks.id tipi ────────────────────────────────────────────────────
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_idtype
    FROM pg_attribute a
   WHERE a.attrelid = 'public.tasks'::regclass
     AND a.attname = 'id' AND a.attnum > 0 AND NOT a.attisdropped;
  IF v_idtype IS NULL THEN
    RAISE EXCEPTION 'public.tasks.id tipi aniqlanmadi — to''xtatildi.';
  END IF;
  INSERT INTO pg_temp.kut_ref VALUES ('idtype', v_idtype, 'tasks.id tipi (katalogdan)');
  RAISE NOTICE 'tasks.id tipi: %', v_idtype;

  -- tasks.project_id tipi (tirik sinov uchun — literalni to'g'ri cast qilamiz)
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_projtyp
    FROM pg_attribute a
   WHERE a.attrelid = 'public.tasks'::regclass
     AND a.attname = 'project_id' AND a.attnum > 0 AND NOT a.attisdropped;
  INSERT INTO pg_temp.kut_ref VALUES ('projtype', v_projtyp, 'tasks.project_id tipi (katalogdan)');

  -- ── 2.b) workspace_id FK nishoni (tasks.workspace_id dan) ─────────────────
  -- ⚠️ ORDER BY conname — bir nechta mos FK bo'lsa tanlov DETERMINISTIK bo'lsin.
  SELECT c.confrelid::regclass::text, af.attname INTO v_t, v_c
    FROM pg_constraint c
    JOIN pg_attribute a  ON a.attrelid  = c.conrelid  AND a.attnum  = c.conkey[1]
    JOIN pg_attribute af ON af.attrelid = c.confrelid AND af.attnum = c.confkey[1]
   WHERE c.conrelid = 'public.tasks'::regclass
     AND c.contype = 'f' AND array_length(c.conkey,1) = 1
     AND a.attname = 'workspace_id'
   ORDER BY c.conname LIMIT 1;
  IF v_t IS NOT NULL THEN
    v_ws_ref := v_t || '(' || quote_ident(v_c) || ')';
    INSERT INTO pg_temp.kut_ref VALUES ('wsref', v_ws_ref, 'tasks.workspace_id FK dan olindi');
    RAISE NOTICE 'workspace_id FK nishoni: %', v_ws_ref;
  ELSE
    INSERT INTO pg_temp.kut_ref VALUES ('wsref', NULL, 'tasks.workspace_id da FK yo''q — workspace_id FK''SIZ qoladi');
    RAISE NOTICE 'ℹ️ tasks.workspace_id da FK yo''q — task_dependencies.workspace_id ham FK''siz bo''ladi.';
  END IF;

  -- ── 2.c) created_by FK nishoni (tasks.created_by dan) ─────────────────────
  v_t := NULL; v_c := NULL;
  SELECT c.confrelid::regclass::text, af.attname INTO v_t, v_c
    FROM pg_constraint c
    JOIN pg_attribute a  ON a.attrelid  = c.conrelid  AND a.attnum  = c.conkey[1]
    JOIN pg_attribute af ON af.attrelid = c.confrelid AND af.attnum = c.confkey[1]
   WHERE c.conrelid = 'public.tasks'::regclass
     AND c.contype = 'f' AND array_length(c.conkey,1) = 1
     AND a.attname = 'created_by'
   ORDER BY c.conname LIMIT 1;
  IF v_t IS NOT NULL THEN
    v_usr_ref := v_t || '(' || quote_ident(v_c) || ')';
    INSERT INTO pg_temp.kut_ref VALUES ('usrref', v_usr_ref, 'tasks.created_by FK dan olindi');
  ELSIF to_regclass('public.profiles') IS NOT NULL THEN
    INSERT INTO pg_temp.kut_ref VALUES ('usrref', 'public.profiles(id)', 'tasks.created_by da FK yo''q — public.profiles(id)');
  ELSIF to_regclass('auth.users') IS NOT NULL THEN
    INSERT INTO pg_temp.kut_ref VALUES ('usrref', 'auth.users(id)', 'profiles topilmadi — auth.users(id)');
  ELSE
    INSERT INTO pg_temp.kut_ref VALUES ('usrref', NULL, 'mos jadval topilmadi — created_by FK''SIZ');
  END IF;

  -- ── 2.d) acceptor_id bormi? + "vazifa egasi" ifodasi ──────────────────────
  -- ⚠️ acceptor_id endi RUXSAT ifodasiga KIRMAYDI (yuqoridagi QA qarori) —
  --    bayroq faqat hisobot uchun o'qiladi.
  v_acc := EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='tasks'
                      AND column_name='acceptor_id');
  -- 🔴 QA QARORI (2026-08-21): FAQAT ws-MENEJERI yoki vazifa YARATUVCHISI.
  --    `assigned_to` / `acceptor_id` ATAYLAB CHIQARILDI: aks holda
  --    BLOKLANGAN bosqichning BAJARUVCHISI o'zini bloklab turgan qatorni
  --    O'CHIRIB, so'ng statusni o'zgartira olardi — modulning butun ma'nosi
  --    yo'qolardi. Bog'liqlik — ish REJASINI tuzgan odamning qarori;
  --    loyiha bosqichlarini baribir owner/admin yaratadi. Sinov: (g-4).
  v_own := 'public.is_ws_manager(t.workspace_id, p_user)'
        || ' OR p_user = t.created_by';
  INSERT INTO pg_temp.kut_ref VALUES ('acceptor', v_acc::text, 'tasks.acceptor_id ustuni bormi');
  INSERT INTO pg_temp.kut_ref VALUES ('ownexpr', v_own, 'can_edit_task_deps: ws-menejeri YOKI vazifa YARATUVCHISI (assigned_to/acceptor_id EMAS)');
  IF NOT v_acc THEN
    RAISE NOTICE 'ℹ️ tasks.acceptor_id yo''q — ruxsat ifodasiga u QO''SHILMADI (42703 bo''lardi).';
  END IF;
END $ref$;


-- ════════════════════════════════════════════════════════════════════════════
-- 3) public.task_dependencies — YANGI JADVAL (SPEC 7-bo'lim)
--    🔴 task_id / depends_on_id tipi `tasks.id` DAN olinadi (qattiq yozilmagan).
--    ⚠️ IDEMPOTENT: jadval bor bo'lsa TIPLAR solishtiriladi (mos kelmasa
--       TO'XTAYMIZ — jimgina "boshqa" jadval bilan ishlash xavfli), yetishmagan
--       ustun/cheklov/indeks qo'shiladi.
-- ════════════════════════════════════════════════════════════════════════════
DO $tbl$
DECLARE
  v_idtype text;
  v_wsref  text;
  v_usrref text;
  v_have   text;
  v_nulls  bigint;
  v_new    boolean := false;
BEGIN
  SELECT v INTO v_idtype FROM pg_temp.kut_ref WHERE k='idtype';
  SELECT v INTO v_wsref  FROM pg_temp.kut_ref WHERE k='wsref';
  SELECT v INTO v_usrref FROM pg_temp.kut_ref WHERE k='usrref';
  IF v_idtype IS NULL THEN
    RAISE EXCEPTION 'idtype aniqlanmagan — 2-bo''lim bajarilmadimi?';
  END IF;

  IF to_regclass('public.task_dependencies') IS NULL THEN
    v_new := true;
    EXECUTE format($t$
      CREATE TABLE public.task_dependencies (
        task_id       %s NOT NULL,
        depends_on_id %s NOT NULL,
        workspace_id  uuid NOT NULL,
        created_by    uuid,
        created_at    timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT task_dependencies_pkey PRIMARY KEY (task_id, depends_on_id),
        CONSTRAINT task_dependencies_self_chk CHECK (task_id <> depends_on_id)
      )
    $t$, v_idtype, v_idtype);
    RAISE NOTICE 'public.task_dependencies YARATILDI (task_id/depends_on_id tipi: %)', v_idtype;
  ELSE
    RAISE NOTICE 'ℹ️ public.task_dependencies mavjud — yetishmagan qismlari to''ldiriladi.';

    -- Tip mosligi: mos kelmasa TO'XTAYMIZ (FK/trigger jimgina buzilmasin)
    SELECT format_type(a.atttypid, a.atttypmod) INTO v_have
      FROM pg_attribute a
     WHERE a.attrelid='public.task_dependencies'::regclass
       AND a.attname='task_id' AND NOT a.attisdropped;
    IF v_have IS NULL THEN
      RAISE EXCEPTION 'Mavjud public.task_dependencies da task_id ustuni yo''q — bu boshqa jadval. To''xtatildi.';
    END IF;
    IF v_have IS DISTINCT FROM v_idtype THEN
      RAISE EXCEPTION 'Mavjud task_dependencies.task_id tipi %, tasks.id tipi esa % — mos emas. Qo''lda ko''rib chiqing; skript hech narsani o''zgartirmadi.', v_have, v_idtype;
    END IF;

    v_have := NULL;
    SELECT format_type(a.atttypid, a.atttypmod) INTO v_have
      FROM pg_attribute a
     WHERE a.attrelid='public.task_dependencies'::regclass
       AND a.attname='depends_on_id' AND NOT a.attisdropped;
    IF v_have IS DISTINCT FROM v_idtype THEN
      RAISE EXCEPTION 'Mavjud task_dependencies.depends_on_id tipi % (kutilgan %) — mos emas. To''xtatildi.', coalesce(v_have, 'YO''Q'), v_idtype;
    END IF;

    -- Yetishmagan ustunlar (eski / yarim yaratilgan jadval holati)
    ALTER TABLE public.task_dependencies ADD COLUMN IF NOT EXISTS workspace_id uuid;
    ALTER TABLE public.task_dependencies ADD COLUMN IF NOT EXISTS created_by   uuid;
    ALTER TABLE public.task_dependencies ADD COLUMN IF NOT EXISTS created_at   timestamptz NOT NULL DEFAULT now();

    -- workspace_id NOT NULL — faqat bo'sh qator YO'Q bo'lsa (ma'lumot buzilmasin)
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='task_dependencies'
                  AND column_name='workspace_id' AND is_nullable='YES') THEN
      SELECT count(*) INTO v_nulls FROM public.task_dependencies WHERE workspace_id IS NULL;
      IF v_nulls = 0 THEN
        ALTER TABLE public.task_dependencies ALTER COLUMN workspace_id SET NOT NULL;
      ELSE
        RAISE WARNING '⚠️ task_dependencies da workspace_id BO''SH bo''lgan % qator bor — NOT NULL QO''YILMADI (mavjud ma''lumot bosilmasin). Ularni to''ldirgach: ALTER TABLE public.task_dependencies ALTER COLUMN workspace_id SET NOT NULL;', v_nulls;
      END IF;
    END IF;
  END IF;

  -- ── PK ────────────────────────────────────────────────────────────────────
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.task_dependencies'::regclass AND contype='p') THEN
    ALTER TABLE public.task_dependencies
      ADD CONSTRAINT task_dependencies_pkey PRIMARY KEY (task_id, depends_on_id);
    RAISE NOTICE 'PRIMARY KEY (task_id, depends_on_id) qo''shildi';
  END IF;

  -- ── CHECK (task_id <> depends_on_id) — SPEC 5.3, sikl himoyasining 3-qatlami
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.task_dependencies'::regclass
                    AND conname='task_dependencies_self_chk') THEN
    ALTER TABLE public.task_dependencies
      ADD CONSTRAINT task_dependencies_self_chk CHECK (task_id <> depends_on_id);
    RAISE NOTICE 'CHECK (task_id <> depends_on_id) qo''shildi';
  END IF;

  -- ── FK: task_id / depends_on_id → tasks(id) ON DELETE CASCADE ─────────────
  --    SPEC 6: bosqich o'chirilsa bog'lanish qatori ham o'chadi.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.task_dependencies'::regclass
                    AND conname='task_dependencies_task_fk') THEN
    ALTER TABLE public.task_dependencies
      ADD CONSTRAINT task_dependencies_task_fk
      FOREIGN KEY (task_id) REFERENCES public.tasks(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.task_dependencies'::regclass
                    AND conname='task_dependencies_dep_fk') THEN
    ALTER TABLE public.task_dependencies
      ADD CONSTRAINT task_dependencies_dep_fk
      FOREIGN KEY (depends_on_id) REFERENCES public.tasks(id) ON DELETE CASCADE;
  END IF;

  -- ── FK: workspace_id (nishon KATALOGDAN, tasks.workspace_id bilan bir xil)
  IF v_wsref IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_constraint
                      WHERE conrelid='public.task_dependencies'::regclass
                        AND conname='task_dependencies_ws_fk') THEN
    BEGIN
      EXECUTE format(
        'ALTER TABLE public.task_dependencies ADD CONSTRAINT task_dependencies_ws_fk FOREIGN KEY (workspace_id) REFERENCES %s ON DELETE CASCADE',
        v_wsref);
    EXCEPTION WHEN OTHERS THEN
      -- FK — QULAYLIK, majburiyat emas: workspace_id ni trigger to'ldiradi.
      RAISE WARNING '⚠️ workspace_id FK (%) qo''shilmadi: % — jadval FK''siz ishlayveradi (qiymatni trigger yozadi).', v_wsref, SQLERRM;
    END;
  END IF;

  -- ── FK: created_by (nishon KATALOGDAN) ────────────────────────────────────
  IF v_usrref IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_constraint
                      WHERE conrelid='public.task_dependencies'::regclass
                        AND conname='task_dependencies_created_by_fk') THEN
    BEGIN
      EXECUTE format(
        'ALTER TABLE public.task_dependencies ADD CONSTRAINT task_dependencies_created_by_fk FOREIGN KEY (created_by) REFERENCES %s ON DELETE SET NULL',
        v_usrref);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '⚠️ created_by FK (%) qo''shilmadi: % — ustun FK''siz qoladi (audit maydoni, mantiqqa ta''sir qilmaydi).', v_usrref, SQLERRM;
    END;
  END IF;

  IF v_new THEN
    RAISE NOTICE 'Jadval tayyor — endi qorovullar (trigger) o''rnatiladi.';
  END IF;
END $tbl$;

-- Indekslar. SPEC 7: depends_on_id bo'yicha indeks SHART — PK faqat task_id ni
-- qoplaydi, "meni kim kutyapti?" so'rovi esa teskari yo'nalishda ketadi.
CREATE INDEX IF NOT EXISTS idx_task_dependencies_dep ON public.task_dependencies (depends_on_id);
CREATE INDEX IF NOT EXISTS idx_task_dependencies_ws  ON public.task_dependencies (workspace_id);

COMMENT ON TABLE public.task_dependencies IS
  'KUTISH (dependency): task_id bosqichi depends_on_id bosqichi TUGAGUNCHA (status completed|cancelled) ochilmaydi. Faqat BITTA loyiha ichida — task_dependencies_guard_trg tekshiradi. Rejim SAQLANMAYDI: mijoz qator borligiga qarab "wait" deb hisoblaydi (SPEC 2-bo''lim). Qator O''ZGARMAS — UPDATE granti yo''q, o''chiriladi va qaytadan qo''shiladi.';
COMMENT ON COLUMN public.task_dependencies.workspace_id IS
  'Vazifaning workspace_id si. Qiymatni TRIGGER yozadi — mijoz yuborganiga ishonilmaydi.';
COMMENT ON COLUMN public.task_dependencies.created_by IS
  'Kim bog''lagan. Qiymatni TRIGGER yozadi (auth.uid()); JWT''siz (service_role/EF) chaqiruvda mijoz yuborgani qoladi.';


-- ════════════════════════════════════════════════════════════════════════════
-- 4) 🔴 SIKL QOROVULI (SPEC 5-bo'lim) — recursive CTE
--    `org_check_ancestor` naqshi, lekin CTE bilan: graf
--    "task_id ---kutadi---> depends_on_id" yo'nalishida yuradi.
--    YANGI (T -> D) qirrasi sikl hosil qiladimi?  ⇔  D dan T ga YO'L bormi?
--    Shuning uchun D dan boshlab depends_on zanjiri bo'ylab yuriladi.
--    ⚠️ IKKI QOROVUL: (1) `path` massivi — bazada ALLAQACHON sikl bo'lsa ham
--       (masalan trigger vaqtincha o'chirilgan paytda yozilgan) rekursiya
--       CHEKSIZ aylanmaydi; (2) `depth < 64` + tugun soni chegarasi —
--       chegaraga yetilsa FAIL-CLOSED: bog'lanish RAD ETILADI (jimgina
--       "sikl yo'q" deyilmaydi).
--    ⚠️ SECURITY DEFINER — trigger ichida RLS tufayli qatorlar KO'RINMAY
--       qolsa sikl "yo'q" bo'lib chiqardi. Funksiya `authenticated` ga
--       BERILMAYDI (uni faqat trigger chaqiradi).
-- ════════════════════════════════════════════════════════════════════════════
DO $cyc$
DECLARE
  v_idtype text;
BEGIN
  SELECT v INTO v_idtype FROM pg_temp.kut_ref WHERE k='idtype';
  IF v_idtype IS NULL THEN
    RAISE EXCEPTION 'idtype aniqlanmagan — 2-bo''lim bajarilmadimi?';
  END IF;

  EXECUTE format($f$
    CREATE OR REPLACE FUNCTION public.task_dep_would_cycle(p_task %s, p_dep %s)
    RETURNS boolean
    LANGUAGE plpgsql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $fb$
    DECLARE
      v_hit   boolean;
      v_depth int;
      v_n     bigint;
    BEGIN
      IF p_task IS NULL OR p_dep IS NULL THEN
        RETURN false;
      END IF;
      -- A -> A (o'zini o'zi kutish) — eng qisqa sikl.
      IF p_task = p_dep THEN
        RETURN true;
      END IF;

      WITH RECURSIVE walk(id, depth, path) AS (
        SELECT p_dep, 0, ARRAY[p_dep]
        UNION ALL
        SELECT d.depends_on_id, w.depth + 1, w.path || d.depends_on_id
          FROM public.task_dependencies d
          JOIN walk w ON d.task_id = w.id
         WHERE w.depth < 64
           AND NOT (d.depends_on_id = ANY (w.path))
      )
      SELECT bool_or(w.id = p_task), coalesce(max(w.depth), 0), count(*)
        INTO v_hit, v_depth, v_n
        FROM walk w;

      -- FAIL-CLOSED: chegaraga yetildi — javobga ishonib bo'lmaydi.
      IF coalesce(v_depth, 0) >= 64 OR coalesce(v_n, 0) >= 20000 THEN
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'Bog''lanish zanjiri juda chuqur yoki juda katta (chuqurlik '
                    || coalesce(v_depth, 0)::text || ', tugun ' || coalesce(v_n, 0)::text
                    || ') — sikl xavfi bor, bog''lanish qabul qilinmadi.',
          HINT    = 'KUTISH (task_dependencies): zanjirni qisqartiring yoki ortiqcha bog''lanishlarni o''chiring.';
      END IF;

      RETURN coalesce(v_hit, false);
    END
    $fb$
  $f$, v_idtype, v_idtype);

  EXECUTE format(
    'COMMENT ON FUNCTION public.task_dep_would_cycle(%s, %s) IS %L',
    v_idtype, v_idtype,
    'YANGI (p_task -> p_dep) bog''lanishi SIKL hosil qiladimi? recursive CTE bilan p_dep dan p_task ga yo''l qidiriladi. SECURITY DEFINER (RLS sikl qatorlarini yashirmasin). Chuqurlik/hajm chegarasida FAIL-CLOSED — RAISE EXCEPTION. Faqat task_dependencies_guard() chaqiradi; mijozga EXECUTE berilmagan.');

  -- 🔴 Mijozga OCHIQ EMAS: trigger funksiyasi SECURITY DEFINER bo'lgani uchun
  --    chaqiruvchida bu funksiyaga huquq bo'lishi shart emas.
  EXECUTE format('REVOKE ALL ON FUNCTION public.task_dep_would_cycle(%s, %s) FROM PUBLIC', v_idtype, v_idtype);
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    EXECUTE format('REVOKE ALL ON FUNCTION public.task_dep_would_cycle(%s, %s) FROM anon', v_idtype, v_idtype);
  END IF;
  EXECUTE format('REVOKE ALL ON FUNCTION public.task_dep_would_cycle(%s, %s) FROM authenticated', v_idtype, v_idtype);
END $cyc$;


-- ── 4.b) task_dependencies_guard() — BEFORE INSERT OR UPDATE qorovuli ───────
--    🔴 SECURITY DEFINER: `tasks` ni RLS'siz o'qiydi. Sabab — qorovul
--       HAQIQATNI bilishi kerak: chaqiruvchi ko'rmaydigan bosqich ham
--       loyihaga tegishli bo'lishi mumkin va u "topilmadi" deb o'tkazib
--       yuborilsa qoida buzilardi.
--    ⚠️ SECURITY DEFINER begona ma'lumotni ochib qo'ymasin deb A'ZOLIK
--       tekshiruvi bor — lekin FAQAT JWT bilan kelgan chaqiruvda
--       (auth.uid() IS NOT NULL). service_role / EF / psql uchun auth.uid()
--       NULL va bu tekshiruv o'tkazib yuboriladi (aks holda EF hech narsa
--       yoza olmasdi).
CREATE OR REPLACE FUNCTION public.task_dependencies_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $g$
DECLARE
  v_uid    uuid := (SELECT auth.uid());
  v_ws_a   uuid;
  v_ws_b   uuid;
  v_a_null boolean;
  v_b_null boolean;
  v_same   boolean;
BEGIN
  IF NEW.task_id IS NULL OR NEW.depends_on_id IS NULL THEN
    RAISE EXCEPTION 'Bog''lanish to''liq emas: bosqich ko''rsatilmagan.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 1-qatlam: o'ziga o'zi (DB CHECK ham bor — bu yerda matn tushunarli bo'lsin)
  IF NEW.task_id = NEW.depends_on_id THEN
    RAISE EXCEPTION 'Bosqich o''zini o''zi kuta olmaydi.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 🔴 A'ZOLIK ENG BIRINCHI (QA 2026-08-21). Avval "topilmadi" / "boshqa
  --    ws" xatolari a'zolik tekshiruvidan OLDIN chiqardi va begona odam
  --    xato MATNIGA qarab begona task_id MAVJUDLIGINI aniqlay olardi
  --    (SECURITY DEFINER qorovul RLS ni chetlab o'tadi).
  --    Endi tartib: (1) task_id ning ws i, (2) a'zolik, (3) qolgan qoidalar.
  --    "Topilmadi" matni ikkala vazifa uchun ham BIR XIL — qaysi biri
  --    yo'qligi ham aytilmaydi.
  SELECT a.workspace_id INTO v_ws_a FROM public.tasks a WHERE a.id = NEW.task_id;

  IF v_uid IS NOT NULL AND (v_ws_a IS NULL OR NOT public.is_ws_member(v_ws_a, v_uid)) THEN
    RAISE EXCEPTION 'Bu ish maydoni sizga ochiq emas.'
      USING ERRCODE = '42501';
  END IF;
  IF v_ws_a IS NULL THEN
    RAISE EXCEPTION 'Bosqich topilmadi (o''chirilgan bo''lishi mumkin).'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT b.workspace_id INTO v_ws_b FROM public.tasks b WHERE b.id = NEW.depends_on_id;
  IF v_ws_b IS NULL THEN
    RAISE EXCEPTION 'Bosqich topilmadi (o''chirilgan bo''lishi mumkin).'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT (a.project_id IS NULL), (b.project_id IS NULL), (a.project_id = b.project_id)
    INTO v_a_null, v_b_null, v_same
    FROM public.tasks a, public.tasks b
   WHERE a.id = NEW.task_id
     AND b.id = NEW.depends_on_id;

  IF v_ws_a IS DISTINCT FROM v_ws_b THEN
    RAISE EXCEPTION 'Bosqichlar har xil ish maydonida — bog''lab bo''lmaydi.'
      USING ERRCODE = 'P0001';
  END IF;

  -- SPEC 6: kutish FAQAT loyiha bosqichlari uchun
  IF v_a_null OR v_b_null THEN
    RAISE EXCEPTION 'Kutish faqat LOYIHA bosqichlari uchun: ikkala vazifa ham loyihaga tegishli bo''lishi kerak.'
      USING ERRCODE = 'P0001';
  END IF;

  -- SPEC 5.4: faqat BIR loyiha ichida
  IF NOT coalesce(v_same, false) THEN
    RAISE EXCEPTION 'Bosqichlar BITTA loyihada bo''lishi shart — boshqa loyihaning bosqichini kutib bo''lmaydi.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 🔴 Mijoz yuborgan workspace_id ga ISHONILMAYDI — vazifadan olinadi.
  NEW.workspace_id := v_ws_a;
  -- created_by ni SERVER yozadi (JWT bo'lsa). JWT'siz (EF/service_role)
  -- chaqiruvda mijoz yuborgani qoladi — u yerda soxtalashtirish ma'nosiz.
  IF v_uid IS NOT NULL THEN
    NEW.created_by := v_uid;
  END IF;
  IF NEW.created_at IS NULL THEN
    NEW.created_at := now();
  END IF;

  -- SPEC 5.2: SIKL
  IF public.task_dep_would_cycle(NEW.task_id, NEW.depends_on_id) THEN
    RAISE EXCEPTION 'Sikl: bu bog''lanish halqa hosil qiladi — bosqich aylanib o''zini kutib qolardi.'
      USING ERRCODE = 'P0001',
            HINT    = 'KUTISH (task_dependencies): faqat YUQORIDAGI (oldin turgan) bosqichlarni tanlang.';
  END IF;

  RETURN NEW;
END
$g$;

COMMENT ON FUNCTION public.task_dependencies_guard() IS
  'task_dependencies BEFORE INSERT/UPDATE qorovuli: BIR loyiha sharti, workspace_id ni SERVER yozishi, created_by ni SERVER yozishi, o''ziga o''zi bog''lanish va SIKL (task_dep_would_cycle) tekshiruvi. SECURITY DEFINER — tasks ni RLS''siz o''qiydi; JWT bor bo''lsa a''zolik ham tekshiriladi.';

REVOKE ALL ON FUNCTION public.task_dependencies_guard() FROM PUBLIC;

DROP TRIGGER IF EXISTS task_dependencies_guard_trg ON public.task_dependencies;
CREATE TRIGGER task_dependencies_guard_trg
  BEFORE INSERT OR UPDATE ON public.task_dependencies
  FOR EACH ROW EXECUTE FUNCTION public.task_dependencies_guard();


-- ════════════════════════════════════════════════════════════════════════════
-- 5) 🔴 HAQIQIY TO'SIQ (SPEC 4-bo'lim) — tasks ustidagi qorovul
--    BEFORE UPDATE OF status ON public.tasks
--
--    🔴 DEP QATORI BO'LMAGAN VAZIFAGA TA'SIR NOL. Funksiyaning birinchi
--       ishi — arzon chiqish shartlari; `task_dependencies` da qator
--       bo'lmasa (ya'ni ilovadagi vazifalarning ~100%) darrov RETURN NEW.
--       Bu skriptdagi (f) TIRIK SINOVI bilan isbotlanadi.
--
--    ⚠️ `UPDATE OF status` — trigger faqat SET ro'yxatida `status` bo'lgan
--       UPDATE'da ishga tushadi. deadline / plan_* / assigned_to yangilashi
--       trigger'ga UMUMAN kirmaydi.
--
--    🔴 NOMI `zz_` BILAN: PostgreSQL bir xil turdagi trigger'larni NOM
--       bo'yicha alifbo tartibida ishga tushiradi. Bizniki OXIRIDA ishlaydi
--       va NEW ning YAKUNIY qiymatini ko'radi (34-migratsiyaning is_locked
--       trigger'i, updated_at trigger'i va h.k. o'z ishini AVVAL qiladi).
--       Biz hech qanday ustunni O'ZGARTIRMAYMIZ — faqat RAISE EXCEPTION,
--       ya'ni boshqa trigger'ning natijasini buza olmaymiz.
--
--    🔴 SECURITY DEFINER: kutilayotgan bosqichlar RLS tufayli chaqiruvchiga
--       KO'RINMASA sanoq 0 chiqib, qoida jimgina chetlab o'tilardi.
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.task_wait_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $w$
DECLARE
  v_wait int;
BEGIN
  -- 🔴 SERVER ROLI UCHUN ISTISNO ATAYLAB YO'Q (fayl sarlavhasi, "QOLGAN XAVF" 1).
  --    Kutish — BIZNES qoidasi, ruxsat masalasi emas: EF / Telegram bot ham
  --    unga bo'ysunadi, aks holda ilovada bloklangan amal bot orqali o'tib
  --    ketardi va tizim foydalanuvchi uchun ZID ishlagan bo'lardi.
  --    Agar kelajakda "server hamma narsani qila oladi" kerak bo'lsa,
  --    QUYIDAGI BITTA QATORNI oching (boshqa hech narsa o'zgarmaydi):
  --      IF (SELECT auth.uid()) IS NULL THEN RETURN NEW; END IF;

  -- (1) status umuman o'zgarmagan bo'lsa — chiqamiz
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  -- (2) FAQAT "'new' dan chiqish" to'siladi (SPEC 4). Bir marta ochilgan
  --     bosqich keyin yopilmaydi: in_progress -> completed TEGILMAYDI.
  -- 🔴 QA (2026-08-21) TESHIK YOPILDI: 'new' VA 'cancelled' — ikkalasi ham
  --    "boshlanmagan" holat. Avval bu yerda faqat 'new' bor edi, ya'ni
  --    new -> cancelled (istisno, o'tadi) -> cancelled -> completed
  --    (OLD 'new' emas => qorovul UMUMAN ishlamasdi) yo'li bilan kutish
  --    qoidasini kanbanda IKKI SUDRASH bilan chetlab o'tish mumkin edi.
  --    Sinov: (i).
  IF coalesce(OLD.status, 'new') NOT IN ('new', 'cancelled') THEN
    RETURN NEW;
  END IF;
  IF coalesce(NEW.status, 'new') = 'new' THEN
    RETURN NEW;
  END IF;

  -- (2b) 🔴 BEKOR QILISH HAR DOIM MUMKIN. Bekor qilish — BAJARISH emas,
  --      administrativ chiqish yo'li: bloklangan bosqichni bekor qila
  --      olmaslik odamni tuzoqqa solardi (kutilayotgani ham bloklangan
  --      bo'lsa zanjir butunlay qotib qolardi). Mijozdagi `depUnmet` ham
  --      'cancelled' ni "bajarilgan" deb biladi — ya'ni bekor qilingan
  --      bosqich unga bog'langanlarni OCHADI. "Bajarildi"/"Jarayonda" esa
  --      baribir to'siladi.
  IF NEW.status = 'cancelled' THEN
    RETURN NEW;
  END IF;

  -- (3) 🔴 ARZON CHIQISH: bu vazifada bog'lanish umuman bormi?
  --     Yo'q bo'lsa — HECH NARSA qilmaymiz (ta'sir NOL).
  IF NOT EXISTS (
    SELECT 1 FROM public.task_dependencies d WHERE d.task_id = NEW.id
  ) THEN
    RETURN NEW;
  END IF;

  -- (4) Kutilayotgan (hali tugallanmagan) bosqichlar soni.
  --     SPEC 6: `cancelled` ham "tugagan" hisoblanadi (mijozdagi
  --     prjTaskOpen bilan AYNAN bir xil ta'rif).
  SELECT count(*) INTO v_wait
    FROM public.task_dependencies d
    JOIN public.tasks t ON t.id = d.depends_on_id
   WHERE d.task_id = NEW.id
     AND coalesce(t.status, 'new') NOT IN ('completed', 'cancelled');

  IF coalesce(v_wait, 0) > 0 THEN
    RAISE EXCEPTION 'Bu bosqich hali ochilmagan: % ta kutilayotgan bosqich tugallanmagan. Avval o''sha bosqich(lar) "Bajarildi" yoki "Bekor" bo''lishi kerak.', v_wait
      USING ERRCODE = 'P0001',
            HINT    = 'KUTISH (task_dependencies) qoidasi. Vazifa: ' || NEW.id::text;
  END IF;

  RETURN NEW;
END
$w$;

COMMENT ON FUNCTION public.task_wait_guard() IS
  'tasks BEFORE UPDATE OF status qorovuli (KUTISH). status ''new'' dan boshqasiga o''tayotganda task_dependencies bo''yicha kutilayotgan bosqichlar (status NOT IN (completed, cancelled)) qolgan bo''lsa RAISE EXCEPTION. ''cancelled'' ISTISNO — bekor qilish har doim mumkin (administrativ chiqish yo''li). Dep qatori BO''LMAGAN vazifaga ta''siri NOL. SECURITY DEFINER — RLS sanoqni pasaytirmasin. service_role/EF uchun ISTISNO YO''Q (biznes qoidasi).';

REVOKE ALL ON FUNCTION public.task_wait_guard() FROM PUBLIC;

-- ⚠️ 🔴 SHU YERDA `public.tasks` GA ACCESS EXCLUSIVE QULF OLINADI.
--    Undan oldingi hamma narsa (jadval, funksiyalar) qulfsiz bajarildi.
DROP TRIGGER IF EXISTS zz_task_wait_guard_trg ON public.tasks;
CREATE TRIGGER zz_task_wait_guard_trg
  BEFORE UPDATE OF status ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.task_wait_guard();


-- ════════════════════════════════════════════════════════════════════════════
-- 6) RLS — SELECT: ws a'zosi · INSERT/DELETE: ws-menejeri YOKI YARATUVCHI
--    🔴 CLAUDE.md 8-qoida: policy ichida workspace_members inline subquery
--       YOZILMAYDI — is_ws_member()/is_ws_manager() ishlatiladi (42P17).
--    🔴 "Yaratuvchi" tekshiruvi policy ichida `tasks` ga to'g'ridan
--       murojaat QILMAYDI: u yerda `tasks` ning O'Z RLS'i qo'llanib, egasiga
--       ham qator ko'rinmay qolishi mumkin edi. O'rniga SECURITY DEFINER
--       yordamchi funksiya — can_see_project() / can_view_planner() naqshi.
-- ════════════════════════════════════════════════════════════════════════════
DO $fn$
DECLARE
  v_idtype text;
  v_own    text;
  r        RECORD;
BEGIN
  SELECT v INTO v_idtype FROM pg_temp.kut_ref WHERE k='idtype';
  SELECT v INTO v_own    FROM pg_temp.kut_ref WHERE k='ownexpr';
  IF v_idtype IS NULL OR v_own IS NULL THEN
    RAISE EXCEPTION 'idtype / ownexpr aniqlanmagan — 2-bo''lim bajarilmadimi?';
  END IF;

  -- Eski, BOSHQA imzoli nusxa qolgan bo'lsa tozalanadi.
  -- ⚠️ Biror policy o'sha nusxaga bog'liq bo'lsa DROP xato beradi va butun
  --    tranzaksiya qaytadi (jimgina buzilmaydi).
  FOR r IN
    SELECT p.oid, pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='can_edit_task_deps'
  LOOP
    IF lower(btrim(r.args)) IS DISTINCT FROM lower('p_task ' || v_idtype || ', p_user uuid') THEN
      RAISE NOTICE 'Eski imzo o''chirilmoqda: can_edit_task_deps(%)', r.args;
      EXECUTE format('DROP FUNCTION public.can_edit_task_deps(%s)', r.args);
    END IF;
  END LOOP;

  EXECUTE format($f$
    CREATE OR REPLACE FUNCTION public.can_edit_task_deps(p_task %s, p_user uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $fb$
      -- 🔴 QOROVUL 1 — `p_user = (SELECT auth.uid())`. MAJBURIY QATOR,
      --    OLIB TASHLAMANG. Funksiya `authenticated` ga EXECUTE bilan ochiq,
      --    ya'ni uni PostgREST orqali to'g'ridan chaqirish mumkin:
      --        POST /rest/v1/rpc/can_edit_task_deps {p_task, p_user}
      --    Bu qatorsiz istalgan foydalanuvchi begona odam haqida
      --    "u falon vazifaning egasimi?" javobini ola olardi (SECURITY
      --    DEFINER RLS ni chetlab o'tadi).
      -- 🔴 QOROVUL 2 — `is_ws_member(...)`. MAJBURIY: jamoadan chiqarilgan
      --    xodim huquqni SAQLAB QOLMASIN (rmxDoRemove uni faqat
      --    workspace_members dan chiqaradi, vazifadagi bajaruvchi/yaratuvchi
      --    ustunlari esa o'sha uid da QOLADI).
      -- ⚠️ Ataylab: bu tanada bajaruvchi/qabul qiluvchi ustunlari UMUMAN
      --    ishlatilmaydi (7-bo'limdagi tekshiruv buni majburlaydi).
      SELECT p_task IS NOT NULL
         AND p_user IS NOT NULL
         AND p_user = (SELECT auth.uid())
         AND EXISTS (
               SELECT 1
                 FROM public.tasks t
                WHERE t.id = p_task
                  AND public.is_ws_member(t.workspace_id, p_user)
                  AND (%s)
             );
    $fb$
  $f$, v_idtype, v_own);

  EXECUTE format(
    'COMMENT ON FUNCTION public.can_edit_task_deps(%s, uuid) IS %L',
    v_idtype,
    'p_user shu vazifaning KUTISH bog''lanishlarini tahrirlay oladimi? FAQAT ws-menejeri YOKI vazifa YARATUVCHISI (created_by). assigned_to / acceptor_id ATAYLAB kirmaydi — bloklangan bosqich bajaruvchisi bog''lanishni o''chirib qoidani chetlab o''tmasin (QA 2026-08-21). SECURITY DEFINER — tasks ni RLS''siz o''qiydi (policy ichidan chaqiriladi). IKKI MAJBURIY qorovul: p_user = auth.uid() (PostgREST /rpc) va is_ws_member (jamoadan chiqarilgan xodim).');

  -- 🔴 REVOKE ... FROM PUBLIC YETARLI EMAS: Supabase'da ALTER DEFAULT
  --    PRIVILEGES ... GRANT ALL ON FUNCTIONS TO anon, authenticated
  --    o'rnatilgan bo'lishi mumkin. Shuning uchun aniq `FROM anon`.
  EXECUTE format('REVOKE ALL ON FUNCTION public.can_edit_task_deps(%s, uuid) FROM PUBLIC', v_idtype);
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    EXECUTE format('REVOKE ALL ON FUNCTION public.can_edit_task_deps(%s, uuid) FROM anon', v_idtype);
  END IF;
  EXECUTE format('REVOKE ALL ON FUNCTION public.can_edit_task_deps(%s, uuid) FROM authenticated', v_idtype);
  -- EXECUTE authenticated'ga SHART: RLS ifodasi CHAQIRUVCHI huquqi bilan
  -- baholanadi (can_see_project / can_view_planner naqshi).
  EXECUTE format('GRANT EXECUTE ON FUNCTION public.can_edit_task_deps(%s, uuid) TO authenticated', v_idtype);
END $fn$;


ALTER TABLE public.task_dependencies ENABLE ROW LEVEL SECURITY;

-- ── Policy'lar. Jadval BIZNIKI (yangi) — shuning uchun o'z policy'larimizni
--    qayta yaratish xavfsiz (idempotentlik). Begona policy'ga TEGILMAYDI.
DROP POLICY IF EXISTS task_deps_select ON public.task_dependencies;
CREATE POLICY task_deps_select ON public.task_dependencies
  FOR SELECT TO authenticated
  USING (public.is_ws_member(workspace_id, (SELECT auth.uid())));

DROP POLICY IF EXISTS task_deps_insert ON public.task_dependencies;
CREATE POLICY task_deps_insert ON public.task_dependencies
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_ws_member(workspace_id, (SELECT auth.uid()))
    AND public.can_edit_task_deps(task_id, (SELECT auth.uid()))
  );

DROP POLICY IF EXISTS task_deps_delete ON public.task_dependencies;
CREATE POLICY task_deps_delete ON public.task_dependencies
  FOR DELETE TO authenticated
  USING (
    public.is_ws_member(workspace_id, (SELECT auth.uid()))
    AND public.can_edit_task_deps(task_id, (SELECT auth.uid()))
  );

-- ⚠️ UPDATE policy ATAYLAB YO'Q: bog'lanish qatori o'zgarmas. O'zgartirish =
--    o'chirish + qo'shish (ikkalasi ham yuqoridagi qoidadan o'tadi).

-- ── GRANT ───────────────────────────────────────────────────────────────────
DO $grant$
BEGIN
  REVOKE ALL ON TABLE public.task_dependencies FROM PUBLIC;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    -- 🔴 anon ga HECH NARSA: kutish grafigi kirmagan odamga ochilmaydi.
    EXECUTE 'REVOKE ALL ON TABLE public.task_dependencies FROM anon';
  END IF;
  GRANT SELECT, INSERT, DELETE ON TABLE public.task_dependencies TO authenticated;
  -- UPDATE grant ATAYLAB berilmaydi (yuqoridagi izoh).
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN
    -- EF (sync-*, admin-*) service_role bilan ishlaydi; RLS unga qo'llanmaydi,
    -- lekin JADVAL granti kerak. Trigger qorovullari unga HAM amal qiladi.
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.task_dependencies TO service_role';
  END IF;
END $grant$;


-- ════════════════════════════════════════════════════════════════════════════
-- 7) TEKSHIRUV — STRUKTURA + FUNKSIYA TANASI + GRANT
--    🔴 "Yaratdim" degan yozuvga ishonmaymiz: hamma narsa KATALOGDAN qayta
--       o'qiladi. Kutilganidek bo'lmasa RAISE EXCEPTION → butun tranzaksiya
--       qaytadi va bazada BIR BELGI ham o'zgarmaydi.
--    ⚠️ Funksiya tanasi tekshiruvida izohlar `regexp_replace` bilan olib
--       tashlanadi — kalit shart IZOHDA yozib qo'yilgani "bor" hisoblanmasin.
-- ════════════════════════════════════════════════════════════════════════════
DO $chk$
DECLARE
  v_idtype text;
  v_src    text;
  v_sig    text;
  v_n      int;
  v_max    text;
  v_p      text;
BEGIN
  SELECT v INTO v_idtype FROM pg_temp.kut_ref WHERE k='idtype';

  -- ── 7.a) JADVAL / USTUNLAR ────────────────────────────────────────────────
  IF to_regclass('public.task_dependencies') IS NULL THEN
    RAISE EXCEPTION 'public.task_dependencies yaratilmadi. HAMMASI QAYTARILDI.';
  END IF;
  FOREACH v_p IN ARRAY ARRAY['task_id','depends_on_id','workspace_id','created_by','created_at'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='task_dependencies' AND column_name=v_p) THEN
      RAISE EXCEPTION 'task_dependencies.% ustuni yo''q. HAMMASI QAYTARILDI.', v_p;
    END IF;
  END LOOP;

  -- ── 7.b) PK / CHECK / FK (ON DELETE CASCADE bo'lishi SHART — SPEC 6) ──────
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.task_dependencies'::regclass AND contype='p') THEN
    RAISE EXCEPTION 'task_dependencies da PRIMARY KEY yo''q — bitta juftlik ikki marta yozilib ketardi. HAMMASI QAYTARILDI.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.task_dependencies'::regclass
                    AND conname='task_dependencies_self_chk' AND contype='c') THEN
    RAISE EXCEPTION 'CHECK (task_id <> depends_on_id) yo''q — sikl himoyasining 3-qatlami (SPEC 5.3). HAMMASI QAYTARILDI.';
  END IF;

  SELECT count(*) INTO v_n
    FROM pg_constraint
   WHERE conrelid='public.task_dependencies'::regclass
     AND contype='f'
     AND conname IN ('task_dependencies_task_fk','task_dependencies_dep_fk')
     AND confrelid = 'public.tasks'::regclass
     AND confdeltype = 'c';
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'task_id / depends_on_id uchun tasks(id) ga ON DELETE CASCADE FK lari to''liq emas (topildi: % / 2). Bosqich o''chirilganda bog''lanish osilib qolardi (SPEC 6). HAMMASI QAYTARILDI.', v_n;
  END IF;

  -- ── 7.c) INDEKS ───────────────────────────────────────────────────────────
  IF NOT EXISTS (SELECT 1 FROM pg_indexes
                  WHERE schemaname='public' AND tablename='task_dependencies'
                    AND indexname='idx_task_dependencies_dep') THEN
    RAISE EXCEPTION 'idx_task_dependencies_dep indeksi yo''q — "meni kim kutyapti?" so''rovi to''liq skan bo''lardi. HAMMASI QAYTARILDI.';
  END IF;

  -- ── 7.d) TRIGGERLAR ───────────────────────────────────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgrelid='public.task_dependencies'::regclass
       AND tgname='task_dependencies_guard_trg' AND NOT tgisinternal
       AND (tgtype::int & 2) = 2 AND (tgtype::int & 1) = 1
       AND (tgtype::int & 4) = 4 AND (tgtype::int & 16) = 16
  ) THEN
    RAISE EXCEPTION 'task_dependencies_guard_trg (BEFORE INSERT OR UPDATE, ROW) yo''q — sikl va "bir loyiha" qorovullari ishlamasdi. HAMMASI QAYTARILDI.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgrelid='public.tasks'::regclass
       AND tgname='zz_task_wait_guard_trg' AND NOT tgisinternal
       AND (tgtype::int & 2) = 2 AND (tgtype::int & 1) = 1
       AND (tgtype::int & 16) = 16
  ) THEN
    RAISE EXCEPTION 'zz_task_wait_guard_trg (BEFORE UPDATE, ROW) yo''q — server tomonda HECH QANDAY to''siq bo''lmasdi. HAMMASI QAYTARILDI.';
  END IF;

  -- Alifbo tartibi: bizniki OXIRIDA ishlashi kerak (majburiy emas — WARNING)
  SELECT max(tgname) INTO v_max
    FROM pg_trigger
   WHERE tgrelid='public.tasks'::regclass AND NOT tgisinternal
     AND (tgtype::int & 2) = 2 AND (tgtype::int & 1) = 1 AND (tgtype::int & 16) = 16
     AND tgname <> 'zz_task_wait_guard_trg';
  IF v_max IS NOT NULL AND v_max > 'zz_task_wait_guard_trg' THEN
    RAISE WARNING '⚠️ tasks da bizdan KEYIN ishlaydigan BEFORE UPDATE trigger bor: %. U NEW.status ni o''zgartirsa bizning tekshiruvimiz eskirgan qiymatga qaragan bo''lardi. Tekshirib chiqing.', v_max;
  END IF;

  -- ── 7.e) FUNKSIYA TANALARI (izohlar tozalab, strpos bilan) ────────────────
  -- task_wait_guard: dep qatori bor-yo'qligini tekshiradimi, 'new' dan
  -- chiqishnigina to'sadimi, completed/cancelled ni "tugagan" deb biladimi.
  SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='task_wait_guard' LIMIT 1;
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'task_wait_guard() topilmadi. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_src, 'task_dependencies') = 0 THEN
    RAISE EXCEPTION 'task_wait_guard() KODIDA task_dependencies o''qilmayapti — to''siq ma''nosiz. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_src, 'completed') = 0 OR strpos(v_src, 'cancelled') = 0 THEN
    RAISE EXCEPTION 'task_wait_guard() KODIDA completed/cancelled ta''rifi yo''q — "tugagan" tushunchasi mijozdagidan farq qilardi (SPEC 6). HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_src, 'NEW.status = ''cancelled''') = 0 THEN
    RAISE EXCEPTION 'task_wait_guard() KODIDA "bekor qilish har doim mumkin" istisnosi (NEW.status = ''''cancelled'''') YO''Q — bloklangan bosqichni bekor qilib bo''lmasdi va zanjir qotib qolardi. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_src, '''new'', ''cancelled''') = 0 AND strpos(v_src, '''new'',''cancelled''') = 0 THEN
    RAISE EXCEPTION 'task_wait_guard() da OLD.status qorovuli faqat ''new'' ni qamrayapti — new->cancelled->completed yo''li bilan qoida chetlab o''tilardi (QA 2026-08-21). HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_src, 'NOT EXISTS') = 0 THEN
    RAISE EXCEPTION 'task_wait_guard() da "dep qatori bormi?" arzon chiqish sharti (NOT EXISTS) yo''q — dep qatori bo''lmagan vazifalarga ham qo''shimcha so''rov tushardi. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_src, 'RAISE EXCEPTION') = 0 THEN
    RAISE EXCEPTION 'task_wait_guard() hech narsani rad etmayapti (RAISE EXCEPTION yo''q). HAMMASI QAYTARILDI.';
  END IF;

  -- task_dependencies_guard: bir loyiha + workspace_id + sikl + a'zolik
  SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='task_dependencies_guard' LIMIT 1;
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'task_dependencies_guard() topilmadi. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_src, 'project_id') = 0 THEN
    RAISE EXCEPTION 'task_dependencies_guard() KODIDA project_id tekshiruvi yo''q — boshqa loyihaning bosqichini kutish mumkin bo''lardi (SPEC 5.4). HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_src, 'task_dep_would_cycle') = 0 THEN
    RAISE EXCEPTION 'task_dependencies_guard() KODIDA SIKL tekshiruvi (task_dep_would_cycle) yo''q. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_src, 'NEW.workspace_id :=') = 0 THEN
    RAISE EXCEPTION 'task_dependencies_guard() workspace_id ni O''ZI yozmayapti — mijoz yuborgan qiymat ishlatilardi. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_src, 'is_ws_member') = 0 THEN
    RAISE EXCEPTION 'task_dependencies_guard() da a''zolik tekshiruvi yo''q — SECURITY DEFINER qorovul begona ish maydoni haqida ma''lumot ochib qo''yardi. HAMMASI QAYTARILDI.';
  END IF;

  -- task_dep_would_cycle: recursive CTE + chuqurlik qorovuli
  SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='task_dep_would_cycle' LIMIT 1;
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'task_dep_would_cycle() topilmadi. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(upper(v_src), 'WITH RECURSIVE') = 0 THEN
    RAISE EXCEPTION 'task_dep_would_cycle() da recursive CTE yo''q — uzun sikl (A→B→C→A) tutilmasdi. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_src, 'depth') = 0 OR strpos(v_src, 'path') = 0 THEN
    RAISE EXCEPTION 'task_dep_would_cycle() da chuqurlik/yo''l qorovuli yo''q — mavjud sikl uchrasa rekursiya cheksiz aylanardi. HAMMASI QAYTARILDI.';
  END IF;

  -- can_edit_task_deps: 2 majburiy qorovul
  SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='can_edit_task_deps' LIMIT 1;
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'can_edit_task_deps() topilmadi. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_src, 'auth.uid()') = 0 THEN
    RAISE EXCEPTION 'can_edit_task_deps() da `p_user = (SELECT auth.uid())` qorovuli yo''q — PostgREST /rpc orqali begona odam haqida ma''lumot olinardi. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_src, 'is_ws_member') = 0 THEN
    RAISE EXCEPTION 'can_edit_task_deps() da is_ws_member qorovuli yo''q — jamoadan chiqarilgan xodim huquqni saqlab qolardi. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_src, 'created_by') = 0 OR strpos(v_src, 'is_ws_manager') = 0 THEN
    RAISE EXCEPTION 'can_edit_task_deps() huquq ifodasi kutilganidek emas (is_ws_manager / created_by yo''q). HAMMASI QAYTARILDI.';
  END IF;
  -- 🔴 QA 2026-08-21: bajaruvchi/qabul qiluvchi KIRMASLIGI SHART
  IF strpos(v_src, 'assigned_to') > 0 OR strpos(v_src, 'acceptor_id') > 0 THEN
    RAISE EXCEPTION 'can_edit_task_deps() ifodasida assigned_to / acceptor_id BOR — bloklangan bosqichning BAJARUVCHISI o''zini bloklab turgan bog''lanishni o''chirib, keyin statusni o''zgartira olardi. HAMMASI QAYTARILDI.';
  END IF;

  -- ── 7.f) RLS + POLICY ─────────────────────────────────────────────────────
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                  WHERE n.nspname='public' AND c.relname='task_dependencies' AND c.relrowsecurity) THEN
    RAISE EXCEPTION 'task_dependencies da RLS YOQILMAGAN — har kim hamma narsani ko''rardi. HAMMASI QAYTARILDI.';
  END IF;
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='public' AND tablename='task_dependencies'
     AND policyname IN ('task_deps_select','task_deps_insert','task_deps_delete');
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'task_dependencies policy''lari to''liq emas (topildi: % / 3). HAMMASI QAYTARILDI.', v_n;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies
              WHERE schemaname='public' AND tablename='task_dependencies'
                AND roles @> ARRAY['anon']::name[]) THEN
    RAISE EXCEPTION 'task_dependencies policy''sida `anon` bor — kirmagan foydalanuvchiga yo''l ochilardi. HAMMASI QAYTARILDI.';
  END IF;
  SELECT qual INTO v_p FROM pg_policies
   WHERE schemaname='public' AND tablename='task_dependencies' AND policyname='task_deps_select';
  IF coalesce(v_p,'') = '' OR strpos(v_p, 'is_ws_member') = 0 THEN
    RAISE EXCEPTION 'task_deps_select policy''sining USING sharti kutilganidek emas (is_ws_member yo''q): %. HAMMASI QAYTARILDI.', coalesce(v_p,'—');
  END IF;

  -- ── 7.g) GRANT ────────────────────────────────────────────────────────────
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    FOREACH v_p IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE'] LOOP
      IF has_table_privilege('anon', 'public.task_dependencies', v_p) THEN
        RAISE EXCEPTION '`anon` roli task_dependencies ustida % huquqiga ega — REVOKE ishlamadi (ALTER DEFAULT PRIVILEGES?). HAMMASI QAYTARILDI.', v_p;
      END IF;
    END LOOP;
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.task_dependencies', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.task_dependencies', 'INSERT')
     OR NOT has_table_privilege('authenticated', 'public.task_dependencies', 'DELETE') THEN
    RAISE EXCEPTION '`authenticated` ga SELECT/INSERT/DELETE grantlari to''liq berilmadi — mijoz kutishni umuman boshqara olmasdi. HAMMASI QAYTARILDI.';
  END IF;
  IF has_table_privilege('authenticated', 'public.task_dependencies', 'UPDATE') THEN
    RAISE WARNING '⚠️ `authenticated` ga task_dependencies uchun UPDATE granti bor (biz bermadik — ALTER DEFAULT PRIVILEGES bo''lishi mumkin). Qator o''zgarmas bo''lishi kerak edi; UPDATE policy YO''Q, shuning uchun amalda RLS to''sadi.';
  END IF;

  v_sig := format('public.can_edit_task_deps(%s,uuid)', v_idtype);
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    IF has_function_privilege('anon', v_sig, 'EXECUTE') THEN
      RAISE EXCEPTION 'can_edit_task_deps() `anon` ga EXECUTE bilan ochiq qolgan. HAMMASI QAYTARILDI.';
    END IF;
  END IF;
  IF NOT has_function_privilege('authenticated', v_sig, 'EXECUTE') THEN
    RAISE EXCEPTION 'can_edit_task_deps() `authenticated` ga EXECUTE bermayapti — policy ifodasi CHAQIRUVCHI huquqi bilan baholanadi, INSERT/DELETE umuman ishlamasdi. HAMMASI QAYTARILDI.';
  END IF;

  v_sig := format('public.task_dep_would_cycle(%s,%s)', v_idtype, v_idtype);
  IF has_function_privilege('authenticated', v_sig, 'EXECUTE') THEN
    RAISE WARNING '⚠️ task_dep_would_cycle() `authenticated` ga EXECUTE bilan ochiq (biz REVOKE qilgandik). Xavf kichik (u faqat boolean qaytaradi), lekin ALTER DEFAULT PRIVILEGES ni tekshiring.';
  END IF;

  RAISE NOTICE '✅ Struktura, funksiya tanalari, RLS va grantlar TEKSHIRILDI.';
END $chk$;


-- ── Natija jadvali ──────────────────────────────────────────────────────────
--    ⚠️ TRANZAKSIYA ICHIDA yaratiladi: skript yiqilsa u ham qaytadi va
--       oxiridagi SELECT bajarilmaydi. Xato holatida hamma raqam
--       "Messages" bo'limidagi NOTICE/EXCEPTION matnida bo'ladi.
DROP TABLE IF EXISTS pg_temp.kut_res;
CREATE TEMP TABLE pg_temp.kut_res (ord int, bosqich text, nom text, qiymat text, izoh text);


-- ════════════════════════════════════════════════════════════════════════════
-- 8) 🔴 TIRIK SINOV — SENTINEL-ROLLBACK bilan
--    Sinovlar (topshiriq a–g):
--      (a) SIKL rad etiladi: A↔A · A→B→A · X→Y→Z→X
--      (b) boshqa loyiha / loyihasiz bosqichga bog'lash rad etiladi
--      (c) kutilayotgan bosqich tugamagan bo'lsa status o'zgarishi RAD ETILADI
--      (d) hammasi tugagach O'TADI
--      (e) `cancelled` ham "tugagan" deb qabul qilinadi
--      (f) 🔴 dep qatori YO'Q vazifada status o'zgarishi AVVALGIDEK o'tadi
--      (i) 🔴 new → cancelled → completed bilan qoidani CHETLAB O'TIB
--          BO'LMAYDI (QA 2026-08-21 teshigi)
--      (h) 🔴 BLOKLANGAN bosqich 'cancelled' ga O'TADI (bekor qilish
--          to'silmaydi) va shundan keyin unga bog'langan bosqich OCHILADI
--      (g) begona ws a'zosi dep qatorini KO'RMAYDI va YOZA OLMAYDI
--          (+ oddiy a'zo yoza olmaydi, ws-menejeri yoza oladi)
--    ⚠️ Yozuv qiladigan qism ichki blokda ATAYLAB EXCEPTION bilan tugatiladi
--       → subtranzaksiya qaytadi va bazada BITTA qator ham qolmaydi.
--       Natijalar xato MATNIDA olib chiqiladi (KUT_PROBE:...).
--    ⚠️ Aniqlik: sequence har RUN da bir necha pog'ona siljiydi va o'lik
--       tuple qoladi (VACUUM tozalaydi) — bular MA'LUMOT emas, xavf yo'q.
-- ════════════════════════════════════════════════════════════════════════════
DO $live$
DECLARE
  v_idtype  text;
  v_projtyp text;
  v_ws      uuid;
  v_mgr     uuid;
  v_mem     uuid;
  v_out     uuid;
  v_p1      text;
  v_p2      text;
  v_prj1    text;
  v_prj2    text;
  v_tpl     text;
  v_tpl2    text;
  v_del     text;
  v_dep_ins text;
  v_dep_i2  text;
  v_upd     text;
  v_selc    text;
  v_bad     text;
  v_id_auto boolean;
  v_imp_ok  boolean := false;
  v_skip    text;
  v_txt     text;
  v_i       bigint;
  v_prjnull boolean;
  v_has_flow  boolean;
  v_has_dpp   boolean;
  v_has_asg   boolean;
  v_has_cb    boolean;
  v_has_title boolean;
  -- sinov vazifalari
  v_a text; v_b text; v_e text; v_f text;
  v_x text; v_y text; v_z text;
  v_g text; v_h text; v_i2 text; v_n0 text; v_m text;
  v_j text; v_k text;
  -- probelar
  p_self    text; p_ab      text; p_cyc2 text; p_chain text; p_cyc3 text;
  p_nullprj text; p_p2      text; p_wsfix text;
  p_block   text; p_pass    text; p_cancel text; p_free text;
  p_mgrins  text; p_memsel  text; p_memins text; p_outsel text; p_outins text;
  p_hblk    text; p_hcan    text; p_hopen  text;
  p_icnl    text; p_icomp   text; p_asgdel text; p_mgrdel text;
  v_probe   text;
  -- hisobot matnlari
  t_cyc text := '— (sinov o''tkazilmadi)';
  t_prj text := '— (sinov o''tkazilmadi)';
  t_blk text := '— (sinov o''tkazilmadi)';
  t_pas text := '— (sinov o''tkazilmadi)';
  t_can text := '— (sinov o''tkazilmadi)';
  t_fre text := '— (sinov o''tkazilmadi)';
  t_hcn text := '— (sinov o''tkazilmadi)';
  t_icn text := '— (sinov o''tkazilmadi)';
  t_rls text := '— (sinov o''tkazilmadi)';
BEGIN
  SELECT v INTO v_idtype  FROM pg_temp.kut_ref WHERE k='idtype';
  SELECT v INTO v_projtyp FROM pg_temp.kut_ref WHERE k='projtype';

  -- ── (0) SINOV UCHUN MA'LUMOT TOPAMIZ ───────────────────────────────────────
  --    ⚠️ Loyiha YARATMAYMIZ — mavjud loyihadan foydalanamiz (projects ning
  --       majburiy ustunlarini taxmin qilib qator yozish xavfli bo'lardi).
  SELECT p.workspace_id, p.id::text INTO v_ws, v_p1
    FROM public.projects p
   WHERE EXISTS (SELECT 1 FROM public.workspace_members m
                  WHERE m.workspace_id = p.workspace_id
                    AND public.is_ws_manager(p.workspace_id, m.user_id))
   ORDER BY p.workspace_id, p.id
   LIMIT 1;

  IF v_ws IS NULL THEN
    v_skip := 'menejeri bor workspace''da loyiha topilmadi';
  ELSE
    SELECT m.user_id INTO v_mgr
      FROM public.workspace_members m
     WHERE m.workspace_id = v_ws AND public.is_ws_manager(v_ws, m.user_id)
     ORDER BY m.user_id LIMIT 1;

    SELECT m.user_id INTO v_mem
      FROM public.workspace_members m
     WHERE m.workspace_id = v_ws
       AND m.user_id <> v_mgr
       AND NOT public.is_ws_manager(v_ws, m.user_id)
     ORDER BY m.user_id LIMIT 1;

    -- Begona ws a'zosi ((g) sinovi uchun)
    SELECT w2.user_id INTO v_out
      FROM public.workspace_members w2
     WHERE w2.workspace_id <> v_ws
       AND NOT EXISTS (SELECT 1 FROM public.workspace_members w3
                        WHERE w3.workspace_id = v_ws AND w3.user_id = w2.user_id)
     ORDER BY w2.user_id LIMIT 1;

    -- Ikkinchi loyiha ((b) sinovi uchun — bo'lmasa "loyihasiz vazifa" varianti)
    SELECT p.id::text INTO v_p2
      FROM public.projects p
     WHERE p.workspace_id = v_ws AND p.id::text <> v_p1
     ORDER BY p.id LIMIT 1;
  END IF;

  -- tasks.id o'zi to'lanadimi?
  SELECT (column_default IS NOT NULL OR is_identity = 'YES') INTO v_id_auto
    FROM information_schema.columns
   WHERE table_schema='public' AND table_name='tasks' AND column_name='id';
  IF v_ws IS NOT NULL AND NOT coalesce(v_id_auto, false) THEN
    v_ws   := NULL;
    v_skip := 'tasks.id da DEFAULT/IDENTITY yo''q — sinov qatorining id sini skript o''ylab topa olmaydi (taxmin bilan yozmaymiz)';
  END IF;

  -- Ustunlar
  v_has_title := EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema='public' AND table_name='tasks' AND column_name='title');
  v_has_flow  := EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema='public' AND table_name='tasks' AND column_name='flow_order');
  v_has_dpp   := EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema='public' AND table_name='tasks' AND column_name='depends_on_prev');
  v_has_asg   := EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema='public' AND table_name='tasks' AND column_name='assigned_to');
  v_has_cb    := EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema='public' AND table_name='tasks' AND column_name='created_by');
  SELECT (is_nullable='YES') INTO v_prjnull
    FROM information_schema.columns
   WHERE table_schema='public' AND table_name='tasks' AND column_name='project_id';

  IF v_ws IS NOT NULL AND NOT v_has_title THEN
    v_ws   := NULL;
    v_skip := 'tasks.title ustuni yo''q — sinov qatorini taxmin bilan to''ldirmaymiz';
  END IF;

  -- Bilmaydigan MAJBURIY ustun bo'lsa sinov o'tkazilmaydi (23502 ga urilmasin)
  IF v_ws IS NOT NULL THEN
    SELECT string_agg(column_name, ', ') INTO v_bad
      FROM information_schema.columns
     WHERE table_schema='public' AND table_name='tasks'
       AND is_nullable='NO' AND column_default IS NULL AND is_identity='NO'
       AND column_name NOT IN ('id','workspace_id','title','status','project_id',
                               'created_by','assigned_to','flow_order','depends_on_prev');
    IF v_bad IS NOT NULL THEN
      v_ws   := NULL;
      v_skip := 'tasks da noma''lum majburiy ustun(lar) bor: ' || v_bad;
    END IF;
  END IF;

  -- ── (0b) IMPERSONATSIYA HARNESSI ((g) sinovi uchun) ───────────────────────
  --    set_config('request.jwt.claims') haqiqatan auth.uid() ga ta'sir
  --    qiladimi? (Eski auth.uid() 'request.jwt.claim.sub' ni o'qishi mumkin —
  --    u holda sinov SOXTA natija bermasligi uchun o'tkazib yuboriladi.)
  IF v_ws IS NOT NULL AND v_mgr IS NOT NULL THEN
    BEGIN
      PERFORM set_config('request.jwt.claims',
               json_build_object('sub', v_mgr::text, 'role', 'authenticated')::text, true);
      EXECUTE 'SET LOCAL ROLE authenticated';
      EXECUTE 'SELECT (SELECT auth.uid())::text' INTO v_txt;
      EXECUTE 'RESET ROLE';
      PERFORM set_config('request.jwt.claims', '', true);
      v_imp_ok := (v_txt IS NOT DISTINCT FROM v_mgr::text);
    EXCEPTION WHEN OTHERS THEN
      BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
      PERFORM set_config('request.jwt.claims', '', true);
      v_imp_ok := false;
    END;
    IF NOT v_imp_ok THEN
      RAISE WARNING '⚠️ Impersonatsiya harnessi ishlamadi (auth.uid() request.jwt.claims dan o''qimayapti) — (g) RLS sinovlari o''tkazib yuborildi. Qolgan sinovlar bajariladi. Prodga chiqarishdan oldin QO''LDA sinang: begona ws a''zosi kutish qatorlarini KO''RMASLIGI kerak.';
    END IF;
  END IF;

  IF v_ws IS NULL THEN
    RAISE WARNING '⚠️ TIRIK SINOVLAR O''TKAZIB YUBORILDI — %. Struktura va funksiya tanasi tekshiruvlari BAJARILDI; prodga chiqishdan oldin qo''lda sinang.', coalesce(v_skip,'sabab noma''lum');
    INSERT INTO pg_temp.kut_res VALUES
      (60, 'sinov', 'TIRIK SINOVLAR', 'o''tkazib yuborildi', coalesce(v_skip,'sabab noma''lum'));
    RETURN;
  END IF;

  -- ── (0c) SO'ROV SHABLONLARI ──────────────────────────────────────────────
  v_prj1 := quote_literal(v_p1) || '::text::' || v_projtyp;
  IF v_p2 IS NOT NULL THEN
    v_prj2 := quote_literal(v_p2) || '::text::' || v_projtyp;
  END IF;

  --  ⚠️ %L = sarlavha, %s = project_id ifodasi. Boshqa marker YO'Q.
  v_tpl := 'INSERT INTO public.tasks (workspace_id, status, title, project_id'
        || CASE WHEN v_has_flow THEN ', flow_order'      ELSE '' END
        || CASE WHEN v_has_cb   THEN ', created_by'      ELSE '' END
        || CASE WHEN v_has_asg  THEN ', assigned_to'     ELSE '' END
        || CASE WHEN v_has_dpp  THEN ', depends_on_prev' ELSE '' END
        || ') VALUES (' || quote_literal(v_ws::text) || '::uuid, ''new'', %L, %s'
        || CASE WHEN v_has_flow THEN ', 1' ELSE '' END
        || CASE WHEN v_has_cb   THEN ', ' || quote_literal(v_mgr::text) || '::uuid' ELSE '' END
        || CASE WHEN v_has_asg  THEN ', ' || quote_literal(v_mgr::text) || '::uuid' ELSE '' END
        || CASE WHEN v_has_dpp  THEN ', false' ELSE '' END
        || ') RETURNING id::text';

  v_dep_ins := 'INSERT INTO public.task_dependencies (task_id, depends_on_id, workspace_id) VALUES ($1::text::'
            || v_idtype || ', $2::text::' || v_idtype || ', $3)';
  -- workspace_id YUBORILMAYDI — trigger to'ldirishi kerak ((g1) sinovi)
  v_dep_i2  := 'INSERT INTO public.task_dependencies (task_id, depends_on_id) VALUES ($1::text::'
            || v_idtype || ', $2::text::' || v_idtype || ')';
  v_upd     := 'UPDATE public.tasks SET status = $1 WHERE id = $2::text::' || v_idtype;
  v_del     := 'DELETE FROM public.task_dependencies WHERE task_id = $1::text::' || v_idtype;

  -- (g-4) sinovi uchun: BAJARUVCHISI oddiy a'zo bo'lgan vazifa shabloni
  -- (created_by baribir menejer — ya'ni a'zo faqat "bajaruvchi", egasi emas).
  IF v_mem IS NOT NULL AND v_has_asg THEN
    v_tpl2 := 'INSERT INTO public.tasks (workspace_id, status, title, project_id'
           || CASE WHEN v_has_flow THEN ', flow_order' ELSE '' END
           || CASE WHEN v_has_cb   THEN ', created_by' ELSE '' END
           || ', assigned_to'
           || CASE WHEN v_has_dpp  THEN ', depends_on_prev' ELSE '' END
           || ') VALUES (' || quote_literal(v_ws::text) || '::uuid, ''new'', %L, %s'
           || CASE WHEN v_has_flow THEN ', 1' ELSE '' END
           || CASE WHEN v_has_cb   THEN ', ' || quote_literal(v_mgr::text) || '::uuid' ELSE '' END
           || ', ' || quote_literal(v_mem::text) || '::uuid'
           || CASE WHEN v_has_dpp  THEN ', false' ELSE '' END
           || ') RETURNING id::text';
  END IF;
  v_selc    := 'SELECT count(*)::text FROM public.task_dependencies WHERE task_id = $1::text::' || v_idtype;

  -- ══════════════ SENTINEL BLOK (hammasi qaytariladi) ══════════════
  BEGIN
    -- Sinov bosqichlari (hammasi P1 loyihasida, status 'new')
    EXECUTE format(v_tpl, 'KUTISH-SINOV A (sentinel, o''chadi)', v_prj1) INTO v_a;
    EXECUTE format(v_tpl, 'KUTISH-SINOV B (sentinel, o''chadi)', v_prj1) INTO v_b;
    EXECUTE format(v_tpl, 'KUTISH-SINOV E (sentinel, o''chadi)', v_prj1) INTO v_e;
    EXECUTE format(v_tpl, 'KUTISH-SINOV F (sentinel, o''chadi)', v_prj1) INTO v_f;
    EXECUTE format(v_tpl, 'KUTISH-SINOV X (sentinel, o''chadi)', v_prj1) INTO v_x;
    EXECUTE format(v_tpl, 'KUTISH-SINOV Y (sentinel, o''chadi)', v_prj1) INTO v_y;
    EXECUTE format(v_tpl, 'KUTISH-SINOV Z (sentinel, o''chadi)', v_prj1) INTO v_z;
    EXECUTE format(v_tpl, 'KUTISH-SINOV G (sentinel, o''chadi)', v_prj1) INTO v_g;
    EXECUTE format(v_tpl, 'KUTISH-SINOV H (sentinel, o''chadi)', v_prj1) INTO v_h;
    EXECUTE format(v_tpl, 'KUTISH-SINOV I (sentinel, o''chadi)', v_prj1) INTO v_i2;
    IF coalesce(v_prjnull, false) THEN
      EXECUTE format(v_tpl, 'KUTISH-SINOV N (loyihasiz, sentinel)', 'NULL') INTO v_n0;
    END IF;
    IF v_prj2 IS NOT NULL THEN
      EXECUTE format(v_tpl, 'KUTISH-SINOV M (2-loyiha, sentinel)', v_prj2) INTO v_m;
    END IF;
    -- (g-4) uchun: J — bajaruvchisi ODDIY A'ZO, yaratuvchisi menejer; J K ni kutadi
    IF v_tpl2 IS NOT NULL THEN
      BEGIN
        EXECUTE format(v_tpl2, 'KUTISH-SINOV J (bajaruvchi a''zo, sentinel)', v_prj1) INTO v_j;
        EXECUTE format(v_tpl2, 'KUTISH-SINOV K (sentinel, o''chadi)', v_prj1) INTO v_k;
        EXECUTE v_dep_ins USING v_j, v_k, v_ws;
      EXCEPTION WHEN OTHERS THEN v_j := NULL; END;
    END IF;

    -- (a-1) O'ZIGA O'ZI — rad etilishi shart (trigger yoki CHECK)
    BEGIN
      EXECUTE v_dep_ins USING v_a, v_a, v_ws;
      p_self := 'OK';
    EXCEPTION WHEN OTHERS THEN p_self := SQLSTATE; END;

    -- Qonuniy bog'lanish: A B ni kutadi
    BEGIN
      EXECUTE v_dep_ins USING v_a, v_b, v_ws;
      p_ab := 'OK';
    EXCEPTION WHEN OTHERS THEN p_ab := 'E' || SQLSTATE; END;

    -- (a-2) SOF SIKL: B A ni kutsa halqa yopiladi
    BEGIN
      EXECUTE v_dep_ins USING v_b, v_a, v_ws;
      p_cyc2 := 'OK';
    EXCEPTION WHEN OTHERS THEN p_cyc2 := SQLSTATE; END;

    -- (a-3) UZUN SIKL: X→Y, Y→Z (qonuniy), keyin Z→X (halqa)
    BEGIN
      EXECUTE v_dep_ins USING v_x, v_y, v_ws;
      EXECUTE v_dep_ins USING v_y, v_z, v_ws;
      p_chain := 'OK';
    EXCEPTION WHEN OTHERS THEN p_chain := 'E' || SQLSTATE; END;
    BEGIN
      EXECUTE v_dep_ins USING v_z, v_x, v_ws;
      p_cyc3 := 'OK';
    EXCEPTION WHEN OTHERS THEN p_cyc3 := SQLSTATE; END;

    -- (b-1) LOYIHASIZ vazifani kutish — rad etilishi shart
    IF v_n0 IS NOT NULL THEN
      BEGIN
        EXECUTE v_dep_ins USING v_a, v_n0, v_ws;
        p_nullprj := 'OK';
      EXCEPTION WHEN OTHERS THEN p_nullprj := SQLSTATE; END;
    ELSE
      p_nullprj := '-';
    END IF;

    -- (b-2) BOSHQA LOYIHA bosqichini kutish — rad etilishi shart
    IF v_m IS NOT NULL THEN
      BEGIN
        EXECUTE v_dep_ins USING v_a, v_m, v_ws;
        p_p2 := 'OK';
      EXCEPTION WHEN OTHERS THEN p_p2 := SQLSTATE; END;
    ELSE
      p_p2 := '-';
    END IF;

    -- (b-3) workspace_id ni TRIGGER to'g'rilaydimi? Ataylab SOXTA ws yuboramiz.
    --       (FK ham buzilmaydi: FK BEFORE trigger'DAN KEYIN tekshiriladi.)
    BEGIN
      EXECUTE v_dep_ins USING v_e, v_f, '00000000-0000-0000-0000-000000000000'::uuid;
      EXECUTE 'SELECT (workspace_id = $3)::text FROM public.task_dependencies WHERE task_id = $1::text::'
              || v_idtype || ' AND depends_on_id = $2::text::' || v_idtype
        INTO p_wsfix USING v_e, v_f, v_ws;
    EXCEPTION WHEN OTHERS THEN p_wsfix := 'E' || SQLSTATE; END;

    -- (c) 🔴 TO'SIQ: A hali B ni kutyapti — status o'zgarishi RAD ETILSIN
    BEGIN
      EXECUTE v_upd USING 'in_progress', v_a;
      GET DIAGNOSTICS v_i = ROW_COUNT;
      p_block := 'OK' || v_i::text;
    EXCEPTION WHEN OTHERS THEN p_block := SQLSTATE; END;

    -- (d) B tugadi → A O'TISHI kerak
    BEGIN
      EXECUTE v_upd USING 'completed', v_b;
      EXECUTE v_upd USING 'in_progress', v_a;
      GET DIAGNOSTICS v_i = ROW_COUNT;
      p_pass := v_i::text;
    EXCEPTION WHEN OTHERS THEN p_pass := 'E' || SQLSTATE; END;

    -- (e) `cancelled` ham "tugagan": F bekor qilinsa E ochilishi kerak
    BEGIN
      EXECUTE v_upd USING 'cancelled', v_f;
      EXECUTE v_upd USING 'in_progress', v_e;
      GET DIAGNOSTICS v_i = ROW_COUNT;
      p_cancel := v_i::text;
    EXCEPTION WHEN OTHERS THEN p_cancel := 'E' || SQLSTATE; END;

    -- (f) 🔴 REGRESSIYA: dep qatori YO'Q vazifa — AVVALGIDEK o'tishi SHART
    BEGIN
      EXECUTE v_upd USING 'in_progress', v_i2;
      GET DIAGNOSTICS v_i = ROW_COUNT;
      p_free := v_i::text;
      -- va to'g'ridan 'completed' ga ham
      EXECUTE v_upd USING 'completed', v_i2;
    EXCEPTION WHEN OTHERS THEN p_free := 'E' || SQLSTATE; END;

    -- (h) 🔴 BEKOR QILISH BLOKLANGAN BOSQICHDA HAM ISHLAYDI.
    --     Holat: Y hali Z ni kutyapti (Z 'new') → Y BLOKLANGAN.
    --     (h-1) Y "Jarayonda" ga o'ta OLMASLIGI kerak (to'siq tirik),
    --     (h-2) Y "Bekor" ga O'TISHI kerak (istisno),
    --     (h-3) shundan keyin X (Y ni kutayotgan) OCHILISHI kerak.
    BEGIN
      EXECUTE v_upd USING 'in_progress', v_y;
      GET DIAGNOSTICS v_i = ROW_COUNT;
      p_hblk := 'OK' || v_i::text;
    EXCEPTION WHEN OTHERS THEN p_hblk := SQLSTATE; END;
    BEGIN
      EXECUTE v_upd USING 'cancelled', v_y;
      GET DIAGNOSTICS v_i = ROW_COUNT;
      p_hcan := v_i::text;
    EXCEPTION WHEN OTHERS THEN p_hcan := 'E' || SQLSTATE; END;
    BEGIN
      EXECUTE v_upd USING 'in_progress', v_x;
      GET DIAGNOSTICS v_i = ROW_COUNT;
      p_hopen := v_i::text;
    EXCEPTION WHEN OTHERS THEN p_hopen := 'E' || SQLSTATE; END;

    -- (i) 🔴 TESHIK SINOVI (QA 2026-08-21): new → cancelled → completed
    --     bilan qoidani CHETLAB O'TIB BO'LMASLIGI kerak.
    --     H hali Z ni kutadi (Z 'new') → H BLOKLANGAN.
    BEGIN
      EXECUTE v_dep_ins USING v_h, v_z, v_ws;
      EXECUTE v_upd USING 'cancelled', v_h;
      GET DIAGNOSTICS v_i = ROW_COUNT;
      p_icnl := v_i::text;
    EXCEPTION WHEN OTHERS THEN p_icnl := 'E' || SQLSTATE; END;
    BEGIN
      EXECUTE v_upd USING 'completed', v_h;
      GET DIAGNOSTICS v_i = ROW_COUNT;
      p_icomp := 'OK' || v_i::text;
    EXCEPTION WHEN OTHERS THEN p_icomp := SQLSTATE; END;

    -- ── (g) RLS — impersonatsiya bilan ────────────────────────────────────
    IF v_imp_ok THEN
      -- (g-1) ws-MENEJERI qonuniy bog'lanish yozadi. workspace_id
      --       YUBORILMAYDI — trigger to'ldirishi kerak.
      BEGIN
        PERFORM set_config('request.jwt.claims',
                 json_build_object('sub', v_mgr::text, 'role', 'authenticated')::text, true);
        EXECUTE 'SET LOCAL ROLE authenticated';
        EXECUTE v_dep_i2 USING v_g, v_h;
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
        p_mgrins := 'OK';
      EXCEPTION WHEN OTHERS THEN
        BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
        PERFORM set_config('request.jwt.claims', '', true);
        p_mgrins := 'E' || SQLSTATE;
      END;

      -- (g-2) ODDIY A'ZO (menejer emas, vazifa egasi emas):
      --       KO'RADI, lekin YOZA OLMAYDI.
      IF v_mem IS NOT NULL THEN
        BEGIN
          PERFORM set_config('request.jwt.claims',
                   json_build_object('sub', v_mem::text, 'role', 'authenticated')::text, true);
          EXECUTE 'SET LOCAL ROLE authenticated';
          EXECUTE v_selc INTO p_memsel USING v_a;
          EXECUTE 'RESET ROLE';
          PERFORM set_config('request.jwt.claims', '', true);
        EXCEPTION WHEN OTHERS THEN
          BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
          PERFORM set_config('request.jwt.claims', '', true);
          p_memsel := 'E' || SQLSTATE;
        END;
        BEGIN
          PERFORM set_config('request.jwt.claims',
                   json_build_object('sub', v_mem::text, 'role', 'authenticated')::text, true);
          EXECUTE 'SET LOCAL ROLE authenticated';
          EXECUTE v_dep_i2 USING v_g, v_i2;
          EXECUTE 'RESET ROLE';
          PERFORM set_config('request.jwt.claims', '', true);
          p_memins := 'OK';
        EXCEPTION WHEN OTHERS THEN
          BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
          PERFORM set_config('request.jwt.claims', '', true);
          p_memins := SQLSTATE;
        END;
      ELSE
        p_memsel := '-'; p_memins := '-';
      END IF;

      -- (g-3) 🔴 BEGONA ws a'zosi: KO'RMAYDI va YOZA OLMAYDI
      IF v_out IS NOT NULL THEN
        BEGIN
          PERFORM set_config('request.jwt.claims',
                   json_build_object('sub', v_out::text, 'role', 'authenticated')::text, true);
          EXECUTE 'SET LOCAL ROLE authenticated';
          EXECUTE v_selc INTO p_outsel USING v_a;
          EXECUTE 'RESET ROLE';
          PERFORM set_config('request.jwt.claims', '', true);
        EXCEPTION WHEN OTHERS THEN
          BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
          PERFORM set_config('request.jwt.claims', '', true);
          p_outsel := 'E' || SQLSTATE;
        END;
        BEGIN
          PERFORM set_config('request.jwt.claims',
                   json_build_object('sub', v_out::text, 'role', 'authenticated')::text, true);
          EXECUTE 'SET LOCAL ROLE authenticated';
          EXECUTE v_dep_i2 USING v_g, v_i2;
          EXECUTE 'RESET ROLE';
          PERFORM set_config('request.jwt.claims', '', true);
          p_outins := 'OK';
        EXCEPTION WHEN OTHERS THEN
          BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
          PERFORM set_config('request.jwt.claims', '', true);
          p_outins := 'E' || SQLSTATE;
        END;
      ELSE
        p_outsel := '-'; p_outins := '-';
      END IF;
      -- (g-4) 🔴 BAJARUVCHI (menejer EMAS, yaratuvchi EMAS) bog'lanishni
      --       O'CHIRA OLMAYDI. Busiz bloklangan bosqich bajaruvchisi o'zini
      --       bloklab turgan qatorni o'chirib, keyin statusni o'zgartirardi.
      --       ⚠️ RLS DELETE ni JIMGINA filtrlaydi → kutilgan natija: 0 qator.
      IF v_j IS NOT NULL THEN
        BEGIN
          PERFORM set_config('request.jwt.claims',
                   json_build_object('sub', v_mem::text, 'role', 'authenticated')::text, true);
          EXECUTE 'SET LOCAL ROLE authenticated';
          EXECUTE v_del USING v_j;
          GET DIAGNOSTICS v_i = ROW_COUNT;
          EXECUTE 'RESET ROLE';
          PERFORM set_config('request.jwt.claims', '', true);
          p_asgdel := v_i::text;
        EXCEPTION WHEN OTHERS THEN
          BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
          PERFORM set_config('request.jwt.claims', '', true);
          p_asgdel := 'E' || SQLSTATE;
        END;
      ELSE
        p_asgdel := '-';
      END IF;

      -- (g-5) IJOBIY NAZORAT: ws-MENEJERI o'zi qo'shgan bog'lanishni o'chira
      --       oladi (aks holda modul foydalanuvchi uchun ishlamasdi).
      BEGIN
        PERFORM set_config('request.jwt.claims',
                 json_build_object('sub', v_mgr::text, 'role', 'authenticated')::text, true);
        EXECUTE 'SET LOCAL ROLE authenticated';
        EXECUTE v_del USING v_g;
        GET DIAGNOSTICS v_i = ROW_COUNT;
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
        p_mgrdel := v_i::text;
      EXCEPTION WHEN OTHERS THEN
        BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
        PERFORM set_config('request.jwt.claims', '', true);
        p_mgrdel := 'E' || SQLSTATE;
      END;
    ELSE
      p_mgrins := '-'; p_memsel := '-'; p_memins := '-';
      p_outsel := '-'; p_outins := '-';
      p_asgdel := '-'; p_mgrdel := '-';
    END IF;

    -- ⚠️ SENTINEL: subtranzaksiyani ATAYLAB qaytaramiz.
    RAISE EXCEPTION 'KUT_PROBE:%',
      coalesce(p_self,'?')   || '|' || coalesce(p_ab,'?')     || '|' ||
      coalesce(p_cyc2,'?')   || '|' || coalesce(p_chain,'?')  || '|' ||
      coalesce(p_cyc3,'?')   || '|' || coalesce(p_nullprj,'?')|| '|' ||
      coalesce(p_p2,'?')     || '|' || coalesce(p_wsfix,'?')  || '|' ||
      coalesce(p_block,'?')  || '|' || coalesce(p_pass,'?')   || '|' ||
      coalesce(p_cancel,'?') || '|' || coalesce(p_free,'?')   || '|' ||
      coalesce(p_mgrins,'?') || '|' || coalesce(p_memsel,'?') || '|' ||
      coalesce(p_memins,'?') || '|' || coalesce(p_outsel,'?') || '|' ||
      coalesce(p_outins,'?') || '|' ||
      coalesce(p_hblk,'?')   || '|' || coalesce(p_hcan,'?')   || '|' ||
      coalesce(p_hopen,'?')  || '|' ||
      coalesce(p_icnl,'?')   || '|' || coalesce(p_icomp,'?')  || '|' ||
      coalesce(p_asgdel,'?') || '|' || coalesce(p_mgrdel,'?')
      USING ERRCODE = '22000';

  EXCEPTION WHEN OTHERS THEN
    BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM set_config('request.jwt.claims', '', true);

    IF SQLERRM NOT LIKE 'KUT_PROBE:%' THEN
      -- Harness xatosi — bu XAVFSIZLIK xatosi EMAS, migratsiya to'xtatilmaydi,
      -- lekin jimgina ham yutilmaydi (CLAUDE.md 6-qoida).
      v_skip := 'sinov qatorlarini yozib bo''lmadi (' || SQLSTATE || '): ' || left(SQLERRM, 200);
      RAISE WARNING '⚠️ TIRIK SINOV O''TKAZIB YUBORILDI — %. Struktura tekshiruvlari bajarildi; prodga chiqishdan oldin QO''LDA sinang.', v_skip;
      INSERT INTO pg_temp.kut_res VALUES
        (60, 'sinov', 'TIRIK SINOVLAR', 'o''tkazib yuborildi', v_skip);
      RETURN;
    END IF;

    v_probe   := replace(SQLERRM, 'KUT_PROBE:', '');
    p_self    := split_part(v_probe, '|', 1);
    p_ab      := split_part(v_probe, '|', 2);
    p_cyc2    := split_part(v_probe, '|', 3);
    p_chain   := split_part(v_probe, '|', 4);
    p_cyc3    := split_part(v_probe, '|', 5);
    p_nullprj := split_part(v_probe, '|', 6);
    p_p2      := split_part(v_probe, '|', 7);
    p_wsfix   := split_part(v_probe, '|', 8);
    p_block   := split_part(v_probe, '|', 9);
    p_pass    := split_part(v_probe, '|', 10);
    p_cancel  := split_part(v_probe, '|', 11);
    p_free    := split_part(v_probe, '|', 12);
    p_mgrins  := split_part(v_probe, '|', 13);
    p_memsel  := split_part(v_probe, '|', 14);
    p_memins  := split_part(v_probe, '|', 15);
    p_outsel  := split_part(v_probe, '|', 16);
    p_outins  := split_part(v_probe, '|', 17);
    p_hblk    := split_part(v_probe, '|', 18);
    p_hcan    := split_part(v_probe, '|', 19);
    p_hopen   := split_part(v_probe, '|', 20);
    p_icnl    := split_part(v_probe, '|', 21);
    p_icomp   := split_part(v_probe, '|', 22);
    p_asgdel  := split_part(v_probe, '|', 23);
    p_mgrdel  := split_part(v_probe, '|', 24);

    -- ══════════════ HUKMLAR ══════════════
    -- Qonuniy bog'lanish yozilmasa qolgan sinovlar ma'nosiz
    IF p_ab <> 'OK' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI: QONUNIY bog''lanish (A B ni kutadi) yozilmadi — %. Modul umuman ishlamasdi. HAMMASI QAYTARILDI.', p_ab;
    END IF;
    IF p_chain <> 'OK' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI: qonuniy X→Y→Z zanjiri yozilmadi — %. HAMMASI QAYTARILDI.', p_chain;
    END IF;

    -- (a) SIKL
    IF p_self = 'OK' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (a): bosqich O''ZINI O''ZI kutadigan qator YOZILDI. CHECK ham, trigger ham to''smadi. HAMMASI QAYTARILDI.';
    END IF;
    IF p_cyc2 = 'OK' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (a): SOF SIKL (A→B→A) yozildi — sikl qorovuli ishlamadi. HAMMASI QAYTARILDI.';
    END IF;
    IF p_cyc3 = 'OK' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (a): UZUN SIKL (X→Y→Z→X) yozildi — recursive CTE zanjirni ko''rmadi. HAMMASI QAYTARILDI.';
    END IF;
    t_cyc := '✅ A↔A: ' || p_self || ' · A→B→A: ' || p_cyc2 || ' · X→Y→Z→X: ' || p_cyc3;

    -- (b) BIR LOYIHA SHARTI
    IF p_nullprj = 'OK' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (b): LOYIHASIZ vazifaga bog''lanish yozildi — "kutish faqat loyiha bosqichlari uchun" sharti ishlamadi (SPEC 6). HAMMASI QAYTARILDI.';
    END IF;
    IF p_p2 = 'OK' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (b): BOSHQA LOYIHA bosqichiga bog''lanish yozildi (SPEC 5.4). HAMMASI QAYTARILDI.';
    END IF;
    IF p_nullprj = '-' AND p_p2 = '-' THEN
      t_prj := '❗ sinalmadi (2-loyiha ham, loyihasiz vazifa ham yo''q) — QO''LDA sinang';
      RAISE WARNING '⚠️ (b) sinovi o''tkazilmadi: bazada ikkinchi loyiha ham, "loyihasiz vazifa" imkoniyati ham topilmadi. Qorovul KODDA bor va tanasi tekshirildi, lekin TIRIK sinalmadi.';
    ELSE
      t_prj := '✅ loyihasiz: ' || p_nullprj || ' · boshqa loyiha: ' || p_p2;
    END IF;
    IF p_wsfix <> 'true' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI: trigger workspace_id ni vazifadan olib to''g''rilamadi (natija: %). Mijoz yuborgan soxta workspace_id bazaga tushardi va RLS o''sha qiymatga qarab ishlardi. HAMMASI QAYTARILDI.', p_wsfix;
    END IF;

    -- (c) TO'SIQ
    IF p_block <> 'P0001' THEN
      IF left(p_block, 2) = 'OK' THEN
        RAISE EXCEPTION 'TIRIK SINOV YIQILDI (c): kutilayotgan bosqich TUGAMAGAN bo''lsa ham status o''zgardi (% qator). Server to''sig''i ISHLAMADI — modulning butun ma''nosi shu edi. HAMMASI QAYTARILDI.', replace(p_block,'OK','');
      END IF;
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (c): status o''zgarishi KUTILMAGAN xato bilan tugadi (%) — kutilgani P0001 (bizning o''zbekcha xato). HAMMASI QAYTARILDI.', p_block;
    END IF;
    t_blk := '✅ rad etildi (P0001)';

    -- (d) hammasi tugagach o'tadi
    IF p_pass <> '1' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (d): kutilayotgan bosqich TUGAGANDAN KEYIN ham status o''zgarmadi (%). Bosqich abadiy qulflanib qolardi. HAMMASI QAYTARILDI.', p_pass;
    END IF;
    t_pas := '✅ 1 qator';

    -- (e) cancelled = tugagan
    IF p_cancel <> '1' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (e): kutilayotgan bosqich BEKOR qilingandan keyin ham status o''zgarmadi (%) — "cancelled = tugagan" ta''rifi mijozdagidan (prjTaskOpen) farq qilyapti. HAMMASI QAYTARILDI.', p_cancel;
    END IF;
    t_can := '✅ 1 qator';

    -- (f) 🔴 REGRESSIYA
    IF p_free <> '1' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (f) 🔴 REGRESSIYA: dep qatori BO''LMAGAN oddiy vazifaning statusini o''zgartirib bo''lmadi (%). Yangi trigger BUTUN ILOVANI buzgan bo''lardi. HAMMASI QAYTARILDI.', p_free;
    END IF;
    t_fre := '✅ 1 qator (dep qatori yo''q vazifa AVVALGIDEK ishlaydi)';

    -- (h) 🔴 BEKOR QILISH TO'SILMAYDI
    IF p_hblk <> 'P0001' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (h): sinov sharti buzilgan — Y bosqichi BLOKLANGAN bo''lishi kerak edi (Z hali tugamagan), lekin "Jarayonda" ga o''tkazish % bilan tugadi (kutilgan P0001). HAMMASI QAYTARILDI.', p_hblk;
    END IF;
    IF p_hcan <> '1' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (h) 🔴: BLOKLANGAN bosqichni BEKOR qilib bo''lmadi (%). Bekor qilish — vazifani BAJARISH emas, administrativ chiqish yo''li; to''silsa odam tuzoqqa tushardi va zanjir qotib qolardi. HAMMASI QAYTARILDI.', p_hcan;
    END IF;
    IF p_hopen <> '1' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (h): BEKOR qilingan bosqichni kutayotgan keyingi bosqich OCHILMADI (%) — mijozdagi depUnmet bilan ZID (u yerda cancelled "bajarilgan" hisoblanadi). HAMMASI QAYTARILDI.', p_hopen;
    END IF;
    t_hcn := '✅ bloklangan holat: P0001 · bekor: 1 qator · keyingisi ochildi: 1 qator';

    -- (i) 🔴 TESHIK: cancelled orqali chetlab o'tish
    IF p_icnl <> '1' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (i): bloklangan bosqichni BEKOR qilib bo''lmadi (%) — (h) bilan zid, sinov sharti buzilgan. HAMMASI QAYTARILDI.', p_icnl;
    END IF;
    IF p_icomp <> 'P0001' THEN
      IF left(p_icomp, 2) = 'OK' THEN
        RAISE EXCEPTION 'QOIDA BUZILDI (i) 🔴: BLOKLANGAN bosqich new → cancelled → completed yo''li bilan TUGALLANDI. Kutish qoidasini kanbanda IKKI SUDRASH bilan chetlab o''tish mumkin edi. HAMMASI QAYTARILDI.';
      END IF;
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (i): kutilmagan xato % (kutilgan P0001). HAMMASI QAYTARILDI.', p_icomp;
    END IF;
    t_icn := '✅ bekor: 1 qator · bekordan "Bajarildi" ga: P0001 (RAD ETILDI)';

    -- (g) RLS
    IF p_mgrins = '-' THEN
      t_rls := '❗ sinalmadi (impersonatsiya harnessi ishlamadi) — QO''LDA sinang';
    ELSE
      IF p_mgrins <> 'OK' THEN
        RAISE EXCEPTION 'TIRIK SINOV YIQILDI (g): ws-MENEJERI bog''lanish qo''sha olmadi (%) — policy yoki grant noto''g''ri, modul foydalanuvchi uchun ishlamasdi. HAMMASI QAYTARILDI.', p_mgrins;
      END IF;
      IF p_memins = 'OK' THEN
        RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (g): vazifa egasi BO''LMAGAN oddiy a''zo bog''lanish yozib qo''ydi. INSERT policy ishlamadi. HAMMASI QAYTARILDI.';
      END IF;
      -- ⚠️ Xato (E42501 va h.k.) — "KO'RDI" degani EMAS, bu ham RAD ETISH.
      --    Yolg'on "XAVFSIZLIK BUZILDI" sababi chiqmasin (QA 2026-08-21).
      IF p_outsel <> '-' AND left(p_outsel, 1) = 'E' THEN
        RAISE WARNING '⚠️ (g): begona ws a''zosining SELECT so''rovi XATO bilan tugadi (%) — qator KO''RINMADI (ya''ni rad etildi), lekin sabab RLS emas. Tekshirib qo''ying.', p_outsel;
      ELSIF p_outsel <> '-' AND p_outsel <> '0' THEN
        RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (g): BEGONA workspace a''zosi kutish qatorlarini KO''RDI (% qator). SELECT policy ishlamadi. HAMMASI QAYTARILDI.', p_outsel;
      END IF;
      IF p_outins = 'OK' THEN
        RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (g): BEGONA workspace a''zosi bog''lanish YOZDI. HAMMASI QAYTARILDI.';
      END IF;
      -- (g-4) 🔴 bajaruvchi o'chira olmasligi SHART
      IF p_asgdel <> '-' AND left(p_asgdel, 1) <> 'E' AND p_asgdel <> '0' THEN
        RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (g-4) 🔴: vazifa BAJARUVCHISI kutish qatorini O''CHIRDI (% qator) — u o''zini bloklab turgan bog''lanishni olib tashlab, keyin statusni bemalol o''zgartira olardi. DELETE policy juda keng. HAMMASI QAYTARILDI.', p_asgdel;
      END IF;
      IF p_mgrins = 'OK' AND p_mgrdel <> '-' AND p_mgrdel <> '1' THEN
        RAISE EXCEPTION 'TIRIK SINOV YIQILDI (g-5): ws-MENEJERI o''zi qo''shgan bog''lanishni O''CHIRA OLMADI (%) — DELETE policy juda tor, modul foydalanuvchi uchun ishlamasdi. HAMMASI QAYTARILDI.', p_mgrdel;
      END IF;
      IF p_memsel <> '-' AND left(p_memsel,1) = 'E' THEN
        RAISE WARNING '⚠️ (g): oddiy a''zoning SELECT so''rovi xato berdi (%) — kutish grafigi unga ko''rinmasligi mumkin.', p_memsel;
      ELSIF p_memsel <> '-' AND p_memsel = '0' THEN
        RAISE WARNING '⚠️ (g): oddiy a''zo O''Z ws idagi kutish qatorini KO''RMADI (0 qator). SELECT policy juda tor — kartada "kutmoqda" belgisi chizilmasligi mumkin.';
      END IF;
      t_rls := '✅ menejer YOZDI/O''CHIRDI (' || p_mgrdel || ') · a''zo YOZOLMADI (' || p_memins ||
               ') · 🔴 BAJARUVCHI O''CHIROLMADI (' || p_asgdel ||
               ') · begona KO''RMADI (' || p_outsel || ') va YOZOLMADI (' || p_outins ||
               ') · a''zo ko''rgan qator: ' || p_memsel;
    END IF;

    INSERT INTO pg_temp.kut_res VALUES
      (60, 'sinov', '(a) 🔴 SIKL rad etiladi', t_cyc,
           'A↔A (CHECK+trigger) · A→B→A (sof sikl) · X→Y→Z→X (uzun sikl, recursive CTE)'),
      (61, 'sinov', '(b) bir loyiha sharti', t_prj,
           'loyihasiz vazifa va boshqa loyiha bosqichi rad etiladi (SPEC 5.4 / 6)'),
      (62, 'sinov', 'workspace_id ni SERVER yozadi', '✅ ' || p_wsfix,
           'ataylab soxta ws yuborildi — trigger vazifadan olib to''g''riladi (FK ham buzilmadi)'),
      (63, 'sinov', '(c) 🔴 kutilayotgan bosqich tugamagan → RAD ETILDI', t_blk,
           'status ''new'' dan ''in_progress'' ga o''ta olmadi — modulning asosiy ma''nosi'),
      (64, 'sinov', '(d) hammasi tugagach O''TADI', t_pas,
           'kutilayotgan bosqich completed bo''lgach status o''zgardi'),
      (65, 'sinov', '(e) `cancelled` ham "tugagan"', t_can,
           'mijozdagi prjTaskOpen ta''rifi bilan bir xil (SPEC 6)'),
      (66, 'sinov', '(f) 🔴 REGRESSIYA — dep qatori YO''Q vazifa', t_fre,
           'oddiy vazifaning statusi AVVALGIDEK o''zgardi: yangi trigger ta''siri NOL'),
      (67, 'sinov', '(h) 🔴 BEKOR QILISH to''silmaydi', t_hcn,
           'bloklangan bosqich ''cancelled'' ga o''tadi va shundan keyin unga bog''langan bosqich OCHILADI (mijozdagi depUnmet bilan bir xil)'),
      (68, 'sinov', '(i) 🔴 cancelled orqali chetlab o''tib bo''lmaydi', t_icn,
           'new → cancelled → completed yo''li YOPIQ: OLD.status qorovuli ''new'' VA ''cancelled'' ni qamraydi (QA 2026-08-21)'),
      (69, 'sinov', '(g) RLS — kim ko''radi / kim yozadi / kim O''CHIRADI', t_rls,
           'begona ws a''zosi KO''RMASLIGI va YOZA OLMASLIGI shart · 🔴 vazifa BAJARUVCHISI bog''lanishni O''CHIRA OLMASLIGI shart (g-4)');

    RAISE NOTICE '✅ TIRIK SINOVLAR O''TDI — sentinel-rollback: bazada bitta qator ham QOLMADI.';
  END;
END $live$;


-- ════════════════════════════════════════════════════════════════════════════
-- 9) YAKUNIY HISOBOT
-- ════════════════════════════════════════════════════════════════════════════
DO $rep$
DECLARE
  v_idtype text;
  v_acc    text;
  v_wsref  text;
  v_usrref text;
  v_trg    int;
  v_skipn  int;
  v_okn    int;
BEGIN
  SELECT v INTO v_idtype FROM pg_temp.kut_ref WHERE k='idtype';
  SELECT v INTO v_acc    FROM pg_temp.kut_ref WHERE k='acceptor';
  SELECT v INTO v_wsref  FROM pg_temp.kut_ref WHERE k='wsref';
  SELECT v INTO v_usrref FROM pg_temp.kut_ref WHERE k='usrref';

  SELECT count(*) INTO v_trg
    FROM pg_trigger
   WHERE tgrelid='public.tasks'::regclass AND NOT tgisinternal;

  INSERT INTO pg_temp.kut_res VALUES
    (1,  'jadval', 'public.task_dependencies', 'bor',
         'task_id / depends_on_id tipi: ' || coalesce(v_idtype,'?') ||
         ' (tasks.id dan KATALOGDAN olindi). PK (task_id, depends_on_id) + CHECK (task_id <> depends_on_id)'),
    (2,  'FK', 'task_id / depends_on_id → public.tasks(id)', 'ON DELETE CASCADE',
         'SPEC 6: bosqich o''chirilsa bog''lanish qatori ham o''chadi'),
    (3,  'FK', 'workspace_id / created_by', coalesce(v_wsref,'FK YO''Q') || ' · ' || coalesce(v_usrref,'FK YO''Q'),
         'nishonlar tasks.workspace_id / tasks.created_by FK laridan olindi (taxmin YO''Q)'),
    (4,  'indeks', 'idx_task_dependencies_dep · idx_task_dependencies_ws', 'bor',
         'depends_on_id — "meni kim kutyapti?" so''rovi uchun (PK faqat task_id ni qoplaydi)'),
    (5,  'funksiya', format('task_dep_would_cycle(%s, %s)', coalesce(v_idtype,'?'), coalesce(v_idtype,'?')), 'yaratildi',
         '🔴 SIKL: recursive CTE (p_dep dan p_task ga yo''l bormi) + path massivi + depth<64 + tugun chegarasi (FAIL-CLOSED). SECURITY DEFINER, mijozga EXECUTE BERILMAGAN'),
    (6,  'trigger', 'task_dependencies_guard_trg (BEFORE INSERT OR UPDATE)', 'bor',
         'bir loyiha sharti · workspace_id ni SERVER yozadi · created_by ni SERVER yozadi · o''ziga o''zi rad · SIKL rad · JWT bo''lsa a''zolik'),
    (7,  'trigger', '🔴 zz_task_wait_guard_trg ON public.tasks (BEFORE UPDATE OF status)', 'bor',
         'status ''new'' dan chiqayotganda kutilayotgan bosqich qolgan bo''lsa RAISE EXCEPTION. Dep qatori YO''Q vazifaga ta''sir NOL. Nomi `zz_` — mavjud ' || (v_trg - 1)::text || ' ta tasks trigger''idan KEYIN ishlaydi va hech qanday ustunni O''ZGARTIRMAYDI'),
    (8,  'funksiya', format('can_edit_task_deps(%s, uuid)', coalesce(v_idtype,'?')), 'yaratildi',
         'SECURITY DEFINER · STABLE · faqat authenticated EXECUTE · 2 MAJBURIY qorovul (p_user = auth.uid() va is_ws_member)' ||
         ' · 🔴 huquq: is_ws_manager YOKI tasks.created_by — assigned_to / acceptor_id ATAYLAB YO''Q (bajaruvchi o''zini bloklab turgan qatorni o''chira olmasin)'),
    (9,  'RLS', 'task_deps_select / _insert / _delete', '3 policy',
         'SELECT — ws a''zosi (is_ws_member) · INSERT/DELETE — ws-menejeri YOKI vazifa YARATUVCHISI (can_edit_task_deps). UPDATE policy ATAYLAB yo''q: qator o''zgarmas'),
    (10, 'grant', 'authenticated: SELECT/INSERT/DELETE · anon: HECH NARSA', 'tekshirildi',
         'anon uchun grant ham, policy ham yo''q; can_edit_task_deps anon ga EXECUTE bermaydi'),
    (11, 'qaror', '🔴 server roli (service_role / EF / TG-bot) uchun ISTISNO', 'YO''Q',
         'Kutish — BIZNES qoidasi, ruxsat masalasi emas. Istisno bo''lsa ilovada bloklangan amal bot orqali o''tib ketardi va tizim ZID ishlardi. Xato matni EF loglarida ham o''zbekcha + HINT ichida task_id bilan chiqadi. Ochish kerak bo''lsa: task_wait_guard() boshidagi bitta izohli qator'),
    (12, 'qaror', 'to''siq nuqtasi: ''new'' dan chiqish', 'SPEC 4 bo''yicha',
         '🔴 ''cancelled'' ISTISNO: bekor qilish HAR DOIM mumkin (bajarish emas, administrativ chiqish yo''li) — aks holda bloklangan bosqichni bekor qilish uchun bog''lanishni o''chirish kerak bo''lardi va zanjir qotib qolardi. Bekor qilingan bosqich unga bog''langanlarni OCHADI (mijozdagi depUnmet bilan bir xil). ''in_progress''/''completed'' esa to''siladi. Sinov: (h)'),
    (13, 'qaror', 'is_locked ga YOZILMAYDI', 'SPEC 3',
         '34-migratsiya trigger''i is_locked ning yagona egasi. Kutish unga yozilsa "qulf qotib qolgan" ziddiyati paydo bo''lardi'),
    (14, 'eslatma', 'rejim (wait/sequential/parallel) SAQLANMAYDI', 'SPEC 2',
         'dep qatori BOR → wait · aks holda depends_on_prev → sequential · aks holda parallel. Yangi ustun QO''SHILMADI (ikki manba ziddiyati bo''lmasin)');

  -- 🔴 QA (2026-08-21): tirik sinov O'TKAZIB YUBORILGAN bo'lsa ham migratsiya
  --    COMMIT bo'ladi (faqat HUKM salbiy bo'lganda qaytadi). Shuning uchun
  --    holat ENG OXIRGI qatorda ko'zga tashlanadigan qilib yoziladi.
  SELECT count(*) INTO v_skipn FROM pg_temp.kut_res
   WHERE bosqich = 'sinov'
     AND (qiymat LIKE '❗%' OR qiymat LIKE '—%' OR qiymat LIKE 'o''tkazib%');
  SELECT count(*) INTO v_okn FROM pg_temp.kut_res
   WHERE bosqich = 'sinov' AND qiymat LIKE '✅%';

  INSERT INTO pg_temp.kut_res VALUES
    (99, 'XULOSA',
     CASE WHEN v_skipn = 0 THEN '✅ TIRIK SINOVLAR TO''LIQ BAJARILDI'
          ELSE '🔴 DIQQAT: ' || v_skipn::text || ' ta sinov O''TKAZIB YUBORILDI' END,
     v_okn::text || ' ta ✅ / ' || v_skipn::text || ' ta o''tkazilgan',
     CASE WHEN v_skipn = 0
          THEN 'Har bir hukm chiqarildi; birortasi salbiy bo''lganda skript COMMIT QILMAGAN bo''lardi.'
          ELSE '⚠️ Migratsiya COMMIT BO''LDI, lekin o''tkazib yuborilgan holat(lar) QO''LDA sinalishi SHART — sabab yuqoridagi "sinov" qatorlarida yozilgan.' END);

  IF v_skipn > 0 THEN
    RAISE WARNING '⚠️ % ta tirik sinov o''tkazib yuborildi — migratsiya baribir COMMIT bo''ldi. Yakuniy jadvalning XULOSA qatoriga va sabablarga qarang.', v_skipn;
  END IF;

  RAISE NOTICE '════ TUGADI — pastdagi jadvalga qarang ════';
END $rep$;

COMMIT;


-- ══════════ NATIJA ══════════
SELECT bosqich, nom, qiymat, izoh FROM pg_temp.kut_res ORDER BY ord;


-- ============================================================================
-- QANDAY O'QISH
-- ============================================================================
--  • Barcha "sinov" qatorlari "✅" bo'lsa ish bitdi.
--  • 🔴 ENG MUHIM QATORLAR: (c) to'siq ishlaydi · (f) regressiya yo'q ·
--    (i) cancelled orqali chetlab o'tib bo'lmaydi · (g) begona ko'rmaydi.
--    ⚠️ ANIQLIK (QA 2026-08-21): sinov HUKM CHIQARSA va u salbiy bo'lsa
--    skript COMMIT qilmaydi. LEKIN sinov UMUMAN o'tkazilmagan bo'lishi ham
--    mumkin (bazada mos ma'lumot yo'q / sinov qatorini yozib bo'lmadi /
--    impersonatsiya harnessi ishlamadi) — u holda migratsiya WARNING bilan
--    COMMIT BO'LADI. Shuning uchun yakuniy jadvalning ENG OXIRGI "XULOSA"
--    qatoriga qarang: u sinovlar bajarilgan-bajarilmaganini ochiq aytadi.
--  • "❗ sinalmadi" — bazada mos ma'lumot topilmadi (masalan ikkinchi loyiha
--    yoki begona ws a'zosi yo'q) yoki impersonatsiya harnessi ishlamadi.
--    Bu XATO emas, lekin o'sha holatni QO'LDA sinash kerak.
--  • "TIRIK SINOVLAR · o'tkazib yuborildi" — sabab o'sha qatorda yozilgan.
--    Struktura va funksiya tanasi tekshiruvlari baribir bajarilgan.
--
-- ── 🔴 RUN'DAN KEYIN — MIJOZ TOMONIDA (boshqa agent) ────────────────────────
--   1) Tur tanlash: "Ketma-ket" (`depends_on_prev = true`) · "Parallel"
--      (`false`) · "Kutish" (task_dependencies qatorlari).
--      🔴 "Kutish" tanlanganda `depends_on_prev = false` YOZILADI — ikki qulf
--         mexanizmi bir vaqtda ishlab bosqich ikki marta bloklanmasin (SPEC 2).
--   2) Rejim HISOBLANADI: `prjDepMode(t, depMap)` — dep qatori bor → 'wait',
--      aks holda depends_on_prev → 'sequential', aks holda 'parallel'.
--      Yangi `dep_mode` ustuni QO'SHILMAYDI.
--   3) Ko'rsatish darvozasi: `prjTaskOpen` / `prjShouldBeOpen` ga yangi shox —
--      dep bor va ularning hammasi `completed|cancelled` emas → OCHIQ EMAS.
--      🔴 `prjShouldBeOpenSeq` (is_locked ga yozadigan yagona joy) TEGILMAYDI.
--   4) Tanlash ro'yxatida FAQAT tepadagi bosqichlar (`flow_order` kichik, bir
--      loyiha) — sikl himoyasining 1-qatlami (SPEC 5.1).
--   5) Xatolar `translateErr()` orqali ko'rsatiladi (CLAUDE.md 6-qoida).
--      Server qaytaradigan matnlar (o'zbekcha, xom Postgres emas):
--        • 'Bu bosqich hali ochilmagan: N ta kutilayotgan bosqich ...'
--        • 'Sikl: bu bog''lanish halqa hosil qiladi ...'
--        • 'Bosqichlar BITTA loyihada bo''lishi shart ...'
--        • 'Kutish faqat LOYIHA bosqichlari uchun ...'
--        • 'Bu ish maydoni sizga ochiq emas.' (42501)
--   6) Har so'rovda `{ error }` DOIM tekshiriladi va `.select()` bilan qator
--      soni ham (RLS jimgina to'smasin).
--   7) 🔴 `workspace_id` ni mijoz YUBORMASA ham bo'ladi — trigger o'zi
--      to'ldiradi (yuborilgani baribir BOSILADI). `created_by` ham shunday.
--   8) Jadval yo'q bazada (bu fayl RUN qilinmagan) ilova AVVALGIDEK ishlashi
--      shart: 42P01 / PGRST205 → sababni OCHIQ aytadi, "kutish" ro'yxati
--      bo'sh, tur `sequential`/`parallel` bo'lib ko'rinadi.
--   9) `prjApplyTypeToTasks` (loyiha turini hamma bosqichga qo'llash) `wait`
--      bosqichlarga TEGMASIN (SPEC 6) — aks holda qo'lda qurilgan bog'liqlik
--      jimgina o'chib ketardi.
--
-- ============================================================================
-- QAYTARISH (ROLLBACK) — kerak bo'lsa, TARTIB MUHIM
-- ============================================================================
--   -- 1) tasks ustidagi TO'SIQ (ilova darrov avvalgi holatga qaytadi)
--   DROP TRIGGER IF EXISTS zz_task_wait_guard_trg ON public.tasks;
--   DROP FUNCTION IF EXISTS public.task_wait_guard();
--   -- 2) bog'lanish jadvalining qorovuli
--   DROP TRIGGER IF EXISTS task_dependencies_guard_trg ON public.task_dependencies;
--   DROP FUNCTION IF EXISTS public.task_dependencies_guard();
--   -- 3) policy'lar (funksiyaga bog'liq — funksiyadan OLDIN)
--   DROP POLICY IF EXISTS task_deps_select ON public.task_dependencies;
--   DROP POLICY IF EXISTS task_deps_insert ON public.task_dependencies;
--   DROP POLICY IF EXISTS task_deps_delete ON public.task_dependencies;
--   -- 4) yordamchi funksiyalar (imzodagi tip = tasks.id tipi — hisobotning
--   --    1-qatorida yozilgan; odatda uuid)
--   -- DROP FUNCTION IF EXISTS public.can_edit_task_deps(uuid, uuid);
--   -- DROP FUNCTION IF EXISTS public.task_dep_would_cycle(uuid, uuid);
--   -- 5) ⚠️ JADVAL — faqat MA'LUMOT KERAK EMASLIGIGA ishonch bo'lsa
--   --    (bu yerda foydalanuvchi qurgan butun kutish grafigi yotadi):
--   -- DROP TABLE IF EXISTS public.task_dependencies;
--
--   🔴 REGRESSIYA BO'LSA butun migratsiyani qaytarish SHART EMAS: 1-qadam
--      (trigger) yetadi — jadval, ma'lumot va RLS joyida qoladi, mijozdagi
--      "kutmoqda" ko'rinishi ishlayveradi, faqat server to'sig'i o'chadi.
-- ============================================================================


-- ============================================================================
-- RUN'DAN KEYINGI TAVSIYA — hech narsani o'zgartirmaydi, faqat xabar beradi.
-- (Tranzaksiyadan TASHQARIDA: COMMIT allaqachon bo'lgan.)
-- ============================================================================
DO $post$
BEGIN
  RAISE NOTICE '════════ RUN''DAN KEYIN NIMA QILINADI ════════';

  RAISE NOTICE '1) 🔴 ENG TEZ TEKSHIRUV (1 daqiqa): ilovadan bitta oddiy (loyihasiz) vazifaning statusini o''zgartiring — u AVVALGIDEK ishlashi shart. Keyin ikkita bosqichni "Kutish" bilan bog''lab, kutilayotgani tugamasdan turib keyingisini "Jarayonda" ga o''tkazib ko''ring — o''zbekcha xato chiqishi kerak.';

  RAISE NOTICE '2) TEZLIKNI O''LCHANG: yangi trigger FAQAT SET ro''yxatida `status` bo''lgan UPDATE da ishga tushadi va birinchi ishi — `EXISTS (task_dependencies WHERE task_id = NEW.id)`. Katta bazada o''lchash: EXPLAIN (ANALYZE, BUFFERS) UPDATE public.tasks SET status = status WHERE id = ''<id>'';';

  RAISE NOTICE '3) ⚠️ TG-BOT / EDGE FUNCTION: ular ham shu qoidaga bo''ysunadi (istisno ATAYLAB qo''yilmagan). Agar bot logida "Bu bosqich hali ochilmagan..." xatosi ko''rinsa — bu XATO EMAS, qoida ishlayapti. Bot xabarini foydalanuvchiga tushunarli qilib ko''rsating.';

  RAISE NOTICE '4) ⚠️ MAVJUD MA''LUMOT: bu skript hech qanday bog''lanish YARATMAYDI — jadval BO''SH boshlanadi va shu sababli RUN kunida hech bir vazifa bloklanmaydi. Kutish faqat foydalanuvchi o''zi bog''laganda paydo bo''ladi.';

  RAISE NOTICE '5) BEKOR QILISH to''silmaydi: bloklangan bosqichni istalgan payt "Bekor" ga o''tkazish mumkin va shundan keyin unga bog''langan bosqich ochiladi (hisobotning 12- va (h) qatorlari). To''silgani faqat "Jarayonda"/"Bajarildi".';

  RAISE NOTICE '════════ TAVSIYA TUGADI ════════';
END $post$;
