-- ============================================================================
-- TASKFIX_8ISH.sql — boy matnli tavsif + IZOH AUDITI + "bajardi" ustunlari
--                    + takrorda ma'lumot ko'chirish + eski reassign migratsiyasi
-- ⚠️ KAM TRAFIK VAQTIDA RUN — public.tasks ga ustun QO'SHILADI va 5b-bo'limda
--    UPDATE qilinadi (ACCESS EXCLUSIVE qulf), task_comments ga TRIGGER qo'yiladi.
-- ============================================================================
-- NIMA QILADI (7 bo'lak — 6 tasi ADDITIVE, 1 tasi MA'LUMOT MIGRATSIYASI)
--
--   1) public.tasks.description_html text
--        Vazifa tavsifining FORMAT bilan saqlangan nusxasi (rich text).
--
--   1b) public.tasks.recur_copy_data boolean NOT NULL DEFAULT false
--        Takrorlanuvchi vazifa: keyingi nusxaga oldingi vazifaning IZOHLARI
--        va FAYLLARI ko'chirilsinmi. Sukut false = AYNAN hozirgi xatti-harakat.
--        🔴 Ustun KERAK, chunki nusxa KEYINROQ (vazifa bajarilganda) yaratiladi
--        va tanlov vazifaning O'ZIDA saqlanishi shart.
--
--   5b) 🔴 MIGRATSIYA — eski "reassign" qilingan vazifalar (YAGONA yozuvchi
--        bo'lak: public.tasks ga UPDATE). `assigned_to = acceptor_id` bo'lgan
--        topshirilgan/tugagan vazifalar asl bajaruvchiga (`submitter_id`)
--        qaytariladi. ZAXIRA: public.tasks_reassign_backup_8ish.
--        ⚙️ Sozlama: `v_include_completed` (fayl boshida, BEGIN; dan keyin).
--
--   2) public.task_comment_history  ← 🔴 ASOSIY BO'LAK
--        Izoh auditi: izoh yozilsa / tahrirlansa / O'CHIRILSA — matni, muallifi,
--        kim o'zgartirgani va qachoni TARIXDA QOLADI. Yozuv FAQAT trigger
--        orqali (mijoz tarixga yoza ham, o'chira ham olmaydi).
--        ↳ 2.0b) author_id / author_name — 🔴 IZOHNI KIM YOZGAN (2026-08-26).
--          Avval faqat `actor_*` (= amalni BAJARGAN odam) bor edi; o'chirilgan
--          izohning MUALLIFI hech qayerda saqlanmasdi. Asilbek talabi:
--          "nima yozilgan, KIM YOZGAN, kim o'chirdi, qachon" — to'rttasi ham.
--
--   3) public.task_comments.edited_at timestamptz
--        Izoh tahrirlangan vaqt (ilovada izoh tahriri qo'shiladi).
--        + kerak bo'lsa `task_cmt_update_own` UPDATE policy'si.
--
--   4) public.tasks.bajardi_user_id / bajardi_at
--        "Kim va qachon bajardi" — TASKFIX_V8.sql dagi bilan AYNAN bir xil,
--        ikkalasini ham ishga tushirish xavfsiz (IF NOT EXISTS).
--
--   4b) 🔴 RLS: qabul qiluvchi topshirilgan vazifani KO'RSIN (2026-08-26)
--        `tasks` ning mavjud SELECT policy'lari o'qiladi; ularda `acceptor_id`
--        BO'LMASA yangi ADDITIVE PERMISSIVE `tasks_select_acceptor` qo'shiladi.
--        Mavjud policy'larga TEGILMAYDI (nom boshqa → qayta RUN xavfsiz).
--        ⚠️ DEPLOY BLOKERI: mijozda "Bajarildi" endi vazifani qabul qiluvchiga
--        KO'CHIRMAYDI (reassign olib tashlandi) — u vazifani faqat
--        `acceptor_id` orqali ko'radi. Policy'da bu ustun bo'lmasa qabul
--        qiluvchining ro'yxati JIMGINA bo'sh bo'lardi (xato ham chiqmasdi).
--
-- ----------------------------------------------------------------------------
-- NEGA SHUNDAY QURILGAN
--
-- 🔴 `tasks.description` USTUNIGA TEGILMAYDI — u TOZA MATN bo'lib qoladi.
--    Sabab: Telegram bot (tg-send / tg-webhook), n8n va send-email Edge
--    Function manbalari repoda YO'Q va ular `tasks.description` ni to'g'ridan
--    o'qiydi. U yerga HTML yozilsa xodim botda xom `<b>`, `<span style=…>`
--    teglarini ko'rardi. Shuning uchun ilova IKKALASINI birga yozadi:
--      description       → toza matn (qidiruv, Telegram, email, eksport)
--      description_html  → format bilan (faqat ilova ichida ko'rsatiladi)
--    Mijoz `description_html` bo'lsa uni, bo'lmasa eski `description` ni
--    chizadi — ya'ni eski vazifalar avvalgidek ko'rinadi.
--
-- 🔴 XSS — SANITIZATSIYA MIJOZDA. Bu ustunga CHECK QO'YILMAGAN (HTML uzunligi
--    ham, mazmuni ham cheklanmaydi): Postgres HTML'ni tahlil qila olmaydi va
--    yarim-cho'loq regex CHECK yolg'on xotirjamlik berardi. Qoida: ilova
--    `description_html` ni ekranga chiqarishdan OLDIN oq ro'yxat bilan
--    tozalaydi (ruxsat: b/i/u/s, br, p, div, span[style: color|background|
--    font-size|font-family|font-weight|font-style|text-decoration], ul/ol/li,
--    a[href: http(s)/mailto]) — `<script>`, `on*=` atributlari, `javascript:`
--    va `data:` URL'lari OLIB TASHLANADI. Yozishda ham, o'qishda ham
--    (bazadagi eski qator ishonchsiz manba deb qaraladi).
--
-- 🔴 AUDIT JADVALIDA BIRORTA HAM FOREIGN KEY YO'Q — ATAYLAB.
--    (a) `comment_id` ga FK qo'yilsa, izoh o'chganda CASCADE/RESTRICT bilan
--        tarix qatori ham o'chib ketardi yoki izohni umuman o'chirib
--        bo'lmasdi — modulning butun ma'nosi ("o'chsa ham yo'qolmasin")
--        yo'qolardi.
--    (b) `task_id` / `workspace_id` ga FK qo'yilsa: vazifa o'chirilganda
--        CASCADE avval `task_comments` qatorlarini o'chiradi → bizning AFTER
--        DELETE trigger'imiz o'sha lahzada `task_id` ga havola qiluvchi YANGI
--        qator yozmoqchi bo'ladi, lekin ota qator allaqachon o'chirilgan →
--        FK buzilishi. Ya'ni FK aynan eng kerak paytda audit yozuvini
--        yiqitardi.
--    Shuning uchun bu jadval hech kimga bog'liq emas: qiymatlar NUSXA sifatida
--    saqlanadi (`actor_name` ham — profil keyin o'zgarsa/o'chsa tarix o'qilishi
--    kerak). Bu — "yo'qolmasin" talabining texnik kafolati.
--    ⚠️ Oqibati: vazifa/workspace o'chsa audit qatorlari "yetim" bo'lib qoladi.
--       Bu ataylab; kerak bo'lsa qo'lda tozalanadi (skript oxiridagi izohga q.).
--
-- 🔴 YOZUV FAQAT TRIGGER ORQALI. `task_comment_history` da INSERT/UPDATE/DELETE
--    policy UMUMAN YO'Q — mijoz PostgREST orqali tarixga yoza ham, uni
--    o'zgartira ham, o'chira ham olmaydi. Yagona yo'l — SECURITY DEFINER
--    trigger funksiyasi (RLS'ni chetlab o'tadi).
--
-- 🔴 TRIGGER NOMI `zz_task_cmt_audit_trg` — `zz_` prefiksi ATAYLAB.
--    Postgres bir hodisadagi triggerlarni NOM bo'yicha alifbo tartibida
--    ishlatadi; audit MAVJUD triggerlardan KEYIN ishlashi kerak
--    (TASKFIX_EMAIL_SYNC.sql dagi `zz_tf_auth_email_to_profile` saboqi).
--
-- 🔴 TRIGGER ASOSIY AMALNI HECH QACHON YIQITMAYDI: butun tanasi
--    `EXCEPTION WHEN OTHERS THEN RAISE WARNING …` ichida. Audit yozuvi
--    yiqilsa (masalan jadval qo'lda o'chirilgan bo'lsa) odam izoh yoza
--    olmay qolmaydi — faqat log'ga ogohlantirish tushadi.
--
-- 🔴 UPDATE'da faqat MATN haqiqatan o'zgarganda yoziladi (`IS DISTINCT FROM`).
--    Aks holda har `edited_at`/`updated_at` teginishi tarixni shishirardi.
--
-- 🔴 RLS policy ichida `workspace_members` inline subquery YOZILMAYDI
--    (42P17 rekursiya, CLAUDE.md 8-qoida) — faqat `is_ws_member()` /
--    `is_ws_manager()`.
--
-- 🔴 `task_id` va `comment_id` TIPLARI QATTIQ YOZILMAYDI — `pg_attribute` dan
--    `public.tasks.id` va `public.task_comments.id` dan DINAMIK olinadi
--    (TASKFIX_VIEWS.sql / TASKFIX_HISTORY.sql naqshi). Sabab: repoda 1–37
--    migratsiyalar YO'Q, id bigint ham, uuid ham bo'lishi mumkin.
--
-- ESLATMA: TEXT + CHECK (ENUM emas — 30/32-migratsiyalardagi saboq).
--
-- ----------------------------------------------------------------------------
-- ADDITIVE + IDEMPOTENT
--   Mavjud jadval / ustun / policy / trigger'ga TEGMAYDI. Qayta RUN xavfsiz —
--   hamma narsa `IF NOT EXISTS` yoki "avval tekshir, keyin yarat" bilan.
--   Yagona istisno: `task_comments` da UPDATE policy'si UMUMAN bo'lmasa yangi
--   `task_cmt_update_own` qo'shiladi (mavjud policy bo'lsa TEGILMAYDI, faqat
--   NOTICE beriladi).
--
-- RUN TARTIBI
--   1) 39_employee_details.sql   (is_ws_member() / is_ws_manager() shu yerda)
--   2) TASKFIX_8ISH.sql          ← shu fayl
--   Boshqa TASKFIX_*.sql fayllariga bog'liq emas, istalgan vaqtda ishlaydi.
--
-- ⚠️ KAM TRAFIK VAQTIDA RUN QILING
--   `CREATE TRIGGER ON public.task_comments` va `CREATE POLICY` — ikkalasi ham
--   `task_comments` ga ACCESS EXCLUSIVE qulf oladi. `ALTER TABLE tasks ADD
--   COLUMN` (NULL, DEFAULT'siz) — metama'lumot amali, tez, lekin u ham qisqa
--   muddatga `tasks` ni qulflaydi.
--   🔴 4b-bo'limdagi `CREATE POLICY ... ON public.tasks` ham `tasks` ga
--   ACCESS EXCLUSIVE qulf oladi — eng band jadval. Kechqurun / dam olish
--   kunida ishga tushiring; qulf qisqa (metama'lumot), lekin uzoq davom
--   etayotgan SELECT tugagunicha kutadi va yangi so'rovlar navbatga turadi.
--
-- BUSIZ ILOVA TO'LIQ ISHLAYDI
--   Mijoz ustun/jadval yo'qligini aniqlaydi va shunchaki UI'ni chizmaydi:
--   tavsif oddiy matn maydoni bo'lib qoladi, izoh tarixi bo'limi ko'rinmaydi,
--   "bajarildi sana" ustuni bo'sh. Hech narsa yiqilmaydi.
--   ⚠️ YAGONA ISTISNO — 4b: agar `tasks` SELECT policy'sida `acceptor_id`
--   bo'lmasa, RUN'gacha qabul qiluvchi TOPSHIRILGAN vazifani ko'rmaydi.
--   Bu bo'lim aynan shuning uchun bor.
--
-- 🔴 Bu faylda index.html GA HECH QANDAY O'ZGARISH YO'Q — mijoz tomoni alohida.
-- ============================================================================

BEGIN;

-- ════════════════════════════════════════════════════════════════════════════
-- ⚙️ SOZLAMA — RUN'DAN OLDIN O'QING (7-bo'lim: eski reassign migratsiyasi)
-- ════════════════════════════════════════════════════════════════════════════
--  v_include_completed   (SUKUT: true)
--
--  🔴 NIMA MIGRATSIYA QILINADI: 2026-08-26 gacha `changeStatus` vazifani
--     topshirishda QABUL QILUVCHIGA ko'chirardi (`assigned_to = acceptor_id`),
--     asl bajaruvchi esa `submitter_id` da qolardi. Reassign OLIB TASHLANDI,
--     lekin BAZADAGI eski qatorlar hamon qabul qiluvchida turibdi — ro'yxatlar
--     va hisobotlar yangi model bilan NOMUVOFIQ. 7-bo'lim ularni qaytaradi.
--
--  ▸ 'qabul_kutilyapti' — DOIM migratsiya qilinadi (sozlamaga bog'liq emas).
--    Bular FAOL vazifalar: hozir kimningdir ro'yxatida noto'g'ri turibdi,
--    eng muhimi ham shu.
--  ▸ 'completed' — v_include_completed bilan boshqariladi.
--      true  = TARIX ham to'g'rilanadi. "Kim bajardi" bo'yicha hisobot va
--              xodim statistikasi to'g'ri bo'ladi, LEKIN o'tmishdagi SONLAR
--              o'zgaradi (kimningdir "bajarilgan" soni kamayadi/ko'payadi).
--      false = tugagan vazifalar O'Z HOLICHA qoladi (tarix "muzlatiladi"),
--              faqat faol vazifalar to'g'rilanadi.
--
--  🔴 BOSHQA STATUSLARGA UMUMAN TEGILMAYDI ('new' / 'in_progress' / boshqa) —
--     sabab 7-bo'lim izohida (qo'lda qayta biriktirish xavfi).
-- ════════════════════════════════════════════════════════════════════════════
DROP TABLE IF EXISTS pg_temp.t8_cfg;
CREATE TEMP TABLE pg_temp.t8_cfg (k text PRIMARY KEY, v boolean, izoh text) ON COMMIT DROP;

DO $cfg$
DECLARE
  -- 🔴🔴 KERAK BO'LSA FAQAT SHU QATORNI O'ZGARTIRING (boshqa joyda emas).
  v_include_completed boolean := true;
BEGIN
  INSERT INTO pg_temp.t8_cfg VALUES
    ('include_completed', v_include_completed,
     'true = "completed" vazifalar ham migratsiya qilinadi (tarix to''g''rilanadi, o''tmishdagi sonlar o''zgaradi)');

  IF v_include_completed THEN
    RAISE NOTICE '⚙️ v_include_completed = TRUE — "completed" vazifalar HAM migratsiya qilinadi (tarixdagi sonlar o''zgarishi mumkin).';
  ELSE
    RAISE NOTICE '⚙️ v_include_completed = FALSE — faqat "qabul_kutilyapti" migratsiya qilinadi, tugagan vazifalar tegilmaydi.';
  END IF;
END $cfg$;

-- ── 0) OLDINDAN TEKSHIRUV + "oldingi holat" fotosurati ──────────────────────
-- Qayta RUN'da "nima allaqachon bor edi" ni aytish uchun holatni DDL'DAN OLDIN
-- yozib olamiz (DO bloklari o'zgaruvchi almashmaydi — vaqtinchalik jadval).
DROP TABLE IF EXISTS _t8_before;
CREATE TEMP TABLE _t8_before (k text PRIMARY KEY, v boolean NOT NULL) ON COMMIT DROP;

DO $$
DECLARE
  v_task_type text;
  v_cmt_type  text;
  v_ct_task   text;
  v_miss      text := '';
BEGIN
  -- 0.a) Asosiy jadvallar
  IF to_regclass('public.tasks') IS NULL THEN
    RAISE EXCEPTION 'public.tasks topilmadi — noto''g''ri baza?';
  END IF;
  IF to_regclass('public.task_comments') IS NULL THEN
    RAISE EXCEPTION 'public.task_comments topilmadi — izoh auditi qurilmaydi. To''xtatildi.';
  END IF;
  IF to_regclass('public.workspaces') IS NULL THEN
    RAISE EXCEPTION 'public.workspaces topilmadi — noto''g''ri baza?';
  END IF;
  IF to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION 'auth.users topilmadi — bu Supabase bazasi emasmi?';
  END IF;

  -- 0.b) RLS yordamchilari — inline subquery YOZILMAYDI (8-qoida)
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='is_ws_member') THEN
    RAISE EXCEPTION 'is_ws_member() topilmadi. Avval 39_employee_details.sql ni ishga tushiring.';
  END IF;

  -- 0.c) auth.uid() — trigger "kim qildi" ni shundan oladi
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='auth' AND p.proname='uid') THEN
    RAISE EXCEPTION 'auth.uid() topilmadi — trigger "kim o''zgartirdi" ni aniqlay olmasdi. To''xtatildi.';
  END IF;

  -- 0.d) 🔴 task_comments da trigger tayanadigan ustunlar BORmi?
  --      (mijoz: insert({workspace_id, task_id, author_id, comment_text}))
  --      Yo'q bo'lsa audit qatori bo'sh/noto'g'ri yozilardi — jimgina emas,
  --      DARROV to'xtaymiz.
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='task_comments' AND column_name='id') THEN
    v_miss := v_miss || 'id, ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='task_comments' AND column_name='workspace_id') THEN
    v_miss := v_miss || 'workspace_id, ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='task_comments' AND column_name='task_id') THEN
    v_miss := v_miss || 'task_id, ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='task_comments' AND column_name='author_id') THEN
    v_miss := v_miss || 'author_id, ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='task_comments' AND column_name='comment_text') THEN
    v_miss := v_miss || 'comment_text, ';
  END IF;
  IF v_miss <> '' THEN
    RAISE EXCEPTION 'public.task_comments da kutilgan ustun(lar) yo''q: % — audit trigger''i shularga tayanadi. To''xtatildi (hech narsa o''zgartirilmadi).', rtrim(v_miss, ', ');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name='workspace_id') THEN
    RAISE EXCEPTION 'public.tasks.workspace_id ustuni yo''q — zaxira workspace qidiruvi ishlamasdi. To''xtatildi.';
  END IF;

  -- 0.e) Tiplar (dinamik)
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_task_type
    FROM pg_attribute a
   WHERE a.attrelid = 'public.tasks'::regclass
     AND a.attname = 'id' AND a.attnum > 0 AND NOT a.attisdropped;
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_cmt_type
    FROM pg_attribute a
   WHERE a.attrelid = 'public.task_comments'::regclass
     AND a.attname = 'id' AND a.attnum > 0 AND NOT a.attisdropped;
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_ct_task
    FROM pg_attribute a
   WHERE a.attrelid = 'public.task_comments'::regclass
     AND a.attname = 'task_id' AND a.attnum > 0 AND NOT a.attisdropped;

  IF v_task_type IS NULL THEN RAISE EXCEPTION 'public.tasks.id ustuni topilmadi'; END IF;
  IF v_cmt_type  IS NULL THEN RAISE EXCEPTION 'public.task_comments.id ustuni topilmadi'; END IF;

  -- task_comments.task_id AYNAN shu ustunga yoziladi — moslikni tekshiramiz.
  -- Butun sonlar oilasi ichida (int2/int4/int8) implicit cast bor, mos deb
  -- hisoblanadi; uuid ↔ bigint kabi tubdan boshqa bo'lsa — to'xtaymiz.
  IF v_ct_task IS NOT NULL
     AND v_ct_task <> v_task_type
     AND NOT (v_ct_task IN ('smallint','integer','bigint')
              AND v_task_type IN ('smallint','integer','bigint')) THEN
    RAISE EXCEPTION 'Tip nomuvofiqligi: tasks.id = "%", task_comments.task_id = "%" — audit ustuni qaysi biriga moslanishi noaniq. To''xtatildi.', v_task_type, v_ct_task;
  END IF;

  RAISE NOTICE 'ℹ️ Tiplar: tasks.id = %, task_comments.id = % (dinamik olindi)', v_task_type, v_cmt_type;

  -- 0.f) Ism manbai (actor_name) — yo'q bo'lsa fatal EMAS, lekin OCHIQ aytiladi
  IF to_regclass('public.profiles') IS NULL THEN
    RAISE NOTICE '⚠️ public.profiles topilmadi — audit qatorlarida actor_name BO''SH qoladi (faqat actor_id yoziladi).';
  ELSE
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='profiles' AND column_name='full_name') THEN
      RAISE NOTICE '⚠️ profiles.full_name yo''q — actor_name email''dan olinadi.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='profiles' AND column_name='email') THEN
      RAISE NOTICE '⚠️ profiles.email yo''q — actor_name faqat full_name''dan olinadi (TASKFIX_EMAIL_SYNC.sql ga q.).';
    END IF;
  END IF;

  -- 0.g) is_ws_manager() — faqat task_comments UPDATE policy'si uchun kerak
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='is_ws_manager') THEN
    RAISE NOTICE '⚠️ is_ws_manager() topilmadi — izoh tahriri uchun UPDATE policy YARATILMAYDI (3-bo''limga q.).';
  END IF;

  -- 0.h) "Oldin nima bor edi" fotosurati (yakuniy XULOSA uchun)
  INSERT INTO _t8_before(k, v) VALUES
    ('tasks.description_html', EXISTS (SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='tasks' AND column_name='description_html')),
    -- 1b — takrorda ma'lumotlarni ko'chirish bayrog'i
    ('tasks.recur_copy_data', EXISTS (SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='tasks' AND column_name='recur_copy_data')),
    -- 7 — eski reassign qilingan vazifalar migratsiyasi (zaxira jadvali)
    ('table.tasks_reassign_backup_8ish', to_regclass('public.tasks_reassign_backup_8ish') IS NOT NULL),
    ('tasks.bajardi_user_id',  EXISTS (SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='tasks' AND column_name='bajardi_user_id')),
    ('tasks.bajardi_at',       EXISTS (SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='tasks' AND column_name='bajardi_at')),
    ('task_comments.edited_at', EXISTS (SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='task_comments' AND column_name='edited_at')),
    ('table.task_comment_history', to_regclass('public.task_comment_history') IS NOT NULL),
    ('trigger.zz_task_cmt_audit_trg', EXISTS (SELECT 1 FROM pg_trigger tg
        WHERE tg.tgrelid = 'public.task_comments'::regclass
          AND tg.tgname = 'zz_task_cmt_audit_trg' AND NOT tg.tgisinternal)),
    ('policy.task_comments_update', EXISTS (SELECT 1 FROM pg_policies
        WHERE schemaname='public' AND tablename='task_comments' AND cmd IN ('UPDATE','ALL'))),
    -- 2.0b — izoh MUALLIFI (jadval avvalgi RUN'da ustunsiz yaratilgan bo'lishi mumkin)
    ('cmt_history.author_id', to_regclass('public.task_comment_history') IS NOT NULL
        AND EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='task_comment_history' AND column_name='author_id')),
    -- 4b — qabul qiluvchi RLS policy'si
    ('policy.tasks_select_acceptor', EXISTS (SELECT 1 FROM pg_policies
        WHERE schemaname='public' AND tablename='tasks' AND policyname='tasks_select_acceptor'));

  RAISE NOTICE '── Oldingi holat ──';
  RAISE NOTICE 'tasks.description_html        : %', (SELECT CASE WHEN v THEN 'BOR' ELSE 'yo''q' END FROM _t8_before WHERE k='tasks.description_html');
  RAISE NOTICE 'tasks.recur_copy_data         : %', (SELECT CASE WHEN v THEN 'BOR' ELSE 'yo''q' END FROM _t8_before WHERE k='tasks.recur_copy_data');
  RAISE NOTICE 'reassign zaxira jadvali       : %', (SELECT CASE WHEN v THEN 'BOR' ELSE 'yo''q' END FROM _t8_before WHERE k='table.tasks_reassign_backup_8ish');
  RAISE NOTICE 'tasks.bajardi_user_id/at      : % / %',
    (SELECT CASE WHEN v THEN 'BOR' ELSE 'yo''q' END FROM _t8_before WHERE k='tasks.bajardi_user_id'),
    (SELECT CASE WHEN v THEN 'BOR' ELSE 'yo''q' END FROM _t8_before WHERE k='tasks.bajardi_at');
  RAISE NOTICE 'task_comments.edited_at       : %', (SELECT CASE WHEN v THEN 'BOR' ELSE 'yo''q' END FROM _t8_before WHERE k='task_comments.edited_at');
  RAISE NOTICE 'task_comment_history jadvali  : %', (SELECT CASE WHEN v THEN 'BOR' ELSE 'yo''q' END FROM _t8_before WHERE k='table.task_comment_history');
  RAISE NOTICE 'zz_task_cmt_audit_trg trigger : %', (SELECT CASE WHEN v THEN 'BOR' ELSE 'yo''q' END FROM _t8_before WHERE k='trigger.zz_task_cmt_audit_trg');
  RAISE NOTICE 'task_comments UPDATE policy   : %', (SELECT CASE WHEN v THEN 'BOR' ELSE 'yo''q' END FROM _t8_before WHERE k='policy.task_comments_update');
  RAISE NOTICE 'cmt_history.author_id         : %', (SELECT CASE WHEN v THEN 'BOR' ELSE 'yo''q' END FROM _t8_before WHERE k='cmt_history.author_id');
  RAISE NOTICE 'tasks_select_acceptor policy  : %', (SELECT CASE WHEN v THEN 'BOR' ELSE 'yo''q' END FROM _t8_before WHERE k='policy.tasks_select_acceptor');
  RAISE NOTICE '───────────────────';
END $$;


-- ============================================================================
-- 1) BOY MATNLI TAVSIF — public.tasks.description_html
-- ============================================================================
-- 🔴 `description` ustuniga TEGILMAYDI (yuqoridagi sarlavha izohiga q.):
--    u toza matn bo'lib qoladi — Telegram bot / n8n / send-email o'shani
--    o'qiydi. Ilova ikkalasini birga yozadi.
-- CHECK ATAYLAB YO'Q — XSS sanitizatsiyasi MIJOZDA (oq ro'yxat), Postgres
--    HTML'ni tahlil qila olmaydi.
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS description_html text;

COMMENT ON COLUMN public.tasks.description_html IS
  'Vazifa tavsifining FORMAT bilan saqlangan nusxasi (rich text HTML). 🔴 tasks.description TOZA MATN bo''lib qoladi — Telegram bot / n8n / send-email o''shani o''qiydi, ikkalasi BIRGA yoziladi. Bo''sh bo''lsa mijoz eski description ni chizadi. ⚠️ XSS: HTML mijozda oq ro''yxat bilan tozalanadi (script/on*=/javascript:/data: yo''q) — bazada CHECK YO''Q.';


-- ============================================================================
-- 1b) TAKRORDA MA'LUMOTLARNI KO'CHIRISH — public.tasks.recur_copy_data
-- ============================================================================
-- Takrorlanuvchi vazifa yaratilganda "ma'lumotlar ko'chirilsinmi?" belgisi.
-- Belgilansa: vazifa bajarilib KEYINGI nusxa yaratilganda oldingi vazifaning
-- IZOHLARI (task_comments) va BIRIKTIRILGAN FAYLLARI (task_attachments)
-- yangi nusxaga ko'chiriladi. Belgilanmasa — bo'sh, YANGI vazifa (hozirgidek).
--
-- 🔴 NEGA USTUN KERAK (bayroq mijozda "esda" turolmaydi): nusxa KEYINROQ —
--    vazifa BAJARILGANDA — yaratiladi (`maybeRecurTask`), ya'ni yaratish
--    oynasi allaqachon yopilgan bo'ladi. Tanlov vazifaning O'ZIDA saqlanishi
--    shart va u zanjir bo'ylab har yangi nusxaga ko'chadi (recur_* naqshi).
--
-- 🔴 NOT NULL DEFAULT false — mavjud MILLIONLAB qatorda AYNAN hozirgi
--    xatti-harakat (ko'chirmaslik). Postgres 11+ da bu ustun qo'shish
--    jadvalni QAYTA YOZMAYDI (default katalogda saqlanadi), ya'ni tez.
--    ⚠️ Baribir ACCESS EXCLUSIVE qulf oladi — kam trafik vaqtida RUN.
--
-- ⚠️ FAYL — mijoz Storage'da NUSXA oladi (`copy`), DB qatori eski yo'lga
--    havola QILMAYDI: aks holda ikki vazifa bitta faylga ko'rsatib, birini
--    o'chirgan odam ikkinchisini ham o'chirib qo'yardi. Yangi Storage policy
--    KERAK EMAS — mavjud `attachments` bucket va mavjud `<ws>/<task>/…` yo'li.
-- ⚠️ IZOH MUALLIFI saqlanadi (`author_id`). Agar task_comments INSERT
--    policy'si `author_id = auth.uid()` ni talab qilsa, BEGONA muallifli
--    izohlar ko'chmaydi — mijoz buni JIMGINA yutmaydi, "N ta izoh ko'chmadi"
--    deb aytadi (bu bo'lim policy'ga TEGMAYDI, additive qoidasi).
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS recur_copy_data boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.tasks.recur_copy_data IS
  'Takrorlanuvchi vazifa: keyingi nusxaga OLDINGI vazifaning izohlari (task_comments) va fayllari (task_attachments) ko''chirilsinmi. false = bo''sh, yangi vazifa (sukut, mavjud xatti-harakat). Bayroq zanjir bo''ylab har yangi nusxaga ko''chadi. Fayl Storage''da NUSXA olinadi — qatorlar eski yo''lga havola qilmaydi.';


-- ============================================================================
-- 2) IZOH AUDITI — public.task_comment_history   🔴 ASOSIY BO'LAK
-- ============================================================================
-- Talab: izoh o'chsa yoki o'zgarsa TARIXDA QOLSIN — nima yozilgan, kim yozgan,
-- kim o'chirdi/tahrirladi, qachon.
--
-- 🔴 BIRORTA FK YO'Q (sarlavhadagi (a)/(b) sabablariga q.) — qiymatlar NUSXA.
DO $$
DECLARE
  v_task_type text;
  v_cmt_type  text;
BEGIN
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_task_type
    FROM pg_attribute a
   WHERE a.attrelid = 'public.tasks'::regclass
     AND a.attname = 'id' AND a.attnum > 0 AND NOT a.attisdropped;

  SELECT format_type(a.atttypid, a.atttypmod) INTO v_cmt_type
    FROM pg_attribute a
   WHERE a.attrelid = 'public.task_comments'::regclass
     AND a.attname = 'id' AND a.attnum > 0 AND NOT a.attisdropped;

  EXECUTE format($f$
    CREATE TABLE IF NOT EXISTS public.task_comment_history (
      id           bigserial   PRIMARY KEY,
      workspace_id uuid        NOT NULL,
      task_id      %s,
      comment_id   %s,
      action       text        NOT NULL,
      old_text     text,
      new_text     text,
      actor_id     uuid,
      actor_name   text,
      at           timestamptz NOT NULL DEFAULT now()
    )
  $f$, v_task_type, v_cmt_type);

  RAISE NOTICE 'task_comment_history: task_id = %, comment_id = % (dinamik)', v_task_type, v_cmt_type;
END $$;

-- CHECK — TEXT + CHECK (ENUM emas). Jadval avvaldan mavjud bo'lsa
-- CREATE TABLE IF NOT EXISTS uni o'tkazib yuboradi, shuning uchun alohida.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'public.task_comment_history'::regclass
                    AND conname  = 'task_cmt_hist_action_chk') THEN
    ALTER TABLE public.task_comment_history
      ADD CONSTRAINT task_cmt_hist_action_chk
      CHECK (action IN ('created', 'edited', 'deleted'));
    RAISE NOTICE '✔ task_cmt_hist_action_chk qo''shildi';
  ELSE
    RAISE NOTICE 'ℹ️ task_cmt_hist_action_chk allaqachon bor';
  END IF;
END $$;

-- ── 2.0b) 🔴 IZOH MUALLIFI — author_id / author_name (2026-08-26, QA-T4) ────
-- Talab: "nima yozilgan, KIM YOZGAN, kim o'chirdi, qachon" — TO'RTTASI.
-- `actor_id`/`actor_name` — AMALNI BAJARGAN odam (o'chirgan/tahrirlagan).
-- Muallif esa BOSHQA odam bo'lishi mumkin (admin begonaning izohini o'chiradi)
-- va o'chirilgandan keyin uni tiklashning HECH QANDAY yo'li qolmasdi:
-- manba qator (`task_comments`) yo'q, `comment_id` ga FK ham yo'q (ataylab).
--
-- 🔴 ALOHIDA ALTER — `CREATE TABLE IF NOT EXISTS` jadval AVVALGI RUN'da
--    yaratilgan bo'lsa uni JIMGINA o'tkazib yuboradi, ya'ni yangi ustunlar
--    qo'shilmasdi. `ADD COLUMN IF NOT EXISTS` ikkala holatni ham qoplaydi.
-- ⚠️ Tip `uuid` QATTIQ yozilgan (task_id/comment_id dan farqli): `author_id`
--    manbasi — `auth.users.id`, u Supabase'da DOIM uuid.
-- ⚠️ Eski qatorlarda NULL bo'lib qoladi — backfill IMKONSIZ (o'sha lahzadagi
--    muallif faqat manba qatorda bor edi va u o'chgan bo'lishi mumkin).
--    Mijoz NULL da qatorni BARIBIR chizadi, muallif qismini o'tkazib yuboradi.
ALTER TABLE public.task_comment_history
  ADD COLUMN IF NOT EXISTS author_id uuid;
ALTER TABLE public.task_comment_history
  ADD COLUMN IF NOT EXISTS author_name text;

COMMENT ON COLUMN public.task_comment_history.author_id IS
  'Izohni YOZGAN odam (task_comments.author_id NUSXASI). 🔴 actor_id dan FARQLI: actor = amalni bajargan (o''chirgan/tahrirlagan), author = muallif. FK YO''Q — jadvalning umumiy qoidasi.';
COMMENT ON COLUMN public.task_comment_history.author_name IS
  'Muallifning o''sha lahzadagi ismi NUSXASI (full_name → email), actor_name bilan AYNAN bir xil ikki bosqichli yo''l bilan olinadi. Eski qatorlarda NULL (backfill imkonsiz).';

COMMENT ON TABLE public.task_comment_history IS
  'Izoh auditi: izoh yozilsa/tahrirlansa/O''CHIRILSA matni va muallifi TARIXDA QOLADI. Yozuv FAQAT zz_task_cmt_audit_trg (SECURITY DEFINER) orqali — INSERT/UPDATE/DELETE policy ATAYLAB YO''Q. 🔴 Birorta FK yo''q: FK bo''lsa izoh/vazifa o''chganda tarix ham o''chib ketardi (modulning ma''nosi shu bilan yo''qolardi).';
COMMENT ON COLUMN public.task_comment_history.workspace_id IS
  'Denormalizatsiya — RLS policy''si tasks/task_comments ga JOIN qilmasin (task_views / task_history naqshi).';
COMMENT ON COLUMN public.task_comment_history.comment_id IS
  'Manba izoh id''si. 🔴 FK YO''Q — izoh o''chganda tarix qatori CASCADE bilan o''chib ketmasligi uchun. Izoh o''chgach bu id bazada mavjud emas (kutilgan holat).';
COMMENT ON COLUMN public.task_comment_history.action IS
  'created | edited | deleted (TEXT + CHECK, ENUM emas).';
COMMENT ON COLUMN public.task_comment_history.actor_id IS
  'Amalni bajargan foydalanuvchi (auth.uid()). NULL bo''lishi mumkin: service_role / Edge Function / Telegram bot yo''li.';
COMMENT ON COLUMN public.task_comment_history.actor_name IS
  'O''sha lahzadagi ism NUSXASI (full_name → email). Profil keyin o''zgarsa yoki o''chsa ham tarix o''qilishi uchun saqlanadi.';

-- ── 2.1) INDEKSLAR ──────────────────────────────────────────────────────────
-- (task_id, at DESC) — vazifa detalidagi "izohlar tarixi" ro'yxati.
CREATE INDEX IF NOT EXISTS idx_task_cmt_hist_task
  ON public.task_comment_history (task_id, at DESC);
-- (comment_id) — bitta izohning butun hayoti (yozildi → tahrirlandi → o'chdi).
CREATE INDEX IF NOT EXISTS idx_task_cmt_hist_comment
  ON public.task_comment_history (comment_id);

-- ── 2.2) RLS ────────────────────────────────────────────────────────────────
-- KO'RISH: workspace a'zosi (izoh ham a'zolarga ochiq edi).
-- YOZISH : policy YO'Q → PostgREST orqali hech kim yoza/o'chira olmaydi.
-- ⚠️ FORCE ROW LEVEL SECURITY QO'YILMAYDI — qo'yilsa egaga ham RLS qo'llanib,
--    SECURITY DEFINER trigger ham yoza olmasdi (audit jimgina o'lardi).
ALTER TABLE public.task_comment_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "task_cmt_history_select" ON public.task_comment_history;
CREATE POLICY "task_cmt_history_select" ON public.task_comment_history
  AS PERMISSIVE FOR SELECT TO authenticated
  USING ( is_ws_member(workspace_id, (SELECT auth.uid())) );

-- 🔴 INSERT / UPDATE / DELETE policy ATAYLAB YO'Q. QO'SHMANG:
--    ular bo'lsa foydalanuvchi o'zi yozgan izohning tarixini o'chirib,
--    "yo'qolmasin" kafolatini buzardi. Yozuv faqat trigger orqali.

-- Grant qatlami (RLS ustiga ikkinchi qatlam)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.task_comment_history FROM authenticated';
    EXECUTE 'GRANT SELECT ON TABLE public.task_comment_history TO authenticated';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON TABLE public.task_comment_history FROM anon';
  END IF;
END $$;

-- ── 2.3) TRIGGER FUNKSIYASI — YAGONA YOZUV NUQTASI ──────────────────────────
-- SECURITY DEFINER: (a) RLS'dan qat'i nazar tarixga yozadi, (b) profiles'dan
-- ismni o'qiy oladi. search_path qat'iy o'rnatilgan (funksiya "o'g'irlanmasin").
CREATE OR REPLACE FUNCTION public.task_cmt_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $body$
DECLARE
  v_actor  uuid;
  v_name   text;
  v_author uuid;   -- 2.0b — izohni KIM YOZGAN
  v_aname  text;
BEGIN
  -- 🔴 BUTUN TANA HIMOYALANGAN: audit yiqilsa ham izoh yozish/o'chirish
  --    IShLAYVERADI (aks holda odam izoh yoza olmay qolardi).
  BEGIN
    -- 1) UPDATE: faqat MATN haqiqatan o'zgargan bo'lsa yoziladi.
    --    IS NOT DISTINCT FROM — NULL ↔ NULL ham "o'zgarmagan" deb qaraladi.
    --    Busiz har edited_at/updated_at teginishi tarixni shishirardi.
    IF TG_OP = 'UPDATE' AND NEW.comment_text IS NOT DISTINCT FROM OLD.comment_text THEN
      RETURN NULL;
    END IF;

    -- 2) Kim qildi. NULL bo'lishi MUMKIN va bu xato emas:
    --    service_role / Edge Function / Telegram bot yo'lida sessiya yo'q.
    BEGIN
      v_actor := auth.uid();
    EXCEPTION WHEN OTHERS THEN
      v_actor := NULL;
    END;

    -- 3) O'sha lahzadagi ism (NUSXA). Ikki bosqich ATAYLAB alohida:
    --    profiles.email ustuni bo'lmagan bazada ham full_name yo'li ishlasin.
    IF v_actor IS NOT NULL THEN
      BEGIN
        SELECT NULLIF(btrim(p.full_name), '') INTO v_name
          FROM public.profiles p WHERE p.id = v_actor;
      EXCEPTION WHEN OTHERS THEN
        v_name := NULL;
      END;
      IF v_name IS NULL THEN
        BEGIN
          SELECT NULLIF(btrim(p.email), '') INTO v_name
            FROM public.profiles p WHERE p.id = v_actor;
        EXCEPTION WHEN OTHERS THEN
          v_name := NULL;
        END;
      END IF;
    END IF;

    -- 3b) 🔴 IZOH MUALLIFI (2.0b). `COALESCE(NEW.author_id, OLD.author_id)`
    --     deb BITTA qatorda yozib bo'lmaydi: PL/pgSQL da tayinlanmagan
    --     record'ga murojaat XATO beradi ("record new is not assigned yet.
    --     The tuple structure of a not-yet-assigned record is indeterminate")
    --     — NEW DELETE'da, OLD esa INSERT'da tayinlanmagan. Shuning uchun
    --     UCHALA amal alohida shoxlanadi (tashqi EXCEPTION bu xatoni
    --     yutib, auditni JIMGINA o'chirib qo'yardi).
    IF TG_OP = 'DELETE' THEN
      v_author := OLD.author_id;
    ELSIF TG_OP = 'UPDATE' THEN
      -- Muallif almashtirilgan bo'lsa yangisi; NULL ga tushib qolmasin.
      v_author := COALESCE(NEW.author_id, OLD.author_id);
    ELSE   -- INSERT
      v_author := NEW.author_id;
    END IF;

    -- Ism — actor_name BILAN AYNAN BIR XIL ikki bosqichli yo'l
    -- (full_name → email). Muallif = amalni bajargan odam bo'lsa ikkinchi
    -- SELECT qilinmaydi (eng ko'p uchraydigan holat: o'zi yozib o'zi o'chirdi).
    IF v_author IS NOT NULL THEN
      IF v_author = v_actor THEN
        v_aname := v_name;
      ELSE
        BEGIN
          SELECT NULLIF(btrim(p.full_name), '') INTO v_aname
            FROM public.profiles p WHERE p.id = v_author;
        EXCEPTION WHEN OTHERS THEN
          v_aname := NULL;
        END;
        IF v_aname IS NULL THEN
          BEGIN
            SELECT NULLIF(btrim(p.email), '') INTO v_aname
              FROM public.profiles p WHERE p.id = v_author;
          EXCEPTION WHEN OTHERS THEN
            v_aname := NULL;
          END;
        END IF;
      END IF;
    END IF;

    -- 4) Yozuv. workspace_id NOT NULL — qator to'ldirilmagan bo'lsa
    --    (eski/tashqi yozuv) tasks dan olinadi. COALESCE lazy: ikkinchi
    --    argument faqat birinchisi NULL bo'lganda hisoblanadi.
    IF TG_OP = 'DELETE' THEN
      INSERT INTO public.task_comment_history
        (workspace_id, task_id, comment_id, action, old_text, new_text, actor_id, actor_name, author_id, author_name)
      VALUES (
        COALESCE(OLD.workspace_id, (SELECT t.workspace_id FROM public.tasks t WHERE t.id = OLD.task_id)),
        OLD.task_id, OLD.id, 'deleted', OLD.comment_text, NULL, v_actor, v_name, v_author, v_aname);

    ELSIF TG_OP = 'UPDATE' THEN
      INSERT INTO public.task_comment_history
        (workspace_id, task_id, comment_id, action, old_text, new_text, actor_id, actor_name, author_id, author_name)
      VALUES (
        COALESCE(NEW.workspace_id, (SELECT t.workspace_id FROM public.tasks t WHERE t.id = NEW.task_id)),
        NEW.task_id, NEW.id, 'edited', OLD.comment_text, NEW.comment_text, v_actor, v_name, v_author, v_aname);

    ELSE   -- INSERT
      INSERT INTO public.task_comment_history
        (workspace_id, task_id, comment_id, action, old_text, new_text, actor_id, actor_name, author_id, author_name)
      VALUES (
        COALESCE(NEW.workspace_id, (SELECT t.workspace_id FROM public.tasks t WHERE t.id = NEW.task_id)),
        NEW.task_id, NEW.id, 'created', NULL, NEW.comment_text, v_actor, v_name, v_author, v_aname);
    END IF;

  EXCEPTION WHEN OTHERS THEN
    -- 🔴 ASOSIY AMAL HECH QACHON YIQILMAYDI — faqat ogohlantirish.
    RAISE WARNING 'task_cmt_audit(%) yozilmadi: % (SQLSTATE %)', TG_OP, SQLERRM, SQLSTATE;
  END;

  -- AFTER trigger — qaytariladigan qiymat e'tiborga olinmaydi.
  RETURN NULL;
END;
$body$;

COMMENT ON FUNCTION public.task_cmt_audit() IS
  'zz_task_cmt_audit_trg uchun trigger funksiyasi: task_comments ustidagi INSERT/UPDATE/DELETE ni task_comment_history ga yozadi. SECURITY DEFINER — bu jadvalga yozishning YAGONA yo''li (yozuv policy''si yo''q). UPDATE faqat comment_text HAQIQATAN o''zgarganda yoziladi. actor_* = amalni BAJARGAN odam, author_* = izoh MUALLIFI (2026-08-26). Butun tanasi EXCEPTION bilan himoyalangan — audit yiqilsa ham izoh yozish/o''chirish ishlayveradi.';

-- Funksiya faqat trigger'dan chaqiriladi — hech kimga EXECUTE kerak emas.
REVOKE ALL ON FUNCTION public.task_cmt_audit() FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.task_cmt_audit() FROM anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.task_cmt_audit() FROM authenticated';
  END IF;
END $$;

-- ── 2.4) TRIGGER ────────────────────────────────────────────────────────────
-- 🔴 NOMI `zz_` bilan boshlanadi — mavjud triggerlardan KEYIN ishlasin
--    (Postgres bir hodisada triggerlarni NOM tartibida ishlatadi).
-- ⚠️ CREATE TRIGGER `task_comments` ga ACCESS EXCLUSIVE qulf oladi —
--    kam trafik vaqtida RUN qiling.
-- AFTER (BEFORE emas): asosiy amal muvaffaqiyatli bo'lgandan keyin yoziladi.
-- `UPDATE OF comment_text` ATAYLAB ishlatilmadi — har qanday UPDATE tutiladi
--    va matn o'zgarganini funksiyaning O'ZI hal qiladi (yagona qoida bitta
--    joyda tursin).
DROP TRIGGER IF EXISTS zz_task_cmt_audit_trg ON public.task_comments;
CREATE TRIGGER zz_task_cmt_audit_trg
  AFTER INSERT OR UPDATE OR DELETE ON public.task_comments
  FOR EACH ROW EXECUTE FUNCTION public.task_cmt_audit();


-- ============================================================================
-- 3) IZOH TAHRIRI — task_comments.edited_at + (kerak bo'lsa) UPDATE policy
-- ============================================================================
-- ⚠️ Ilovada hozir izohni TAHRIRLASH umuman yo'q — u qo'shiladi.
-- `edited_at` ni TRIGGER to'ldirmaydi: u AFTER trigger, NEW ga yoza olmaydi.
--    Mijoz o'zi yozadi: update({ comment_text, edited_at: new Date().toISOString() })
ALTER TABLE public.task_comments
  ADD COLUMN IF NOT EXISTS edited_at timestamptz;

COMMENT ON COLUMN public.task_comments.edited_at IS
  'Izoh oxirgi marta tahrirlangan vaqt. Mijoz yozadi (AFTER trigger NEW ga yoza olmaydi). NULL = hech qachon tahrirlanmagan. Tahrir TARIXI task_comment_history da.';

DO $$
DECLARE
  v_rls  boolean;
  v_pols text;
  v_mgr  boolean;
BEGIN
  SELECT c.relrowsecurity INTO v_rls
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname='public' AND c.relname='task_comments';

  SELECT string_agg(policyname || ' (' || cmd || ')', ', ') INTO v_pols
    FROM pg_policies
   WHERE schemaname='public' AND tablename='task_comments' AND cmd IN ('UPDATE','ALL');

  v_mgr := EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='public' AND p.proname='is_ws_manager');

  IF NOT COALESCE(v_rls, false) THEN
    RAISE NOTICE 'ℹ️ task_comments da RLS YOQILMAGAN — UPDATE baribir ochiq. Policy qo''shilmadi (mavjud sozlamaga tegilmaydi).';

  ELSIF v_pols IS NOT NULL THEN
    -- 🔴 MAVJUD POLICY'GA TEGILMAYDI (additive qoidasi) — faqat xabar.
    RAISE NOTICE 'ℹ️ task_comments da UPDATE amalini qamrovchi policy allaqachon bor: % — TEGILMADI. Izoh tahriri o''sha policy shartlariga bo''ysunadi.', v_pols;

  ELSIF NOT v_mgr THEN
    -- Jimgina o'tmaydi: sababni OCHIQ aytamiz.
    RAISE NOTICE '⚠️ task_comments da UPDATE policy YO''Q va is_ws_manager() ham topilmadi → policy YARATILMADI. Izoh tahriri RLS da to''siladi (mijoz "ruxsat yo''q" xatosini oladi). Avval 39_employee_details.sql ni ishga tushiring va bu faylni QAYTA RUN qiling.';

  ELSE
    -- Yangi ADDITIVE policy: muallif O'ZI yoki ws menejeri tahrirlaydi.
    -- ⚠️ workspace_members inline subquery YOZILMAYDI (42P17) — is_ws_manager().
    -- WITH CHECK ham AYNI shart: muallif izohni boshqa odamga "o'tkazib"
    -- yubora olmasin (author_id ni almashtirib qochib qolmasin).
    EXECUTE $p$
      CREATE POLICY "task_cmt_update_own" ON public.task_comments
        AS PERMISSIVE FOR UPDATE TO authenticated
        USING (
          author_id = (SELECT auth.uid())
          OR is_ws_manager(workspace_id, (SELECT auth.uid()))
        )
        WITH CHECK (
          author_id = (SELECT auth.uid())
          OR is_ws_manager(workspace_id, (SELECT auth.uid()))
        )
    $p$;
    RAISE NOTICE '✔ task_cmt_update_own policy''si qo''shildi (muallif yoki ws menejeri izohni tahrirlaydi).';
  END IF;

  -- Grant qatlami — RLS o'tsa ham UPDATE granti bo'lmasa tahrir ishlamaydi.
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated')
     AND NOT has_table_privilege('authenticated', 'public.task_comments', 'UPDATE') THEN
    RAISE NOTICE '⚠️ authenticated roli task_comments ga UPDATE granti YO''Q — izoh tahriri ishlamaydi. (Bu skript grantlarni o''zgartirmaydi — mavjud sozlamaga tegmaslik qoidasi.)';
  END IF;
END $$;


-- ============================================================================
-- 4) "BAJARDI" USTUNLARI — TASKFIX_V8.sql BILAN AYNAN BIR XIL
-- ============================================================================
-- Bu ikki ustun TASKFIX_V8.sql da ham bor, lekin u hali RUN qilinmagan.
-- Ikkalasini ham ishga tushirish XAVFSIZ: `ADD COLUMN IF NOT EXISTS` +
-- `CREATE INDEX IF NOT EXISTS` — qaysi biri birinchi ishlasa, ikkinchisi
-- jimgina o'tadi (ustun ta'rifi va indeks nomi ham AYNAN bir xil).
-- Kerak: "Bajarildi" ustunida vazifa QACHON bajarilgani ko'rinsin
-- (jadval/kanban ustunida ham, vazifa detalida ham).
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS bajardi_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS bajardi_at timestamptz;

COMMENT ON COLUMN public.tasks.bajardi_user_id IS 'Vazifani "Bajarildi" deb belgilagan foydalanuvchi (bajaruvchi)';
COMMENT ON COLUMN public.tasks.bajardi_at IS 'Vazifa "Bajarildi" deb belgilangan vaqt';

CREATE INDEX IF NOT EXISTS idx_tasks_bajardi_user ON public.tasks (bajardi_user_id);


-- ============================================================================
-- 4b) 🔴 RLS — QABUL QILUVCHI TOPSHIRILGAN VAZIFANI KO'RSIN
-- ============================================================================
-- NEGA KERAK (2026-08-26, QA-T3 — DEPLOY BLOKERI)
--   Mijozda "Bajarildi" oqimi o'zgardi: avval `changeStatus` topshirishda
--   `assigned_to = acceptor_id` deb REASSIGN qilardi, ya'ni vazifa qabul
--   qiluvchiga KO'CHIB o'tardi va har qanday `assigned_to`-asosli RLS
--   policy'si ostida ham unga ko'rinardi. Endi reassign YO'Q — vazifa
--   bajaruvchida qoladi, qabul qiluvchi uni FAQAT `acceptor_id` orqali
--   ko'radi.
--   ⚠️ Mijozdagi `tasksQuery` da `acceptor_id.eq.<me>` borligi HECH NARSANI
--      isbotlamaydi: u so'rov FILTRI, RLS esa serverda qaysi qator umuman
--      qaytishini hal qiladi. Policy'da `acceptor_id` bo'lmasa PostgREST
--      xato ham bermaydi — ro'yxat JIMGINA bo'sh keladi (eng yomon turdagi
--      nosozlik).
--
-- NIMA QILADI
--   1) `public.tasks` ning MAVJUD SELECT/ALL policy'larini o'qib NOTICE bilan
--      chiqaradi (diagnostika — nima borligi ko'rinsin).
--   2) `qual` matnida `acceptor_id` BO'LSA — hech narsa qo'shmaydi, faqat
--      NOTICE (allaqachon qoplangan).
--   3) BO'LMASA — yangi ADDITIVE PERMISSIVE `tasks_select_acceptor`.
--
-- 🔴 MAVJUD POLICY'LARGA TEGILMAYDI. PERMISSIVE policy'lar OR bilan
--    birlashadi → hech kimning ko'rinishi TORAYMAYDI, faqat kengayadi.
--    Nom yangi (`tasks_select_acceptor`) → boshqa skriptlar qayta RUN
--    qilinganda ham to'qnashmaydi (TASKFIX_LOYIHA_RLS.sql naqshi).
-- 🔴 `workspace_members` inline subquery YOZILMAYDI (42P17, 8-qoida) —
--    `is_ws_member()`. `(SELECT auth.uid())` — initplan, har qator uchun
--    qayta hisoblanmasin (TASKFIX_SCALE.sql saboqi).
-- ⚠️ `CREATE POLICY ON public.tasks` — ACCESS EXCLUSIVE qulf. Kam trafik!
-- ⚠️ RESTRICTIVE policy topilsa ogohlantiramiz: u AND bilan qo'llanadi va
--    yangi PERMISSIVE policy'ni baribir to'sib qo'yishi mumkin.
DO $$
DECLARE
  v_has_acc  boolean;
  v_rls      boolean;
  v_sel_n    int := 0;
  v_restr_n  int := 0;
  v_qual     text;
  v_exists   boolean;
  r          record;
BEGIN
  -- 4b.1) Shartlar
  v_has_acc := EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_schema='public' AND table_name='tasks' AND column_name='acceptor_id');

  SELECT c.relrowsecurity INTO v_rls
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname='public' AND c.relname='tasks';

  SELECT count(*) INTO v_sel_n FROM pg_policies
   WHERE schemaname='public' AND tablename='tasks'
     AND permissive='PERMISSIVE' AND cmd IN ('SELECT','ALL');

  SELECT count(*) INTO v_restr_n FROM pg_policies
   WHERE schemaname='public' AND tablename='tasks' AND permissive='RESTRICTIVE';

  v_exists := EXISTS (SELECT 1 FROM pg_policies
                       WHERE schemaname='public' AND tablename='tasks'
                         AND policyname='tasks_select_acceptor');

  -- 4b.2) DIAGNOSTIKA — nima borligi OCHIQ ko'rinsin
  RAISE NOTICE '';
  RAISE NOTICE '── 4b) public.tasks SELECT policy''lari ──';
  RAISE NOTICE 'RLS: %   | acceptor_id ustuni: %   | PERMISSIVE SELECT/ALL: % ta   | RESTRICTIVE: % ta',
    CASE WHEN COALESCE(v_rls,false) THEN 'YOQIQ' ELSE 'O''CHIQ' END,
    CASE WHEN v_has_acc THEN 'BOR' ELSE 'YO''Q' END, v_sel_n, v_restr_n;
  FOR r IN
    SELECT policyname, cmd, permissive, roles::text AS roles,
           regexp_replace(COALESCE(qual, '(qual yo''q)'), '\s+', ' ', 'g') AS q
      FROM pg_policies
     WHERE schemaname='public' AND tablename='tasks' AND cmd IN ('SELECT','ALL')
     ORDER BY permissive, policyname
  LOOP
    RAISE NOTICE '  • [%] % (%) roles=% → %', r.permissive, r.policyname, r.cmd, r.roles, left(r.q, 300);
  END LOOP;

  -- Mavjud qoplama: PERMISSIVE SELECT/ALL policy'lari matnida acceptor_id bormi?
  SELECT string_agg(COALESCE(qual, ''), ' | ') INTO v_qual
    FROM pg_policies
   WHERE schemaname='public' AND tablename='tasks'
     AND permissive='PERMISSIVE' AND cmd IN ('SELECT','ALL')
     AND policyname <> 'tasks_select_acceptor';   -- o'zimizni "dalil" deb hisoblamaymiz

  -- 4b.3) QAROR
  IF NOT v_has_acc THEN
    RAISE NOTICE '⚠️ tasks.acceptor_id ustuni YO''Q — qabul qiluvchi mexanizmi bu bazada umuman ishlamaydi. Policy QO''SHILMADI (himoyalanadigan narsa yo''q).';

  ELSIF NOT COALESCE(v_rls, false) THEN
    RAISE NOTICE 'ℹ️ public.tasks da RLS O''CHIQ — qatorlar baribir ochiq, policy baholanmasdi. QO''SHILMADI (mavjud sozlamaga tegilmaydi).';

  ELSIF v_sel_n = 0 THEN
    -- TASKFIX_LOYIHA_RLS.sql dagi ayni qaror: yolg'iz "acceptor" policy'si
    -- asosiy ko'rish qoidasining o'rnini bosib qolardi (owner/admin baribir
    -- ko'rmasdi) va nosozlikni NIQOBLARDI.
    RAISE WARNING 'public.tasks da PERMISSIVE SELECT policy UMUMAN YO''Q — bu holatda hozir HECH KIM vazifani ko''rmayapti. tasks_select_acceptor QO''SHILMADI: avval asosiy vazifa SELECT policy''sini tiklang, so''ng bu faylni QAYTA RUN qiling (idempotent).';

  ELSIF v_qual IS NOT NULL AND v_qual ~* 'acceptor_id' THEN
    RAISE NOTICE '✅ Mavjud tasks SELECT policy''sida `acceptor_id` ALLAQACHON bor — yangi policy QO''SHILMADI (ortiqcha bo''lardi).';

  ELSE
    -- 🔴 ADDITIVE. DROP faqat O'ZIMIZNING nomdagi policy uchun (qayta RUN).
    DROP POLICY IF EXISTS tasks_select_acceptor ON public.tasks;
    EXECUTE $p$
      CREATE POLICY tasks_select_acceptor ON public.tasks
        AS PERMISSIVE FOR SELECT TO authenticated
        USING ( acceptor_id = (SELECT auth.uid())
                AND is_ws_member(workspace_id, (SELECT auth.uid())) )
    $p$;
    IF v_exists THEN
      RAISE NOTICE '✅ tasks_select_acceptor policy''si QAYTA yaratildi (avvalgi RUN''dan qolgan edi).';
    ELSE
      RAISE NOTICE '✅ tasks_select_acceptor policy''si QO''SHILDI — endi qabul qiluvchi topshirilgan vazifani ko''radi (mavjud policy''larga tegilmadi).';
    END IF;
  END IF;

  IF v_restr_n > 0 THEN
    RAISE WARNING 'public.tasks da % ta RESTRICTIVE policy bor — ular AND bilan qo''llanadi va yangi PERMISSIVE policy''ni ham to''sishi mumkin. Yuqoridagi ro''yxatni ko''rib chiqing.', v_restr_n;
  END IF;
  RAISE NOTICE '';
END $$;


-- ============================================================================
-- 5) TEKSHIRUV — JIMGINA O'TMASIN
-- ============================================================================
DO $$
DECLARE
  v_cnt   int;
  v_txt   text;
  v_src   text;
  v_norm  text;
  v_type  int2;
BEGIN
  -- 5.a) Jadval bor
  IF to_regclass('public.task_comment_history') IS NULL THEN
    RAISE EXCEPTION 'task_comment_history yaratilmadi';
  END IF;

  -- 5.b) Ustunlar TO'LIQ (jadval avval BOSHQA sxema bilan yaratilgan bo'lishi
  --      mumkin — CREATE TABLE IF NOT EXISTS bunday holatni jimgina o'tkazadi)
  SELECT count(*) INTO v_cnt FROM information_schema.columns
   WHERE table_schema='public' AND table_name='task_comment_history'
     AND column_name IN ('id','workspace_id','task_id','comment_id','action',
                         'old_text','new_text','actor_id','actor_name','at');
  IF v_cnt <> 10 THEN
    RAISE EXCEPTION 'task_comment_history ustunlari to''liq emas (% / 10) — jadval avval boshqa sxema bilan yaratilgan bo''lishi mumkin. Qo''lda tekshiring.', v_cnt;
  END IF;

  -- 5.b2) 🔴 IZOH MUALLIFI ustunlari (2.0b). Jadval avvalgi RUN'da ustunsiz
  --       yaratilgan bo'lsa `CREATE TABLE IF NOT EXISTS` uni jimgina o'tkazib
  --       yuborardi — shuning uchun ALOHIDA tekshiramiz.
  SELECT count(*) INTO v_cnt FROM information_schema.columns
   WHERE table_schema='public' AND table_name='task_comment_history'
     AND column_name IN ('author_id','author_name');
  IF v_cnt <> 2 THEN
    RAISE EXCEPTION 'task_comment_history da author_id/author_name ustunlari to''liq emas (% / 2) — "izohni KIM YOZGAN" talabi bajarilmasdi.', v_cnt;
  END IF;

  -- 5.c) 🔴 FK YO'Qligi — modulning asosiy kafolati.
  --      Kimdir "toza bo'lsin" deb FK qo'shsa: izoh o'chganda tarix ham
  --      o'chib ketardi (yoki vazifa o'chirilganda audit yozuvi FK bilan
  --      yiqilardi). Shuning uchun bu yerda TO'XTAYMIZ.
  SELECT string_agg(conname, ', ') INTO v_txt
    FROM pg_constraint
   WHERE conrelid = 'public.task_comment_history'::regclass AND contype = 'f';
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'task_comment_history da FOREIGN KEY topildi: % — audit qatorlari hech kimga bog''liq bo''lmasligi SHART (izoh/vazifa o''chganda tarix yo''qolmasin). To''xtatildi.', v_txt;
  END IF;

  -- 5.d) CHECK bor va aynan 3 qiymatni qamraydi
  SELECT pg_get_constraintdef(oid) INTO v_txt
    FROM pg_constraint
   WHERE conrelid = 'public.task_comment_history'::regclass
     AND conname = 'task_cmt_hist_action_chk';
  IF v_txt IS NULL THEN
    RAISE EXCEPTION 'task_cmt_hist_action_chk yaratilmadi — action ustuniga istalgan matn yozilardi.';
  END IF;
  IF strpos(v_txt, 'created') = 0 OR strpos(v_txt, 'edited') = 0 OR strpos(v_txt, 'deleted') = 0 THEN
    RAISE EXCEPTION 'task_cmt_hist_action_chk kutilgan qiymatlarni qamramaydi (created/edited/deleted). Hozirgi: %', v_txt;
  END IF;

  -- 5.e) Indekslar
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                  AND tablename='task_comment_history' AND indexname='idx_task_cmt_hist_task') THEN
    RAISE EXCEPTION 'idx_task_cmt_hist_task indeksi yaratilmadi';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                  AND tablename='task_comment_history' AND indexname='idx_task_cmt_hist_comment') THEN
    RAISE EXCEPTION 'idx_task_cmt_hist_comment indeksi yaratilmadi';
  END IF;

  -- 5.f) RLS yoqilgan
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname='public' AND c.relname='task_comment_history' AND c.relrowsecurity) THEN
    RAISE EXCEPTION 'task_comment_history da RLS yoqilmadi — izoh tarixi HAMMAGA ochiq qolardi!';
  END IF;

  -- 5.g) SELECT policy bor VA haqiqatan workspace bilan cheklaydi.
  --   ⚠️ Faqat NOM bo'yicha tekshirish yetarli emas: kimdir shu nomdagi
  --      policy'ni USING (true) bilan qayta yozsa tekshiruv o'tib ketardi va
  --      begona workspace a'zosi boshqa jamoaning izohlarini o'qirdi.
  SELECT upper(regexp_replace(qual, '\s+', ' ', 'g')) INTO v_txt
    FROM pg_policies
   WHERE schemaname='public' AND tablename='task_comment_history'
     AND policyname='task_cmt_history_select' AND cmd='SELECT';
  IF v_txt IS NULL THEN
    RAISE EXCEPTION 'task_cmt_history_select policy''si yaratilmadi (yoki cmd SELECT emas) — RLS yoqiq, policy yo''q = hech kim tarixni ko''ra olmasdi.';
  END IF;
  IF strpos(v_txt, 'IS_WS_MEMBER(') = 0 OR strpos(v_txt, 'WORKSPACE_ID') = 0 THEN
    RAISE EXCEPTION 'task_cmt_history_select policy''sida is_ws_member(workspace_id, ...) sharti yo''q — hozirgi shart: %. Begona workspace a''zosi izohlarni o''qirdi. To''xtatildi.', v_txt;
  END IF;

  -- 5.h) 🔴 YOZUV policy'si YO'Qligi (kelajakda kimdir qo'shsa — shu yerda to'xtaydi)
  SELECT string_agg(policyname || ' (' || cmd || ')', ', ') INTO v_txt
    FROM pg_policies
   WHERE schemaname='public' AND tablename='task_comment_history' AND cmd <> 'SELECT';
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'task_comment_history da yozuv policy''si topildi: % — yozuv FAQAT trigger orqali bo''lishi kerak (aks holda odam o''z izohi tarixini o''chirardi). To''xtatildi.', v_txt;
  END IF;

  -- 5.i) Funksiya bor va SECURITY DEFINER
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='task_cmt_audit' AND p.prosecdef) THEN
    RAISE EXCEPTION 'task_cmt_audit() yaratilmadi yoki SECURITY DEFINER emas (SECURITY DEFINER bo''lmasa RLS yozuvni to''sadi — audit hech qachon ishlamasdi).';
  END IF;

  -- 5.j) 🔴 Funksiya TANASIDAGI qorovullar joyidami?
  --   IZOHLAR AVVAL TOZALANADI (TASKFIX_HR_EDITORS.sql 4.b2 / TASKFIX_VIEWS.sql
  --   5.i naqshi): tanadagi izohlarda ham aynan shu so'zlar bor — xom matnda
  --   qidirsak KOD o'chirilib IZOH qolgan holatni sezmasdik.
  SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='task_cmt_audit' AND p.pronargs = 0
   LIMIT 1;
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'task_cmt_audit() tanasi o''qilmadi — funksiya yaratilmadimi?';
  END IF;
  v_norm := upper(regexp_replace(v_src, '\s+', ' ', 'g'));

  -- (1) "asosiy amal yiqilmasin" himoyasi
  IF strpos(v_norm, 'EXCEPTION WHEN OTHERS THEN RAISE WARNING') = 0 THEN
    RAISE EXCEPTION 'task_cmt_audit() KODIDA tashqi "EXCEPTION WHEN OTHERS THEN RAISE WARNING" himoyasi topilmadi — audit yiqilsa odam izoh yoza olmay qolardi. To''xtatildi.';
  END IF;

  -- (2) UPDATE'da bo'sh teginish yozilmasin
  IF strpos(v_norm, 'NEW.COMMENT_TEXT IS NOT DISTINCT FROM OLD.COMMENT_TEXT') = 0 THEN
    RAISE EXCEPTION 'task_cmt_audit() KODIDA "NEW.comment_text IS NOT DISTINCT FROM OLD.comment_text" qorovuli topilmadi — har edited_at teginishi tarixni shishirardi. To''xtatildi.';
  END IF;

  -- (3) Uchala amal ham yoziladi
  IF strpos(v_norm, '''DELETED''') = 0 OR strpos(v_norm, '''EDITED''') = 0 OR strpos(v_norm, '''CREATED''') = 0 THEN
    RAISE EXCEPTION 'task_cmt_audit() KODIDA created/edited/deleted shoxlarining hammasi yo''q — audit to''liq emas. To''xtatildi.';
  END IF;

  -- (4) 🔴 MUALLIF haqiqatan YOZILADIMI? Ustun bor-u funksiya eski
  --     (author'siz) versiyada qolgan bo'lishi mumkin — masalan kimdir
  --     TASKFIX_8ISH.sql ning oldingi nusxasini keyinroq qayta RUN qilsa.
  --     U holda "kim yozgan" JIMGINA NULL bo'lib qolardi.
  IF strpos(v_norm, 'AUTHOR_ID') = 0 OR strpos(v_norm, 'AUTHOR_NAME') = 0 THEN
    RAISE EXCEPTION 'task_cmt_audit() KODIDA author_id/author_name yozuvi topilmadi — ustunlar bor, lekin funksiya ESKI (muallif jimgina NULL qolardi). Shu faylni to''liq qayta RUN qiling.';
  END IF;
  -- DELETE shoxida NEW ga murojaat qilinmasin ("record new is not assigned yet")
  IF strpos(v_norm, 'V_AUTHOR := OLD.AUTHOR_ID') = 0 THEN
    RAISE EXCEPTION 'task_cmt_audit() da DELETE uchun `v_author := OLD.author_id` shoxi yo''q — DELETE trigger''ida NEW tayinlanmagan bo''ladi va audit har o''chirishda yiqilardi (WARNING ostida jimgina).';
  END IF;

  -- 5.k) Trigger bor, ROW + AFTER + INSERT/UPDATE/DELETE, yoqilgan
  SELECT tg.tgtype INTO v_type
    FROM pg_trigger tg
   WHERE tg.tgrelid = 'public.task_comments'::regclass
     AND tg.tgname = 'zz_task_cmt_audit_trg' AND NOT tg.tgisinternal;
  IF v_type IS NULL THEN
    RAISE EXCEPTION 'zz_task_cmt_audit_trg trigger''i yaratilmadi — izohlar tarixga TUSHMASDI.';
  END IF;
  IF (v_type & 1) <> 1 THEN
    RAISE EXCEPTION 'zz_task_cmt_audit_trg FOR EACH ROW emas (statement-level) — NEW/OLD o''qilmasdi.';
  END IF;
  IF (v_type & 2) <> 0 THEN
    RAISE EXCEPTION 'zz_task_cmt_audit_trg BEFORE trigger — AFTER bo''lishi kerak (amal muvaffaqiyatli bo''lgach yozilsin).';
  END IF;
  IF (v_type & 4) <> 4 OR (v_type & 8) <> 8 OR (v_type & 16) <> 16 THEN
    RAISE EXCEPTION 'zz_task_cmt_audit_trg uchala hodisani (INSERT/UPDATE/DELETE) qamramaydi — tgtype=%. 🔴 DELETE qamrab olinmasa "o''chgan izoh yo''qolmasin" talabi bajarilmaydi.', v_type;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger tg
                  WHERE tg.tgrelid='public.task_comments'::regclass
                    AND tg.tgname='zz_task_cmt_audit_trg' AND tg.tgenabled <> 'D') THEN
    RAISE EXCEPTION 'zz_task_cmt_audit_trg O''CHIRILGAN (tgenabled = D) — audit yozilmasdi.';
  END IF;

  -- 5.l) Ustunlar (1, 3, 4-bo'limlar)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name='description_html') THEN
    RAISE EXCEPTION 'tasks.description_html qo''shilmadi';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='task_comments' AND column_name='edited_at') THEN
    RAISE EXCEPTION 'task_comments.edited_at qo''shilmadi';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name='bajardi_user_id') THEN
    RAISE EXCEPTION 'tasks.bajardi_user_id qo''shilmadi';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name='bajardi_at') THEN
    RAISE EXCEPTION 'tasks.bajardi_at qo''shilmadi';
  END IF;

  -- 5.l2) 🔴 4b — QABUL QILUVCHI QOPLAMASI. Shartlar 4b dagi QAROR bilan
  --      AYNAN bir xil bo'lishi shart, aks holda o'tkazib yuborilgan holat
  --      bu yerda "xato" deb butun migratsiyani qaytarib yuborardi.
  --      Tekshiruv shu sababli ham muhim: policy qo'shildi deb NOTICE
  --      chiqarilib, aslida `qual` boshqacha bo'lib qolishi mumkin.
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='tasks' AND column_name='acceptor_id')
     AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname='public' AND c.relname='tasks' AND c.relrowsecurity)
     AND (SELECT count(*) FROM pg_policies
           WHERE schemaname='public' AND tablename='tasks'
             AND permissive='PERMISSIVE' AND cmd IN ('SELECT','ALL')) > 0
  THEN
    SELECT string_agg(COALESCE(qual, ''), ' | ') INTO v_txt
      FROM pg_policies
     WHERE schemaname='public' AND tablename='tasks'
       AND permissive='PERMISSIVE' AND cmd IN ('SELECT','ALL');
    IF v_txt IS NULL OR v_txt !~* 'acceptor_id' THEN
      RAISE EXCEPTION 'public.tasks SELECT policy''larida `acceptor_id` YO''Q va tasks_select_acceptor ham qo''shilmadi — qabul qiluvchi topshirilgan vazifani KO''RMAS EDI (ro''yxati jimgina bo''sh bo''lardi). To''xtatildi, hech narsa o''zgartirilmadi.';
    END IF;
    -- Yangi policy AYNAN kutilgan shartda ekanini tekshiramiz (kimdir uni
    -- keyinroq `USING (true)` bilan qayta yozib qo'ysa — begona ws vazifalari
    -- ochilib ketardi).
    SELECT upper(regexp_replace(qual, '\s+', ' ', 'g')) INTO v_txt
      FROM pg_policies
     WHERE schemaname='public' AND tablename='tasks' AND policyname='tasks_select_acceptor';
    IF v_txt IS NOT NULL THEN
      IF strpos(v_txt, 'ACCEPTOR_ID') = 0 OR strpos(v_txt, 'IS_WS_MEMBER(') = 0 THEN
        RAISE EXCEPTION 'tasks_select_acceptor policy''sining sharti kutilgandek emas: % — u AYNAN `acceptor_id = auth.uid() AND is_ws_member(workspace_id, auth.uid())` bo''lishi kerak. To''xtatildi.', v_txt;
      END IF;
    END IF;
  END IF;

  -- 5.m) 🔴 `description` TEGILMAGANmi? (u toza matn bo'lib qolishi SHART)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name='description') THEN
    RAISE NOTICE '⚠️ tasks.description ustuni topilmadi — bu skript unga TEGMAGAN, lekin mijoz/Telegram o''shani o''qiydi. Tekshiring.';
  END IF;

  RAISE NOTICE '✅ Tekshiruv o''tdi: task_comment_history (RLS yoqiq, 1 SELECT policy, yozuv policy''si yo''q, FK yo''q, author_id/author_name bor) + zz_task_cmt_audit_trg (AFTER, ROW, I/U/D, muallifni yozadi) + 4 ta yangi ustun + tasks SELECT qoplamasida acceptor_id.';
END $$;


-- ============================================================================
-- 5b) 🔴 MIGRATSIYA — ESKI "REASSIGN" QILINGAN VAZIFALAR
--     ⚠️ public.tasks ga UPDATE — KAM TRAFIK VAQTIDA RUN QILINSIN
-- ============================================================================
-- MUAMMO
--   2026-08-26 gacha mijozdagi `changeStatus` vazifani TOPSHIRISHDA qabul
--   qiluvchiga KO'CHIRARDI:  patch.assigned_to = prev.acceptor_id
--   Asl bajaruvchi esa `submitter_id` ga yozilardi. O'sha reassign OLIB
--   TASHLANDI (Asilbek qarori) — endi vazifa BAJARUVCHIDA qoladi.
--   Lekin BAZADAGI eski qatorlar hamon qabul qiluvchida turibdi: ro'yxatlar,
--   "kimda nechta vazifa" va hisobotlar yangi model bilan NOMUVOFIQ.
--
-- NISHON SHART (aynan shu 4 shart birga)
--   submitter_id IS NOT NULL          -- topshirilgan (reassign izi bor)
--   AND acceptor_id IS NOT NULL       -- qabul qiluvchisi bor
--   AND assigned_to = acceptor_id     -- hozir qabul qiluvchida turibdi
--   AND submitter_id <> acceptor_id   -- ikkovi bir odam emas (aks holda ma'nosiz)
--   →  assigned_to := submitter_id
--
-- 🔴 STATUS CHEKLOVI — QO'LDA QAYTA BIRIKTIRISH XAVFI
--   `taskReassign` (ras*) moduli orqali odam vazifani ATAYLAB qabul
--   qiluvchiga bergan bo'lishi mumkin. U holda `assigned_to = acceptor_id`
--   TASODIFAN mos keladi va migratsiya uning qarorini NOTO'G'RI qaytarardi.
--   Shuning uchun faqat ESKI OQIM QOLDIRADIGAN ikki status olinadi:
--     • 'qabul_kutilyapti' — aynan topshirish natijasi (eski reassign shu
--       lahzada bo'lardi);
--     • 'completed'        — o'sha topshirish qabul qilingandan keyingi holat.
--   'new' / 'in_progress' va boshqa statuslarda `assigned_to = acceptor_id`
--   holati eski reassign'dan KELIB CHIQMAYDI (u yerda reassign hech qachon
--   bo'lmagan) — demak u FAQAT qo'lda biriktirishdan bo'lishi mumkin va
--   biz unga TEGMAYMIZ.
--   ⚠️ Qoldiq xavf: 'qabul_kutilyapti'/'completed' vazifani qo'lda qabul
--   qiluvchiga biriktirgan bo'lsa u ham qaytariladi — shuning uchun
--   ZAXIRA JADVALI bor (pastda) va qaytarish UPDATE'i yozib qo'yilgan.
--
-- ⚠️ BU UPDATE `task_history` GA TUSHMAYDI — vazifa tarixini MIJOZ yozadi
--    (`thRecord`), `tasks` da tarix trigger'i ATAYLAB yo'q. Ya'ni detal
--    oynasidagi "Tarix" bo'limida bu o'zgarish KO'RINMAYDI. Iz — quyidagi
--    zaxira jadvali.
-- ⚠️ Bildirishnoma/Telegram/email HAM ketmaydi (server tomonda yuboruvchi
--    yo'q) — bu ONGLI: 100+ eski vazifa uchun xabar to'lqini kerak emas.
--
-- IDEMPOTENT: migratsiyadan keyin `assigned_to = submitter_id` bo'ladi, ya'ni
--   nishon shart o'z-o'zidan bajarilmay qoladi → qayta RUN'da 0 qator.
--   Zaxiraga ham takror yozilmaydi (PK + ON CONFLICT DO NOTHING).
-- ============================================================================

-- ── 5b.1) ZAXIRA JADVALI — migratsiya QAYTARILADIGAN bo'lsin ───────────────
-- 🔴 RLS yoqiladi va POLICY UMUMAN QO'SHILMAYDI + anon/authenticated dan
--    REVOKE: bu ichki, ma'muriy jadval — PostgREST orqali o'qilmasin.
DO $bk$
DECLARE
  v_task_type text;
BEGIN
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_task_type
    FROM pg_attribute a
   WHERE a.attrelid = 'public.tasks'::regclass
     AND a.attname = 'id' AND a.attnum > 0 AND NOT a.attisdropped;
  IF v_task_type IS NULL THEN
    RAISE EXCEPTION 'public.tasks.id ustuni topilmadi — zaxira jadvali qurilmaydi.';
  END IF;

  -- FK ATAYLAB YO'Q: vazifa o'chirilsa ham "nima o'zgartirilgan edi" izi qolsin
  -- (task_comment_history bilan bir xil sabab).
  EXECUTE format($f$
    CREATE TABLE IF NOT EXISTS public.tasks_reassign_backup_8ish (
      task_id         %s PRIMARY KEY,
      old_assigned_to uuid,
      new_assigned_to uuid,
      status          text,
      at              timestamptz NOT NULL DEFAULT now()
    )
  $f$, v_task_type);

  EXECUTE 'ALTER TABLE public.tasks_reassign_backup_8ish ENABLE ROW LEVEL SECURITY';
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    EXECUTE 'REVOKE ALL ON public.tasks_reassign_backup_8ish FROM anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    EXECUTE 'REVOKE ALL ON public.tasks_reassign_backup_8ish FROM authenticated';
  END IF;
END $bk$;

COMMENT ON TABLE public.tasks_reassign_backup_8ish IS
  'TASKFIX_8ISH.sql 5b-bo''limi: "eski reassign" migratsiyasining ZAXIRASI (assigned_to qabul qiluvchidan asl bajaruvchiga qaytarilgan qatorlar). Qaytarish UPDATE''i skript oxirida izoh sifatida yozilgan. RLS yoqiq, policy YO''Q — faqat service_role/superuser o''qiydi.';


-- ── 5b.2) MIGRATSIYANING O'ZI ──────────────────────────────────────────────
DO $mig$
DECLARE
  v_inc        boolean;
  v_st         text[];
  v_has_sub    boolean;
  v_cnt_pend   int := 0;
  v_cnt_done   int := 0;
  v_bk         int := 0;
  v_upd        int := 0;
  v_left       int := 0;
  v_cond       text;
BEGIN
  SELECT v INTO v_inc FROM pg_temp.t8_cfg WHERE k = 'include_completed';
  v_inc := COALESCE(v_inc, true);
  v_st  := CASE WHEN v_inc THEN ARRAY['qabul_kutilyapti','completed']
                ELSE ARRAY['qabul_kutilyapti'] END;

  -- `submitter_id` bo'lmasa eski reassign hech qachon ishlamagan → migratsiya
  -- ma'nosiz. Jimgina o'tmaymiz — sababni AYTAMIZ.
  v_has_sub := EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_schema='public' AND table_name='tasks' AND column_name='submitter_id');
  IF NOT v_has_sub THEN
    RAISE NOTICE '';
    RAISE NOTICE '── 5b) MIGRATSIYA — O''TKAZIB YUBORILDI ──';
    RAISE NOTICE 'ℹ️ public.tasks.submitter_id ustuni YO''Q → eski "reassign" oqimi bu bazada hech qachon ishlamagan. Migratsiya qilinadigan qator yo''q.';
    RETURN;
  END IF;

  -- 🔴 Shart BITTA joyda yoziladi (sanoq / zaxira / update / tekshiruv AYNI
  --    shartni ishlatsin — nusxa ko'chirilgan shart vaqt o'tib ajralib ketardi).
  v_cond := 't.submitter_id IS NOT NULL '
         || 'AND t.acceptor_id IS NOT NULL '
         || 'AND t.assigned_to = t.acceptor_id '
         || 'AND t.submitter_id <> t.acceptor_id';

  -- (a) Diagnostika — status bo'yicha nechta qator TOPILDI (sozlamadan qat'i nazar)
  EXECUTE format($q$
    SELECT count(*) FILTER (WHERE t.status = 'qabul_kutilyapti'),
           count(*) FILTER (WHERE t.status = 'completed')
      FROM public.tasks t
     WHERE %s AND t.status IN ('qabul_kutilyapti','completed')
  $q$, v_cond) INTO v_cnt_pend, v_cnt_done;

  RAISE NOTICE '';
  RAISE NOTICE '── 5b) ESKI REASSIGN MIGRATSIYASI ──';
  RAISE NOTICE 'Topildi: qabul_kutilyapti = % ta | completed = % ta', v_cnt_pend, v_cnt_done;
  RAISE NOTICE 'Sozlama: v_include_completed = % → migratsiya statuslari: %', v_inc, array_to_string(v_st, ', ');

  -- (b) ZAXIRA — UPDATE'DAN OLDIN (keyin bo'lsa eski qiymat allaqachon yo'q edi)
  EXECUTE format($q$
    INSERT INTO public.tasks_reassign_backup_8ish (task_id, old_assigned_to, new_assigned_to, status)
    SELECT t.id, t.assigned_to, t.submitter_id, t.status
      FROM public.tasks t
     WHERE %s AND t.status = ANY($1)
    ON CONFLICT (task_id) DO NOTHING
  $q$, v_cond) USING v_st;
  GET DIAGNOSTICS v_bk = ROW_COUNT;
  RAISE NOTICE 'Zaxiraga yozildi: % ta qator (public.tasks_reassign_backup_8ish)', v_bk;

  -- (c) MIGRATSIYA
  EXECUTE format($q$
    UPDATE public.tasks t
       SET assigned_to = t.submitter_id
     WHERE %s AND t.status = ANY($1)
  $q$, v_cond) USING v_st;
  GET DIAGNOSTICS v_upd = ROW_COUNT;
  RAISE NOTICE 'Yangilandi: % ta vazifa (assigned_to → submitter_id)', v_upd;

  -- (d) 🔴 TEKSHIRUV — jimgina o'tmasin. Kiritilgan statuslar bo'yicha nishon
  --     shartga mos qator QOLMASLIGI shart; qolsa hammasi QAYTADI.
  -- ⚠️ PL/pgSQL: INTO ... USING (aynan shu tartib) — teskarisi sintaksis xatosi.
  EXECUTE format($q$
    SELECT count(*) FROM public.tasks t WHERE %s AND t.status = ANY($1)
  $q$, v_cond) INTO v_left USING v_st;

  IF v_left <> 0 THEN
    RAISE EXCEPTION 'MIGRATSIYA TO''LIQ EMAS: nishon shartga mos % ta qator QOLDI (statuslar: %). Ehtimol trigger UPDATE''ni qaytardi yoki shart bilan yozuv orasida qator o''zgardi. Hammasi qaytarildi — hech narsa o''zgartirilmadi.',
      v_left, array_to_string(v_st, ', ');
  END IF;

  IF v_upd = 0 THEN
    RAISE NOTICE 'ℹ️ 0 qator yangilandi — migratsiya AVVAL bajarilgan yoki bunday vazifa yo''q (idempotent, normal holat).';
  END IF;
  IF NOT v_inc AND v_cnt_done > 0 THEN
    RAISE NOTICE '⚠️ % ta "completed" vazifa TEGILMADI (v_include_completed = false). Kerak bo''lsa sozlamani true qilib QAYTA RUN qiling — skript idempotent.', v_cnt_done;
  END IF;
  RAISE NOTICE '⚠️ Bu o''zgarish task_history ga TUSHMAYDI (tarixni mijoz yozadi). Iz — public.tasks_reassign_backup_8ish jadvalida.';
  RAISE NOTICE '───────────────────';
END $mig$;


-- ============================================================================
-- 6) XULOSA — nima QO'SHILDI / nima ALLAQACHON BOR EDI
-- ============================================================================
DO $$
DECLARE
  r record;
  v_new int := 0;
  v_old int := 0;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '════════════════ TASKFIX_8ISH.sql — XULOSA ════════════════';
  FOR r IN
    SELECT k, v FROM _t8_before
     ORDER BY CASE k
       WHEN 'tasks.description_html'         THEN 1
       WHEN 'tasks.recur_copy_data'          THEN 1.5
       WHEN 'table.tasks_reassign_backup_8ish' THEN 9.5
       WHEN 'table.task_comment_history'     THEN 2
       WHEN 'cmt_history.author_id'          THEN 3
       WHEN 'trigger.zz_task_cmt_audit_trg'  THEN 4
       WHEN 'task_comments.edited_at'        THEN 5
       WHEN 'policy.task_comments_update'    THEN 6
       WHEN 'tasks.bajardi_user_id'          THEN 7
       WHEN 'tasks.bajardi_at'               THEN 8
       WHEN 'policy.tasks_select_acceptor'   THEN 9
       ELSE 10 END
  LOOP
    IF r.v THEN
      v_old := v_old + 1;
      RAISE NOTICE '  ℹ️  % — allaqachon bor edi (tegilmadi)', rpad(r.k, 32);
    ELSE
      v_new := v_new + 1;
      RAISE NOTICE '  ✔  % — QO''SHILDI', rpad(r.k, 32);
    END IF;
  END LOOP;
  RAISE NOTICE '───────────────────────────────────────────────────────────';
  RAISE NOTICE '  Yangi: %   |   Avvaldan bor: %', v_new, v_old;
  RAISE NOTICE '';
  RAISE NOTICE '  ⚠️ policy.task_comments_update "allaqachon bor" bo''lsa — MAVJUD';
  RAISE NOTICE '     policy TEGILMAGAN, izoh tahriri o''sha shartlarga bo''ysunadi.';
  RAISE NOTICE '  ⚠️ Ilova bu ustun/jadvalsiz ham TO''LIQ ishlaydi — RUN''dan keyin';
  RAISE NOTICE '     mijoz boy matn + izoh tarixi UI''sini chizadi.';
  RAISE NOTICE '  🔴 policy.tasks_select_acceptor "QO''SHILDI" bo''lsa: qabul';
  RAISE NOTICE '     qiluvchi endi topshirilgan vazifani ko''radi. "allaqachon';
  RAISE NOTICE '     bor" yoki 4b da "acceptor_id ALLAQACHON bor" desa — mavjud';
  RAISE NOTICE '     policy o''zi qoplagan, hech narsa o''zgartirilmadi.';
  RAISE NOTICE '  🔴 cmt_history.author_id — endi tarixda "kim YOZGAN" ham bor';
  RAISE NOTICE '     (actor_* = kim o''chirdi/tahrirladi). Eski qatorlarda NULL.';
  RAISE NOTICE '  📋 tasks.recur_copy_data — takrorlanuvchi vazifada "ma''lumotlar';
  RAISE NOTICE '     ko''chirilsinmi" belgisi (izoh + fayl). Sukut FALSE = hozirgi';
  RAISE NOTICE '     xatti-harakat; mijozda yaratish oynasidan yoqiladi.';
  RAISE NOTICE '  🔴 5b) ESKI REASSIGN MIGRATSIYASI — yuqoridagi "5b" NOTICE''lariga';
  RAISE NOTICE '     qarang: nechta topildi / zaxiraga yozildi / yangilandi.';
  RAISE NOTICE '     Zaxira: public.tasks_reassign_backup_8ish (qaytarish UPDATE''i';
  RAISE NOTICE '     fayl oxirida izoh sifatida yozilgan).';
  RAISE NOTICE '═══════════════════════════════════════════════════════════';
END $$;

COMMIT;

-- ============================================================================
-- MIJOZ TOMONI (index.html) — bu faylda O'ZGARISH YO'Q, ma'lumot uchun
-- ============================================================================
-- 1) BOY MATNLI TAVSIF
--      // yozish — IKKALASI BIRGA (description TOZA MATN bo'lib qoladi!)
--      const { error } = await sb.from('tasks')
--        .update({ description: plainText, description_html: safeHtml })
--        .eq('id', t.id).select('id');
--      if (error) throw error;                    // CLAUDE.md 6-qoida
--      // o'qish
--      const html = t.description_html ? sanitizeHtml(t.description_html)
--                                      : escapeHtml(t.description || '');
--    ⚠️ Ustun yo'q bo'lsa PostgREST PGRST204 ("column ... does not exist")
--       qaytaradi — mijoz `description_html` ni payload'dan tashlab QAYTA
--       yozadi va sababni toastda aytadi (rdl*/rcx* naqshi), jimgina yo'qotmaydi.
--
-- 2) IZOH TARIXI
--      const { data, error } = await sb.from('task_comment_history')
--        .select('*')            // 🔴 nomma-nom EMAS: author_* ustunlari
--        .eq('task_id', t.id)    //    bo'lmagan bazada 42703 bilan yiqilardi
--        .order('at', { ascending: false }).limit(200);
--      if (error) { /* jadval yo'q (42P01/PGRST205) → _cahMissing = true */ }
--    ⚠️ Jadval yo'q bo'lsa bo'lim JIMGINA bo'sh qolmasin — "TASKFIX_8ISH.sql
--       ishga tushirilmagan" deb yozsin (th*/tv* naqshi).
--    ⚠️ Tarixga mijoz HECH QACHON yozmaydi — trigger o'zi yozadi.
--    👤 `author_id`/`author_name` — izoh MUALLIFI. Mijoz uni faqat
--       `author_id <> actor_id` bo'lganda ko'rsatadi (o'zi yozib o'zi
--       o'chirgan holat eng ko'p uchraydi va takror ko'rinardi).
--
-- 3) IZOH TAHRIRI
--      const { data, error } = await sb.from('task_comments')
--        .update({ comment_text: newText, edited_at: new Date().toISOString() })
--        .eq('id', id).select('id');
--      if (error) throw error;
--      if (!data || !data.length) throw new Error('RLS to''sdi');  // yolg'on "Saqlandi" bo'lmasin
--
-- 4) BAJARILGAN SANA — `tasks.bajardi_at` / `bajardi_user_id`.
--    ⚠️ 2026-08-26 (QA-T1/T2) dan mijoz qoidalari:
--      • `bajardi_*` FAQAT topshirish lahzasida (yoki qabul qiluvchisi YO'Q
--        vazifa `completed` bo'lganda) yoziladi — qabul qiluvchi/admin uni
--        HECH QACHON bosmaydi (`acceptTask` bilan bir xil natija);
--      • ular HECH QACHON tozalanmaydi (qaytarilgan vazifada "kim topshirgan
--        edi" ma'lumoti qoladi), shuning uchun "Bajarildi" SANASI mijozda
--        `status = 'completed'` qorovuli bilan ko'rsatiladi.
--
-- 5) 4b — RLS: qabul qiluvchi topshirilgan vazifani ko'rishi. Mijozda
--    HECH QANDAY o'zgarish talab qilinmaydi (`tasksQuery` da `acceptor_id`
--    allaqachon bor) — bu bo'lim SERVER tomonidagi kafolatni beradi.
--
-- 6) 📋 TAKRORDA MA'LUMOTLARNI KO'CHIRISH — `tasks.recur_copy_data`
--      // yaratishda (saveCreate) — FAQAT true bo'lganda payload'ga qo'shiladi
--      if (recurCopy) inserts.forEach(r => { r.recur_copy_data = true; });
--      // zanjirda (maybeRecurTask) — bayroq YANGI nusxaga ham ko'chadi
--      if (rcpWant(task)) row.recur_copy_data = true;
--      // nusxa yaratilgandan KEYIN: izoh + fayl ko'chiriladi
--      if (rcpWant(task) && data && data.id) rcpReport(await rcpCopyData(task, data));
--    ⚠️ Ustun yo'q bo'lsa `task.recur_copy_data` === undefined → ko'chirish
--       UMUMAN bo'lmaydi (0 ta so'rov), xato ham, toast ham yo'q. Yozuvda
--       42703/PGRST204 kelsa mijoz bayroqni tashlab QAYTA yozadi va sababni
--       toastda aytadi (rcx*/rte* naqshi).
--    🔴 IZOH MUALLIFI (`author_id`) saqlanadi — matn boshqa odam nomiga
--       yozilib qolmasin. Agar `task_comments` INSERT policy'si
--       `author_id = auth.uid()` ni talab qilsa, begona muallifli izohlar
--       ko'chmaydi: mijoz O'Z izohlarini ko'chiradi va qolganini OCHIQ aytadi
--       ("N ta izoh ko'chmadi"). Bu skript o'sha policy'ga TEGMAYDI.
--    🔴 FAYL: Storage'da `copy()` bilan NUSXA olinadi (mavjud `attachments`
--       bucket, mavjud `<ws>/<task>/…` yo'li) — yangi Storage policy KERAK
--       EMAS. Qator ESKI yo'lga havola qilmaydi: aks holda birinchi vazifadagi
--       faylni o'chirgan odam ikkinchisinikini ham o'chirardi.
--    ⚠️ Ko'chirilgan izohlar `zz_task_cmt_audit_trg` orqali tarixga `created`
--       bo'lib tushadi — bu TO'G'RI (yangi vazifada izoh haqiqatan yaratildi).
--       Mijoz `created` yozuvlarini KO'RSATMAYDI (2026-08-26 qarori), ya'ni
--       ko'chirish izoh tarixini shovqin bilan to'ldirmaydi.
--
-- 7) 📝 IZOH TARIXIDA `created` KO'RSATILMAYDI (mijoz, 2026-08-26)
--    Izoh qo'shilgani "Izohlar" bo'limida allaqachon ko'rinadi — tarixda
--    takrorlansa BITTA narsa ikki marta ko'rinardi. 🔴 TRIGGER `created`
--    qatorini YOZISHDA DAVOM ETADI: izoh keyin O'CHIRILSA, uning qachon va
--    kim tomonidan YOZILGANI faqat o'sha qatorda qoladi. Bu FAQAT ko'rsatish
--    filtri (`cahVisibleRows`) — bu skriptda hech narsa o'zgarmaydi.
--
-- ============================================================================
-- QAYTARISH (rollback) — kerak bo'lsa QO'LDA, ehtiyot bo'lib:
--   -- 🔴 5b) ESKI REASSIGN MIGRATSIYASINI QAYTARISH (zaxiradan, xavfsiz):
--   --   UPDATE public.tasks t
--   --      SET assigned_to = b.old_assigned_to
--   --     FROM public.tasks_reassign_backup_8ish b
--   --    WHERE t.id = b.task_id
--   --      AND t.assigned_to IS NOT DISTINCT FROM b.new_assigned_to;
--   --   ⚠️ Oxirgi shart MAJBURIY: migratsiyadan KEYIN odam vazifani qo'lda
--   --      boshqa xodimga bergan bo'lsa, uning qarori BOSILMASIN.
--   --   Qaytargandan so'ng zaxira qatorlarini o'chirish (ixtiyoriy):
--   --   DELETE FROM public.tasks_reassign_backup_8ish;
--   DROP TRIGGER IF EXISTS zz_task_cmt_audit_trg ON public.task_comments;
--   DROP FUNCTION IF EXISTS public.task_cmt_audit();
--   DROP POLICY IF EXISTS tasks_select_acceptor ON public.tasks;   -- 4b
--   -- 🔴 quyidagi qator BUTUN IZOH TARIXINI o'chiradi — orqaga yo'l yo'q:
--   -- DROP TABLE IF EXISTS public.task_comment_history;
--   -- DROP POLICY IF EXISTS "task_cmt_update_own" ON public.task_comments;
--   -- Ustunlar (description_html / edited_at / bajardi_* / author_*) ATAYLAB
--   -- ro'yxatda yo'q: ularni tashlash ma'lumot yo'qotadi.
--   ⚠️ tasks_select_acceptor o'chirilsa qabul qiluvchi topshirilgan vazifani
--      QAYTA ko'rmay qoladi (mijoz kodi unga tayanadi).
--
-- YETIM QATORLARNI TOZALASH (ixtiyoriy, FK yo'qligi oqibati):
--   DELETE FROM public.task_comment_history h
--    WHERE NOT EXISTS (SELECT 1 FROM public.tasks t WHERE t.id = h.task_id);
--   ⚠️ Bu AUDIT MA'LUMOTINI o'chiradi — faqat ongli qaror bilan.
-- ============================================================================
