-- ============================================================================
-- TASKFIX_SHABLON.sql — LOYIHA BOSQICHI SHABLONI + SIKL (shb*)
-- ============================================================================
-- Asilbek RUN qiladi (Supabase SQL Editor, postgres roli).
--
-- 🔴🔴 KAM TRAFIK VAQTIDA RUN QILING — bu fayl `public.tasks` GA
--      ACCESS EXCLUSIVE QULF OLADI VA UNI TRANZAKSIYA OXIRIGACHA USHLAB
--      TURADI. Ya'ni birinchi `ALTER TABLE public.tasks ...` dan COMMIT
--      gacha bo'lgan BUTUN vaqt davomida (migratsiya sikli ham shu ichida)
--      tasks ga har qanday SELECT/INSERT/UPDATE KUTIB turadi.
--      Skript migratsiyadan OLDIN nechta bosqich ko'chirilishini RAISE NOTICE
--      bilan aytadi — hajm katta bo'lsa (5000+) alohida WARNING chiqadi.
--
-- ── NIMA QILADI (ADDITIVE + IDEMPOTENT) ─────────────────────────────────────
--   1) public.project_cycles — YANGI jadval (loyihaning har SIKLI bitta qator).
--      🔴 UNIQUE (project_id, cycle_no) — materializatsiya DA'VOSI shu indeks
--         orqali ATOMIK bo'ladi: mijoz siklni INSERT qiladi, 23505 qaytsa
--         "boshqa admin ulgurdi" (bayroq/`last_reset_at` naqshi emas — INDEKS).
--   2) public.tasks ga 3 ustun:
--        is_template  boolean NOT NULL DEFAULT false — SHABLON (ta'rif), ish EMAS
--        template_id  (tasks.id tipida) → tasks(id) ON DELETE SET NULL
--        cycle_id     uuid              → project_cycles(id) ON DELETE SET NULL
--      + CHECK tasks_template_flags_chk:
--        is_template IS NOT TRUE OR (template_id IS NULL AND cycle_id IS NULL)
--        (shablon o'zi na instansiya, na siklga tegishli).
--   3) public.template_history — YANGI jadval (shablon meta-tarixi).
--      action TEXT + CHECK ('created','edited','materialized','archived')
--      — ENUM EMAS (30/32-migratsiyalar saboqi).
--   4) MAVJUD MA'LUMOT MIGRATSIYASI (pastda batafsil).
--   5) RLS + GRANT + indekslar + COMMENT.
--
-- ── 🔴 MIGRATSIYA YO'NALISHI — ENG NOZIK JOY ────────────────────────────────
--   Mavjud loyiha bosqichi qatorlari FOYDALANUVCHI ISHLAYOTGAN qatorlar:
--   task_comments, attachments, task_history, task_subtasks, task_dependencies,
--   task_views va notifications.meta.task_id — HAMMASI o'sha `tasks.id` ga
--   bog'langan. Ularni "shablon" ga AYLANTIRIB bo'lmaydi (odam ishlagan ish
--   ta'rifga aylanib, uning ro'yxatidan yo'qolardi va izohlari begona
--   obyektga osilib qolardi).
--   Shuning uchun TESKARI yo'nalish:
--     R (mavjud bosqich) — JOYIDA QOLADI, id si O'ZGARMAYDI.
--     T (yangi qator)    — R ning TA'RIF maydonlari nusxasi, is_template=true.
--     R.template_id = T.id ;  R.cycle_id = <1-sikl>
--   Ya'ni mavjud qator 1-SIKLNING INSTANSIYASI bo'lib qoladi, hamma izoh/
--   fayl/tarixi joyida. Skript buni 7-bo'limda HAQIQIY sanoq bilan tasdiqlaydi.
--
-- ── 🔴 NUSXA OLINADIGAN USTUNLAR — DINAMIK, NOMMA-NOM EMAS ──────────────────
--   TASKFIX_LOYIHA_V2.sql / TASKFIX_REL_DEADLINE.sql / TASKFIX_KUTISH.sql /
--   TASKFIX_PLANNER.sql / TASKFIX_VIEWS.sql HALI RUN QILINMAGAN bo'lishi
--   mumkin — ya'ni deadline_days, deadline_hours, plan_date, respect_dayoff,
--   recur_weekdays kabi ustunlar BAZADA BO'LMASLIGI MUMKIN. Nomma-nom
--   INSERT ... SELECT yozilsa migratsiya 42703 bilan yiqilardi.
--   Shuning uchun ustun ro'yxati `information_schema.columns` dan ISTISNO
--   RO'YXATI ayirib olinadi (dinamik SQL):
--     ISTISNO: id, created_at, updated_at, status, completed_at, started_at,
--              accepted_at, submitted_at, bajardi_user_id, bajardi_at,
--              is_locked, is_template, template_id, cycle_id
--     (+ GENERATED va IDENTITY ustunlar avtomat chiqariladi — ularga yozib
--       bo'lmaydi.)
--   `is_locked` ATAYLAB istisnoda: SHABLON HECH QACHON QULFLANMAYDI (u ish
--   emas, ta'rif; qulf 34-migratsiya trigger'ining ketma-ketlik belgisi).
--   `status` alohida beriladi (pastdagi izoh).
--   🔴 Agar ISTISNOdagi biror ustun NOT NULL bo'lsa va DEFAULT'i bo'lmasa —
--   skript TO'XTAYDI (qiymatni TAXMIN qilmaymiz).
--
-- ── 🔴 NIMA QILMAYDI (ATAYLAB) ──────────────────────────────────────────────
--   1) TRIGGER YO'Q. Materializatsiyani (yangi sikl instansiyalarini ochish)
--      MIJOZ qiladi — LAZY, admin loyihani ochganda (mavjud prjRecurDue /
--      prjResetRecurrence / prjStartKickoff naqshi). Server hisoblasa mijoz
--      bilan POYGA qilardi (ikkovi bir jadvalga yozadi) va ilovada cron ham,
--      EF ham yo'q. CLAUDE.md dagi TASKFIX_REL_DEADLINE qarori bilan bir xil.
--   2) MAVJUD TRIGGERLARGA TEGILMAYDI: 34-migratsiyaning qulf trigger'i va
--      `zz_task_wait_guard_trg` (KUTISH) o'z joyida qoladi. Migratsiya
--      `status` ni YANGILAMAYDI, ya'ni `BEFORE UPDATE OF status` qorovuli
--      umuman ishga tushmaydi.
--      🔴 LEKIN ULAR TEKSHIRILADI: manbalari repoda YO'Q (faqat bazada),
--      shuning uchun skript 0e-bo'limda HAR triggerni pg_trigger/pg_proc
--      dan O'ZI o'qiydi va xavfli naqsh topsa TO'XTAYDI (fail-closed),
--      8b-bo'limda esa uni sentinel sahnada HARAKATDA sinaydi.
--   3) `tasks` NING MAVJUD RLS POLICY'LARIGA TEGILMAYDI. Shablon ham `tasks`
--      qatori, RLS esa QATOR darajasida ishlaydi → mavjud policy'lar uni
--      allaqachon qamraydi. (Ustun darajasidagi GRANT bor-yo'qligi 5-bo'limda
--      alohida tekshiriladi — U meros olinmaydi.)
--   4) `can_see_project()` (TASKFIX_LOYIHA_RLS.sql) MAJBURIY EMAS va
--      ISHLATILMAYDI. Sabab: ko'rish sharti `is_ws_member` — u can_see_project
--      DAN KENG, ya'ni OR bilan qo'shsak bir zarra ham qo'shimcha qator
--      bermasdi, lekin hali RUN qilinmagan faylga bog'liqlik yaratardi.
--      Skript uning bor-yo'qligini FAQAT hisobotda aytadi.
--   5) Izoh / fayl / subtask / ko'rish soni SHABLONGA NUSXALANMAYDI — ular
--      ISH artefaktlari, ta'rif emas. Faqat `task_dependencies` (KUTISH grafi)
--      nusxalanadi va u ham FAQAT jadval mavjud bo'lsa (aks holda qadam
--      JIMGINA o'tkaziladi, skript yiqilmaydi).
--   6) `projects` jadvaliga BIR USTUN ham qo'shilmaydi.
--
-- ── BUSIZ ILOVA NIMA QILADI ─────────────────────────────────────────────────
--   Hech narsa buzilmaydi. Mijoz "ustun/jadval yo'q" holatini aniqlaydi
--   (42703 / PGRST205) → shablon UI'si UMUMAN chizilmaydi, loyiha bosqichlari
--   bugungidek ishlaydi. Ya'ni bu fayl ISHLATILMASA ham ilova to'liq ishlaydi.
--
-- ── BOG'LIQLIK ──────────────────────────────────────────────────────────────
--   Boshqa TASKFIX_*.sql fayllariga BOG'LIQ EMAS, RUN tartibi muhim emas.
--   Talab qilinadigan yagona narsa — bazada `is_ws_member(uuid,uuid)` va
--   `is_ws_manager(uuid,uuid)` funksiyalari (CLAUDE.md 8-qoida: policy ichida
--   workspace_members inline subquery YOZILMAYDI → 42P17).
--   TASKFIX_KUTISH.sql RUN qilingan bo'lsa shablonlar uchun kutish grafi ham
--   ko'chiriladi; qilinmagan bo'lsa o'sha qadam o'tkazib yuboriladi.
--
-- ── TEKSHIRUV ───────────────────────────────────────────────────────────────
--   0e-bo'lim: 🔴 public.tasks DAGI MAVJUD TRIGGERLAR — HAR QANDAY DDL DAN
--     OLDIN inventarizatsiya (nomi/vaqti/hodisasi/funksiyasi RAISE NOTICE
--     bilan) va XAVF TAHLILI: funksiya tanasida (izohlar tozalangach) tartib
--     raqami (flow_order/order_index) yoki is_locked bor-u, `is_template`
--     YO'Q bo'lsa — XAVFLI; tanasi o'qilmasa — ham xavfli (fail-closed).
--     Sukut bo'yicha RAISE EXCEPTION; chetlab o'tish faqat fayl boshidagi
--     SOZLAMA blokidagi v_allow_risky_trigger := true orqali.
--   7-bo'lim: migratsiya natijasi HAQIQIY sanoq bilan tekshiriladi
--     (a) har loyihada shablon soni = bosqich soni
--     (b) har bosqichning template_id to'lgan va cycle_id 1-siklga ishora qiladi
--     (c) 🔴 ENG MUHIMI: mavjud qator id'lari O'ZGARMAGAN va ularga bog'langan
--         izoh/fayl/tarix/subtask qatorlari soni AYNAN o'sha
--     (c3) 🔴 mavjud bosqichlarning MA'NOLI maydonlari (status / is_locked /
--         deadline / assigned_to / acceptor_id / flow_order / depends_on_prev /
--         title / project_id / workspace_id) BARMOQ IZI bilan solishtiriladi —
--         `public.tasks` dagi BEGONA trigger shablon insertiga javoban mavjud
--         qatorlarni jimgina qayta hisoblab yuborsa shu yerda tutiladi
--     (g) idempotentlik: migratsiya drayveri endi 0 loyiha qaytaradi
--   8-bo'lim: TIRIK SINOVLAR (sentinel-rollback) — bazada bitta qator ham
--     qolmaydi:
--     (d) UNIQUE (project_id, cycle_no) ikkinchi insertni RAD etadi
--     (e1) CHECK shablonga template_id yozishni RAD etadi
--     (e2) toza shablon (ikkovi NULL) O'TADI
--     (e3) instansiya (template_id + cycle_id) O'TADI
--     (f1..f5) RLS: begona ws a'zosi project_cycles / template_history ni
--              KO'RMAYDI va YOZA OLMAYDI; ws a'zosi ko'radi
--     (h) REGRESSIYA: mavjud vazifani oddiy UPDATE qilish avvalgidek ishlaydi
--   8b-bo'lim: 🔴 TIRIK TRIGGER SINOVI (sentinel loyiha + 2 bosqich + 2
--     shablon + 2-sikl instansiyalari — hammasi QAYTARILADI):
--     (t1) shablon qo'shilishi MAVJUD bosqichning is_locked iga tegmadi
--     (t2) trigger SHABLON qatoriga is_locked = true yozmadi
--     (t3) 1-bosqich `completed` bo'lgach 2-bosqich OCHILDI (shablon uni
--          abadiy ushlab qolmadi)
--     (t4) 2-SIKL bosqichi QULFLANDI (o'tgan siklning `completed` qatori uni
--          noto'g'ri ochib yubormadi)
--     ⚠️ Qulf trigger'i qulf yozmasa (t3)/(t4) 'ENV:' bilan o'tkaziladi.
--   Bittasi kutilgandek chiqmasa RAISE EXCEPTION → HAMMASI QAYTADI.
-- ============================================================================

BEGIN;

-- ════════════════════════════════════════════════════════════════════════════
-- ⚙️ SOZLAMA — RUN'DAN OLDIN O'QING (odatda TEGISHGA HOJAT YO'Q)
-- ════════════════════════════════════════════════════════════════════════════
--  v_allow_risky_trigger   (SUKUT: false = FAIL-CLOSED)
--
--  🔴 NIMA UCHUN BOR: migratsiyadan keyin BITTA loyihada bir xil tartib
--     raqami (flow_order / order_index) IKKI marta uchraydi — SHABLON qatori
--     va uning INSTANSIYASI; har yangi sikl esa yana N ta qator qo'shadi.
--     `public.tasks` da 34-migratsiyaning QULF trigger'i bor (manbasi repoda
--     YO'Q — faqat bazada). Agar u "oldingi bosqich" ni loyiha + tartib
--     raqami bo'yicha qidirsa:
--       (a) SHABLON (status = 'new', HECH QACHON tugamaydi) keyingi bosqichni
--           ABADIY qulflab qo'yishi;
--       (b) yoki O'TGAN SIKLNING `completed` qatorini ko'rib yangi siklning
--           bosqichini NOTO'G'RI ochib yuborishi mumkin.
--     Aynan shu naqsh mijoz kodida jonli tutilgan (prjShiftNextDeadline
--     shablonni "keyingi bosqich" deb tanlab olgan edi) — trigger ham shunday
--     yozilgan bo'lishi ehtimoli yuqori.
--
--  Shuning uchun 0e-bo'lim `public.tasks` dagi HAR triggerni O'ZI o'qiydi
--  (Asilbekning qo'lda dump qilishiga TAYANMAYMIZ) va xavfli naqsh topsa
--  MIGRATSIYANI TO'XTATADI — bazada bir belgi ham o'zgarmaydi. Ikki yo'l:
--    1) TAVSIYA ETILADI — trigger funksiyasidagi "oldingi/keyingi bosqich"
--       qidiruviga qorovul qo'shing:
--            AND is_template IS NOT TRUE
--            AND cycle_id IS NOT DISTINCT FROM NEW.cycle_id
--       (birinchisi shablonni, ikkinchisi o'tgan sikl qatorlarini chetlab
--       o'tadi), so'ng shu skriptni QAYTA RUN qiling — u idempotent.
--    2) ATAYLAB DAVOM ETISH — pastdagi qiymatni `true` qiling. U holda
--       migratsiya o'tadi, LEKIN bosqich qulflari noto'g'ri hisoblanishi
--       mumkin (yuqoridagi (a)/(b)) va 8b tirik sinovi ham faqat WARNING
--       beradi.
-- ════════════════════════════════════════════════════════════════════════════
DROP TABLE IF EXISTS pg_temp.shb_cfg;
CREATE TEMP TABLE pg_temp.shb_cfg (k text PRIMARY KEY, v boolean, izoh text);

DO $cfg$
DECLARE
  -- 🔴🔴 KERAK BO'LSA FAQAT SHU QATORNI O'ZGARTIRING (boshqa joyda emas).
  v_allow_risky_trigger boolean := false;
BEGIN
  INSERT INTO pg_temp.shb_cfg VALUES
    ('allow_risky_trigger', v_allow_risky_trigger,
     'true = public.tasks dagi xavfli trigger topilsa ham migratsiya davom etadi (fail-OPEN, ataylab)');

  IF v_allow_risky_trigger THEN
    RAISE WARNING '⚙️ v_allow_risky_trigger = TRUE — public.tasks dagi XAVFLI trigger migratsiyani TO''XTATMAYDI va 8b tirik sinovi faqat WARNING beradi. Bosqich qulflari (is_locked) noto''g''ri hisoblanishi mumkin; RUN''dan keyin loyiha sahifasini QO''LDA tekshiring.';
  END IF;
END $cfg$;


-- ════════════════════════════════════════════════════════════════════════════
-- 0) OLD SHARTLAR — noto'g'ri/yarim bazada ishga tushmasin
--    🔴 Fail-closed: bu yerda tekshirilmagan har bir taxmin keyinroq xom
--       42703 / 23502 bo'lib chiqardi.
-- ════════════════════════════════════════════════════════════════════════════
DO $pre$
DECLARE
  v_c   text;
  v_def text;
  v_idn text;
BEGIN
  IF to_regclass('public.tasks') IS NULL THEN
    RAISE EXCEPTION 'public.tasks topilmadi — bu TaskFix bazasi emasmi? Hech narsa o''zgartirilmadi.';
  END IF;
  IF to_regclass('public.projects') IS NULL THEN
    RAISE EXCEPTION 'public.projects topilmadi — SHABLON faqat loyiha bosqichlari uchun. Hech narsa o''zgartirilmadi.';
  END IF;
  IF to_regclass('public.workspace_members') IS NULL THEN
    RAISE EXCEPTION 'public.workspace_members topilmadi — RLS va tirik sinov unga tayanadi. Hech narsa o''zgartirilmadi.';
  END IF;

  FOREACH v_c IN ARRAY ARRAY['id','workspace_id','project_id'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='tasks' AND column_name=v_c) THEN
      RAISE EXCEPTION 'public.tasks.% ustuni yo''q — shablon migratsiyasi aynan shu ustunlarga tayanadi. To''xtatildi.', v_c;
    END IF;
  END LOOP;

  FOREACH v_c IN ARRAY ARRAY['id','workspace_id'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='projects' AND column_name=v_c) THEN
      RAISE EXCEPTION 'public.projects.% ustuni yo''q — sikl qatori workspace_id ni aynan loyihadan oladi. To''xtatildi.', v_c;
    END IF;
  END LOOP;

  -- tasks.id o'zi to'lanadimi? (migratsiya YANGI qator yozadi)
  SELECT column_default, is_identity INTO v_def, v_idn
    FROM information_schema.columns
   WHERE table_schema='public' AND table_name='tasks' AND column_name='id';
  IF v_def IS NULL AND coalesce(v_idn,'NO') <> 'YES' THEN
    RAISE EXCEPTION 'public.tasks.id da DEFAULT ham, IDENTITY ham yo''q — shablon qatorining id sini skript o''ylab topa olmaydi (taxmin bilan yozmaymiz). To''xtatildi.';
  END IF;

  -- tasks.id PK bo'lgan YAGONA ustunmi? (template_id FK aynan shunga qo'yiladi)
  IF NOT EXISTS (
    SELECT 1
      FROM pg_index i
      JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
     WHERE i.indrelid = 'public.tasks'::regclass
       AND i.indisprimary AND i.indnatts = 1 AND a.attname = 'id'
  ) THEN
    RAISE EXCEPTION 'public.tasks ning PRIMARY KEY i bitta `id` ustuni EMAS — tasks.template_id FK si aynan tasks(id) ga qo''yiladi. Sxema kutilganidan boshqa, to''xtatildi.';
  END IF;

  -- 🔴 CLAUDE.md 8-qoida: policy ichida workspace_members inline subquery
  --    YOZILMAYDI (42P17) — shu sababli bu ikki funksiya SHART.
  IF to_regprocedure('public.is_ws_member(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'is_ws_member(uuid, uuid) topilmadi (nomi bor, imzosi boshqa bo''lishi mumkin). Avval 39_employee_details.sql (yoki 35_fix_projects_rls.sql) ni ishga tushiring.';
  END IF;
  IF to_regprocedure('public.is_ws_manager(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'is_ws_manager(uuid, uuid) topilmadi (nomi bor, imzosi boshqa bo''lishi mumkin). Avval 35_fix_projects_rls.sql / 39_employee_details.sql ni ishga tushiring.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    RAISE EXCEPTION '`authenticated` roli topilmadi — bu Supabase bazasi emasmi?';
  END IF;
END $pre$;

-- ════════════════════════════════════════════════════════════════════════════
-- 0b) TIP MOSLIGI — uchala ustun ALLAQACHON boshqa tipda bo'lsa TO'XTAYMIZ
--     (jimgina davom etsak CHECK va FK boshqa ma'no kasb etardi)
-- ════════════════════════════════════════════════════════════════════════════
DO $typ$
DECLARE
  v_idtype text;
  v_isT    text;
  v_tpl    text;
  v_cyc    text;
BEGIN
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_idtype
    FROM pg_attribute a
   WHERE a.attrelid='public.tasks'::regclass AND a.attname='id' AND NOT a.attisdropped;

  SELECT format_type(a.atttypid, a.atttypmod) INTO v_isT
    FROM pg_attribute a
   WHERE a.attrelid='public.tasks'::regclass AND a.attname='is_template' AND NOT a.attisdropped;
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_tpl
    FROM pg_attribute a
   WHERE a.attrelid='public.tasks'::regclass AND a.attname='template_id' AND NOT a.attisdropped;
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_cyc
    FROM pg_attribute a
   WHERE a.attrelid='public.tasks'::regclass AND a.attname='cycle_id' AND NOT a.attisdropped;

  IF v_isT IS NOT NULL AND v_isT <> 'boolean' THEN
    RAISE EXCEPTION 'public.tasks.is_template ALLAQACHON mavjud, lekin tipi "%" (kutilgan: boolean). Skript uni O''ZGARTIRMAYDI. Qo''lda ko''rib chiqing. Hech narsa o''zgartirilmadi.', v_isT;
  END IF;
  IF v_tpl IS NOT NULL AND v_tpl IS DISTINCT FROM v_idtype THEN
    RAISE EXCEPTION 'public.tasks.template_id ALLAQACHON mavjud, lekin tipi "%" (kutilgan: tasks.id tipi "%"). Skript uni O''ZGARTIRMAYDI. Hech narsa o''zgartirilmadi.', v_tpl, v_idtype;
  END IF;
  IF v_cyc IS NOT NULL AND v_cyc <> 'uuid' THEN
    RAISE EXCEPTION 'public.tasks.cycle_id ALLAQACHON mavjud, lekin tipi "%" (kutilgan: uuid — project_cycles.id tipi). Skript uni O''ZGARTIRMAYDI. Hech narsa o''zgartirilmadi.', v_cyc;
  END IF;
END $typ$;

-- ════════════════════════════════════════════════════════════════════════════
-- 0c) KATALOGDAN ANIQLASH — TAXMIN QILMAYMIZ
--     🔴 tasks.id / projects.id TIPI, FK NISHONLARI, uuid generator, nusxa
--        olinadigan USTUN RO'YXATI — hammasi katalogdan.
-- ════════════════════════════════════════════════════════════════════════════
DROP TABLE IF EXISTS pg_temp.shb_ref;
CREATE TEMP TABLE pg_temp.shb_ref (k text PRIMARY KEY, v text, izoh text);

DO $ref$
DECLARE
  v_idtype  text;
  v_projtyp text;
  v_wsref   text;
  v_usrref  text;
  v_uuidfn  text;
  v_t       text;
  v_c       text;
  v_excl    text[] := ARRAY['id','created_at','updated_at','status','completed_at',
                            'started_at','accepted_at','submitted_at','bajardi_user_id',
                            'bajardi_at','is_locked','is_template','template_id','cycle_id'];
  v_cols    text;
  v_colsrc  text;
  v_forced  text;
  v_own     text;
  v_uq      text;
  v_expr    text;
  v_stmode  text;
  v_copy    text[];
BEGIN
  -- ── tasks.id tipi ─────────────────────────────────────────────────────────
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_idtype
    FROM pg_attribute a
   WHERE a.attrelid='public.tasks'::regclass AND a.attname='id' AND NOT a.attisdropped;
  IF v_idtype IS NULL THEN
    RAISE EXCEPTION 'public.tasks.id tipi aniqlanmadi — to''xtatildi.';
  END IF;
  INSERT INTO pg_temp.shb_ref VALUES ('idtype', v_idtype, 'tasks.id tipi (katalogdan)');

  -- ── projects.id tipi ──────────────────────────────────────────────────────
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_projtyp
    FROM pg_attribute a
   WHERE a.attrelid='public.projects'::regclass AND a.attname='id' AND NOT a.attisdropped;
  IF v_projtyp IS NULL THEN
    RAISE EXCEPTION 'public.projects.id tipi aniqlanmadi — to''xtatildi.';
  END IF;
  INSERT INTO pg_temp.shb_ref VALUES ('projtype', v_projtyp, 'projects.id tipi (katalogdan)');
  RAISE NOTICE 'tasks.id tipi: % · projects.id tipi: %', v_idtype, v_projtyp;

  -- ── uuid generatori (project_cycles.id / template_history.id) ─────────────
  IF to_regprocedure('gen_random_uuid()') IS NOT NULL THEN
    v_uuidfn := 'gen_random_uuid()';
  ELSIF to_regprocedure('uuid_generate_v4()') IS NOT NULL THEN
    v_uuidfn := 'uuid_generate_v4()';
  ELSE
    RAISE EXCEPTION 'gen_random_uuid() ham, uuid_generate_v4() ham topilmadi — project_cycles.id uchun DEFAULT yoza olmayman. `CREATE EXTENSION IF NOT EXISTS pgcrypto;` bajaring va qayta RUN qiling. Hech narsa o''zgartirilmadi.';
  END IF;
  INSERT INTO pg_temp.shb_ref VALUES ('uuidfn', v_uuidfn, 'uuid generatori (katalogdan)');

  -- ── workspace_id FK nishoni (tasks.workspace_id dan olinadi) ──────────────
  --    ⚠️ ORDER BY conname — bir nechta mos FK bo'lsa tanlov DETERMINISTIK.
  SELECT c.confrelid::regclass::text, af.attname INTO v_t, v_c
    FROM pg_constraint c
    JOIN pg_attribute a  ON a.attrelid  = c.conrelid  AND a.attnum  = c.conkey[1]
    JOIN pg_attribute af ON af.attrelid = c.confrelid AND af.attnum = c.confkey[1]
   WHERE c.conrelid='public.tasks'::regclass AND c.contype='f'
     AND array_length(c.conkey,1)=1 AND a.attname='workspace_id'
   ORDER BY c.conname LIMIT 1;
  IF v_t IS NOT NULL THEN
    v_wsref := v_t || '(' || quote_ident(v_c) || ')';
    INSERT INTO pg_temp.shb_ref VALUES ('wsref', v_wsref, 'tasks.workspace_id FK dan olindi');
  ELSIF to_regclass('public.workspaces') IS NOT NULL THEN
    INSERT INTO pg_temp.shb_ref VALUES ('wsref', 'public.workspaces(id)', 'tasks.workspace_id da FK yo''q — public.workspaces(id)');
  ELSE
    INSERT INTO pg_temp.shb_ref VALUES ('wsref', NULL, 'mos jadval topilmadi — workspace_id FK''SIZ');
  END IF;

  -- ── created_by FK nishoni ─────────────────────────────────────────────────
  v_t := NULL; v_c := NULL;
  SELECT c.confrelid::regclass::text, af.attname INTO v_t, v_c
    FROM pg_constraint c
    JOIN pg_attribute a  ON a.attrelid  = c.conrelid  AND a.attnum  = c.conkey[1]
    JOIN pg_attribute af ON af.attrelid = c.confrelid AND af.attnum = c.confkey[1]
   WHERE c.conrelid='public.tasks'::regclass AND c.contype='f'
     AND array_length(c.conkey,1)=1 AND a.attname='created_by'
   ORDER BY c.conname LIMIT 1;
  IF v_t IS NOT NULL THEN
    v_usrref := v_t || '(' || quote_ident(v_c) || ')';
    INSERT INTO pg_temp.shb_ref VALUES ('usrref', v_usrref, 'tasks.created_by FK dan olindi');
  ELSIF to_regclass('public.profiles') IS NOT NULL THEN
    INSERT INTO pg_temp.shb_ref VALUES ('usrref', 'public.profiles(id)', 'tasks.created_by da FK yo''q — public.profiles(id)');
  ELSIF to_regclass('auth.users') IS NOT NULL THEN
    INSERT INTO pg_temp.shb_ref VALUES ('usrref', 'auth.users(id)', 'profiles topilmadi — auth.users(id)');
  ELSE
    INSERT INTO pg_temp.shb_ref VALUES ('usrref', NULL, 'mos jadval topilmadi — created_by FK''SIZ');
  END IF;

  -- ── projects dagi ixtiyoriy ustunlar (TASKFIX_LOYIHA.sql RUN qilinmagan
  --    bo'lishi mumkin → start_at / end_at BO'LMASLIGI MUMKIN) ──────────────
  INSERT INTO pg_temp.shb_ref
  SELECT 'prj_start',
         (EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='projects' AND column_name='start_at'))::text,
         'projects.start_at bormi (TASKFIX_LOYIHA.sql)';
  INSERT INTO pg_temp.shb_ref
  SELECT 'prj_end',
         (EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='projects' AND column_name='end_at'))::text,
         'projects.end_at bormi (TASKFIX_LOYIHA.sql)';
  INSERT INTO pg_temp.shb_ref
  SELECT 'prj_cb',
         (EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='projects' AND column_name='created_by'))::text,
         'projects.created_by bormi (yozuv huquqi ifodasi shunga qaraydi)';
  INSERT INTO pg_temp.shb_ref
  SELECT 'has_flow',
         (EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='tasks' AND column_name='flow_order'))::text,
         'tasks.flow_order bormi (shablon tartibi)';

  -- ── 🔴 NUSXA OLINADIGAN USTUN RO'YXATI (DINAMIK) ──────────────────────────
  SELECT string_agg(quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position),
         string_agg('t.' || quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position)
    INTO v_cols, v_colsrc
    FROM information_schema.columns c
   WHERE c.table_schema='public' AND c.table_name='tasks'
     AND c.is_generated = 'NEVER'
     AND c.is_identity  = 'NO'
     AND NOT (c.column_name = ANY (v_excl));
  IF v_cols IS NULL OR v_cols = '' THEN
    RAISE EXCEPTION 'Nusxa olinadigan ustun topilmadi — istisno ro''yxati butun jadvalni yeb qo''ydimi? To''xtatildi.';
  END IF;
  INSERT INTO pg_temp.shb_ref VALUES ('cols',   v_cols,   'shablonga NUSXALANADIGAN ustunlar (dinamik)');
  INSERT INTO pg_temp.shb_ref VALUES ('colsrc', v_colsrc, 'ayni ro''yxat, t. prefiksi bilan');
  RAISE NOTICE 'Shablonga nusxalanadigan ustunlar: %', v_cols;

  -- ── 🔴 ISTISNOdagi NOT NULL + DEFAULT'siz ustun bo'lsa TO'XTAYMIZ ─────────
  --    (aks holda migratsiya birinchi INSERT dayoq 23502 bilan yiqilardi —
  --     lekin ALLAQACHON qulf olingan va DDL bajarilgan holatda.)
  SELECT string_agg(column_name, ', ' ORDER BY ordinal_position) INTO v_forced
    FROM information_schema.columns
   WHERE table_schema='public' AND table_name='tasks'
     AND is_nullable='NO' AND column_default IS NULL
     AND is_identity='NO' AND is_generated='NEVER'
     AND column_name = ANY (v_excl)
     AND column_name NOT IN ('id','status','is_template');
  IF v_forced IS NOT NULL THEN
    RAISE EXCEPTION 'public.tasks da NOT NULL + DEFAULT''siz ustun(lar) shablon nusxasidan CHIQARIB tashlangan: %. Skript ularga qiymat TAXMIN QILMAYDI. Yo ularni istisno ro''yxatidan olib tashlang (ya''ni nusxalansin), yo DEFAULT bering. Hech narsa o''zgartirilmadi.', v_forced;
  END IF;

  -- ── status rejimi: DEFAULT bo'lsa umuman yozilmaydi, aks holda 'new' ──────
  --    (DB DEFAULT'i ta'rifan YAROQLI qiymat; qattiq yozilgan literal esa
  --     status CHECK'i o'zgargan bazada 23514 berishi mumkin edi.)
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='tasks' AND column_name='status') THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='tasks' AND column_name='status'
                  AND column_default IS NOT NULL) THEN
      v_stmode := 'default';
    ELSE
      v_stmode := 'new';
    END IF;
  ELSE
    v_stmode := 'yoq';
  END IF;
  INSERT INTO pg_temp.shb_ref VALUES ('stmode', v_stmode, 'shablon status manbai: default | new | yoq');

  -- ── "loyihani boshqara oladimi" ifodasi (bir marta quriladi) ──────────────
  v_own := 'public.is_ws_manager(p.workspace_id, p_user)';
  IF (SELECT v FROM pg_temp.shb_ref WHERE k='prj_cb') = 'true' THEN
    v_own := v_own || ' OR p_user = p.created_by';
  END IF;
  INSERT INTO pg_temp.shb_ref VALUES ('ownexpr', v_own,
    'can_edit_project_cycles: ws-menejeri YOKI loyiha YARATUVCHISI');

  -- ── 🔴 UNIQUE INDEKS TO'QNASHUVI QOROVULI ────────────────────────────────
  --    Shablon — mavjud qatorning AYNAN nusxasi (nusxalanadigan ustunlar
  --    bo'yicha). Agar tasks da UNIQUE (qisman bo'lmagan) indeks bo'lsa va
  --    uning BARCHA kalit ustunlari nusxalanadigan ro'yxatga tushsa, INSERT
  --    23505 bilan yiqilardi (klassik holat: UNIQUE (project_id, flow_order)).
  --    ⚠️ Bu tekshiruv HAR QANDAY DDL DAN OLDIN turadi — bazada bir belgi ham
  --       o'zgarmasidan to'xtaymiz.
  --    ⚠️ `indkey` — int2vector. Uni int[] GA cast qilib bo'lmaydi (bunday
  --       cast ro'yxatdan o'tmagan) — faqat int2[]. Ustun ro'yxati ham
  --       so'rovdan TASHQARIDA massivga aylantiriladi (aks holda `k` nomi
  --       ichki so'rovdagi shb_ref.k bilan chalkashardi).
  v_copy := string_to_array(replace(v_cols, '"', ''), ', ');

  SELECT string_agg(x.idx, ', ' ORDER BY x.idx) INTO v_uq
    FROM (
      SELECT i.indexrelid::regclass::text AS idx
        FROM pg_index i
       WHERE i.indrelid = 'public.tasks'::regclass
         AND i.indisunique
         AND i.indpred IS NULL
         AND array_position(i.indkey::int2[], 0::int2) IS NULL
         AND (SELECT bool_and(a.attname = ANY (v_copy))
                FROM unnest(i.indkey::int2[]) AS ik(attnum)
                JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ik.attnum)
    ) x;
  IF v_uq IS NOT NULL THEN
    RAISE EXCEPTION 'public.tasks da UNIQUE indeks(lar) bor va ularning HAMMA kalit ustunlari shablonga nusxalanadi: %. Shablon mavjud qatorning nusxasi bo''lgani uchun migratsiya 23505 (unique_violation) bilan yiqilardi. YECHIM: o''sha indeksni QISMAN qiling, masalan — DROP INDEX <nom>; CREATE UNIQUE INDEX <nom> ON public.tasks (...) WHERE is_template = false; (ustun bu skriptdan keyin paydo bo''ladi, shuning uchun avval faqat DROP qilib skriptni RUN qiling, so''ng qisman indeksni yarating). Hech narsa o''zgartirilmadi.', v_uq;
  END IF;

  -- Ifodali (expression) UNIQUE indekslarni tahlil qila olmaymiz — ochiq aytamiz
  SELECT string_agg(i.indexrelid::regclass::text, ', ') INTO v_expr
    FROM pg_index i
   WHERE i.indrelid = 'public.tasks'::regclass
     AND i.indisunique AND i.indpred IS NULL
     AND array_position(i.indkey::int2[], 0::int2) IS NOT NULL;
  IF v_expr IS NOT NULL THEN
    RAISE WARNING 'public.tasks da IFODALI (expression) UNIQUE indeks bor: %. Skript uning shablon nusxasi bilan to''qnashishini OLDINDAN ayta olmaydi. Migratsiya 23505 bersa butun tranzaksiya qaytadi (bazaga zarar yo''q) — o''sha indeksni qisman qilib qayta urinib ko''ring.', v_expr;
  END IF;
END $ref$;

-- ════════════════════════════════════════════════════════════════════════════
-- 0d) HISOBOT JADVALLARI + O'ZGARISHDAN OLDINGI HOLAT
-- ════════════════════════════════════════════════════════════════════════════
DROP TABLE IF EXISTS pg_temp.shb_res;
CREATE TEMP TABLE pg_temp.shb_res (ord int, bosqich text, nom text, qiymat text, izoh text);

DROP TABLE IF EXISTS pg_temp.shb_pre;
CREATE TEMP TABLE pg_temp.shb_pre (k text PRIMARY KEY, v boolean);

INSERT INTO pg_temp.shb_pre VALUES
  ('col_is_template', EXISTS (SELECT 1 FROM information_schema.columns
                               WHERE table_schema='public' AND table_name='tasks' AND column_name='is_template')),
  ('col_template_id', EXISTS (SELECT 1 FROM information_schema.columns
                               WHERE table_schema='public' AND table_name='tasks' AND column_name='template_id')),
  ('col_cycle_id',    EXISTS (SELECT 1 FROM information_schema.columns
                               WHERE table_schema='public' AND table_name='tasks' AND column_name='cycle_id')),
  ('tbl_cycles',      to_regclass('public.project_cycles') IS NOT NULL),
  ('tbl_history',     to_regclass('public.template_history') IS NOT NULL),
  ('has_deps',        to_regclass('public.task_dependencies') IS NOT NULL),
  ('has_csp',         to_regprocedure('public.can_see_project(uuid,uuid)') IS NOT NULL);

-- ════════════════════════════════════════════════════════════════════════════
-- 0e) 🔴 public.tasks DAGI MAVJUD TRIGGERLAR — INVENTARIZATSIYA + XAVF TAHLILI
--     🔴 HAR QANDAY DDL DAN OLDIN turadi: hukm salbiy bo'lsa bazada bir belgi
--        ham o'zgarmaydi.
--     Manba: pg_trigger + pg_proc — trigger manbalari repoda YO'Q, faqat
--     bazada. Skript ularni O'ZI o'qiydi (qo'lda dump qilishga tayanmaymiz).
--
--     Funksiya tanasida (IZOHLAR TOZALANGANDAN KEYIN) nima izlanadi:
--       flow_order / order_index → "oldingi bosqich" ni TARTIB bo'yicha qidirish
--       is_locked                → qulf YOZISH
--       project_id               → loyiha bo'yicha boshqa qatorlarni qidirish
--       is_template / cycle_id   → SHABLON va SIKLNI hisobga oluvchi QOROVUL
--
--     HUKM:
--       XAVFLI    — (tartib raqami YOKI is_locked) bor, `is_template` esa
--                   UMUMAN YO'Q → migratsiyadan keyin shablon va o'tgan sikl
--                   qatorlari unga "bosqich" bo'lib ko'rinadi
--       O'QILMADI — tanasi o'qilmadi (C/internal funksiya) → hukm chiqara
--                   olmaymiz → FAIL-CLOSED (shubha bo'lsa TO'XTAYMIZ)
--       DIQQAT    — loyiha bo'yicha qidiradi, lekin tartib raqamiga ham,
--                   qulfga ham tegmaydi → faqat WARNING (u "oldingi bosqich"
--                   ni hisoblay olmaydi)
--       XAVFSIZ   — yo shablonni biladi, yo bu maydonlarga umuman tegmaydi
--       O'CHIQ    — trigger DISABLE qilingan (ishga tushmaydi)
--
--     🔴 FAIL-CLOSED: XAVFLI yoki O'QILMADI topilsa RAISE EXCEPTION.
--        Chetlab o'tish — FAQAT fayl boshidagi SOZLAMA (v_allow_risky_trigger).
--     ⚠️ Bu bo'lim hech narsani O'ZGARTIRMAYDI — faqat O'QIYDI va hukm chiqaradi.
-- ════════════════════════════════════════════════════════════════════════════
DROP TABLE IF EXISTS pg_temp.shb_trg;
CREATE TEMP TABLE pg_temp.shb_trg (
  trg text, tim text, evt text, fn text, holat text, belgi text, hukm text
);

DO $trg$
DECLARE
  r         RECORD;
  v_body    text;
  v_tim     text;
  v_evt     text;
  v_belgi   text;
  v_hukm    text;
  v_read    boolean;
  v_ord     boolean;
  v_lock    boolean;
  v_proj    boolean;
  v_tmpl    boolean;
  v_cyc     boolean;
  v_n       int := 0;
  v_risky   int := 0;
  v_watch   int := 0;
  v_lockw   int := 0;
  v_allow   boolean := false;
  v_bad     text := '';
  v_watchn  text := '';
  v_names   text := '';
  v_msg     text;
BEGIN
  SELECT v INTO v_allow FROM pg_temp.shb_cfg WHERE k='allow_risky_trigger';

  RAISE NOTICE '── public.tasks dagi TRIGGERLAR (inventarizatsiya) ──';

  FOR r IN
    SELECT tg.tgname::text AS trg,
           tg.tgenabled    AS en,
           tg.tgtype::int  AS typ,
           p.oid           AS fnoid,
           (quote_ident(n.nspname) || '.' || quote_ident(p.proname)) AS fn,
           l.lanname::text AS lang
      FROM pg_trigger   tg
      JOIN pg_proc      p ON p.oid = tg.tgfoid
      JOIN pg_namespace n ON n.oid = p.pronamespace
      JOIN pg_language  l ON l.oid = p.prolang
     WHERE tg.tgrelid = 'public.tasks'::regclass
       AND NOT tg.tgisinternal
     ORDER BY tg.tgname
  LOOP
    v_n := v_n + 1;

    -- ── vaqti / hodisasi (pg_trigger.tgtype bit maskasi) ──────────────────
    IF (r.typ & 2) <> 0 THEN
      v_tim := 'BEFORE';
    ELSIF (r.typ & 64) <> 0 THEN
      v_tim := 'INSTEAD OF';
    ELSE
      v_tim := 'AFTER';
    END IF;

    v_evt := '';
    IF (r.typ & 4)  <> 0 THEN v_evt := v_evt || 'INSERT ';   END IF;
    IF (r.typ & 8)  <> 0 THEN v_evt := v_evt || 'DELETE ';   END IF;
    IF (r.typ & 16) <> 0 THEN v_evt := v_evt || 'UPDATE ';   END IF;
    IF (r.typ & 32) <> 0 THEN v_evt := v_evt || 'TRUNCATE '; END IF;
    IF (r.typ & 1)  <> 0 THEN
      v_evt := v_evt || '· ROW';
    ELSE
      v_evt := v_evt || '· STATEMENT';
    END IF;

    -- ── tanasi ────────────────────────────────────────────────────────────
    --    ⚠️ plpgsql/sql BO'LMAGAN til (C, internal) — tanasi o'qilmaydi,
    --       ya'ni hukm chiqara olmaymiz → fail-closed.
    v_read := (r.lang IN ('plpgsql', 'sql'));
    v_body := NULL;
    IF v_read THEN
      BEGIN
        v_body := pg_get_functiondef(r.fnoid);
      EXCEPTION WHEN OTHERS THEN
        v_body := NULL;
      END;
    END IF;
    IF v_body IS NULL THEN
      v_read := false;
    END IF;

    v_ord := false; v_lock := false; v_proj := false; v_tmpl := false; v_cyc := false;
    IF v_read THEN
      -- 🔴 IZOHLAR TOZALANADI — izohda qolgan "is_template" so'zi QOROVUL
      --    deb hisoblanmasin (mavjud TASKFIX_* fayllaridagi naqsh).
      v_body := regexp_replace(v_body, '/\*.*?\*/', ' ', 'gs');
      v_body := regexp_replace(v_body, '--[^\n]*', ' ', 'g');
      v_body := lower(v_body);
      v_ord  := (v_body ~ 'flow_order' OR v_body ~ 'order_index');
      v_lock := (v_body ~ 'is_locked');
      v_proj := (v_body ~ 'project_id');
      v_tmpl := (v_body ~ 'is_template');
      v_cyc  := (v_body ~ 'cycle_id');
    END IF;

    -- ── hukm ──────────────────────────────────────────────────────────────
    IF r.en = 'D' THEN
      v_hukm := 'O''CHIQ';
    ELSIF NOT v_read THEN
      v_hukm := 'O''QILMADI';
    ELSIF (v_ord OR v_lock) AND NOT v_tmpl THEN
      v_hukm := 'XAVFLI';
    ELSIF v_proj AND NOT v_tmpl THEN
      v_hukm := 'DIQQAT';
    ELSE
      v_hukm := 'XAVFSIZ';
    END IF;

    v_belgi := '';
    IF NOT v_read THEN
      v_belgi := 'tanasi O''QILMADI (til: ' || r.lang || ')';
    ELSE
      IF v_ord  THEN v_belgi := v_belgi || 'tartib(flow_order/order_index) '; END IF;
      IF v_lock THEN v_belgi := v_belgi || 'is_locked '; END IF;
      IF v_proj THEN v_belgi := v_belgi || 'project_id '; END IF;
      IF v_tmpl THEN v_belgi := v_belgi || '+QOROVUL:is_template '; END IF;
      IF v_cyc  THEN v_belgi := v_belgi || '+QOROVUL:cycle_id '; END IF;
      IF v_belgi = '' THEN v_belgi := '(bu maydonlarga umuman tegmaydi)'; END IF;
    END IF;

    IF v_lock AND r.en <> 'D' THEN
      v_lockw := v_lockw + 1;
    END IF;

    INSERT INTO pg_temp.shb_trg VALUES
      (r.trg, v_tim, v_evt, r.fn || '()',
       CASE WHEN r.en = 'D' THEN 'o''chiq' ELSE 'yoqilgan' END,
       v_belgi, v_hukm);

    RAISE NOTICE '  • % | % % | % | HUKM: % | belgilar: %',
      r.trg, v_tim, v_evt, r.fn, v_hukm, v_belgi;

    IF v_hukm = 'XAVFLI' OR v_hukm = 'O''QILMADI' THEN
      v_risky := v_risky + 1;
      v_names := v_names || CASE WHEN v_names = '' THEN '' ELSE ', ' END || r.trg;
      v_bad   := v_bad || chr(10) || '    - ' || r.trg || '  ->  ' || r.fn
              || '()   [' || v_hukm || ': ' || v_belgi || ']';
      IF v_read THEN
        -- Asilbek darrov ko'rsin — tuzatish aynan shu funksiyada.
        RAISE NOTICE '── % funksiyasining TANASI (xavf tahlili uchun) ──%',
          r.fn, chr(10) || left(pg_get_functiondef(r.fnoid), 3000);
      END IF;
    ELSIF v_hukm = 'DIQQAT' THEN
      v_watch  := v_watch + 1;
      v_watchn := v_watchn || CASE WHEN v_watchn = '' THEN '' ELSE ', ' END || r.trg;
    END IF;
  END LOOP;

  IF v_n = 0 THEN
    RAISE NOTICE '  (public.tasks da foydalanuvchi trigger''i YO''Q)';
  END IF;
  RAISE NOTICE '── JAMI: % ta trigger · xavfli/o''qilmagan: % · diqqat: % · is_locked ga tegadigan: %',
    v_n, v_risky, v_watch, v_lockw;

  INSERT INTO pg_temp.shb_ref VALUES
    ('trg_n',     v_n::text,     'public.tasks dagi trigger soni (tgisinternal EMAS)'),
    ('trg_lockw', v_lockw::text, 'is_locked ga tegadigan FAOL trigger soni (8b sinovi shunga qaraydi)'),
    ('trg_risky', v_risky::text, 'XAVFLI + O''QILMADI hukmini olgan trigger soni'),
    ('trg_names', CASE WHEN v_names = '' THEN '-' ELSE v_names END, 'xavfli trigger nomlari');

  -- ── 🔴 FAIL-CLOSED HUKM ───────────────────────────────────────────────────
  IF v_risky > 0 AND NOT coalesce(v_allow, false) THEN
    v_msg := '🔴 public.tasks da SHABLON MIGRATSIYASI UCHUN XAVFLI trigger topildi: '
      || v_risky::text || ' ta.' || v_bad
      || chr(10) || 'NIMA UCHUN XAVFLI: migratsiyadan keyin bitta loyihada bir xil tartib raqami (flow_order/order_index) IKKI marta bo''ladi — SHABLON (is_template = true; uning statusi hech qachon "completed" bo''lmaydi) va uning INSTANSIYASI; har yangi sikl yana N ta qator qo''shadi. Yuqoridagi trigger(lar) tartib raqami / qulf bilan ishlaydi, lekin tanasida `is_template` UMUMAN YO''Q — ya''ni shablon ham, o''tgan sikl qatori ham unga BOSQICH bo''lib ko''rinadi. Natija: (a) shablon keyingi bosqichni ABADIY qulflab qo''yadi, yoki (b) o''tgan siklning `completed` qatori yangi sikl bosqichini NOTO''G''RI ochib yuboradi.'
      || chr(10) || 'IKKI YO''L: (1) TAVSIYA ETILADI — trigger funksiyasidagi "oldingi/keyingi bosqich" qidiruviga qorovul qo''shing: `AND is_template IS NOT TRUE` va sikl uchun `AND cycle_id IS NOT DISTINCT FROM NEW.cycle_id`, so''ng shu skriptni QAYTA RUN qiling (idempotent). Funksiya tanasi yuqorida NOTICE bilan to''liq chop etildi. (2) ATAYLAB DAVOM ETISH — fayl boshidagi SOZLAMA blokida `v_allow_risky_trigger boolean := true` qiling.'
      || chr(10) || '🔴 HOZIRCHA HECH NARSA O''ZGARMADI — bu tekshiruv HAR QANDAY DDL DAN OLDIN turadi.';
    RAISE EXCEPTION '%', v_msg;
  END IF;

  IF v_risky > 0 THEN
    RAISE WARNING '⚙️ % ta XAVFLI trigger topildi (%), lekin v_allow_risky_trigger = TRUE — migratsiya ATAYLAB davom etmoqda. Bosqich qulflari noto''g''ri hisoblanishi mumkin.', v_risky, v_names;
  END IF;
  IF v_watch > 0 THEN
    RAISE WARNING 'DIQQAT: % ta trigger loyiha bo''yicha boshqa qatorlarni qidiradi va `is_template` ni bilmaydi (%). Tartib raqami/qulf bilan ishlamagani uchun MIGRATSIYA TO''XTATILMADI, lekin RUN''dan keyin ularning xatti-harakatini ko''rib chiqing.', v_watch, v_watchn;
  END IF;

  INSERT INTO pg_temp.shb_res VALUES
    (30, 'trigger', 'public.tasks dagi triggerlar (inventarizatsiya)',
     v_n::text || ' ta',
     'pg_trigger + pg_proc dan O''QILDI (tgisinternal EMAS). To''liq ro''yxat — RUN jurnalidagi NOTICE larda: nomi · vaqti (BEFORE/AFTER/INSTEAD OF) · hodisasi · funksiyasi · hukmi. is_locked ga tegadigan FAOL trigger: ' || v_lockw::text || ' ta.'),
    (31, 'trigger', '🔴 xavfli naqsh tekshiruvi (0e, statik)',
     CASE WHEN v_risky = 0 THEN 'XAVFLI YO''Q'
          ELSE '⚠️ ATAYLAB O''TKAZILDI: ' || v_names END,
     'Naqsh: funksiya tanasida (izohlar tozalangach) tartib raqami (flow_order/order_index) YOKI is_locked bor, `is_template` esa YO''Q → XAVFLI; tanasi o''qilmasa (C/internal) → ham XAVFLI (fail-closed). Sukut bo''yicha RAISE EXCEPTION bilan TO''XTATADI; chetlab o''tish faqat fayl boshidagi v_allow_risky_trigger := true orqali. Diqqat (loyiha bo''yicha qidiradi, tartib/qulfga tegmaydi): ' || v_watch::text || ' ta.');
END $trg$;



-- ════════════════════════════════════════════════════════════════════════════
-- 1) public.project_cycles — YANGI JADVAL
--    🔴 UNIQUE (project_id, cycle_no) — materializatsiya DA'VOSI shu indeks
--       orqali ATOMIK. Bayroq emas, INDEKS: ikki admin bir vaqtda loyihani
--       ochsa ikkinchisi 23505 oladi va JIM chiqadi (mavjud last_reset_at
--       optimistik da'vosining ruhi, lekin poyga oynasi umuman yo'q).
--    ⚠️ `end_at > start_at` CHECK ATAYLAB QO'YILMAYDI — sikl sanalari
--       loyihadan KO'CHIRILADI, TASKFIX_LOYIHA.sql esa RUN qilinmagan
--       bo'lishi mumkin (ya'ni projects da bunday CHECK yo'q va zid sana
--       bo'lishi mumkin). CHECK qo'yilsa migratsiya BITTA buzuq loyiha
--       tufayli TO'LIQ yiqilardi. Sikl sanasi — TA'RIFLOVCHI ma'lumot.
-- ════════════════════════════════════════════════════════════════════════════
DO $cyc$
DECLARE
  v_projtyp text;
  v_uuidfn  text;
  v_wsref   text;
  v_usrref  text;
  v_have    text;
BEGIN
  SELECT v INTO v_projtyp FROM pg_temp.shb_ref WHERE k='projtype';
  SELECT v INTO v_uuidfn  FROM pg_temp.shb_ref WHERE k='uuidfn';
  SELECT v INTO v_wsref   FROM pg_temp.shb_ref WHERE k='wsref';
  SELECT v INTO v_usrref  FROM pg_temp.shb_ref WHERE k='usrref';

  IF to_regclass('public.project_cycles') IS NULL THEN
    EXECUTE format($t$
      CREATE TABLE public.project_cycles (
        id              uuid PRIMARY KEY DEFAULT %s,
        workspace_id    uuid NOT NULL,
        project_id      %s   NOT NULL,
        cycle_no        int  NOT NULL,
        start_at        timestamptz,
        end_at          timestamptz,
        materialized_at timestamptz,
        closed_at       timestamptz,
        created_by      uuid,
        created_at      timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT project_cycles_no_chk CHECK (cycle_no >= 1),
        CONSTRAINT project_cycles_project_no_uq UNIQUE (project_id, cycle_no)
      )
    $t$, v_uuidfn, v_projtyp);
    RAISE NOTICE 'public.project_cycles YARATILDI (project_id tipi: %)', v_projtyp;
  ELSE
    RAISE NOTICE 'public.project_cycles mavjud — yetishmagan qismlari to''ldiriladi.';

    SELECT format_type(a.atttypid, a.atttypmod) INTO v_have
      FROM pg_attribute a
     WHERE a.attrelid='public.project_cycles'::regclass AND a.attname='project_id' AND NOT a.attisdropped;
    IF v_have IS NULL THEN
      RAISE EXCEPTION 'Mavjud public.project_cycles da project_id ustuni yo''q — bu boshqa jadval. To''xtatildi.';
    END IF;
    IF v_have IS DISTINCT FROM v_projtyp THEN
      RAISE EXCEPTION 'Mavjud project_cycles.project_id tipi %, projects.id tipi esa % — mos emas. Qo''lda ko''rib chiqing; skript hech narsani o''zgartirmadi.', v_have, v_projtyp;
    END IF;

    ALTER TABLE public.project_cycles ADD COLUMN IF NOT EXISTS workspace_id    uuid;
    ALTER TABLE public.project_cycles ADD COLUMN IF NOT EXISTS cycle_no        int;
    ALTER TABLE public.project_cycles ADD COLUMN IF NOT EXISTS start_at        timestamptz;
    ALTER TABLE public.project_cycles ADD COLUMN IF NOT EXISTS end_at          timestamptz;
    ALTER TABLE public.project_cycles ADD COLUMN IF NOT EXISTS materialized_at timestamptz;
    ALTER TABLE public.project_cycles ADD COLUMN IF NOT EXISTS closed_at       timestamptz;
    ALTER TABLE public.project_cycles ADD COLUMN IF NOT EXISTS created_by      uuid;
    ALTER TABLE public.project_cycles ADD COLUMN IF NOT EXISTS created_at      timestamptz NOT NULL DEFAULT now();
  END IF;

  -- 🔴 UNIQUE (project_id, cycle_no) — modulning YURAGI
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.project_cycles'::regclass
                    AND conname='project_cycles_project_no_uq') THEN
    ALTER TABLE public.project_cycles
      ADD CONSTRAINT project_cycles_project_no_uq UNIQUE (project_id, cycle_no);
    RAISE NOTICE 'UNIQUE (project_id, cycle_no) qo''shildi';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.project_cycles'::regclass
                    AND conname='project_cycles_no_chk') THEN
    ALTER TABLE public.project_cycles ADD CONSTRAINT project_cycles_no_chk CHECK (cycle_no >= 1);
  END IF;

  -- FK: project_id → projects(id) ON DELETE CASCADE (loyiha o'chsa sikllari ham)
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.project_cycles'::regclass
                    AND conname='project_cycles_project_fk') THEN
    ALTER TABLE public.project_cycles
      ADD CONSTRAINT project_cycles_project_fk
      FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;
  END IF;

  -- FK: workspace_id (nishon KATALOGDAN)
  IF v_wsref IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_constraint
                      WHERE conrelid='public.project_cycles'::regclass
                        AND conname='project_cycles_ws_fk') THEN
    BEGIN
      EXECUTE format('ALTER TABLE public.project_cycles ADD CONSTRAINT project_cycles_ws_fk FOREIGN KEY (workspace_id) REFERENCES %s ON DELETE CASCADE', v_wsref);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'workspace_id FK (%) qo''shilmadi: % — jadval FK''siz ishlayveradi (qiymat loyihadan olinadi).', v_wsref, SQLERRM;
    END;
  END IF;

  IF v_usrref IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_constraint
                      WHERE conrelid='public.project_cycles'::regclass
                        AND conname='project_cycles_created_by_fk') THEN
    BEGIN
      EXECUTE format('ALTER TABLE public.project_cycles ADD CONSTRAINT project_cycles_created_by_fk FOREIGN KEY (created_by) REFERENCES %s ON DELETE SET NULL', v_usrref);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'created_by FK (%) qo''shilmadi: % — audit maydoni, mantiqqa ta''sir qilmaydi.', v_usrref, SQLERRM;
    END;
  END IF;

  -- workspace_id / cycle_no NOT NULL — faqat bo'sh qator YO'Q bo'lsa
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='project_cycles'
                AND column_name='workspace_id' AND is_nullable='YES')
     AND NOT EXISTS (SELECT 1 FROM public.project_cycles WHERE workspace_id IS NULL) THEN
    ALTER TABLE public.project_cycles ALTER COLUMN workspace_id SET NOT NULL;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='project_cycles'
                AND column_name='cycle_no' AND is_nullable='YES')
     AND NOT EXISTS (SELECT 1 FROM public.project_cycles WHERE cycle_no IS NULL) THEN
    ALTER TABLE public.project_cycles ALTER COLUMN cycle_no SET NOT NULL;
  END IF;
END $cyc$;

-- ⚠️ (project_id, cycle_no) BO'YICHA ALOHIDA `CREATE INDEX` YOZILMADI —
--    UNIQUE cheklovi ayni shu ustunlar bo'yicha indeksni O'ZI yaratadi.
--    Ikkinchisini qo'shish DUBLIKAT bo'lardi (qo'shimcha yozuv yuki, nol foyda).
--    Boshqa yo'nalishlar uchun ikkita foydali indeks:
CREATE INDEX IF NOT EXISTS idx_project_cycles_ws   ON public.project_cycles (workspace_id);
CREATE INDEX IF NOT EXISTS idx_project_cycles_open ON public.project_cycles (project_id) WHERE closed_at IS NULL;

COMMENT ON TABLE public.project_cycles IS
  'Loyihaning bitta SIKLI (takrorlanuvchi loyihaning bir aylanishi). 🔴 UNIQUE (project_id, cycle_no) — materializatsiya DA''VOSI shu indeks orqali ATOMIK: mijoz keyingi siklni INSERT qiladi, 23505 qaytsa "boshqa admin ulgurdi" va JIM chiqadi. Bayroq/ustun bilan da''vo qilinsa poyga oynasi qolardi. Sikl QATORI HECH QACHON O''CHIRILMAYDI (DELETE policy ham, granti ham yo''q) — o''chirilsa unga tegishli instansiyalarning cycle_id si NULL bo''lib, ular hamma sikl filtridan yo''qolardi.';
COMMENT ON COLUMN public.project_cycles.cycle_no IS
  'Sikl raqami, 1 dan boshlanadi. Migratsiya MAVJUD bosqichlarni 1-siklga bog''laydi.';
COMMENT ON COLUMN public.project_cycles.start_at IS
  'Sikl boshlanishi. Migratsiyada projects.start_at dan KO''CHIRILADI (ustun bo''lmasa NULL). ⚠️ end_at > start_at CHECK ATAYLAB yo''q — TASKFIX_LOYIHA.sql RUN qilinmagan bazada projects da bunday cheklov yo''q va bitta zid sana butun migratsiyani yiqitardi.';
COMMENT ON COLUMN public.project_cycles.materialized_at IS
  'Shu sikl instansiyalari shablonlardan OCHILGAN vaqt. Migratsiyada 1-sikl uchun darrov to''ldiriladi (mavjud bosqichlar allaqachon "ochilgan").';
COMMENT ON COLUMN public.project_cycles.closed_at IS
  'Sikl YOPILGAN vaqt. Mijoz keyingi siklni ochishdan oldin joriysini yopadi. NULL = ochiq (joriy) sikl.';


-- ════════════════════════════════════════════════════════════════════════════
-- 2) public.tasks GA 3 USTUN + CHECK
--    ⚠️ 🔴 SHU YERDA `public.tasks` GA ACCESS EXCLUSIVE QULF OLINADI va u
--       COMMIT gacha USHLAB TURILADI.
--    ⚠️ is_template DEFAULT false — PG11+ da bu "fast default", jadval QAYTA
--       YOZILMAYDI (faqat katalog yozuvi + CHECK skanerlash).
-- ════════════════════════════════════════════════════════════════════════════
DO $tcol$
DECLARE
  v_idtype text;
  v_nulls  bigint;
BEGIN
  SELECT v INTO v_idtype FROM pg_temp.shb_ref WHERE k='idtype';

  ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS is_template boolean NOT NULL DEFAULT false;
  EXECUTE format('ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS template_id %s', v_idtype);
  ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS cycle_id uuid;

  -- Ustun ALLAQACHON bor va NULLABLE bo'lsa (yarim o'rnatilgan holat)
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='tasks'
                AND column_name='is_template' AND is_nullable='YES') THEN
    SELECT count(*) INTO v_nulls FROM public.tasks WHERE is_template IS NULL;
    IF v_nulls = 0 THEN
      ALTER TABLE public.tasks ALTER COLUMN is_template SET NOT NULL;
      ALTER TABLE public.tasks ALTER COLUMN is_template SET DEFAULT false;
    ELSE
      RAISE WARNING 'public.tasks.is_template da NULL bo''lgan % qator bor — NOT NULL QO''YILMADI (mavjud ma''lumot bosilmasin). CHECK NULL ni ham to''g''ri qabul qiladi (IS NOT TRUE). Ularni to''ldirgach: ALTER TABLE public.tasks ALTER COLUMN is_template SET NOT NULL;', v_nulls;
    END IF;
  END IF;
END $tcol$;

-- FK'lar
DO $tfk$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.tasks'::regclass AND conname='tasks_template_fk') THEN
    ALTER TABLE public.tasks
      ADD CONSTRAINT tasks_template_fk
      FOREIGN KEY (template_id) REFERENCES public.tasks(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.tasks'::regclass AND conname='tasks_cycle_fk') THEN
    ALTER TABLE public.tasks
      ADD CONSTRAINT tasks_cycle_fk
      FOREIGN KEY (cycle_id) REFERENCES public.project_cycles(id) ON DELETE SET NULL;
  END IF;

  -- 🔴 CHECK: shablon o'zi na instansiya, na siklga tegishli.
  --    `IS NOT TRUE` ataylab (`= false` emas): is_template NULL bo'lib qolgan
  --    yarim holatda ham qoida to'g'ri ishlaydi va mavjud qator buzilmaydi.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.tasks'::regclass AND conname='tasks_template_flags_chk') THEN
    ALTER TABLE public.tasks
      ADD CONSTRAINT tasks_template_flags_chk
      CHECK (is_template IS NOT TRUE OR (template_id IS NULL AND cycle_id IS NULL));
  END IF;
END $tfk$;

COMMENT ON COLUMN public.tasks.is_template IS
  '🔴 SHABLON belgisi: true = bu qator ISH EMAS, loyiha bosqichining TA''RIFI. Shablondan har sikl uchun yangi INSTANSIYA (is_template=false) ochiladi. ⚠️ Shablon ILOVANING QOLGAN QISMIDA KO''RINMAYDI: mijozda yagona choke-point (tasksAcceptRow) uni tasksCache ga qo''ymaydi — so''rov darajasida .eq(''is_template'', false) YOZILMAYDI, chunki ustun yo''q bazada butun so''rov 42703 bilan yiqilib ilova o''lardi. ⚠️ is_locked shablonga HECH QACHON yozilmaydi — u 34-migratsiya trigger''ining ketma-ketlik belgisi, shablon esa hech qachon qulflanmaydi.';
COMMENT ON COLUMN public.tasks.template_id IS
  'INSTANSIYA → o''z SHABLONI (tasks.id). Faqat is_template = false qatorlarda to''ladi (tasks_template_flags_chk). ON DELETE SET NULL — shablon o''chirilsa bajarilgan ish qatorlari YO''QOLMAYDI, shunchaki shablonsiz qoladi. Migratsiya har MAVJUD bosqich uchun shablon yaratib, aynan shu ustunni to''ldirgan.';
COMMENT ON COLUMN public.tasks.cycle_id IS
  'INSTANSIYA → o''zi tegishli SIKL (project_cycles.id). Faqat is_template = false qatorlarda to''ladi. ON DELETE SET NULL. Kanban/loyiha sahifasidagi SIKL FILTRI aynan shu ustun bo''yicha ishlaydi — shuning uchun o''tgan siklning REJA/FAKT holati bazada SAQLANIB qoladi (avval prjResetRecurrence qatorlarni JOYIDA status=''new'' ga qaytarardi va o''tgan sikl fakti YO''QOLARDI).';

-- Indekslar (tasks). ⚠️ CREATE INDEX tranzaksiya ichida CONCURRENTLY BO'LA
--    OLMAYDI; baribir tasks ga ACCESS EXCLUSIVE allaqachon olingan.
--    🔴 cycle_id / template_id indekslari QISMAN (WHERE ... IS NOT NULL):
--       ular faqat loyiha bosqichlarida to'ladi, ya'ni 20k vazifali bazada
--       indeks o'nlab marta kichik bo'ladi va `= $1` so'rovlarini AYNAN
--       to'liq indeks kabi qoplaydi.
CREATE INDEX IF NOT EXISTS idx_tasks_project_is_template ON public.tasks (project_id, is_template);
CREATE INDEX IF NOT EXISTS idx_tasks_cycle    ON public.tasks (cycle_id)    WHERE cycle_id    IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_template ON public.tasks (template_id) WHERE template_id IS NOT NULL;


-- ════════════════════════════════════════════════════════════════════════════
-- 3) public.template_history — YANGI JADVAL (shablon meta-tarixi)
--    TEXT + CHECK, ENUM EMAS (CLAUDE.md 3-qoida).
-- ════════════════════════════════════════════════════════════════════════════
DO $th$
DECLARE
  v_idtype  text;
  v_projtyp text;
  v_uuidfn  text;
  v_wsref   text;
  v_usrref  text;
  v_have    text;
BEGIN
  SELECT v INTO v_idtype  FROM pg_temp.shb_ref WHERE k='idtype';
  SELECT v INTO v_projtyp FROM pg_temp.shb_ref WHERE k='projtype';
  SELECT v INTO v_uuidfn  FROM pg_temp.shb_ref WHERE k='uuidfn';
  SELECT v INTO v_wsref   FROM pg_temp.shb_ref WHERE k='wsref';
  SELECT v INTO v_usrref  FROM pg_temp.shb_ref WHERE k='usrref';

  IF to_regclass('public.template_history') IS NULL THEN
    EXECUTE format($t$
      CREATE TABLE public.template_history (
        id              uuid PRIMARY KEY DEFAULT %s,
        workspace_id    uuid NOT NULL,
        project_id      %s   NOT NULL,
        template_id     %s,
        action          text NOT NULL,
        task_id         %s,
        cycle_id        uuid,
        changes         jsonb,
        changed_by      uuid,
        changed_by_name text,
        changed_at      timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT template_history_action_chk
          CHECK (action IN ('created', 'edited', 'materialized', 'archived'))
      )
    $t$, v_uuidfn, v_projtyp, v_idtype, v_idtype);
    RAISE NOTICE 'public.template_history YARATILDI';
  ELSE
    RAISE NOTICE 'public.template_history mavjud — yetishmagan qismlari to''ldiriladi.';

    SELECT format_type(a.atttypid, a.atttypmod) INTO v_have
      FROM pg_attribute a
     WHERE a.attrelid='public.template_history'::regclass AND a.attname='template_id' AND NOT a.attisdropped;
    IF v_have IS NOT NULL AND v_have IS DISTINCT FROM v_idtype THEN
      RAISE EXCEPTION 'Mavjud template_history.template_id tipi % (kutilgan %) — mos emas. To''xtatildi.', v_have, v_idtype;
    END IF;

    EXECUTE format('ALTER TABLE public.template_history ADD COLUMN IF NOT EXISTS template_id %s', v_idtype);
    EXECUTE format('ALTER TABLE public.template_history ADD COLUMN IF NOT EXISTS task_id %s', v_idtype);
    ALTER TABLE public.template_history ADD COLUMN IF NOT EXISTS cycle_id        uuid;
    ALTER TABLE public.template_history ADD COLUMN IF NOT EXISTS changes         jsonb;
    ALTER TABLE public.template_history ADD COLUMN IF NOT EXISTS changed_by      uuid;
    ALTER TABLE public.template_history ADD COLUMN IF NOT EXISTS changed_by_name text;
    ALTER TABLE public.template_history ADD COLUMN IF NOT EXISTS changed_at      timestamptz NOT NULL DEFAULT now();

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid='public.template_history'::regclass
                      AND conname='template_history_action_chk') THEN
      ALTER TABLE public.template_history
        ADD CONSTRAINT template_history_action_chk
        CHECK (action IN ('created', 'edited', 'materialized', 'archived'));
    END IF;
  END IF;

  -- FK'lar
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.template_history'::regclass
                    AND conname='template_history_project_fk') THEN
    ALTER TABLE public.template_history
      ADD CONSTRAINT template_history_project_fk
      FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.template_history'::regclass
                    AND conname='template_history_template_fk') THEN
    ALTER TABLE public.template_history
      ADD CONSTRAINT template_history_template_fk
      FOREIGN KEY (template_id) REFERENCES public.tasks(id) ON DELETE CASCADE;
  END IF;

  -- ⚠️ task_id / cycle_id — SET NULL: instansiya yoki sikl o'chsa "shablondan
  --    ochildi" hodisasining O'ZI yo'qolmasin (bu audit yozuvi).
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.template_history'::regclass
                    AND conname='template_history_task_fk') THEN
    ALTER TABLE public.template_history
      ADD CONSTRAINT template_history_task_fk
      FOREIGN KEY (task_id) REFERENCES public.tasks(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.template_history'::regclass
                    AND conname='template_history_cycle_fk') THEN
    ALTER TABLE public.template_history
      ADD CONSTRAINT template_history_cycle_fk
      FOREIGN KEY (cycle_id) REFERENCES public.project_cycles(id) ON DELETE SET NULL;
  END IF;

  IF v_wsref IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_constraint
                      WHERE conrelid='public.template_history'::regclass
                        AND conname='template_history_ws_fk') THEN
    BEGIN
      EXECUTE format('ALTER TABLE public.template_history ADD CONSTRAINT template_history_ws_fk FOREIGN KEY (workspace_id) REFERENCES %s ON DELETE CASCADE', v_wsref);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'template_history.workspace_id FK (%) qo''shilmadi: % — jadval FK''siz ishlayveradi.', v_wsref, SQLERRM;
    END;
  END IF;

  IF v_usrref IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_constraint
                      WHERE conrelid='public.template_history'::regclass
                        AND conname='template_history_changed_by_fk') THEN
    BEGIN
      EXECUTE format('ALTER TABLE public.template_history ADD CONSTRAINT template_history_changed_by_fk FOREIGN KEY (changed_by) REFERENCES %s ON DELETE SET NULL', v_usrref);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'template_history.changed_by FK (%) qo''shilmadi: % — audit maydoni.', v_usrref, SQLERRM;
    END;
  END IF;
END $th$;

CREATE INDEX IF NOT EXISTS idx_template_history_tpl ON public.template_history (template_id, changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_template_history_prj ON public.template_history (project_id,  changed_at DESC);

COMMENT ON TABLE public.template_history IS
  'SHABLON meta-tarixi: shablon qachon yaratilgan/tahrirlangan, qaysi siklda materializatsiya qilingan, qachon arxivlangan. ⚠️ Bu vazifa tarixi (task_history) EMAS — u instansiyaning deadline/assigned_to/status o''zgarishlarini yozadi va tegilmagan. Qator O''ZGARMAS: UPDATE/DELETE policy ham, granti ham YO''Q.';
COMMENT ON COLUMN public.template_history.action IS
  'created | edited | materialized | archived — TEXT + CHECK (ENUM EMAS, 30/32-migratsiyalar saboqi: ENUM ga yangi qiymat qo''shish jadvalni qulflaydi va eskisini o''chirib bo''lmaydi).';
COMMENT ON COLUMN public.template_history.changes IS
  'Ixtiyoriy jsonb tafsilot. Migratsiya yozgan qatorlarda: {"source":"TASKFIX_SHABLON.sql","from_task":"<eski bosqich id>","cycle_no":1}.';
COMMENT ON COLUMN public.template_history.changed_by_name IS
  'O''zgartirgan odam ismi — TEXT, profiles JOIN shart emas (odam o''chsa ham qoladi). 🔴 BU YERGA TARJIMA YOZILMAYDI (CLAUDE.md 10-qoida): migratsiya qatorlarida NULL, matnni mijoz tr() bilan chizadi.';


-- ════════════════════════════════════════════════════════════════════════════
-- 4) RUXSAT FUNKSIYASI + RLS + GRANT
--    🔴 CLAUDE.md 8-qoida: policy ichida workspace_members inline subquery
--       YOZILMAYDI (42P17) — is_ws_member()/is_ws_manager().
--    🔴 "Loyiha yaratuvchisi" tekshiruvi policy ichida `projects` ga TO'G'RIDAN
--       murojaat QILMAYDI: u yerda projects ning O'Z RLS'i qo'llanib, egasiga
--       ham qator ko'rinmay qolishi mumkin edi. O'rniga SECURITY DEFINER
--       yordamchi funksiya — can_see_project() / can_edit_task_deps() naqshi.
-- ════════════════════════════════════════════════════════════════════════════
DO $fn$
DECLARE
  v_projtyp text;
  v_own     text;
  r         RECORD;
BEGIN
  SELECT v INTO v_projtyp FROM pg_temp.shb_ref WHERE k='projtype';
  SELECT v INTO v_own     FROM pg_temp.shb_ref WHERE k='ownexpr';
  IF v_projtyp IS NULL OR v_own IS NULL THEN
    RAISE EXCEPTION 'projtype / ownexpr aniqlanmagan — 0c bo''limi bajarilmadimi?';
  END IF;

  -- Eski, BOSHQA imzoli nusxa qolgan bo'lsa tozalanadi.
  FOR r IN
    SELECT p.oid, pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='can_edit_project_cycles'
  LOOP
    IF lower(btrim(r.args)) IS DISTINCT FROM lower('p_project ' || v_projtyp || ', p_user uuid') THEN
      RAISE NOTICE 'Eski imzo o''chirilmoqda: can_edit_project_cycles(%)', r.args;
      EXECUTE format('DROP FUNCTION public.can_edit_project_cycles(%s)', r.args);
    END IF;
  END LOOP;

  EXECUTE format($f$
    CREATE OR REPLACE FUNCTION public.can_edit_project_cycles(p_project %s, p_user uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $fb$
      -- 🔴 QOROVUL 1 — `p_user = (SELECT auth.uid())`. MAJBURIY QATOR,
      --    OLIB TASHLAMANG. Funksiya `authenticated` ga EXECUTE bilan ochiq,
      --    ya'ni uni PostgREST orqali to'g'ridan chaqirish mumkin:
      --        POST /rest/v1/rpc/can_edit_project_cycles {p_project, p_user}
      --    Bu qatorsiz istalgan foydalanuvchi begona odam haqida
      --    "u falon loyihaning egasimi?" javobini ola olardi (SECURITY
      --    DEFINER RLS ni chetlab o'tadi).
      -- 🔴 QOROVUL 2 — `is_ws_member(...)`. MAJBURIY: jamoadan CHIQARILGAN
      --    xodim huquqni SAQLAB QOLMASIN. rmxDoRemove uni faqat
      --    workspace_members dan chiqaradi, projects.created_by esa o'sha
      --    uid da QOLADI — ya'ni busiz u chiqarilgandan keyin ham sikl
      --    ocha/yopa olardi (SELECT to'silgani uchun KO'RMASDAN).
      SELECT p_project IS NOT NULL
         AND p_user IS NOT NULL
         AND p_user = (SELECT auth.uid())
         AND EXISTS (
               SELECT 1
                 FROM public.projects p
                WHERE p.id = p_project
                  AND public.is_ws_member(p.workspace_id, p_user)
                  AND (%s)
             );
    $fb$
  $f$, v_projtyp, v_own);

  EXECUTE format(
    'COMMENT ON FUNCTION public.can_edit_project_cycles(%s, uuid) IS %L',
    v_projtyp,
    'p_user shu loyihaning SIKL va SHABLON TARIXI qatorlarini yoza oladimi? FAQAT ws-menejeri YOKI loyiha YARATUVCHISI (projects.created_by, ustun bo''lsa). SECURITY DEFINER — projects ni RLS''siz o''qiydi (policy ichidan chaqiriladi). IKKI MAJBURIY qorovul: p_user = auth.uid() (PostgREST /rpc teshigi) va is_ws_member (jamoadan chiqarilgan xodim).');

  -- 🔴 REVOKE ... FROM PUBLIC YETARLI EMAS: Supabase'da ALTER DEFAULT
  --    PRIVILEGES ... GRANT ALL ON FUNCTIONS TO anon, authenticated
  --    o'rnatilgan bo'lishi mumkin. Shuning uchun aniq `FROM anon`.
  EXECUTE format('REVOKE ALL ON FUNCTION public.can_edit_project_cycles(%s, uuid) FROM PUBLIC', v_projtyp);
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    EXECUTE format('REVOKE ALL ON FUNCTION public.can_edit_project_cycles(%s, uuid) FROM anon', v_projtyp);
  END IF;
  EXECUTE format('REVOKE ALL ON FUNCTION public.can_edit_project_cycles(%s, uuid) FROM authenticated', v_projtyp);
  -- EXECUTE authenticated'ga SHART: RLS ifodasi CHAQIRUVCHI huquqi bilan
  -- baholanadi (can_see_project / can_view_planner naqshi).
  EXECUTE format('GRANT EXECUTE ON FUNCTION public.can_edit_project_cycles(%s, uuid) TO authenticated', v_projtyp);
END $fn$;

ALTER TABLE public.project_cycles   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.template_history ENABLE ROW LEVEL SECURITY;

-- ── project_cycles ──────────────────────────────────────────────────────────
--    KO'RISH: ws a'zosi (loyiha sahifasi hamma a'zoga ochiq — sikl tanlagichi
--             ham ochiq bo'lishi kerak).
--    YOZISH:  ws-menejeri YOKI loyiha yaratuvchisi.
--    DELETE policy ATAYLAB YO'Q — sikl tarixiy yozuv (jadval izohiga qarang).
DROP POLICY IF EXISTS project_cycles_select ON public.project_cycles;
CREATE POLICY project_cycles_select ON public.project_cycles
  FOR SELECT TO authenticated
  USING (public.is_ws_member(workspace_id, (SELECT auth.uid())));

DROP POLICY IF EXISTS project_cycles_insert ON public.project_cycles;
CREATE POLICY project_cycles_insert ON public.project_cycles
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_ws_member(workspace_id, (SELECT auth.uid()))
    AND public.can_edit_project_cycles(project_id, (SELECT auth.uid()))
  );

DROP POLICY IF EXISTS project_cycles_update ON public.project_cycles;
CREATE POLICY project_cycles_update ON public.project_cycles
  FOR UPDATE TO authenticated
  USING (
    public.is_ws_member(workspace_id, (SELECT auth.uid()))
    AND public.can_edit_project_cycles(project_id, (SELECT auth.uid()))
  )
  WITH CHECK (
    public.is_ws_member(workspace_id, (SELECT auth.uid()))
    AND public.can_edit_project_cycles(project_id, (SELECT auth.uid()))
  );

-- ── template_history ────────────────────────────────────────────────────────
--    KO'RISH: ws a'zosi. YOZISH: ws-menejeri YOKI loyiha yaratuvchisi, va
--    FAQAT O'Z NOMIDAN (changed_by = auth.uid() — task_history naqshi).
--    UPDATE/DELETE policy YO'Q → tarix o'zgarmas.
DROP POLICY IF EXISTS template_history_select ON public.template_history;
CREATE POLICY template_history_select ON public.template_history
  FOR SELECT TO authenticated
  USING (public.is_ws_member(workspace_id, (SELECT auth.uid())));

DROP POLICY IF EXISTS template_history_insert ON public.template_history;
CREATE POLICY template_history_insert ON public.template_history
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_ws_member(workspace_id, (SELECT auth.uid()))
    AND public.can_edit_project_cycles(project_id, (SELECT auth.uid()))
    AND changed_by = (SELECT auth.uid())
  );

DO $grant$
BEGIN
  REVOKE ALL ON TABLE public.project_cycles   FROM PUBLIC;
  REVOKE ALL ON TABLE public.template_history FROM PUBLIC;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    -- 🔴 anon ga HECH NARSA: sikl/shablon tarixi kirmagan odamga ochilmaydi.
    EXECUTE 'REVOKE ALL ON TABLE public.project_cycles   FROM anon';
    EXECUTE 'REVOKE ALL ON TABLE public.template_history FROM anon';
  END IF;

  -- ⚠️ DELETE granti ATAYLAB berilmaydi (ikkala jadvalda ham).
  GRANT SELECT, INSERT, UPDATE ON TABLE public.project_cycles   TO authenticated;
  GRANT SELECT, INSERT         ON TABLE public.template_history TO authenticated;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.project_cycles   TO service_role';
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.template_history TO service_role';
  END IF;
END $grant$;


-- ════════════════════════════════════════════════════════════════════════════
-- 5) STRUKTURA TEKSHIRUVI — "yaratdim" degan yozuvga ishonmaymiz
--    Hamma narsa KATALOGDAN qayta o'qiladi. Kutilganidek bo'lmasa
--    RAISE EXCEPTION → butun tranzaksiya qaytadi.
-- ════════════════════════════════════════════════════════════════════════════
DO $ver$
DECLARE
  v_n      int;
  v_miss   text;
  v_def    text;
  v_colacl int;
  v_names  text;
  v_rls    boolean;
BEGIN
  -- (a) tasks 3 ustun
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='tasks'
     AND column_name IN ('is_template','template_id','cycle_id');
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'TEKSHIRUV: tasks da 3 yangi ustun kutilgandi, % ta topildi. HAMMASI QAYTARILDI.', v_n;
  END IF;

  -- (b) CHECK + FK'lar
  SELECT string_agg(c, ', ') INTO v_miss FROM unnest(ARRAY[
    'tasks_template_flags_chk','tasks_template_fk','tasks_cycle_fk'
  ]) c WHERE NOT EXISTS (SELECT 1 FROM pg_constraint
                          WHERE conname=c AND conrelid='public.tasks'::regclass);
  IF v_miss IS NOT NULL THEN
    RAISE EXCEPTION 'TEKSHIRUV: tasks da cheklov(lar) yetishmayapti: %. HAMMASI QAYTARILDI.', v_miss;
  END IF;

  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint
   WHERE conname='tasks_template_flags_chk' AND conrelid='public.tasks'::regclass;
  IF strpos(coalesce(v_def,''), 'template_id') = 0 OR strpos(coalesce(v_def,''), 'cycle_id') = 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV: tasks_template_flags_chk MAVJUD, lekin ta''rifi kutilganidan BOSHQA (template_id / cycle_id ga murojaat qilmaydi). Hozirgi ta''rif: %. HAMMASI QAYTARILDI.', coalesce(v_def, 'YO''Q');
  END IF;

  -- (c) project_cycles: jadval + UNIQUE
  IF to_regclass('public.project_cycles') IS NULL THEN
    RAISE EXCEPTION 'TEKSHIRUV: public.project_cycles yaratilmadi. HAMMASI QAYTARILDI.';
  END IF;
  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint
   WHERE conname='project_cycles_project_no_uq' AND conrelid='public.project_cycles'::regclass;
  IF v_def IS NULL THEN
    RAISE EXCEPTION 'TEKSHIRUV: 🔴 project_cycles_project_no_uq (UNIQUE project_id, cycle_no) YO''Q. Materializatsiya da''vosi shu indeksga tayanadi — usiz ikki admin bir siklni ikki marta ocha olardi. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_def, 'project_id') = 0 OR strpos(v_def, 'cycle_no') = 0 OR strpos(v_def, 'UNIQUE') = 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV: project_cycles_project_no_uq ta''rifi kutilganidan BOSHQA: %. HAMMASI QAYTARILDI.', v_def;
  END IF;

  -- (d) template_history: jadval + action CHECK 4 qiymat
  IF to_regclass('public.template_history') IS NULL THEN
    RAISE EXCEPTION 'TEKSHIRUV: public.template_history yaratilmadi. HAMMASI QAYTARILDI.';
  END IF;
  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint
   WHERE conname='template_history_action_chk' AND conrelid='public.template_history'::regclass;
  IF v_def IS NULL THEN
    RAISE EXCEPTION 'TEKSHIRUV: template_history_action_chk YO''Q. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_def,'created')=0 OR strpos(v_def,'edited')=0
     OR strpos(v_def,'materialized')=0 OR strpos(v_def,'archived')=0 THEN
    RAISE EXCEPTION 'TEKSHIRUV: template_history_action_chk da 4 qiymatning hammasi yo''q: %. HAMMASI QAYTARILDI.', v_def;
  END IF;

  -- (e) RLS yoqilganmi + policy'lar joyidami
  SELECT relrowsecurity INTO v_rls FROM pg_class WHERE oid='public.project_cycles'::regclass;
  IF NOT coalesce(v_rls,false) THEN
    RAISE EXCEPTION 'TEKSHIRUV: project_cycles da RLS YOQILMAGAN. HAMMASI QAYTARILDI.';
  END IF;
  SELECT relrowsecurity INTO v_rls FROM pg_class WHERE oid='public.template_history'::regclass;
  IF NOT coalesce(v_rls,false) THEN
    RAISE EXCEPTION 'TEKSHIRUV: template_history da RLS YOQILMAGAN. HAMMASI QAYTARILDI.';
  END IF;

  SELECT string_agg(c, ', ') INTO v_miss FROM unnest(ARRAY[
    'project_cycles_select','project_cycles_insert','project_cycles_update'
  ]) c WHERE NOT EXISTS (SELECT 1 FROM pg_policies
                          WHERE schemaname='public' AND tablename='project_cycles' AND policyname=c);
  IF v_miss IS NOT NULL THEN
    RAISE EXCEPTION 'TEKSHIRUV: project_cycles policy(lar) yetishmayapti: %. HAMMASI QAYTARILDI.', v_miss;
  END IF;

  SELECT string_agg(c, ', ') INTO v_miss FROM unnest(ARRAY[
    'template_history_select','template_history_insert'
  ]) c WHERE NOT EXISTS (SELECT 1 FROM pg_policies
                          WHERE schemaname='public' AND tablename='template_history' AND policyname=c);
  IF v_miss IS NOT NULL THEN
    RAISE EXCEPTION 'TEKSHIRUV: template_history policy(lar) yetishmayapti: %. HAMMASI QAYTARILDI.', v_miss;
  END IF;

  -- 🔴 O'ZGARMASLIK: template_history ga UPDATE/DELETE policy QO'SHILMAGAN bo'lsin
  IF EXISTS (SELECT 1 FROM pg_policies
              WHERE schemaname='public' AND tablename='template_history'
                AND cmd IN ('UPDATE','DELETE')) THEN
    RAISE EXCEPTION 'TEKSHIRUV: template_history ga UPDATE/DELETE policy qo''shilibdi — tarix O''ZGARMAS bo''lishi kerak. HAMMASI QAYTARILDI.';
  END IF;

  -- (f) ruxsat funksiyasi tanasidagi IKKI MAJBURIY QOROVUL
  --     ⚠️ izohlar olib tashlanadi — "izohda bor" yetarli emas.
  SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='can_edit_project_cycles' LIMIT 1;
  IF v_def IS NULL THEN
    RAISE EXCEPTION 'TEKSHIRUV: can_edit_project_cycles() yaratilmadi. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_def, 'auth.uid()') = 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV: can_edit_project_cycles() da `p_user = (SELECT auth.uid())` qorovuli YO''Q — PostgREST /rpc orqali begona odam haqida ma''lumot berardi. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_def, 'is_ws_member') = 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV: can_edit_project_cycles() da is_ws_member qorovuli YO''Q — jamoadan chiqarilgan xodim huquqni saqlab qolardi. HAMMASI QAYTARILDI.';
  END IF;
  IF strpos(v_def, 'is_ws_manager') = 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV: can_edit_project_cycles() da is_ws_manager yo''q — huquq ifodasi kutilganidek emas. HAMMASI QAYTARILDI.';
  END IF;

  -- (g) tasks da USTUN darajasidagi GRANT — u YANGI ustunlarga MEROS O'TMAYDI
  SELECT count(*), string_agg(attname, ', ') INTO v_colacl, v_names
    FROM pg_attribute
   WHERE attrelid='public.tasks'::regclass
     AND attnum > 0 AND NOT attisdropped AND attacl IS NOT NULL;
  IF coalesce(v_colacl,0) > 0 THEN
    RAISE WARNING 'public.tasks da USTUN darajasidagi GRANT bor (%). Bunday grant YANGI ustunlarga MEROS O''TMAYDI — is_template / template_id / cycle_id PostgREST orqali ko''rinmasligi mumkin. Kerak bo''lsa qo''lda: GRANT SELECT(is_template, template_id, cycle_id), UPDATE(is_template, template_id, cycle_id) ON public.tasks TO authenticated;', v_names;
  END IF;

  RAISE NOTICE 'TASKFIX_SHABLON: struktura OK — 3 ustun + CHECK + 2 jadval + RLS joyida.';
END $ver$;


-- ════════════════════════════════════════════════════════════════════════════
-- 6) 🔴 MAVJUD MA'LUMOT MIGRATSIYASI
--    Har loyiha uchun: 1-sikl qatori + har bosqichning SHABLON nusxasi.
--    🔴 IDEMPOTENTLIK QOROVULI: loyihada ALLAQACHON project_cycles qatori
--       bo'lsa — o'sha loyiha BUTUNLAY o'tkazib yuboriladi. Sabab: "bosqichda
--       template_id yo'q" sharti yetarli EMAS — migratsiyadan KEYIN 2-, 3-...
--       siklda qo'lda qo'shilgan bosqich ham shu shartga tushib, JIMGINA
--       1-SIKLGA bog'lanib qolardi (o'tgan sikl fakti buzilardi).
-- ════════════════════════════════════════════════════════════════════════════

-- O'zgarishdan OLDINGI holat: mavjud bosqich id'lari + ularga bog'langan
-- bola qatorlar soni. (c) tekshiruvi aynan shu ikkisini solishtiradi.
DROP TABLE IF EXISTS pg_temp.shb_before;
CREATE TEMP TABLE pg_temp.shb_before (id text PRIMARY KEY, fp text, fp_after text);

DROP TABLE IF EXISTS pg_temp.shb_child;
CREATE TEMP TABLE pg_temp.shb_child (tbl text, col text, n_before bigint, n_after bigint);

DROP TABLE IF EXISTS pg_temp.shb_map;
CREATE TEMP TABLE pg_temp.shb_map (old_id text PRIMARY KEY, new_id text, project_id text, cycle_id uuid);

DROP TABLE IF EXISTS pg_temp.shb_done;
CREATE TEMP TABLE pg_temp.shb_done (project_id text PRIMARY KEY, ws uuid, cycle_id uuid, stages int);

-- 🔴 BARMOQ IZI (fingerprint): mavjud bosqichning MA'NOLI maydonlari.
--    Nima uchun kerak: `public.tasks` da BEGONA triggerlar bor (34-migratsiya
--    qulf trigger'i, zz_task_wait_guard_trg va ehtimol boshqalar) va ular
--    YANGI qator INSERT qilinganda MAVJUD qatorlarni ham o'zgartirib
--    yuborishi mumkin (masalan is_locked ni qayta hisoblash). Bunday
--    o'zgarish JIMGINA sodir bo'lardi. Shu sabab oldin/keyin solishtiramiz.
--    ⚠️ template_id / cycle_id ATAYLAB kirmaydi — ularni migratsiyaning O'ZI
--       to'ldiradi; updated_at ham kirmaydi (trigger uni yangilashi normal).
DROP TABLE IF EXISTS pg_temp.shb_fp;
CREATE TEMP TABLE pg_temp.shb_fp (expr text);

DO $fp$
DECLARE
  v_e   text;
  v_c   text;
BEGIN
  SELECT string_agg('coalesce(t.' || quote_ident(c) || '::text, '''')', ' || ''|'' || ')
    INTO v_e
    FROM unnest(ARRAY['status','is_locked','deadline','assigned_to','acceptor_id',
                      'flow_order','depends_on_prev','title','project_id','workspace_id']) c
   WHERE EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name=c);
  IF v_e IS NULL THEN
    v_e := '''''';   -- hech biri yo'q (bo'lmasligi kerak) — bo'sh barmoq izi
    RAISE WARNING 'Barmoq izi uchun bironta ham kutilgan ustun topilmadi — (c3) tekshiruvi ma''nosiz bo''ladi.';
  END IF;
  INSERT INTO pg_temp.shb_fp VALUES (v_e);

  EXECUTE 'INSERT INTO pg_temp.shb_before (id, fp) SELECT t.id::text, ' || v_e
       || ' FROM public.tasks t WHERE t.project_id IS NOT NULL AND t.is_template IS NOT TRUE';
END $fp$;

-- tasks(id) ga FK bilan bog'langan HAR JADVAL (tasks ning o'zidan tashqari)
DO $child$
DECLARE
  r  RECORD;
  v_n bigint;
BEGIN
  FOR r IN
    SELECT c.conrelid::regclass::text AS tbl, a.attname AS col
      FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=c.conkey[1]
     WHERE c.contype='f' AND c.confrelid='public.tasks'::regclass
       AND array_length(c.conkey,1)=1
       AND c.conrelid <> 'public.tasks'::regclass
     ORDER BY 1, 2
  LOOP
    EXECUTE format('SELECT count(*) FROM %s x JOIN pg_temp.shb_before b ON x.%I::text = b.id',
                   r.tbl, r.col) INTO v_n;
    INSERT INTO pg_temp.shb_child VALUES (r.tbl, r.col, v_n, NULL);
  END LOOP;
END $child$;

DO $mig$
DECLARE
  v_idtype  text;
  v_projtyp text;
  v_cols    text;
  v_colsrc  text;
  v_stmode  text;
  v_hasflow boolean;
  v_prjsel  text;
  v_inspre  text;
  v_inspost text;
  v_ordexpr text;
  v_p       text;
  v_ws      uuid;
  v_st      timestamptz;
  v_en      timestamptz;
  v_cb      uuid;
  v_cyc     uuid;
  v_old     text;
  v_new     text;
  v_stage   int;
  v_total   bigint;
  v_prjn    int := 0;
  v_skipn   int := 0;
  v_tpln    int := 0;
  v_depn    bigint := 0;
  v_ex      boolean;
BEGIN
  SELECT v INTO v_idtype  FROM pg_temp.shb_ref WHERE k='idtype';
  SELECT v INTO v_projtyp FROM pg_temp.shb_ref WHERE k='projtype';
  SELECT v INTO v_cols    FROM pg_temp.shb_ref WHERE k='cols';
  SELECT v INTO v_colsrc  FROM pg_temp.shb_ref WHERE k='colsrc';
  SELECT v INTO v_stmode  FROM pg_temp.shb_ref WHERE k='stmode';
  SELECT (v = 'true') INTO v_hasflow FROM pg_temp.shb_ref WHERE k='has_flow';

  -- ── Hajm haqida OCHIQ xabar (qulf shu vaqt davomida ushlab turiladi) ─────
  SELECT count(*) INTO v_total FROM public.tasks t
   WHERE t.project_id IS NOT NULL AND t.is_template IS NOT TRUE AND t.template_id IS NULL;
  RAISE NOTICE 'Migratsiya: ko''chiriladigan bosqich soni (yuqori chegara) = %', v_total;
  IF v_total > 5000 THEN
    RAISE WARNING 'Ko''chiriladigan bosqich soni juda katta (%). public.tasks ga ACCESS EXCLUSIVE qulf shu davomiylikda ushlab turiladi — ilova javob bermay turishi mumkin.', v_total;
  END IF;

  -- ── Loyiha ma'lumoti so'rovi (ixtiyoriy ustunlar hisobga olinadi) ────────
  v_prjsel := 'SELECT p.workspace_id, '
    || CASE WHEN (SELECT v FROM pg_temp.shb_ref WHERE k='prj_start') = 'true'
            THEN 'p.start_at' ELSE 'NULL::timestamptz' END || ', '
    || CASE WHEN (SELECT v FROM pg_temp.shb_ref WHERE k='prj_end') = 'true'
            THEN 'p.end_at' ELSE 'NULL::timestamptz' END || ', '
    || CASE WHEN (SELECT v FROM pg_temp.shb_ref WHERE k='prj_cb') = 'true'
            THEN 'p.created_by' ELSE 'NULL::uuid' END
    || ' FROM public.projects p WHERE p.id = ';

  -- ── SHABLON INSERT shabloni ──────────────────────────────────────────────
  --    ⚠️ Manba qator id'si LITERAL sifatida qo'yiladi (quote_literal + cast)
  --       — busiz `t.id::text = $1` yozishga to'g'ri kelardi va u INDEKSNI
  --       ISHLATMASDI (har bosqich uchun butun tasks ni skanerlash).
  v_inspre := 'INSERT INTO public.tasks (is_template'
    || CASE WHEN v_stmode = 'new' THEN ', status' ELSE '' END
    || ', ' || v_cols || ') SELECT true'
    || CASE WHEN v_stmode = 'new' THEN ', ''new''' ELSE '' END
    || ', ' || v_colsrc || ' FROM public.tasks t WHERE t.id = ';
  v_inspost := ' RETURNING id::text';

  v_ordexpr := CASE WHEN v_hasflow THEN 't.flow_order NULLS LAST, t.id' ELSE 't.id' END;

  -- ── LOYIHALAR BO'YICHA ───────────────────────────────────────────────────
  FOR v_p IN
    EXECUTE 'SELECT DISTINCT t.project_id::text FROM public.tasks t'
         || ' WHERE t.project_id IS NOT NULL AND t.is_template IS NOT TRUE'
         || ' ORDER BY 1'
  LOOP
    -- 🔴 IDEMPOTENTLIK: sikl qatori bor = bu loyiha ALLAQACHON migratsiya
    --    qilingan (yoki mijoz o'zi sikl ochgan). Umuman tegilmaydi.
    EXECUTE 'SELECT EXISTS (SELECT 1 FROM public.project_cycles c WHERE c.project_id = '
            || quote_literal(v_p) || '::' || v_projtyp || ')' INTO v_ex;
    IF v_ex THEN
      v_skipn := v_skipn + 1;
      CONTINUE;
    END IF;

    v_ws := NULL; v_st := NULL; v_en := NULL; v_cb := NULL;
    EXECUTE v_prjsel || quote_literal(v_p) || '::' || v_projtyp
      INTO v_ws, v_st, v_en, v_cb;

    IF v_ws IS NULL THEN
      -- Loyiha qatori yo'q (yoki workspace_id bo'sh) — sikl yarata olmaymiz.
      -- JIMGINA o'tkazmaymiz: sabab ochiq aytiladi (CLAUDE.md 6-qoida ruhi).
      RAISE WARNING 'Loyiha % uchun projects qatori topilmadi yoki workspace_id bo''sh — bu loyiha bosqichlari SHABLONSIZ qoldi. Ma''lumot buzilmadi; sababni ko''rib chiqing.', v_p;
      v_skipn := v_skipn + 1;
      CONTINUE;
    END IF;

    -- Nechta bosqich ko'chadi?
    EXECUTE 'SELECT count(*) FROM public.tasks t WHERE t.project_id = '
            || quote_literal(v_p) || '::' || v_projtyp
            || ' AND t.is_template IS NOT TRUE AND t.template_id IS NULL'
      INTO v_stage;

    IF coalesce(v_stage,0) = 0 THEN
      v_skipn := v_skipn + 1;
      CONTINUE;
    END IF;

    -- 1-SIKL
    EXECUTE 'INSERT INTO public.project_cycles'
         || ' (workspace_id, project_id, cycle_no, start_at, end_at, materialized_at, created_by)'
         || ' VALUES ($1, $2::' || v_projtyp || ', 1, $3, $4, now(), $5) RETURNING id'
      INTO v_cyc USING v_ws, v_p, v_st, v_en, v_cb;

    INSERT INTO pg_temp.shb_done VALUES (v_p, v_ws, v_cyc, v_stage);
    v_prjn := v_prjn + 1;

    -- BOSQICHLAR → SHABLON
    FOR v_old IN
      EXECUTE 'SELECT t.id::text FROM public.tasks t WHERE t.project_id = '
              || quote_literal(v_p) || '::' || v_projtyp
              || ' AND t.is_template IS NOT TRUE AND t.template_id IS NULL'
              || ' ORDER BY ' || v_ordexpr
    LOOP
      EXECUTE v_inspre || quote_literal(v_old) || '::' || v_idtype || v_inspost INTO v_new;
      INSERT INTO pg_temp.shb_map VALUES (v_old, v_new, v_p, v_cyc);
      v_tpln := v_tpln + 1;
    END LOOP;
  END LOOP;

  -- ── MAVJUD QATORLARNI 1-SIKL INSTANSIYASIGA AYLANTIRAMIZ ────────────────
  --    ⚠️ BITTA to'plamli UPDATE (loyiha ichida emas) — aks holda har loyiha
  --       uchun tasks bo'ylab alohida hash-join qilinardi.
  IF v_tpln > 0 THEN
    EXECUTE 'UPDATE public.tasks r'
         || '   SET template_id = m.new_id::' || v_idtype || ', cycle_id = m.cycle_id'
         || '  FROM pg_temp.shb_map m'
         || ' WHERE r.id::text = m.old_id';

    -- ── SHABLON TARIXI: har shablon uchun bitta "created" qatori ──────────
    --    🔴 changed_by / changed_by_name = NULL: bu SYSTEM yozuvi, hech kim
    --       qilmagan. Ekranda matnni mijoz tr() bilan chizadi (CLAUDE.md 10).
    EXECUTE 'INSERT INTO public.template_history'
         || ' (workspace_id, project_id, template_id, action, cycle_id, changes)'
         || ' SELECT tt.workspace_id, tt.project_id, tt.id, ''created'', m.cycle_id,'
         || '        jsonb_build_object(''source'', ''TASKFIX_SHABLON.sql'','
         || '                           ''from_task'', m.old_id, ''cycle_no'', 1)'
         || '   FROM pg_temp.shb_map m'
         || '   JOIN public.tasks tt ON tt.id::text = m.new_id'
         || '  WHERE tt.project_id IS NOT NULL';
  END IF;

  -- ── KUTISH GRAFI (task_dependencies) — jadval BO'LSA nusxalanadi ────────
  --    Jadval yo'q → qadam JIMGINA o'tkaziladi (TASKFIX_KUTISH.sql hali RUN
  --    qilinmagan bo'lishi mumkin — bu XATO emas).
  IF to_regclass('public.task_dependencies') IS NOT NULL AND v_tpln > 0 THEN
    BEGIN
      EXECUTE 'INSERT INTO public.task_dependencies (task_id, depends_on_id, workspace_id, created_by)'
           || ' SELECT m1.new_id::' || v_idtype || ', m2.new_id::' || v_idtype || ', d.workspace_id, d.created_by'
           || '   FROM public.task_dependencies d'
           || '   JOIN pg_temp.shb_map m1 ON m1.old_id = d.task_id::text'
           || '   JOIN pg_temp.shb_map m2 ON m2.old_id = d.depends_on_id::text'
           || '  ON CONFLICT DO NOTHING';
      GET DIAGNOSTICS v_depn = ROW_COUNT;
      RAISE NOTICE 'KUTISH grafi shablonlarga ko''chirildi: % qator', v_depn;
    EXCEPTION WHEN OTHERS THEN
      -- 🔴 JIMGINA YUTILMAYDI: sabab aytilib, HAMMASI qaytariladi.
      RAISE EXCEPTION 'task_dependencies nusxalash yiqildi (%): %. Ehtimol task_dependencies_guard_trg qorovuli rad etdi (masalan shablonlar boshqa loyihada ko''rinmoqda yoki grafda allaqachon sikl bor). HAMMASI QAYTARILDI.', SQLSTATE, left(SQLERRM, 200);
    END;
  END IF;

  INSERT INTO pg_temp.shb_res VALUES
    (40, 'migratsiya', 'ko''chirilgan loyiha', v_prjn::text,
     'Har biri uchun 1-sikl (project_cycles) va har bosqich uchun SHABLON yaratildi'),
    (41, 'migratsiya', 'o''tkazib yuborilgan loyiha', v_skipn::text,
     '🔴 IDEMPOTENTLIK: project_cycles da qatori BOR loyiha butunlay o''tkaziladi (ikkinchi RUN yangi shablon yaratmaydi). Bunga loyiha qatori topilmagan holat ham kiradi (u WARNING beradi).'),
    (42, 'migratsiya', 'yaratilgan SHABLON', v_tpln::text,
     'is_template = true. Mavjud bosqich qatorlari JOYIDA qoldi va 1-sikl INSTANSIYASI bo''ldi (id lari O''ZGARMADI).'),
    (43, 'migratsiya', 'ko''chirilgan KUTISH bog''lanishi',
     CASE WHEN to_regclass('public.task_dependencies') IS NULL THEN 'o''tkazildi (jadval yo''q)' ELSE v_depn::text END,
     CASE WHEN to_regclass('public.task_dependencies') IS NULL
          THEN 'TASKFIX_KUTISH.sql RUN qilinmagan — bu XATO emas, qadam jimgina o''tkazildi.'
          ELSE 'Shablonlar orasida R→T xaritasi bilan qayta qurildi (kelajakdagi sikl grafi tayyor).' END),
    (44, 'migratsiya', 'shablon status manbai',
     CASE v_stmode WHEN 'default' THEN 'jadval DEFAULT''i'
                   WHEN 'new'     THEN '''new'' (status da DEFAULT yo''q edi)'
                   ELSE 'status ustuni yo''q' END,
     'Qattiq yozilgan literal o''rniga DB DEFAULT''i afzal — u ta''rifan YAROQLI qiymat (status CHECK''i o''zgargan bazada literal 23514 berardi).');
END $mig$;

-- Bola qatorlar sonini VA mavjud bosqichlarning barmoq izini QAYTA
-- hisoblaymiz ((c2) / (c3) tekshiruvlari uchun)
DO $child2$
DECLARE
  r    RECORD;
  v_n  bigint;
  v_e  text;
BEGIN
  FOR r IN SELECT tbl, col FROM pg_temp.shb_child ORDER BY tbl, col LOOP
    EXECUTE format('SELECT count(*) FROM %s x JOIN pg_temp.shb_before b ON x.%I::text = b.id',
                   r.tbl, r.col) INTO v_n;
    UPDATE pg_temp.shb_child SET n_after = v_n WHERE tbl = r.tbl AND col = r.col;
  END LOOP;

  -- 🔴 AYNI ifoda bilan (shb_fp da saqlangan) — aks holda solishtiruv ma'nosiz
  SELECT expr INTO v_e FROM pg_temp.shb_fp LIMIT 1;
  EXECUTE 'UPDATE pg_temp.shb_before b SET fp_after = s.f FROM ('
       || ' SELECT t.id::text AS i, ' || v_e || ' AS f FROM public.tasks t'
       || ' WHERE t.project_id IS NOT NULL AND t.is_template IS NOT TRUE) s'
       || ' WHERE s.i = b.id';
END $child2$;


-- ════════════════════════════════════════════════════════════════════════════
-- 7) MIGRATSIYA TEKSHIRUVI — jimgina o'tmasin
--    (a) har loyihada shablon soni = bosqich soni
--    (b) har bosqichning template_id / cycle_id to'g'ri
--    (c)  🔴 mavjud qator id'lari O'ZGARMAGAN
--    (c2) 🔴 ularga bog'langan bola qatorlar soni AYNAN o'sha (izoh/fayl/tarix)
--    (c3) 🔴 ularning MA'NOLI maydonlari (barmoq izi) o'zgarmagan — begona
--         trigger jimgina qayta hisoblab yuborgan bo'lsa shu yerda tutiladi
--    (g) idempotentlik: drayver so'rovi endi 0 loyiha qaytaradi
-- ════════════════════════════════════════════════════════════════════════════
DO $mver$
DECLARE
  v_bad   bigint;
  v_txt   text;
  v_idtyp text;
  v_n     bigint;
  v_before bigint;
  v_gone  bigint;
BEGIN
  SELECT v INTO v_idtyp FROM pg_temp.shb_ref WHERE k='idtype';

  -- ── (a) shablon soni = bosqich soni (loyiha bo'yicha) ───────────────────
  SELECT count(*), string_agg(d.project_id || ' (kutilgan ' || d.stages::text || ', yaratilgan ' || coalesce(m.n,0)::text || ')', '; ')
    INTO v_bad, v_txt
    FROM pg_temp.shb_done d
    LEFT JOIN (SELECT project_id, count(*) AS n FROM pg_temp.shb_map GROUP BY project_id) m
           ON m.project_id = d.project_id
   WHERE coalesce(m.n, 0) <> d.stages;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV (a): % loyihada shablon soni bosqich soniga TENG EMAS: %. HAMMASI QAYTARILDI.', v_bad, left(v_txt, 400);
  END IF;

  -- Xaritadagi har new_id haqiqatan SHABLON bo'lib bazada turibdimi?
  EXECUTE 'SELECT count(*) FROM pg_temp.shb_map m'
       || ' WHERE NOT EXISTS (SELECT 1 FROM public.tasks t'
       || '                    WHERE t.id::text = m.new_id AND t.is_template = true'
       || '                      AND t.template_id IS NULL AND t.cycle_id IS NULL)'
    INTO v_bad;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV (a2): % ta yaratilgan qator SHABLON emas (is_template=true + template_id/cycle_id NULL kutilgandi). HAMMASI QAYTARILDI.', v_bad;
  END IF;

  -- ── (b) har bosqichning template_id / cycle_id kutilganday ─────────────
  EXECUTE 'SELECT count(*) FROM pg_temp.shb_map m'
       || '  JOIN public.tasks r ON r.id::text = m.old_id'
       || ' WHERE r.template_id::text IS DISTINCT FROM m.new_id'
       || '    OR r.cycle_id IS DISTINCT FROM m.cycle_id'
       || '    OR r.is_template IS TRUE'
    INTO v_bad;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV (b): % ta mavjud bosqichning template_id / cycle_id si kutilganidek EMAS (yoki qator shablonga aylanib qolgan). HAMMASI QAYTARILDI.', v_bad;
  END IF;

  -- Sikl haqiqatan 1-siklmi?
  SELECT count(*) INTO v_bad
    FROM pg_temp.shb_done d
    JOIN public.project_cycles c ON c.id = d.cycle_id
   WHERE c.cycle_no <> 1;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV (b2): % ta loyihada bog''langan sikl 1-sikl EMAS. HAMMASI QAYTARILDI.', v_bad;
  END IF;

  -- ── (c) 🔴 MAVJUD QATORLAR JOYIDA — ENG MUHIM TEKSHIRUV ────────────────
  SELECT count(*) INTO v_before FROM pg_temp.shb_before;
  EXECUTE 'SELECT count(*) FROM pg_temp.shb_before b'
       || ' WHERE NOT EXISTS (SELECT 1 FROM public.tasks t'
       || '                    WHERE t.id::text = b.id AND t.is_template IS NOT TRUE)'
    INTO v_gone;
  IF v_gone > 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV (c): 🔴 migratsiyadan OLDIN mavjud bo''lgan % ta bosqich qatori endi TOPILMADI yoki SHABLONGA aylanib qolgan. Bu izoh/fayl/tarix havolalarini uzardi. HAMMASI QAYTARILDI.', v_gone;
  END IF;

  SELECT count(*), string_agg(tbl || '.' || col || ' (' || n_before::text || ' -> ' || coalesce(n_after,-1)::text || ')', '; ')
    INTO v_bad, v_txt
    FROM pg_temp.shb_child
   WHERE n_before IS DISTINCT FROM n_after;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV (c2): 🔴 mavjud bosqichlarga bog''langan bola qatorlar soni O''ZGARDI: %. Izoh/fayl/tarix/subtask havolalari buzilgan. HAMMASI QAYTARILDI.', left(v_txt, 400);
  END IF;

  -- ── (c3) 🔴 MAVJUD QATORLARNING MA'NOLI MAYDONLARI O'ZGARMAGAN ─────────
  --    Bu tekshiruv BEGONA TRIGGERLARDAN himoya qiladi: yangi qator (shablon)
  --    INSERT qilinganda mavjud bosqichlarning is_locked / status / deadline
  --    kabi maydonlari JIMGINA qayta hisoblanib ketishi mumkin edi.
  SELECT count(*), string_agg(b.id || ': [' || coalesce(b.fp, 'YO''Q') || '] -> ['
                              || coalesce(b.fp_after, 'YO''Q') || ']', ' ; ')
    INTO v_bad, v_txt
    FROM (SELECT * FROM pg_temp.shb_before
           WHERE fp IS DISTINCT FROM fp_after LIMIT 5) b;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV (c3): 🔴 mavjud bosqichlarning MA''NOLI maydonlari (status / is_locked / deadline / assigned_to / acceptor_id / flow_order / depends_on_prev / title / project_id / workspace_id) O''ZGARDI. Ehtimol public.tasks dagi begona trigger yangi shablon qatoriga javoban mavjud qatorlarni ham qayta hisoblagan. Birinchi farqlar: %. HAMMASI QAYTARILDI.', left(coalesce(v_txt, ''), 500);
  END IF;

  -- ── (g) IDEMPOTENTLIK: drayver so'rovi endi bo'sh bo'lishi SHART ────────
  EXECUTE 'SELECT count(*) FROM ('
       || '  SELECT DISTINCT t.project_id AS pid FROM public.tasks t'
       || '   WHERE t.project_id IS NOT NULL AND t.is_template IS NOT TRUE'
       || ') d WHERE NOT EXISTS (SELECT 1 FROM public.project_cycles c WHERE c.project_id = d.pid)'
    INTO v_n;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV (g) IDEMPOTENTLIK: migratsiyadan keyin ham % ta loyiha "ko''chirilmagan" holatda qoldi — ikkinchi RUN ularga IKKINCHI shablon to''plamini yaratardi. HAMMASI QAYTARILDI.', v_n;
  END IF;

  INSERT INTO pg_temp.shb_res VALUES
    (45, 'tekshiruv', '(a) shablon soni = bosqich soni', 'OK',
     'Har ko''chirilgan loyiha bo''yicha alohida sanaldi; har yangi qator haqiqatan is_template=true + template_id/cycle_id NULL.'),
    (46, 'tekshiruv', '(b) template_id / cycle_id', 'OK',
     'Har mavjud bosqich o''z shabloniga va 1-siklga ishora qiladi; birortasi shablonga aylanib qolmagan.'),
    (47, 'tekshiruv', '(c) 🔴 mavjud qator id lari', 'OK — ' || v_before::text || ' ta qator joyida',
     'Migratsiyadan oldingi HAR bosqich id si bazada, is_template = false. Izoh/fayl/tarix/subtask FK lari uzilmagan.'),
    (48, 'tekshiruv', '(c2) 🔴 bola qatorlar soni',
     'OK — ' || (SELECT count(*)::text FROM pg_temp.shb_child) || ' ta FK tekshirildi',
     'tasks(id) ga FK bilan bog''langan har jadval bo''yicha mavjud bosqichlarga tegishli qatorlar soni oldin/keyin AYNAN teng: '
     || coalesce((SELECT string_agg(tbl || '.' || col || '=' || n_after::text, ', ' ORDER BY tbl, col) FROM pg_temp.shb_child), 'FK topilmadi')),
    (50, 'tekshiruv', '(c3) 🔴 mavjud qatorlarning maydonlari', 'OK — o''zgarmagan',
     'status / is_locked / deadline / assigned_to / acceptor_id / flow_order / depends_on_prev / title / project_id / workspace_id oldin va keyin AYNAN bir xil — public.tasks dagi begona trigger (34-migratsiya qulfi, zz_task_wait_guard_trg) shablon insertiga javoban mavjud qatorlarga TEGMAGAN.'),
    (51, 'tekshiruv', '(g) idempotentlik', 'OK — 0 loyiha kutmoqda',
     'Migratsiya drayveri (project_cycles qatori YO''Q loyihalar) endi bo''sh — ikkinchi RUN hech narsa qilmaydi.');

  RAISE NOTICE 'MIGRATSIYA TEKSHIRUVLARI O''TDI (a, b, c, c2, c3, g).';
END $mver$;


-- ════════════════════════════════════════════════════════════════════════════
-- 8) 🔴 TIRIK SINOVLAR — SENTINEL-ROLLBACK bilan
--    (d)  UNIQUE (project_id, cycle_no) ikkinchi insertni RAD etadi
--    (e1) CHECK: shablon + template_id            → RAD
--    (e2) toza shablon (ikkovi NULL)              → O'TADI
--    (e3) instansiya (template_id + cycle_id)     → O'TADI
--    (f1) ws-MENEJERI project_cycles ni KO'RADI
--    (f2) BEGONA ws a'zosi project_cycles ni KO'RMAYDI
--    (f3) BEGONA ws a'zosi template_history ni KO'RMAYDI
--    (f4) BEGONA ws a'zosi project_cycles ga YOZA OLMAYDI
--    (f5) oddiy A'ZO project_cycles ni KO'RADI (ko'rish hammaga ochiq)
--    (h)  REGRESSIYA: mavjud vazifani oddiy UPDATE qilish ishlaydi
--    ⚠️ Yozuv qiladigan qism ichki blokda ATAYLAB EXCEPTION bilan tugatiladi
--       → subtranzaksiya qaytadi, bazada BITTA qator ham qolmaydi.
--    ⚠️ 'ENV:' = sinov MUHITI to'sdi (begona trigger/FK/NOT NULL) — bu
--       MIGRATSIYA xatosi EMAS va hukm chiqarilmaydi (soxta salbiy bo'lmasin).
-- ════════════════════════════════════════════════════════════════════════════
DO $live$
DECLARE
  v_idtype  text;
  v_projtyp text;
  v_ws      uuid;
  v_mgr     uuid;
  v_mem     uuid;
  v_out     uuid;
  v_prj     text;
  v_cyc     uuid;
  v_hist    uuid;
  v_real    text;
  v_prjexpr text;
  v_tpl     text;
  v_skip    text;
  v_imp_ok  boolean := false;
  v_id_auto boolean;
  v_bad     text;
  v_txt     text;
  v_n       bigint;
  v_tmp     text;
  v_probe   text;
  v_err     text;
  v_state   text;
  v_cn      text;
  v_has_title boolean;
  v_has_cb    boolean;
  v_has_asg   boolean;
  v_has_flow  boolean;
  v_has_dpp   boolean;
  v_has_stat  boolean;
  p_d text; p_e1 text; p_e2 text; p_e3 text;
  p_f1 text; p_f2 text; p_f3 text; p_f4 text; p_f5 text; p_h text;
BEGIN
  SELECT v INTO v_idtype  FROM pg_temp.shb_ref WHERE k='idtype';
  SELECT v INTO v_projtyp FROM pg_temp.shb_ref WHERE k='projtype';

  -- ── (8.0) SINOV UCHUN MA'LUMOT ───────────────────────────────────────────
  --    ⚠️ Loyiha ham, workspace ham YARATMAYMIZ — mavjudidan foydalanamiz.
  SELECT c.project_id::text, c.id, c.workspace_id INTO v_prj, v_cyc, v_ws
    FROM public.project_cycles c
   WHERE EXISTS (SELECT 1 FROM public.workspace_members m
                  WHERE m.workspace_id = c.workspace_id
                    AND public.is_ws_manager(c.workspace_id, m.user_id))
   ORDER BY c.workspace_id, c.project_id, c.cycle_no
   LIMIT 1;

  IF v_prj IS NULL THEN
    v_skip := 'menejeri bor workspace''da sikl (project_cycles) topilmadi — migratsiya ko''chiradigan loyiha bo''lmagan (bo''sh baza)';
  END IF;

  IF v_skip IS NULL THEN
    SELECT m.user_id INTO v_mgr FROM public.workspace_members m
     WHERE m.workspace_id = v_ws AND public.is_ws_manager(v_ws, m.user_id)
     ORDER BY m.user_id LIMIT 1;

    SELECT m.user_id INTO v_mem FROM public.workspace_members m
     WHERE m.workspace_id = v_ws AND m.user_id <> v_mgr
       AND NOT public.is_ws_manager(v_ws, m.user_id)
     ORDER BY m.user_id LIMIT 1;

    SELECT w2.user_id INTO v_out FROM public.workspace_members w2
     WHERE w2.workspace_id <> v_ws
       AND NOT EXISTS (SELECT 1 FROM public.workspace_members w3
                        WHERE w3.workspace_id = v_ws AND w3.user_id = w2.user_id)
     ORDER BY w2.user_id LIMIT 1;

    SELECT h.id INTO v_hist FROM public.template_history h
     WHERE h.workspace_id = v_ws ORDER BY h.id LIMIT 1;

    IF v_mgr IS NULL THEN
      v_skip := 'workspace menejeri topilmadi';
    END IF;
  END IF;

  SELECT (column_default IS NOT NULL OR is_identity = 'YES') INTO v_id_auto
    FROM information_schema.columns
   WHERE table_schema='public' AND table_name='tasks' AND column_name='id';
  IF v_skip IS NULL AND NOT coalesce(v_id_auto, false) THEN
    v_skip := 'tasks.id da DEFAULT/IDENTITY yo''q — sinov qatorining id sini skript o''ylab topa olmaydi';
  END IF;

  v_has_title := EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema='public' AND table_name='tasks' AND column_name='title');
  v_has_cb    := EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema='public' AND table_name='tasks' AND column_name='created_by');
  v_has_asg   := EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema='public' AND table_name='tasks' AND column_name='assigned_to');
  v_has_flow  := EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema='public' AND table_name='tasks' AND column_name='flow_order');
  v_has_dpp   := EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema='public' AND table_name='tasks' AND column_name='depends_on_prev');
  v_has_stat  := EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema='public' AND table_name='tasks' AND column_name='status');

  IF v_skip IS NULL AND NOT v_has_title THEN
    v_skip := 'tasks.title ustuni yo''q — sinov qatorini taxmin bilan to''ldirmaymiz';
  END IF;

  -- Bilmaydigan MAJBURIY ustun bo'lsa sinov o'tkazilmaydi (23502 ga urilmasin)
  IF v_skip IS NULL THEN
    SELECT string_agg(column_name, ', ') INTO v_bad
      FROM information_schema.columns
     WHERE table_schema='public' AND table_name='tasks'
       AND is_nullable='NO' AND column_default IS NULL AND is_identity='NO'
       AND column_name NOT IN ('id','workspace_id','title','status','project_id',
                               'created_by','assigned_to','flow_order','depends_on_prev',
                               'is_template','template_id','cycle_id');
    IF v_bad IS NOT NULL THEN
      v_skip := 'tasks da noma''lum majburiy ustun(lar) bor: ' || v_bad;
    END IF;
  END IF;

  -- Impersonatsiya harnessi ((f) sinovlari uchun)
  IF v_skip IS NULL AND v_mgr IS NOT NULL THEN
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
      RAISE WARNING 'Impersonatsiya harnessi ishlamadi (auth.uid() request.jwt.claims dan o''qimayapti) — (f) RLS sinovlari o''tkazib yuborildi. Qolgan sinovlar bajariladi. Prodga chiqarishdan oldin QO''LDA sinang: begona ws a''zosi project_cycles / template_history ni KO''RMASLIGI kerak.';
    END IF;
  END IF;

  IF v_skip IS NOT NULL THEN
    RAISE WARNING 'TIRIK SINOVLAR O''TKAZIB YUBORILDI — %. Struktura va migratsiya tekshiruvlari BAJARILDI; prodga chiqishdan oldin qo''lda sinang.', v_skip;
    INSERT INTO pg_temp.shb_res VALUES
      (60, 'sinov', 'TIRIK SINOVLAR', 'o''tkazib yuborildi', v_skip);
    RETURN;
  END IF;

  -- ── (8.1) tasks INSERT shabloni ──────────────────────────────────────────
  --    %L = sarlavha · 1-%s = is_template · 2-%s = template_id · 3-%s = cycle_id
  --    ⚠️ project_id qiymati id TIPIGA bog'lanmasin deb subselect bilan;
  --       ehtiyot uchun % qochiriladi (u format() shablonining bir qismi).
  v_prjexpr := replace('(SELECT p.id FROM public.projects p WHERE p.id::text = '
                       || quote_literal(v_prj) || ')', '%', '%%');

  SELECT t.id::text INTO v_real FROM public.tasks t
   WHERE t.workspace_id = v_ws AND t.is_template IS NOT TRUE LIMIT 1;

  v_tpl := 'INSERT INTO public.tasks (workspace_id, title, project_id, is_template, template_id, cycle_id'
        || CASE WHEN v_has_stat THEN ', status'          ELSE '' END
        || CASE WHEN v_has_flow THEN ', flow_order'      ELSE '' END
        || CASE WHEN v_has_cb   THEN ', created_by'      ELSE '' END
        || CASE WHEN v_has_asg  THEN ', assigned_to'     ELSE '' END
        || CASE WHEN v_has_dpp  THEN ', depends_on_prev' ELSE '' END
        || ') VALUES (' || quote_literal(v_ws::text) || '::uuid, %L, ' || v_prjexpr || ', %s, %s, %s'
        || CASE WHEN v_has_stat THEN ', ''new''' ELSE '' END
        --  ⚠️ flow_order har sinov qatorida BOSHQA bo'lsin (mavjud UNIQUE
        --     indeks bo'lsa 23505 berib sinovlarni ENV ga aylantirmasin).
        || CASE WHEN v_has_flow
                THEN ', (SELECT coalesce(max(t2.flow_order), 0) + 1 FROM public.tasks t2)'
                ELSE '' END
        || CASE WHEN v_has_cb  THEN ', ' || quote_literal(v_mgr::text) || '::uuid' ELSE '' END
        || CASE WHEN v_has_asg THEN ', ' || quote_literal(v_mgr::text) || '::uuid' ELSE '' END
        || CASE WHEN v_has_dpp THEN ', false' ELSE '' END
        || ') RETURNING id::text';

  -- ══════════════ SENTINEL BLOK (hammasi qaytariladi) ══════════════
  BEGIN
    -- (d) 🔴 UNIQUE (project_id, cycle_no) — MATERIALIZATSIYA DA'VOSI
    BEGIN
      EXECUTE 'INSERT INTO public.project_cycles (workspace_id, project_id, cycle_no)'
           || ' VALUES ($1, $2::' || v_projtyp || ', 1)'
        USING v_ws, v_prj;
      p_d := 'YOZILDI';
    EXCEPTION
      WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
        p_d := 'RAD:' || coalesce(v_cn, '?');
      WHEN OTHERS THEN
        p_d := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
    END;

    -- (e2) toza SHABLON (ikkovi NULL) → O'TISHI SHART
    BEGIN
      EXECUTE format(v_tpl, 'SHB-SINOV E2 (sentinel, o''chadi)', 'true', 'NULL', 'NULL') INTO v_tmp;
      p_e2 := 'OK';
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
        IF coalesce(v_cn,'') = 'tasks_template_flags_chk' THEN p_e2 := 'RAD:' || v_cn;
        ELSE p_e2 := 'ENV:23514:' || coalesce(v_cn, '?'); END IF;
      WHEN OTHERS THEN
        p_e2 := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
    END;

    -- (e1) SHABLON + template_id → RAD (tasks_template_flags_chk)
    BEGIN
      EXECUTE format(v_tpl, 'SHB-SINOV E1 (sentinel, o''chadi)', 'true',
                     quote_literal(coalesce(v_real, v_tmp)) || '::' || v_idtype, 'NULL') INTO v_tmp;
      p_e1 := 'YOZILDI';
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
        IF coalesce(v_cn,'') = 'tasks_template_flags_chk' THEN p_e1 := 'RAD:' || v_cn;
        ELSE p_e1 := 'ENV:23514:' || coalesce(v_cn, '?'); END IF;
      WHEN OTHERS THEN
        p_e1 := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
    END;

    -- (e3) INSTANSIYA (is_template=false + template_id + cycle_id) → O'TISHI SHART
    BEGIN
      -- ⚠️ Nishon: mavjud vazifa, u topilmasa (e2) da yaratilgan sentinel
      --    shablon. Qattiq yozilgan "nol uuid" ISHLATILMAYDI — tasks.id
      --    bigint bo'lgan bazada cast xatosi berib, sinov ENV ga aylanardi.
      EXECUTE format(v_tpl, 'SHB-SINOV E3 (sentinel, o''chadi)', 'false',
                     quote_literal(coalesce(v_real, v_tmp)) || '::' || v_idtype,
                     quote_literal(v_cyc::text) || '::uuid') INTO v_tmp;
      p_e3 := 'OK';
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
        IF coalesce(v_cn,'') = 'tasks_template_flags_chk' THEN p_e3 := 'RAD:' || v_cn;
        ELSE p_e3 := 'ENV:23514:' || coalesce(v_cn, '?'); END IF;
      WHEN OTHERS THEN
        p_e3 := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
    END;

    -- (h) 🔴 REGRESSIYA: mavjud vazifani oddiy yangilash AVVALGIDEK o'tadimi?
    --     "SET title = title" — qator QAYTA YOZILADI, ya'ni Postgres qatorning
    --     BARCHA CHECK'larini qayta baholaydi (yangi CHECK ham).
    IF v_real IS NULL THEN
      p_h := 'ENV:qator:yoq';
    ELSE
      BEGIN
        EXECUTE 'UPDATE public.tasks SET title = title WHERE id::text = $1' USING v_real;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n = 1 THEN p_h := 'OK'; ELSE p_h := 'ENV:qator:' || v_n::text; END IF;
      EXCEPTION
        WHEN check_violation THEN
          GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
          p_h := 'RAD:' || coalesce(v_cn, '?');
        WHEN OTHERS THEN
          p_h := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
      END;
    END IF;

    -- ── (f) RLS — impersonatsiya bilan ───────────────────────────────────
    IF v_imp_ok THEN
      -- (f1) ws-MENEJERI o'z siklini KO'RADI
      BEGIN
        PERFORM set_config('request.jwt.claims',
                 json_build_object('sub', v_mgr::text, 'role', 'authenticated')::text, true);
        EXECUTE 'SET LOCAL ROLE authenticated';
        EXECUTE 'SELECT count(*)::text FROM public.project_cycles WHERE id = $1' INTO p_f1 USING v_cyc;
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
      EXCEPTION WHEN OTHERS THEN
        BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
        PERFORM set_config('request.jwt.claims', '', true);
        p_f1 := 'E' || SQLSTATE;
      END;

      -- (f5) oddiy A'ZO ham KO'RADI (ko'rish butun jamoaga ochiq)
      IF v_mem IS NOT NULL THEN
        BEGIN
          PERFORM set_config('request.jwt.claims',
                   json_build_object('sub', v_mem::text, 'role', 'authenticated')::text, true);
          EXECUTE 'SET LOCAL ROLE authenticated';
          EXECUTE 'SELECT count(*)::text FROM public.project_cycles WHERE id = $1' INTO p_f5 USING v_cyc;
          EXECUTE 'RESET ROLE';
          PERFORM set_config('request.jwt.claims', '', true);
        EXCEPTION WHEN OTHERS THEN
          BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
          PERFORM set_config('request.jwt.claims', '', true);
          p_f5 := 'E' || SQLSTATE;
        END;
      ELSE
        p_f5 := '-';
      END IF;

      -- (f2)/(f3)/(f4) 🔴 BEGONA ws a'zosi
      IF v_out IS NOT NULL THEN
        BEGIN
          PERFORM set_config('request.jwt.claims',
                   json_build_object('sub', v_out::text, 'role', 'authenticated')::text, true);
          EXECUTE 'SET LOCAL ROLE authenticated';
          EXECUTE 'SELECT count(*)::text FROM public.project_cycles WHERE id = $1' INTO p_f2 USING v_cyc;
          EXECUTE 'RESET ROLE';
          PERFORM set_config('request.jwt.claims', '', true);
        EXCEPTION WHEN OTHERS THEN
          BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
          PERFORM set_config('request.jwt.claims', '', true);
          p_f2 := 'E' || SQLSTATE;
        END;

        IF v_hist IS NOT NULL THEN
          BEGIN
            PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_out::text, 'role', 'authenticated')::text, true);
            EXECUTE 'SET LOCAL ROLE authenticated';
            EXECUTE 'SELECT count(*)::text FROM public.template_history WHERE id = $1' INTO p_f3 USING v_hist;
            EXECUTE 'RESET ROLE';
            PERFORM set_config('request.jwt.claims', '', true);
          EXCEPTION WHEN OTHERS THEN
            BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
            PERFORM set_config('request.jwt.claims', '', true);
            p_f3 := 'E' || SQLSTATE;
          END;
        ELSE
          p_f3 := '-';
        END IF;

        BEGIN
          PERFORM set_config('request.jwt.claims',
                   json_build_object('sub', v_out::text, 'role', 'authenticated')::text, true);
          EXECUTE 'SET LOCAL ROLE authenticated';
          EXECUTE 'INSERT INTO public.project_cycles (workspace_id, project_id, cycle_no)'
               || ' VALUES ($1, $2::' || v_projtyp || ', 99)'
            USING v_ws, v_prj;
          EXECUTE 'RESET ROLE';
          PERFORM set_config('request.jwt.claims', '', true);
          p_f4 := 'YOZDI';
        EXCEPTION WHEN OTHERS THEN
          BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
          PERFORM set_config('request.jwt.claims', '', true);
          p_f4 := 'RAD:' || SQLSTATE;
        END;
      ELSE
        p_f2 := '-'; p_f3 := '-'; p_f4 := '-';
      END IF;
    ELSE
      p_f1 := '-'; p_f2 := '-'; p_f3 := '-'; p_f4 := '-'; p_f5 := '-';
    END IF;

    -- ⚠️ SENTINEL: subtranzaksiyani ATAYLAB qaytaramiz.
    --    Natijalar "|" bilan ajratiladi (ENV matnlaridagi "|" yuqorida "/" ga
    --    almashtirilgan — split_part siljimasin).
    RAISE EXCEPTION 'SHB_PROBE:%',
      coalesce(p_d, '?') || '|' || coalesce(p_e1, '?') || '|' || coalesce(p_e2, '?') || '|' ||
      coalesce(p_e3, '?') || '|' || coalesce(p_f1, '?') || '|' || coalesce(p_f2, '?') || '|' ||
      coalesce(p_f3, '?') || '|' || coalesce(p_f4, '?') || '|' || coalesce(p_f5, '?') || '|' ||
      coalesce(p_h, '?')
      USING ERRCODE = '22000';

  EXCEPTION WHEN OTHERS THEN
    -- 🔴 SQLERRM / SQLSTATE ENG BIRINCHI BO'LIB nusxalanadi. Pastda ichma-ich
    --    BEGIN ... EXCEPTION bloki bor (RESET ROLE) — u ishga tushsa o'z
    --    SQLERRM ini o'rnatadi va probe satri o'qilmay qolish xavfi tug'ilardi.
    v_err   := SQLERRM;
    v_state := SQLSTATE;
    BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM set_config('request.jwt.claims', '', true); EXCEPTION WHEN OTHERS THEN NULL; END;

    IF v_err NOT LIKE 'SHB_PROBE:%' THEN
      -- Harness xatosi — migratsiya to'xtatilmaydi, lekin JIMGINA HAM
      -- YUTILMAYDI (CLAUDE.md 6-qoida).
      v_skip := 'sinov qatorini yozib bo''lmadi (' || v_state || '): ' || left(v_err, 200);
      RAISE WARNING 'TIRIK SINOVLAR O''TKAZIB YUBORILDI — %. Struktura va migratsiya tekshiruvlari BAJARILDI; prodga chiqishdan oldin QO''LDA sinang.', v_skip;
      INSERT INTO pg_temp.shb_res VALUES
        (60, 'sinov', 'TIRIK SINOVLAR', 'o''tkazib yuborildi', v_skip);
      RETURN;
    END IF;

    v_probe := replace(v_err, 'SHB_PROBE:', '');
    p_d  := split_part(v_probe, '|', 1);
    p_e1 := split_part(v_probe, '|', 2);
    p_e2 := split_part(v_probe, '|', 3);
    p_e3 := split_part(v_probe, '|', 4);
    p_f1 := split_part(v_probe, '|', 5);
    p_f2 := split_part(v_probe, '|', 6);
    p_f3 := split_part(v_probe, '|', 7);
    p_f4 := split_part(v_probe, '|', 8);
    p_f5 := split_part(v_probe, '|', 9);
    p_h  := split_part(v_probe, '|', 10);

    -- ══════════ 0) MUHIT (ENV) — HUKM CHIQARILMAYDI ══════════
    IF p_d LIKE 'ENV:%' OR p_e1 LIKE 'ENV:%' OR p_e2 LIKE 'ENV:%'
       OR p_e3 LIKE 'ENV:%' OR p_h LIKE 'ENV:%' THEN
      v_skip := 'sinov muhiti qator yozishga/yangilashga imkon bermadi (bu CHECK/RLS aybi EMAS) — d=' || p_d
             || ' e1=' || p_e1 || ' e2=' || p_e2 || ' e3=' || p_e3 || ' h=' || p_h;
      RAISE WARNING 'TIRIK SINOVLAR O''TKAZIB YUBORILDI — %. Struktura va migratsiya tekshiruvlari BAJARILDI; prodga chiqishdan oldin QO''LDA sinang.', v_skip;
      INSERT INTO pg_temp.shb_res VALUES
        (60, 'sinov', 'TIRIK SINOVLAR', 'o''tkazib yuborildi', v_skip);
      RETURN;
    END IF;

    -- ══════════ HUKMLAR (biri salbiy bo'lsa HAMMASI QAYTADI) ══════════
    IF p_d <> 'RAD:project_cycles_project_no_uq' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (d): (project_id, cycle_no) juftligini IKKINCHI marta yozish rad etilmadi (natija: %, kutilgan: RAD:project_cycles_project_no_uq). Materializatsiya DA''VOSI aynan shu indeksga tayanadi — usiz ikki admin bir siklni ikki marta ochib, bosqichlar IKKI NUSXA bo''lardi. HAMMASI QAYTARILDI.', p_d;
    END IF;

    IF p_e2 <> 'OK' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (e2): toza SHABLON (is_template = true, template_id/cycle_id NULL) yozilmadi (%). Modulning o''zi ishlamasdi. HAMMASI QAYTARILDI.', p_e2;
    END IF;

    IF p_e1 <> 'RAD:tasks_template_flags_chk' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (e1): SHABLONGA template_id yozish rad etilmadi (natija: %, kutilgan: RAD:tasks_template_flags_chk). Shablon o''zi instansiyaga aylanib, materializatsiya cheksiz zanjir qurardi. HAMMASI QAYTARILDI.', p_e1;
    END IF;

    IF p_e3 <> 'OK' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (e3) 🔴 REGRESSIYA: INSTANSIYA (is_template = false + template_id + cycle_id) yozilmadi (%). CHECK juda qattiq — normal ish qatori ham to''silgan bo''lardi. HAMMASI QAYTARILDI.', p_e3;
    END IF;

    IF p_h <> 'OK' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (h) 🔴 REGRESSIYA: mavjud vazifani oddiy yangilash (title) ishlamadi (%). Yangi CHECK butun ilovadagi har UPDATE ni yiqitgan bo''lardi. HAMMASI QAYTARILDI.', p_h;
    END IF;

    -- RLS hukmlari (impersonatsiya ishlagan bo'lsa)
    IF p_f2 <> '-' AND left(p_f2, 1) = 'E' THEN
      RAISE WARNING '(f2): begona ws a''zosining project_cycles SELECT so''rovi XATO bilan tugadi (%) — qator KO''RINMADI, lekin sabab RLS emas. Tekshirib qo''ying.', p_f2;
    ELSIF p_f2 <> '-' AND p_f2 <> '0' THEN
      RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (f2): BEGONA workspace a''zosi project_cycles qatorini KO''RDI (% qator). SELECT policy ishlamadi. HAMMASI QAYTARILDI.', p_f2;
    END IF;

    IF p_f3 <> '-' AND left(p_f3, 1) = 'E' THEN
      RAISE WARNING '(f3): begona ws a''zosining template_history SELECT so''rovi XATO bilan tugadi (%) — qator KO''RINMADI, lekin sabab RLS emas.', p_f3;
    ELSIF p_f3 <> '-' AND p_f3 <> '0' THEN
      RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (f3): BEGONA workspace a''zosi template_history qatorini KO''RDI (% qator). SELECT policy ishlamadi. HAMMASI QAYTARILDI.', p_f3;
    END IF;

    IF p_f4 = 'YOZDI' THEN
      RAISE EXCEPTION 'XAVFSIZLIK BUZILDI (f4): BEGONA workspace a''zosi project_cycles ga QATOR YOZDI. INSERT policy ishlamadi. HAMMASI QAYTARILDI.';
    END IF;

    IF p_f1 <> '-' AND left(p_f1, 1) <> 'E' AND p_f1 = '0' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (f1): ws-MENEJERI o''z workspace''idagi siklni KO''RMADI (natija: %). SELECT policy juda qattiq — loyiha sahifasidagi sikl tanlagichi bo''sh qolardi. HAMMASI QAYTARILDI.', p_f1;
    END IF;

    IF p_f5 <> '-' AND left(p_f5, 1) <> 'E' AND p_f5 = '0' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (f5): oddiy A''ZO o''z workspace''idagi siklni KO''RMADI (natija: %). Ko''rish butun jamoaga ochiq bo''lishi kerak. HAMMASI QAYTARILDI.', p_f5;
    END IF;

    INSERT INTO pg_temp.shb_res VALUES
      (70, 'sinov', '(d) 🔴 UNIQUE (project_id, cycle_no)', 'rad etildi',
       'project_cycles_project_no_uq — materializatsiya DA''VOSI atomik: 23505 = "boshqa admin ulgurdi"'),
      (71, 'sinov', '(e2) toza SHABLON', 'o''tdi',
       'is_template = true + template_id/cycle_id NULL — modulning asosiy holati'),
      (72, 'sinov', '(e1) SHABLON + template_id', 'rad etildi',
       'tasks_template_flags_chk — shablon o''zi na instansiya, na siklga tegishli'),
      (73, 'sinov', '(e3) INSTANSIYA', 'o''tdi',
       'is_template = false + template_id + cycle_id — normal ish qatori to''silmaydi (REGRESSIYA yo''q)'),
      (74, 'sinov', '(h) oddiy UPDATE (title)', 'o''tdi',
       'UPDATE da Postgres qatorning BARCHA CHECK''larini qayta baholaydi — yangi cheklov mavjud ma''lumotga zid emas'),
      (75, 'sinov', '(f) RLS',
       CASE WHEN v_imp_ok THEN 'o''tdi' ELSE 'o''tkazib yuborildi (impersonatsiya harnessi ishlamadi)' END,
       'menejer ko''rdi (' || coalesce(p_f1,'?') || ') · a''zo ko''rdi (' || coalesce(p_f5,'?')
       || ') · begona KO''RMADI: cycles=' || coalesce(p_f2,'?') || ' history=' || coalesce(p_f3,'?')
       || ' · begona YOZOLMADI (' || coalesce(p_f4,'?') || ')'),
      (76, 'sinov', 'SENTINEL-ROLLBACK', 'toza',
       'Sinov qatorlari subtranzaksiya bilan QAYTARILDI — bazada bitta qator ham qolmadi (sequence bir necha pog''ona siljigan bo''lishi mumkin, bu ma''lumot emas)');

    RAISE NOTICE 'TIRIK SINOVLAR O''TDI — sentinel-rollback: bazada bitta qator ham QOLMADI.';
  END;
END $live$;

-- ════════════════════════════════════════════════════════════════════════════
-- 8b) 🔴 TIRIK TRIGGER SINOVI — SENTINEL-ROLLBACK
--     0e-bo'lim triggerni O'QIB hukm chiqardi; bu bo'lim uni HARAKATDA
--     sinaydi. Statik tahlil yetarli emas: trigger boshqa funksiyani chaqirishi
--     yoki dinamik SQL yozishi mumkin.
--
--     Sahna (hammasi sentinel — oxirida QAYTARILADI):
--       sentinel loyiha + 1-sikl + 2 bosqich (tartib 1 va 2, ikkinchisi
--       depends_on_prev = true) + o'sha bosqichlarning 2 SHABLONI + 2-sikl
--       instansiyalari.
--       (t1) SHABLONLAR qo'shilishi MAVJUD bosqichning is_locked ini
--            o'zgartirdimi? (o'zgarsa — trigger shablonni BOSQICH deb biladi)
--       (t2) trigger SHABLON qatoriga is_locked = true yozib qo'ydimi?
--       (t3) 1-bosqich `completed` bo'lgach 2-bosqich OCHILDIMI — yoki shablon
--            (status = 'new') uni ushlab qoldimi? [xavf (a)]
--       (t4) 2-SIKL bosqichi QULFLANDIMI — yoki 1-siklning `completed` qatori
--            uni noto'g'ri ochib yubordimi? [xavf (b)]
--
--     ⚠️ (t3)/(t4) FAQAT qulf trigger'i HAQIQATAN qulf yozganda hukm qilinadi:
--        agar 2-bosqich insert paytida ham qulflanmagan bo'lsa (ya'ni bazada
--        qulf trigger'i yo'q yoki u qulf yozmaydi) — kutiladigan natija YO'Q →
--        'ENV:' bilan belgilanib O'TKAZIB YUBORILADI (soxta salbiy bo'lmasin,
--        mavjud 8-bo'lim naqshi).
--     ⚠️ Yozuv qiladigan qism ichki blokda ATAYLAB EXCEPTION bilan tugatiladi
--        → subtranzaksiya qaytadi, bazada BITTA qator ham qolmaydi.
--     ⚠️ v_allow_risky_trigger = true bo'lsa hukmlar EXCEPTION emas, WARNING
--        beradi — aks holda "ataylab davom etish" yo'li ishlamas edi.
-- ════════════════════════════════════════════════════════════════════════════
DO $live2$
DECLARE
  v_idtype   text;
  v_projtyp  text;
  v_ws       uuid;
  v_mgr      uuid;
  v_skip     text;
  v_bad      text;
  v_allow    boolean := false;
  v_lockw    int := 0;
  v_pname    text;
  v_pins     text;
  v_ins      text;
  v_sel      text;
  v_upd      text;
  v_pexpr    text;
  v_ordcols  text := '';
  v_ordvals  text := '';
  v_pcols    text := '';
  v_pvals    text := '';
  v_tcols    text := '';
  v_tvals    text := '';
  v_prj2     text;
  v_c1       uuid;
  v_c2       uuid;
  v_a        text;
  v_b        text;
  v_ta       text;
  v_tb       text;
  v_b2       text;
  v_tmp      text;
  v_err      text;
  v_state    text;
  v_tprobe   text;
  v_fail     text := '';
  v_msg      text;
  v_has_cmpl boolean;
  q_l1 text; q_l2 text; q_ta text; q_tb text; q_l3 text; q_l4 text;
BEGIN
  SELECT v INTO v_idtype  FROM pg_temp.shb_ref WHERE k='idtype';
  SELECT v INTO v_projtyp FROM pg_temp.shb_ref WHERE k='projtype';
  SELECT v INTO v_allow   FROM pg_temp.shb_cfg WHERE k='allow_risky_trigger';
  SELECT v INTO v_bad     FROM pg_temp.shb_ref WHERE k='trg_lockw';
  v_lockw := coalesce(v_bad, '0')::int;
  v_bad := NULL;

  -- ── (8b.0) SHART-SHAROIT ─────────────────────────────────────────────────
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name='is_locked') THEN
    v_skip := 'public.tasks da is_locked ustuni yo''q — qulf sinovi ma''nosiz';
  END IF;
  IF v_skip IS NULL AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name='status') THEN
    v_skip := 'public.tasks da status ustuni yo''q';
  END IF;
  IF v_skip IS NULL AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name='title') THEN
    v_skip := 'public.tasks da title ustuni yo''q — sinov qatorini taxmin bilan to''ldirmaymiz';
  END IF;
  IF v_skip IS NULL AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name='project_id') THEN
    v_skip := 'public.tasks da project_id ustuni yo''q';
  END IF;

  -- Tartib ustuni: flow_order VA/YOKI order_index — ikkalasiga ham bir xil
  -- qiymat yoziladi (qaysi birini trigger o'qishini bilmaymiz).
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='tasks' AND column_name='flow_order') THEN
    v_ordcols := v_ordcols || ', flow_order';
    v_ordvals := v_ordvals || ', %6$s';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='tasks' AND column_name='order_index') THEN
    v_ordcols := v_ordcols || ', order_index';
    v_ordvals := v_ordvals || ', %6$s';
  END IF;
  IF v_skip IS NULL AND v_ordcols = '' THEN
    v_skip := 'public.tasks da flow_order ham, order_index ham yo''q — "oldingi bosqich" tushunchasi yo''q';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='tasks' AND column_name='depends_on_prev') THEN
    v_tcols := v_tcols || ', depends_on_prev';
    v_tvals := v_tvals || ', %7$s';
  END IF;

  v_has_cmpl := EXISTS (SELECT 1 FROM information_schema.columns
                         WHERE table_schema='public' AND table_name='tasks' AND column_name='completed_at');

  -- tasks.id / projects.id avtomatikmi
  IF v_skip IS NULL AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name='id'
                    AND (column_default IS NOT NULL OR is_identity='YES')) THEN
    v_skip := 'public.tasks.id da DEFAULT/IDENTITY yo''q — sinov qatorining id sini skript o''ylab topa olmaydi';
  END IF;
  IF v_skip IS NULL AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='projects' AND column_name='id'
                    AND (column_default IS NOT NULL OR is_identity='YES')) THEN
    v_skip := 'public.projects.id da DEFAULT/IDENTITY yo''q';
  END IF;

  -- Bilmaydigan MAJBURIY ustun bo'lsa sinov o'tkazilmaydi (23502 ga urilmasin)
  IF v_skip IS NULL THEN
    SELECT string_agg(column_name, ', ') INTO v_bad
      FROM information_schema.columns
     WHERE table_schema='public' AND table_name='tasks'
       AND is_nullable='NO' AND column_default IS NULL AND is_identity='NO'
       AND column_name NOT IN ('id','workspace_id','title','status','project_id',
                               'created_by','assigned_to','flow_order','order_index',
                               'depends_on_prev','is_locked','is_template','template_id','cycle_id');
    IF v_bad IS NOT NULL THEN
      v_skip := 'public.tasks da noma''lum majburiy ustun(lar): ' || v_bad;
    END IF;
  END IF;
  IF v_skip IS NULL THEN
    SELECT string_agg(column_name, ', ') INTO v_bad
      FROM information_schema.columns
     WHERE table_schema='public' AND table_name='projects'
       AND is_nullable='NO' AND column_default IS NULL AND is_identity='NO'
       AND column_name NOT IN ('id','workspace_id','name','title','created_by','status');
    IF v_bad IS NOT NULL THEN
      v_skip := 'public.projects da noma''lum majburiy ustun(lar): ' || v_bad;
    END IF;
  END IF;

  -- Menejeri bor workspace (sentinel loyiha o'sha yerda tug'iladi)
  IF v_skip IS NULL THEN
    SELECT m.workspace_id, m.user_id INTO v_ws, v_mgr
      FROM public.workspace_members m
     WHERE public.is_ws_manager(m.workspace_id, m.user_id)
     ORDER BY m.workspace_id, m.user_id
     LIMIT 1;
    IF v_ws IS NULL THEN
      v_skip := 'menejeri bor workspace topilmadi (bo''sh baza)';
    END IF;
  END IF;

  -- projects dagi nom ustuni
  IF v_skip IS NULL THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='projects' AND column_name='name') THEN
      v_pname := 'name';
    ELSIF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='projects' AND column_name='title') THEN
      v_pname := 'title';
    ELSE
      v_skip := 'public.projects da name/title ustuni yo''q';
    END IF;
  END IF;

  IF v_skip IS NOT NULL THEN
    RAISE WARNING 'TRIGGER TIRIK SINOVI (8b) O''TKAZIB YUBORILDI — %. 0e-bo''limdagi STATIK tahlil BAJARILDI; prodga chiqishdan oldin loyiha bosqichlari qulfini QO''LDA sinang.', v_skip;
    INSERT INTO pg_temp.shb_res VALUES
      (85, 'sinov', 'TRIGGER TIRIK SINOVI (t1..t4)', 'o''tkazib yuborildi', v_skip);
    RETURN;
  END IF;

  -- ── (8b.1) INSERT shablonlari ────────────────────────────────────────────
  --    projects: workspace_id + nom (+ created_by / status — faqat MAJBURIY bo'lsa)
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='projects' AND column_name='created_by') THEN
    v_pcols := v_pcols || ', created_by';
    v_pvals := v_pvals || ', ' || quote_literal(v_mgr::text) || '::uuid';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='projects' AND column_name='status'
                AND is_nullable='NO' AND column_default IS NULL) THEN
    v_pcols := v_pcols || ', status';
    v_pvals := v_pvals || ', ' || quote_literal('active');
  END IF;

  v_pins := 'INSERT INTO public.projects (workspace_id, ' || quote_ident(v_pname) || v_pcols
         || ') VALUES (' || quote_literal(v_ws::text) || '::uuid, '
         || quote_literal('SHB-TRG SINOV (sentinel)') || v_pvals || ') RETURNING id::text';

  --    tasks: created_by / assigned_to — qiymat QATTIQ (menejer), format
  --    argumenti EMAS; qolgani pozitsion (%1$..%8$) markerlar bilan.
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='tasks' AND column_name='created_by') THEN
    v_tcols := v_tcols || ', created_by';
    v_tvals := v_tvals || ', ' || quote_literal(v_mgr::text) || '::uuid';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='tasks' AND column_name='assigned_to') THEN
    v_tcols := v_tcols || ', assigned_to';
    v_tvals := v_tvals || ', ' || quote_literal(v_mgr::text) || '::uuid';
  END IF;

  v_sel := 'SELECT is_locked::text FROM public.tasks WHERE id::text = $1';

  -- ══════════════ SENTINEL BLOK (hammasi qaytariladi) ══════════════
  BEGIN
    EXECUTE v_pins INTO v_prj2;

    --  ⚠️ project_id qiymati id TIPIGA bog'lanmasin deb subselect bilan;
    --     ehtiyot uchun % qochiriladi (u format() shablonining bir qismi).
    v_pexpr := replace('(SELECT p.id FROM public.projects p WHERE p.id::text = '
                       || quote_literal(v_prj2) || ')', '%', '%%');

    v_ins := 'INSERT INTO public.tasks (workspace_id, project_id, title, is_template,'
          || ' template_id, cycle_id, status, is_locked' || v_ordcols || v_tcols
          || ') VALUES (' || quote_literal(v_ws::text) || '::uuid, ' || v_pexpr
          || ', %1$L, %2$s, %3$s, %4$s, %5$s, %8$s' || v_ordvals || v_tvals
          || ') RETURNING id::text';

    EXECUTE 'INSERT INTO public.project_cycles (workspace_id, project_id, cycle_no)'
         || ' VALUES ($1, $2::' || v_projtyp || ', 1) RETURNING id'
      INTO v_c1 USING v_ws, v_prj2;
    EXECUTE 'INSERT INTO public.project_cycles (workspace_id, project_id, cycle_no)'
         || ' VALUES ($1, $2::' || v_projtyp || ', 2) RETURNING id'
      INTO v_c2 USING v_ws, v_prj2;

    -- 1-sikl bosqichlari: A (tartib 1) va B (tartib 2, oldingisiga bog'liq)
    EXECUTE format(v_ins, 'SHB-TRG A1 (sentinel)', 'false', 'NULL',
                   quote_literal(v_c1::text) || '::uuid', quote_literal('new'),
                   '1', 'false', 'false') INTO v_a;
    EXECUTE format(v_ins, 'SHB-TRG B1 (sentinel)', 'false', 'NULL',
                   quote_literal(v_c1::text) || '::uuid', quote_literal('new'),
                   '2', 'true', 'false') INTO v_b;

    -- 🔴 BAZAVIY holat: qulf trigger'i B ni QULFLADIMI? (t3)/(t4) shunga qaraydi
    EXECUTE v_sel INTO q_l1 USING v_b;

    -- SHABLONLAR (aynan migratsiya yaratadigan qatorlar: is_template = true,
    -- template_id/cycle_id NULL, is_locked KO'CHIRILMAYDI → false)
    EXECUTE format(v_ins, 'SHB-TRG TA (sentinel)', 'true', 'NULL', 'NULL',
                   quote_literal('new'), '1', 'false', 'false') INTO v_ta;
    EXECUTE format(v_ins, 'SHB-TRG TB (sentinel)', 'true', 'NULL', 'NULL',
                   quote_literal('new'), '2', 'true', 'false') INTO v_tb;

    -- (t1) mavjud bosqichning qulfi o'zgardimi?  (t2) shablon qulflandimi?
    EXECUTE v_sel INTO q_l2 USING v_b;
    EXECUTE v_sel INTO q_ta USING v_ta;
    EXECUTE v_sel INTO q_tb USING v_tb;

    -- 1-bosqichni TUGATAMIZ → 2-bosqich ochilishi kerak
    v_upd := 'UPDATE public.tasks SET status = ' || quote_literal('completed');
    IF v_has_cmpl THEN
      v_upd := v_upd || ', completed_at = now()';
    END IF;
    v_upd := v_upd || ' WHERE id::text = $1';
    EXECUTE v_upd USING v_a;

    EXECUTE v_sel INTO q_l3 USING v_b;   -- (t3)

    -- 2-SIKL instansiyalari (materializatsiya natijasi)
    EXECUTE format(v_ins, 'SHB-TRG A2 (sentinel)', 'false',
                   quote_literal(v_ta) || '::' || v_idtype,
                   quote_literal(v_c2::text) || '::uuid', quote_literal('new'),
                   '1', 'false', 'false') INTO v_tmp;
    EXECUTE format(v_ins, 'SHB-TRG B2 (sentinel)', 'false',
                   quote_literal(v_tb) || '::' || v_idtype,
                   quote_literal(v_c2::text) || '::uuid', quote_literal('new'),
                   '2', 'true', 'false') INTO v_b2;

    EXECUTE v_sel INTO q_l4 USING v_b2;  -- (t4)

    -- ⚠️ SENTINEL: subtranzaksiyani ATAYLAB qaytaramiz.
    --    Ajratgich '~' (mavjud 8-bo'limdagi '|' bilan chalkashmasin).
    RAISE EXCEPTION 'SHB_TRG:%',
      coalesce(q_l1, '?') || '~' || coalesce(q_l2, '?') || '~' || coalesce(q_ta, '?') || '~' ||
      coalesce(q_tb, '?') || '~' || coalesce(q_l3, '?') || '~' || coalesce(q_l4, '?')
      USING ERRCODE = '22000';

  EXCEPTION WHEN OTHERS THEN
    v_err   := SQLERRM;
    v_state := SQLSTATE;

    IF v_err NOT LIKE 'SHB_TRG:%' THEN
      -- Harness xatosi — migratsiya to'xtatilmaydi, lekin JIMGINA HAM
      -- YUTILMAYDI (CLAUDE.md 6-qoida).
      v_skip := 'sinov sahnasini qurib bo''lmadi (' || v_state || '): ' || left(v_err, 200);
      RAISE WARNING 'TRIGGER TIRIK SINOVI (8b) O''TKAZIB YUBORILDI — %. 0e-bo''limdagi STATIK tahlil BAJARILDI; prodga chiqishdan oldin QO''LDA sinang.', v_skip;
      INSERT INTO pg_temp.shb_res VALUES
        (85, 'sinov', 'TRIGGER TIRIK SINOVI (t1..t4)', 'o''tkazib yuborildi', v_skip);
      RETURN;
    END IF;

    v_tprobe := replace(v_err, 'SHB_TRG:', '');
    q_l1 := split_part(v_tprobe, '~', 1);
    q_l2 := split_part(v_tprobe, '~', 2);
    q_ta := split_part(v_tprobe, '~', 3);
    q_tb := split_part(v_tprobe, '~', 4);
    q_l3 := split_part(v_tprobe, '~', 5);
    q_l4 := split_part(v_tprobe, '~', 6);

    RAISE NOTICE '8b natijalari: B qulfi (insert)=% · shablonlardan keyin=% · TA=% · TB=% · A tugagach B=% · 2-sikl B2=%',
      q_l1, q_l2, q_ta, q_tb, q_l3, q_l4;

    -- ══════════ HUKMLAR ══════════
    -- (t1) SHABLON qo'shilishi MAVJUD bosqichga TEGMASLIGI kerak
    IF q_l2 IS DISTINCT FROM q_l1 THEN
      v_fail := v_fail || chr(10)
        || '  (t1) SHABLONLAR qo''shilgach MAVJUD bosqichning is_locked qiymati "'
        || q_l1 || '" dan "' || q_l2 || '" ga O''ZGARDI — trigger shablonni BOSQICH deb biladi.';
    END IF;

    -- (t2) SHABLON hech qachon qulflanmaydi (u ish emas, ta'rif)
    IF q_ta = 'true' OR q_tb = 'true' THEN
      v_fail := v_fail || chr(10)
        || '  (t2) trigger SHABLON qatoriga is_locked = true yozdi (TA=' || q_ta || ', TB=' || q_tb
        || ') — shablon ISH emas, TA''RIF; migratsiya shu sababli is_locked ni nusxalamaydi ham.';
    END IF;

    -- (t3)/(t4) — faqat qulf trigger'i HAQIQATAN qulflagan bo'lsa hukm qilinadi
    IF q_l1 <> 'true' THEN
      RAISE NOTICE '(t3)/(t4) ENV: 2-bosqich insert paytida ham qulflanmagan (is_locked = %) — bazada qulf trigger''i yo''q yoki u qulf yozmaydi (0e: is_locked ga tegadigan trigger % ta). Hukm chiqarilmadi.', q_l1, v_lockw;
    ELSE
      IF q_l3 <> 'false' THEN
        v_fail := v_fail || chr(10)
          || '  (t3) 1-bosqich `completed` bo''lgach 2-bosqich OCHILMADI (is_locked = ' || q_l3
          || ') — SHABLON (status = ''new'', hech qachon tugamaydi) "oldingi bosqich" bo''lib uni ABADIY ushlab turibdi. [xavf (a)]';
      END IF;
      IF q_l4 <> 'true' THEN
        v_fail := v_fail || chr(10)
          || '  (t4) 2-SIKL bosqichi QULFLANMADI (is_locked = ' || q_l4
          || ') — 1-siklning `completed` qatori uni NOTO''G''RI ochib yubordi. [xavf (b)]';
      END IF;
    END IF;

    IF v_fail <> '' THEN
      v_msg := '🔴 TRIGGER TIRIK SINOVI (8b) YIQILDI — public.tasks dagi trigger SHABLON/SIKL qatorlarini oddiy bosqich deb hisoblayapti:'
        || v_fail
        || chr(10) || 'YECHIM: trigger funksiyasidagi "oldingi/keyingi bosqich" qidiruviga qorovul qo''shing — `AND is_template IS NOT TRUE` (shablon) va `AND cycle_id IS NOT DISTINCT FROM NEW.cycle_id` (o''tgan sikl), so''ng shu skriptni QAYTA RUN qiling. Trigger funksiyalarining tanasi 0e-bo''limda NOTICE bilan chop etilgan.'
        || chr(10) || 'Ataylab davom etish: fayl boshidagi SOZLAMA blokida v_allow_risky_trigger := true.'
        || chr(10) || 'HAMMASI QAYTARILDI — bazada bir belgi ham o''zgarmadi.';
      IF coalesce(v_allow, false) THEN
        RAISE WARNING '%', v_msg;
        INSERT INTO pg_temp.shb_res VALUES
          (85, 'sinov', 'TRIGGER TIRIK SINOVI (t1..t4)', '⚠️ YIQILDI — ATAYLAB O''TKAZILDI',
           'v_allow_risky_trigger = true bo''lgani uchun migratsiya to''xtatilmadi. Tafsilot RUN jurnalidagi WARNING da.');
        RETURN;
      END IF;
      RAISE EXCEPTION '%', v_msg;
    END IF;

    INSERT INTO pg_temp.shb_res VALUES
      (80, 'sinov', '(t1) 🔴 shablon MAVJUD bosqich qulfiga tegmadi', 'o''tdi',
       '2 ta SHABLON qo''shilgandan keyin mavjud bosqichning is_locked qiymati o''zgarmadi (' || q_l1 || ').'),
      (81, 'sinov', '(t2) 🔴 SHABLON qulflanmadi', 'o''tdi',
       'Trigger shablon qatorlariga is_locked = true yozmadi (TA=' || q_ta || ', TB=' || q_tb || ') — shablon ish emas, ta''rif.'),
      (82, 'sinov', '(t3) 1-bosqich tugagach 2-bosqich ochildi',
       CASE WHEN q_l1 = 'true' THEN 'o''tdi' ELSE 'ENV — qulf trigger''i qulf yozmaydi' END,
       'Shablon (status = ''new'') "oldingi bosqich" bo''lib keyingisini ABADIY ushlab qolmadi. Natija: is_locked = ' || q_l3 || '.'),
      (83, 'sinov', '(t4) 2-sikl bosqichi qulflandi',
       CASE WHEN q_l1 = 'true' THEN 'o''tdi' ELSE 'ENV — qulf trigger''i qulf yozmaydi' END,
       'O''tgan siklning `completed` qatori yangi sikl bosqichini noto''g''ri ochib yubormadi. Natija: is_locked = ' || q_l4 || '.'),
      (84, 'sinov', 'SENTINEL-ROLLBACK (8b)', 'toza',
       'Sentinel loyiha, 2 sikl, 6 vazifa qatori subtranzaksiya bilan QAYTARILDI — bazada bitta qator ham qolmadi.');

    RAISE NOTICE 'TRIGGER TIRIK SINOVI (8b) O''TDI — sentinel-rollback: bazada bitta qator ham QOLMADI.';
  END;
END $live2$;



-- ════════════════════════════════════════════════════════════════════════════
-- 9) YAKUNIY HISOBOT
-- ════════════════════════════════════════════════════════════════════════════
DO $rep$
DECLARE
  v_c_ist  boolean;
  v_c_tpl  boolean;
  v_c_cyc  boolean;
  v_t_cyc  boolean;
  v_t_his  boolean;
  v_deps   boolean;
  v_csp    boolean;
  v_skipn  int;
  v_skipt  int;
  v_envt   int;
  v_trgn   text;
  v_trgr   text;
  v_trgnm  text;
  v_cols   text;
BEGIN
  SELECT v INTO v_c_ist FROM pg_temp.shb_pre WHERE k='col_is_template';
  SELECT v INTO v_c_tpl FROM pg_temp.shb_pre WHERE k='col_template_id';
  SELECT v INTO v_c_cyc FROM pg_temp.shb_pre WHERE k='col_cycle_id';
  SELECT v INTO v_t_cyc FROM pg_temp.shb_pre WHERE k='tbl_cycles';
  SELECT v INTO v_t_his FROM pg_temp.shb_pre WHERE k='tbl_history';
  SELECT v INTO v_deps  FROM pg_temp.shb_pre WHERE k='has_deps';
  SELECT v INTO v_csp   FROM pg_temp.shb_pre WHERE k='has_csp';
  SELECT v INTO v_cols  FROM pg_temp.shb_ref WHERE k='cols';

  INSERT INTO pg_temp.shb_res VALUES
    (1, 'ustun', 'public.tasks.is_template (boolean NOT NULL DEFAULT false)',
     CASE WHEN coalesce(v_c_ist,false) THEN 'allaqachon bor edi' ELSE 'QO''SHILDI' END,
     '🔴 SHABLON belgisi: true = ta''rif, ish EMAS. Mijozda yagona choke-point (tasksAcceptRow) uni tasksCache ga qo''ymaydi; so''rovda .eq(''is_template'', false) YOZILMAYDI (ustun yo''q bazada 42703 butun ilovani o''ldirardi).'),
    (2, 'ustun', 'public.tasks.template_id (tasks.id tipida)',
     CASE WHEN coalesce(v_c_tpl,false) THEN 'allaqachon bor edi' ELSE 'QO''SHILDI' END,
     'INSTANSIYA → SHABLON. FK tasks(id) ON DELETE SET NULL — shablon o''chsa bajarilgan ish YO''QOLMAYDI.'),
    (3, 'ustun', 'public.tasks.cycle_id (uuid)',
     CASE WHEN coalesce(v_c_cyc,false) THEN 'allaqachon bor edi' ELSE 'QO''SHILDI' END,
     'INSTANSIYA → SIKL. FK project_cycles(id) ON DELETE SET NULL. Kanban sikl filtri aynan shu ustunga tayanadi.'),
    (4, 'CHECK', 'tasks_template_flags_chk', 'joyida',
     'is_template IS NOT TRUE OR (template_id IS NULL AND cycle_id IS NULL). `IS NOT TRUE` ataylab — is_template NULL bo''lib qolgan yarim holatda ham qoida to''g''ri ishlaydi.'),
    (5, 'jadval', 'public.project_cycles',
     CASE WHEN coalesce(v_t_cyc,false) THEN 'allaqachon bor edi' ELSE 'YARATILDI' END,
     '🔴 UNIQUE (project_id, cycle_no) = materializatsiya DA''VOSI (bayroq emas, INDEKS). DELETE granti/policy''si ATAYLAB yo''q.'),
    (6, 'jadval', 'public.template_history',
     CASE WHEN coalesce(v_t_his,false) THEN 'allaqachon bor edi' ELSE 'YARATILDI' END,
     'action TEXT + CHECK (created|edited|materialized|archived) — ENUM EMAS. UPDATE/DELETE policy YO''Q → tarix o''zgarmas.'),
    (7, 'indeks', 'tasks(project_id, is_template) · tasks(cycle_id) · tasks(template_id)', 'joyida',
     'Oxirgi ikkitasi QISMAN (WHERE ... IS NOT NULL) — ular faqat loyiha bosqichlarida to''ladi, ya''ni 20k vazifali bazada indeks o''nlab marta kichik va `= $1` so''rovini AYNAN to''liq indeks kabi qoplaydi.'),
    (8, 'indeks', 'project_cycles(project_id, cycle_no)', 'UNIQUE cheklovidan',
     '⚠️ Alohida CREATE INDEX YOZILMADI — UNIQUE cheklovi ayni shu indeksni O''ZI yaratadi, ikkinchisi DUBLIKAT bo''lardi. Qo''shimcha: project_cycles(workspace_id) va (project_id) WHERE closed_at IS NULL.'),
    (9, 'indeks', 'template_history(template_id, changed_at DESC)', 'joyida',
     'Qo''shimcha: (project_id, changed_at DESC) — loyiha darajasidagi meta-tarix ko''rinishi uchun.'),
    (10, 'RLS', 'project_cycles', 'SELECT · INSERT · UPDATE',
     'KO''RISH — ws a''zosi (is_ws_member). YOZISH — ws-menejeri YOKI loyiha yaratuvchisi (can_edit_project_cycles). DELETE policy/granti YO''Q: sikl o''chirilsa unga tegishli instansiyalarning cycle_id si NULL bo''lib, ular hamma sikl filtridan yo''qolardi.'),
    (11, 'RLS', 'template_history', 'SELECT · INSERT',
     'KO''RISH — ws a''zosi. YOZISH — ws-menejeri/loyiha yaratuvchisi va FAQAT O''Z NOMIDAN (changed_by = auth.uid(), task_history naqshi). UPDATE/DELETE — YO''Q.'),
    (12, 'funksiya', 'public.can_edit_project_cycles(project, uuid)', 'yaratildi',
     'SECURITY DEFINER · STABLE · faqat authenticated EXECUTE · 2 MAJBURIY qorovul (p_user = auth.uid() — PostgREST /rpc teshigi; is_ws_member — jamoadan chiqarilgan xodim). Huquq: is_ws_manager YOKI projects.created_by.'),
    (20, 'qaror', '🔴 TRIGGER', 'YO''Q (ataylab)',
     'Materializatsiyani MIJOZ qiladi (LAZY, admin loyihani ochganda — mavjud prjRecurDue/prjResetRecurrence/prjStartKickoff naqshi). Server hisoblasa mijoz bilan POYGA qilardi va ilovada cron/EF yo''q.'),
    (21, 'qaror', 'mavjud tasks policy / trigger', 'TEGILMADI',
     '34-migratsiya qulf trigger''i va zz_task_wait_guard_trg o''z joyida. Migratsiya status ni YANGILAMAYDI → BEFORE UPDATE OF status qorovuli umuman ishga tushmaydi.'),
    (22, 'qaror', 'nusxalanadigan ustunlar', 'DINAMIK',
     'information_schema dan istisno ro''yxati ayirilgan (nomma-nom INSERT hali RUN qilinmagan migratsiyalar ustunlari yo''qligi sababli 42703 berardi). Bu bazada: ' || coalesce(v_cols, '?')),
    (23, 'qaror', 'is_locked shablonga', 'KO''CHIRILMADI',
     'Shablon HECH QACHON qulflanmaydi — qulf 34-migratsiya trigger''ining ketma-ketlik belgisi, shablon esa ish emas.'),
    (24, 'qaror', 'izoh / fayl / subtask / ko''rish soni', 'KO''CHIRILMADI',
     'Ular ISH artefaktlari, ta''rif emas. Faqat task_dependencies (KUTISH grafi) ko''chiriladi va u ham jadval mavjud bo''lsa.'),
    (25, 'qaror', 'task_dependencies',
     CASE WHEN coalesce(v_deps,false) THEN 'mavjud — nusxalandi' ELSE 'jadval YO''Q — qadam o''tkazildi' END,
     'TASKFIX_KUTISH.sql RUN qilinmagan bo''lsa bu XATO emas; keyin RUN qilinsa shablon grafi bo''sh qoladi (mijoz uni loyiha ochilganda qayta qura oladi).'),
    (26, 'qaror', 'can_see_project() (TASKFIX_LOYIHA_RLS.sql)',
     CASE WHEN coalesce(v_csp,false) THEN 'bazada BOR — lekin ishlatilmadi' ELSE 'bazada YO''Q — kerak ham emas' END,
     'Ko''rish sharti is_ws_member — u can_see_project DAN KENG, ya''ni OR bilan qo''shsak bir zarra ham qo''shimcha qator bermasdi, lekin hali RUN qilinmagan faylga MAJBURIY bog''liqlik yaratardi.'),
    (27, 'qaror', 'project_cycles da end_at > start_at CHECK', 'QO''YILMADI (ataylab)',
     'Sikl sanalari loyihadan KO''CHIRILADI; TASKFIX_LOYIHA.sql RUN qilinmagan bazada projects da bunday cheklov yo''q va BITTA zid sana butun migratsiyani yiqitardi. Sikl sanasi — ta''riflovchi ma''lumot.');

  -- ⚠️ 8-bo''lim (ord < 80) va 8b-bo''lim (ord >= 80) sinovlari ALOHIDA
  --    sanaladi — biri o''tkazib yuborilsa ikkinchisining natijasi
  --    "0/10" bo''lib ko''rinib qolmasin.
  SELECT count(*) INTO v_skipn FROM pg_temp.shb_res
   WHERE bosqich = 'sinov' AND qiymat LIKE 'o''tkazib%' AND ord < 80;
  SELECT count(*) INTO v_skipt FROM pg_temp.shb_res
   WHERE bosqich = 'sinov' AND ord >= 80
     AND (qiymat LIKE 'o''tkazib%' OR qiymat LIKE '⚠️%');
  -- ⚠️ 'ENV' = qulf trigger'i qulf YOZMAYDI → (t3)/(t4) uchun kutiladigan
  --    natija yo'q, hukm chiqarilmadi. Bu XATO emas, lekin XULOSA da
  --    JIMGINA "bajarildi" deb ko'rsatilmaydi.
  SELECT count(*) INTO v_envt FROM pg_temp.shb_res
   WHERE bosqich = 'sinov' AND ord >= 80 AND qiymat LIKE 'ENV%';

  SELECT v INTO v_trgn  FROM pg_temp.shb_ref WHERE k='trg_n';
  SELECT v INTO v_trgr  FROM pg_temp.shb_ref WHERE k='trg_risky';
  SELECT v INTO v_trgnm FROM pg_temp.shb_ref WHERE k='trg_names';

  -- 🔴 public.tasks DAGI TRIGGERLAR — tekshiruv ROSTDAN bajarildimi va natijasi
  INSERT INTO pg_temp.shb_res VALUES
    (98, 'XULOSA', '🔴 public.tasks TRIGGERLARI TEKSHIRILDI',
     '0e statik: ' || coalesce(v_trgn, '?') || ' ta trigger o''qildi, xavfli: ' || coalesce(v_trgr, '?')
       || ' · 8b tirik: ' || CASE WHEN v_skipt > 0 THEN 'BAJARILMADI'
                                  WHEN v_envt  > 0 THEN 't1, t2 BAJARILDI · t3, t4 = ENV'
                                  ELSE 't1..t4 BAJARILDI' END,
     'Har trigger pg_trigger + pg_proc dan o''qildi (nomi/vaqti/hodisasi/funksiyasi — RUN jurnalidagi NOTICE larda), funksiya tanasi izohlardan tozalab tahlil qilindi: tartib raqami (flow_order/order_index) YOKI is_locked bor-u `is_template` YO''Q bo''lsa — XAVFLI (RAISE EXCEPTION, fail-closed). Xavfli trigger(lar): ' || coalesce(v_trgnm, '-')
       || CASE WHEN v_skipt = 0 AND v_envt = 0
               THEN ' · TIRIK sinov (sentinel loyiha + 2 bosqich + 2 shablon + 2-sikl): shablon mavjud bosqich qulfiga TEGMADI, shablon QULFLANMADI, 1-bosqich tugagach 2-bosqich OCHILDI, 2-sikl bosqichi QULFLANDI.'
               WHEN v_skipt = 0
               THEN ' · TIRIK sinov: (t1) shablon mavjud bosqich qulfiga TEGMADI va (t2) shablon QULFLANMADI — bajarildi. ⚠️ (t3)/(t4) ENV: bazadagi trigger insert paytida qulf YOZMAGANI uchun "oldingi bosqich" mantiqini sinab bo''lmadi — loyiha bosqichlari navbatini QO''LDA tekshiring.'
               ELSE ' · ⚠️ TIRIK sinov o''tkazib yuborildi yoki ataylab chetlab o''tildi — sabab "sinov" qatorida. Loyiha bosqichlari qulfini QO''LDA sinang.' END);

  INSERT INTO pg_temp.shb_res VALUES
    (99, 'XULOSA',
     CASE WHEN v_skipn = 0 THEN 'TIRIK SINOVLAR TO''LIQ BAJARILDI'
          ELSE '🔴 DIQQAT: TIRIK SINOVLAR O''TKAZIB YUBORILDI' END,
     CASE WHEN v_skipn = 0 THEN '10/10' ELSE '0/10' END
       || CASE WHEN v_skipt > 0 THEN ' · trigger 0/4'
               WHEN v_envt  > 0 THEN ' · trigger 2/4 (t3, t4 = ENV)'
               ELSE ' · trigger 4/4' END,
     CASE WHEN v_skipn = 0
          THEN 'Migratsiya tekshiruvlari (a, b, c, c2, g) VA tirik sinovlar (d, e1, e2, e3, f1..f5, h) bajarildi; birortasi salbiy bo''lsa skript COMMIT QILMAGAN bo''lardi. Sinov qatorlari qaytarildi.'
          ELSE '⚠️ Migratsiya COMMIT BO''LDI (struktura va migratsiya tekshiruvlari o''tdi), lekin TIRIK sinovlar bajarilmadi — sabab "sinov" qatorida yozilgan. Prodga chiqishdan oldin QO''LDA sinang.' END
     || ' · 🔴 public.tasks TRIGGERLARI: 0e statik tahlil BAJARILDI (' || coalesce(v_trgn, '?') || ' ta trigger), 8b tirik sinov: '
     || CASE WHEN v_skipt > 0 THEN 'BAJARILMADI — (98) qatorga qarang'
             WHEN v_envt  > 0 THEN 'QISMAN (t1, t2) — (98) qatorga qarang'
             ELSE 'BAJARILDI (t1..t4)' END);

  IF v_skipn > 0 OR v_skipt > 0 THEN
    RAISE WARNING 'Tirik sinovlar (8 va/yoki 8b) o''tkazib yuborildi — migratsiya baribir COMMIT bo''ldi. Yakuniy jadvalning XULOSA qatorlariga (98, 99) qarang.';
  END IF;

  RAISE NOTICE 'TASKFIX_SHABLON TUGADI — pastdagi jadvalga qarang.';
END $rep$;

COMMIT;

-- PostgREST sxema keshini yangilash (Supabase'da odatda event trigger o'zi
-- qiladi; bu qator kafolat uchun — zararsiz va idempotent).
NOTIFY pgrst, 'reload schema';


-- ══════════ NATIJA ══════════
SELECT bosqich, nom, qiymat, izoh FROM pg_temp.shb_res ORDER BY ord;


-- ============================================================================
-- QANDAY O'QISH
-- ============================================================================
--  • Barcha "tekshiruv" va "sinov" qatorlari OK bo'lsa ish bitdi.
--  • "allaqachon bor edi" — skript ikkinchi marta RUN qilingan. Bu XATO emas:
--    ustunlar/jadvallar qayta yaratilmaydi va MIGRATSIYA ham ikkinchi shablon
--    to'plamini YARATMAYDI (project_cycles qatori bor loyiha o'tkaziladi).
--  • 🔴 ENG MUHIM QATORLAR:
--      (c)  mavjud qator id lari joyida — izoh/fayl/tarix havolalari butun
--      (c2) bola qatorlar soni oldin/keyin AYNAN teng
--      (d)  UNIQUE (project_id, cycle_no) haqiqatan ikkinchi insertni RAD etadi
--      (e1) shablonga template_id yozib bo'lmaydi
--      (e3)/(h) REGRESSIYA yo'q — normal ish qatori va oddiy UPDATE ishlaydi
--      (f2)/(f3)/(f4) begona ws a'zosi KO'RMAYDI va YOZOLMAYDI
--      (30)/(31) 🔴 public.tasks dagi TRIGGERLAR o'qildi va xavf tahlili
--           qilindi (xavfli topilsa skript RUN'ni TO'XTATADI — pastga qarang)
--      (t1)..(t4) 🔴 trigger SHABLON/SIKL qatorlarini oddiy bosqich deb
--           hisoblamayotgani SENTINEL sahnada tirik sinaldi
--      (98) trigger tekshiruvi ROSTDAN bajarildimi — natijasi shu qatorda
--    ⚠️ ANIQLIK: hukm chiqarilib salbiy bo'lsa skript COMMIT QILMAYDI. LEKIN
--    tirik sinov UMUMAN o'tkazilmagan bo'lishi ham mumkin (bo'sh baza / tasks
--    da noma'lum majburiy ustun / id da DEFAULT yo'q / impersonatsiya
--    harnessi ishlamadi = "ENV:") — u holda migratsiya WARNING bilan COMMIT
--    BO'LADI. Shuning uchun ENG OXIRGI "XULOSA" qatoriga qarang.
--  • "ENV:" prefiksi — muhit to'sdi, bu migratsiyaning aybi EMAS.
--  • WARNING'lar (agar chiqsa): ustun darajasidagi GRANT · ifodali UNIQUE
--    indeks · loyihasi topilmagan bosqich · katta hajm. Ular migratsiyani
--    to'xtatmaydi, lekin e'tibor talab qiladi.
--
-- ── RUN'DAN OLDIN CHIQISHI MUMKIN BO'LGAN TO'XTATUVCHI XATO ────────────────
--   🔴 "public.tasks da SHABLON MIGRATSIYASI UCHUN XAVFLI trigger topildi"
--   Sabab: 0e-bo'lim trigger funksiyasining tanasida tartib raqami
--   (flow_order/order_index) yoki is_locked bilan ishlashni topdi, lekin
--   `is_template` qorovulini TOPMADI (yoki tanasini umuman o'qiy olmadi).
--   Migratsiyadan keyin bitta loyihada bir xil tartib raqami IKKI marta
--   bo'ladi (shablon + instansiya) va har sikl yana N ta qator qo'shadi —
--   ya'ni bunday trigger (a) keyingi bosqichni ABADIY qulflab qo'yishi yoki
--   (b) o'tgan siklning `completed` qatoriga qarab uni NOTO'G'RI ochib
--   yuborishi mumkin.
--   Yechim xato matnida va fayl boshidagi SOZLAMA blokida yozilgan:
--   trigger funksiyasiga `AND is_template IS NOT TRUE` (+ sikl uchun
--   `AND cycle_id IS NOT DISTINCT FROM NEW.cycle_id`) qo'shib QAYTA RUN,
--   yoki ataylab `v_allow_risky_trigger := true`.
--   ⚠️ Bu tekshiruv HAR QANDAY DDL DAN OLDIN turadi — bazada bir belgi ham
--   o'zgarmaydi. Trigger funksiyalarining TO'LIQ tanasi RUN jurnalida
--   NOTICE bilan chop etiladi (qo'lda dump qilish shart emas).
--
--   "public.tasks da UNIQUE indeks(lar) bor va ularning HAMMA kalit ustunlari
--    shablonga nusxalanadi: ..."
--   Sabab: shablon mavjud qatorning nusxasi — bunday indeks 23505 berardi.
--   Yechim xato matnida yozilgan (indeksni QISMAN qilish). Bu tekshiruv HAR
--   QANDAY DDL DAN OLDIN turadi, ya'ni bazada bir belgi ham o'zgarmaydi.
--
-- ── RUN'DAN KEYIN — MIJOZ TOMONIDA (boshqa agent) ──────────────────────────
--   3-bo'lim (materializatsiya, LAZY): project_cycles ga (project_id, cycle_no)
--     bilan INSERT → 23505 = boshqa admin ulgurdi → JIM chiqish.
--   4-bo'lim: 🔴 tasksAcceptRow — YAGONA choke-point, shablon tasksCache ga
--     TUSHMAYDI. So'rovda .eq('is_template', false) YOZILMAYDI (ustun yo'q
--     bazada 42703 butun ilovani o'ldirardi); mijozda r.is_template === true
--     tekshiruvi — ustun yo'q bo'lsa undefined bo'lib hamma qator o'tadi
--     (AYNAN eski xatti-harakat).
--   5–6-bo'lim: shablon detali (template_history) va kanban sikl filtri
--     (tasks.cycle_id bo'yicha).
--
-- ============================================================================
-- QAYTARISH (kerak bo'lsa)
--   ⚠️ TARTIB MUHIM: avval tasks dagi havolalar, keyin jadvallar.
--   ⚠️ 🔴 Bu MIGRATSIYANI QAYTARMAYDI — yaratilgan SHABLON qatorlari
--      public.tasks da QOLADI (is_template ustuni o'chgach ular oddiy
--      vazifadek ko'rinadi). Shablonlarni ham tozalash kerak bo'lsa AVVAL:
--        DELETE FROM public.tasks WHERE is_template = true;
--      (mavjud bosqichlar bunga TUSHMAYDI — ularning is_template si false.)
--
--   DELETE FROM public.tasks WHERE is_template = true;
--   ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS tasks_template_flags_chk;
--   ALTER TABLE public.tasks DROP COLUMN IF EXISTS template_id;
--   ALTER TABLE public.tasks DROP COLUMN IF EXISTS cycle_id;
--   ALTER TABLE public.tasks DROP COLUMN IF EXISTS is_template;
--   DROP TABLE IF EXISTS public.template_history;
--   DROP TABLE IF EXISTS public.project_cycles;
--   DROP FUNCTION IF EXISTS public.can_edit_project_cycles(uuid, uuid);
--   (FK va indekslar ustun/jadval bilan birga o'chadi)
-- ============================================================================
