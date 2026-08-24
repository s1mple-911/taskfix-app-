-- ============================================================================
-- TASKFIX_REL_DEADLINE.sql — LOYIHA BOSQICHI UCHUN NISBIY DEADLINE (rdl*)
-- ============================================================================
-- Asilbek RUN qiladi (Supabase SQL Editor, postgres roli).
--
-- 🔴 KAM TRAFIK VAQTIDA RUN QILING (rostini aytganda):
--    ALTER TABLE ... ADD CONSTRAINT ... CHECK butun public.tasks jadvalini
--    ACCESS EXCLUSIVE qulfi ostida SKANERLAYDI. Uchala ustun ham shu
--    tranzaksiyada tug'iladi va TO'LIQ NULL bo'ladi, ya'ni skanerlash tez
--    (20k qatorda millisekundlar), LEKIN qulf davomida tasks ga har qanday
--    SELECT/INSERT/UPDATE KUTIB turadi. Katta bazada bu bir necha soniya
--    bo'lishi mumkin.
--
-- ── NIMA QILADI (ADDITIVE + IDEMPOTENT) ─────────────────────────────────────
--   public.tasks ga 3 ta ustun:
--     deadline_days  smallint — nisbiy KUN soni. 🔴 0 YAROQLI ("o'sha kuni").
--     deadline_time  text     — 'HH:MM' (24 soatlik, Asia/Tashkent).
--     deadline_hours smallint — 🔴 YANGI: nisbiy SOATLIK DAVOMIYLIK ("1 soat",
--                               "4 soat"). Kun ham, soat-vaqti ham kiritilmaydi.
--
--   🔴 UCH REJIM — AYNI PAYTDA FAQAT BITTASI (tasks_deadline_rel_pair_chk):
--     A) hammasi NULL   — ESKI usul: bosqich absolut tasks.deadline bilan ishlaydi.
--     B) days + time    — KUN + SOAT: anchor + N kun, o'sha kuni soat HH:MM da.
--                         🔴 days = 0 => "o'sha kuni soat HH:MM" — bu ESKI
--                         semantika va u O'ZGARMADI (soatlik rejim BOSHQA ma'no).
--     C) hours          — SOATLIK DAVOMIYLIK: anchor + N soat. Kun ham, soat-vaqti
--                         ham YO'Q (aks holda bitta deadline ni ikki HAR XIL manba
--                         da'vo qilardi va mijoz qaysi biri ustunligini bilmasdi).
--
--   + 4 ta CHECK:
--     tasks_deadline_days_chk      IS NULL OR 0..3650  (~10 yil)
--     tasks_deadline_time_chk      IS NULL OR '^([01][0-9]|2[0-3]):[0-5][0-9]$'
--     tasks_deadline_hours_chk     IS NULL OR 1..8760  (1 soat … 1 yil)
--     tasks_deadline_rel_pair_chk  REJIM XOR — yuqoridagi A/B/C dan AYNAN bittasi.
--       → B rejimida soat MAJBURIY: usiz absolut deadline ni hisoblab bo'lmaydi,
--         ya'ni "yarim to'ldirilgan" qator mijozda jimgina noto'g'ri sanaga
--         aylanardi. Yolg'iz soat, yolg'iz kun va aralash (days+hours) — RAD.
--   + 3 ta COMMENT ON COLUMN (ma'no bazada ham yozilgan bo'lsin).
--
--   Qayta RUN xavfsiz: ustunlar IF NOT EXISTS, CHECK'lar pg_constraint dan
--   conrelid bilan tekshiriladi (conname global unikal EMAS).
--   ⚠️ ESKI (2 ustunli) versiya ALLAQACHON RUN qilingan bazada
--      tasks_deadline_rel_pair_chk eski tanasi bilan turadi. Skript uni TANIB
--      (ta'rifida deadline_hours YO'Q, lekin days+time BOR) DROP + qayta ADD
--      qiladi — nom SAQLANADI. Begona tanani ko'rsa TEGMAYDI, EXCEPTION beradi.
--      Mavjud qatorlar buzilmaydi: yangi ta'rif eski YAROQLI holatlarning
--      hammasini (hammasi NULL / days+time) qabul qiladi.
--
-- ── 🔴 NIMA QILMAYDI (ATAYLAB) ──────────────────────────────────────────────
--   1) TRIGGER YO'Q va GENERATED COLUMN YO'Q — absolut tasks.deadline ni
--      SERVER HISOBLAMAYDI.
--      Sabab: boshlanish nuqtasi (anchor) "oldingi bosqich TUGAGANDA" bo'lishi
--      mumkin, ya'ni hisob HODISAGA bog'liq va vaqt o'tishi bilan o'zgaradi;
--      ilovada esa cron ham, EF ham YO'Q. Server tomonda trigger qo'yilsa u
--      mijozdagi rdlSync bilan POYGA qilardi (ikkovi bir ustunga yozadi, kim
--      oxirgi bo'lsa o'shanikisi qoladi) va tasks ga har UPDATE'da qo'shimcha
--      yuk tushardi. Shuning uchun absolut qiymatni MIJOZ uchta aniq nuqtada
--      yozadi: bosqich YARATILGANDA · bosqich COMPLETED/CANCELLED bo'lganda ·
--      loyiha OCHILGANDA (lazy, prjSyncLocks naqshi).
--   2) YANGI RLS POLICY YO'Q — yangi ustunlar mavjud tasks QATORINING bir
--      qismi, RLS esa QATOR darajasida ishlaydi, ya'ni mavjud policy'lar
--      ularni allaqachon qamraydi. (Skript buni 4-bo'limda TEKSHIRIB, NOTICE
--      bilan tasdiqlaydi — va ustun darajasidagi GRANT bor-yo'qligini ham
--      alohida qaraydi, chunki U meros olinmaydi.)
--   3) BACKFILL YO'Q — tasks.deadline ga BIR ZARRA tegilmaydi. Mavjud
--      bosqichlar absolut deadline bilan AVVALGIDEK ishlashda davom etadi
--      (deadline_days IS NULL = eski rejim).
--   4) Yangi jadval / funksiya / indeks / GRANT YO'Q. Indeks ataylab
--      qo'shilmadi: bu ustunlar bo'yicha FILTR yo'q — qiymat allaqachon
--      project_id bo'yicha o'qilgan bosqich qatorida keladi.
--
-- ── HAQIQAT MANBAI (o'qib bo'lsin deb takrorlanadi) ─────────────────────────
--   tasks.deadline (absolut) — YAGONA haqiqat. Butun ilova (ro'yxat, kanban,
--   kalendar, jadval, dofBadge, Telegram, email, tarix, dlh* zanjiri,
--   prjState, planner) AYNAN shu ustunni o'qiydi.
--   deadline_days + deadline_time (kun+soat) YOKI deadline_hours (soatlik
--   davomiylik) — MANBA (nisbiy retsept).
--   Anchor NOMA'LUM bo'lsa (oldingi bosqich hali tugamagan) mijoz deadline ni
--   NULL qoldiradi va ekranda nisbiy yorliq ko'rsatadi — YOLG'ON sana bazaga
--   YOZILMAYDI. ⚠️ Shu sabab tasks.deadline NULLABLE bo'lishi SHART; skript
--   buni tekshiradi va NOT NULL bo'lsa OCHIQ ogohlantiradi.
--
-- ── BUSIZ ILOVA NIMA QILADI ─────────────────────────────────────────────────
--   Hech narsa buzilmaydi. Mijoz "ustun yo'q" xatosini (42703 / PGRST204)
--   aniqlaydi → _rdlMissing = true → nisbiy maydon UMUMAN chizilmaydi va
--   bosqich yaratish/tahrirlash ESKI KALENDAR rejimiga (dlx*, sana + soat)
--   qaytadi; sabab bir marta console.error + saqlashda toast bilan ochiq
--   aytiladi (CLAUDE.md 6-qoida). Ya'ni bu fayl ISHLATILMASA ham ilova
--   hozirgidek to'liq ishlaydi.
--
-- ── BOG'LIQLIK: YO'Q ────────────────────────────────────────────────────────
--   Boshqa TASKFIX_*.sql fayllariga bog'liq emas, RUN tartibi muhim emas.
--   TASKFIX_KUTISH.sql / TASKFIX_LOYIHA*.sql bilan urishmaydi (ular boshqa
--   ustun va jadvallarga tegadi).
--
-- ── TIRIK SINOV ─────────────────────────────────────────────────────────────
--   5-bo'limda 12 ta holat HAQIQIY INSERT/UPDATE bilan sinaladi va SENTINEL-
--   ROLLBACK bilan qaytariladi — bazada BITTA qator ham qolmaydi. Bittasi
--   kutilgandek chiqmasa BUTUN migratsiya qaytadi (COMMIT bo'lmaydi).
--   ⚠️ Aniqlik: sinov qatorlari tasks.id sequence'ini bir necha pog'ona
--      siljitadi va o'lik tuple qoldiradi (VACUUM tozalaydi) — bular
--      MA'LUMOT emas, xavf yo'q.
-- ============================================================================

BEGIN;

-- ════════════════════════════════════════════════════════════════════════════
-- 0) OLD SHART — bu TaskFix bazasimi?
--    🔴 Fail-closed: mijoz moduli (rdlAnchor / rdlCompute / rdlSync) AYNAN shu
--    ustunlarni o'qiydi. Biri yo'q bo'lsa migratsiya "o'tdi" deb ko'rinib,
--    modul jimgina noto'g'ri ishlardi.
-- ════════════════════════════════════════════════════════════════════════════
DO $pre$
DECLARE
  v_miss text;
BEGIN
  IF to_regclass('public.tasks') IS NULL THEN
    RAISE EXCEPTION 'public.tasks jadvali topilmadi — bu TaskFix bazasi emasmi? Hech narsa o''zgartirilmadi.';
  END IF;

  SELECT string_agg(c, ', ') INTO v_miss
    FROM unnest(ARRAY['deadline','project_id','flow_order','status']) c
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = 'tasks'
                        AND column_name = c);
  IF v_miss IS NOT NULL THEN
    RAISE EXCEPTION 'public.tasks da kutilgan ustun(lar) YO''Q: %. Nisbiy deadline moduli shularga tayanadi (deadline = hisoblangan natija, project_id + flow_order = anchor zanjiri, status = tugagan-tugamagan ta''rifi). Migratsiya to''xtatildi — hech narsa o''zgartirilmadi.', v_miss;
  END IF;
END $pre$;

-- ════════════════════════════════════════════════════════════════════════════
-- 0b) TIP MOSLIGI — ustun ALLAQACHON boshqa tipda bo'lsa TO'XTAYMIZ
--     (jimgina davom etsak CHECK'lar boshqa ma'no kasb etardi)
-- ════════════════════════════════════════════════════════════════════════════
DO $typ$
DECLARE
  v_days  text;
  v_time  text;
  v_hours text;
BEGIN
  SELECT data_type INTO v_days FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'deadline_days';
  SELECT data_type INTO v_time FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'deadline_time';
  SELECT data_type INTO v_hours FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'deadline_hours';

  IF v_days IS NOT NULL AND v_days <> 'smallint' THEN
    RAISE EXCEPTION 'public.tasks.deadline_days ALLAQACHON mavjud, lekin tipi "%" (kutilgan: smallint). Skript uni O''ZGARTIRMAYDI (ma''lumot yo''qolishi mumkin). Qo''lda hal qiling: ustunni ko''rib chiqing yoki nomini o''zgartiring, so''ng bu skriptni qayta RUN qiling. Hech narsa o''zgartirilmadi.', v_days;
  END IF;

  IF v_time IS NOT NULL AND v_time NOT IN ('text', 'character varying') THEN
    RAISE EXCEPTION 'public.tasks.deadline_time ALLAQACHON mavjud, lekin tipi "%" (kutilgan: text). Skript uni O''ZGARTIRMAYDI. Hech narsa o''zgartirilmadi.', v_time;
  END IF;

  IF v_hours IS NOT NULL AND v_hours <> 'smallint' THEN
    RAISE EXCEPTION 'public.tasks.deadline_hours ALLAQACHON mavjud, lekin tipi "%" (kutilgan: smallint). Skript uni O''ZGARTIRMAYDI (ma''lumot yo''qolishi mumkin). Qo''lda hal qiling: ustunni ko''rib chiqing yoki nomini o''zgartiring, so''ng bu skriptni qayta RUN qiling. Hech narsa o''zgartirilmadi.', v_hours;
  END IF;

  IF v_time = 'character varying' THEN
    RAISE WARNING 'public.tasks.deadline_time tipi "character varying" (kutilgan "text"). Regex CHECK ikkalasida AYNAN bir xil ishlaydi va PostgREST ikkalasini ham satr qilib qaytaradi — shuning uchun TO''XTAMAYMIZ, lekin bu ustunni shu fayl yaratmaganini bilib qo''ying.';
  END IF;
END $typ$;

-- ════════════════════════════════════════════════════════════════════════════
-- 0c) HISOBOT JADVALLARI + O'ZGARISHDAN OLDINGI HOLAT
-- ════════════════════════════════════════════════════════════════════════════
DROP TABLE IF EXISTS pg_temp.rdl_res;
CREATE TEMP TABLE pg_temp.rdl_res (ord int, bosqich text, nom text, qiymat text, izoh text);

DROP TABLE IF EXISTS pg_temp.rdl_pre;
CREATE TEMP TABLE pg_temp.rdl_pre (k text PRIMARY KEY, v boolean);

INSERT INTO pg_temp.rdl_pre VALUES
  ('col_days', EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'deadline_days')),
  ('col_time', EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'deadline_time')),
  ('chk_days', EXISTS (SELECT 1 FROM pg_constraint
                        WHERE conname = 'tasks_deadline_days_chk' AND conrelid = 'public.tasks'::regclass)),
  ('chk_time', EXISTS (SELECT 1 FROM pg_constraint
                        WHERE conname = 'tasks_deadline_time_chk' AND conrelid = 'public.tasks'::regclass)),
  ('col_hours', EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'deadline_hours')),
  ('chk_hours', EXISTS (SELECT 1 FROM pg_constraint
                        WHERE conname = 'tasks_deadline_hours_chk' AND conrelid = 'public.tasks'::regclass)),
  -- 🔴 pair CHECK BOR, lekin ESKI (2 ustunli) tanasi bilanmi? (deadline_hours ni bilmaydi)
  ('chk_pair_old', EXISTS (SELECT 1 FROM pg_constraint
                        WHERE conname = 'tasks_deadline_rel_pair_chk' AND conrelid = 'public.tasks'::regclass
                          AND strpos(pg_get_constraintdef(oid), 'deadline_hours') = 0)),
  ('chk_pair', EXISTS (SELECT 1 FROM pg_constraint
                        WHERE conname = 'tasks_deadline_rel_pair_chk' AND conrelid = 'public.tasks'::regclass));

-- ════════════════════════════════════════════════════════════════════════════
-- 1) USTUNLAR
--    ⚠️ DEFAULT berilmaydi → jadval QAYTA YOZILMAYDI (faqat katalog yozuvi).
-- ════════════════════════════════════════════════════════════════════════════
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS deadline_days smallint;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS deadline_time text;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS deadline_hours smallint;

COMMENT ON COLUMN public.tasks.deadline_days IS
  'NISBIY DEADLINE — MANBA (faqat loyiha bosqichlari uchun ma''noli). Ma''nosi: anchor + N kun. 🔴 0 YAROQLI = anchor kunining O''ZI ("o''sha kuni"). NULL = bosqich ESKI usulda, absolut tasks.deadline bilan ishlaydi. 🔴 BOSHLANISH NUQTASI (anchor) BAZADA SAQLANMAYDI va SERVER uni HISOBLAMAYDI — u MIJOZDA (rdlAnchor) topiladi: kutish bog''lanishlari bo''lsa ularning eng kechki tugash vaqti; depends_on_prev bo''lsa oldingi bosqich (flow_order) tugash vaqti; aks holda projects.start_at (yo''q bo''lsa projects.created_at). Hisoblangan ABSOLUT natija tasks.deadline ga yoziladi (rdlSync) — tasks.deadline butun ilova uchun yagona haqiqat bo''lib qoladi.';

COMMENT ON COLUMN public.tasks.deadline_time IS
  'NISBIY DEADLINE — MANBA, "KUN + SOAT" rejimidagi soat HH:MM (24 soatlik, Asia/Tashkent). deadline_days bilan BIRGA to''ladi yoki ikkovi NULL (tasks_deadline_rel_pair_chk) — soat MAJBURIY, usiz absolut deadline ni hisoblab bo''lmaydi. 🔴 deadline_hours bilan BIRGA TO''LMAYDI (rejim XOR). Anchor noma''lum bo''lganda mijoz tasks.deadline ni NULL qoldiradi va ekranda nisbiy yorliq ko''rsatadi (yolg''on sana yozilmaydi).';

COMMENT ON COLUMN public.tasks.deadline_hours IS
  'NISBIY DEADLINE — MANBA, IKKINCHI REJIM: SOATLIK DAVOMIYLIK. Ma''nosi: anchor + N SOAT (1..8760 = 1 soat … 1 yil). Misol: "1 soat", "4 soat" — bosqich boshlanish nuqtasidan shuncha soat keyin tugashi kerak. 🔴 Bu rejimda deadline_days ham, deadline_time ham TO''LDIRILMAYDI (tasks_deadline_rel_pair_chk = rejim XOR): kun+soat va soatlik davomiylik — BIR deadline ni hisoblashning ikki HAR XIL usuli; ikkovi birga bo''lsa qaysi biri ustunligi noaniq bo''lardi. ⚠️ deadline_days = 0 BOSHQA ma''no ("o''sha kuni soat HH:MM") va u O''ZGARMADI. 🔴 Anchor BAZADA SAQLANMAYDI va SERVER uni HISOBLAMAYDI — mijozdagi rdlAnchor topadi, hisoblangan ABSOLUT natija tasks.deadline ga yoziladi (rdlSync).';

-- ════════════════════════════════════════════════════════════════════════════
-- 2) CHECK CHEKLOVLARI (TEXT + CHECK — ENUM EMAS, 30/32-migratsiyalar saboqi)
--    ⚠️ Har biri "IS NULL OR ..." shaklida → bironta MAVJUD qator buzilmaydi
--       va skript hech qanday UPDATE qilmaydi.
--    ⚠️ conname global unikal EMAS → conrelid bilan skoplangan.
-- ════════════════════════════════════════════════════════════════════════════
DO $chk$
DECLARE
  v_pair text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'tasks_deadline_days_chk'
                    AND conrelid = 'public.tasks'::regclass) THEN
    ALTER TABLE public.tasks ADD CONSTRAINT tasks_deadline_days_chk
      CHECK (deadline_days IS NULL OR (deadline_days >= 0 AND deadline_days <= 3650));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'tasks_deadline_time_chk'
                    AND conrelid = 'public.tasks'::regclass) THEN
    ALTER TABLE public.tasks ADD CONSTRAINT tasks_deadline_time_chk
      CHECK (deadline_time IS NULL OR deadline_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'tasks_deadline_hours_chk'
                    AND conrelid = 'public.tasks'::regclass) THEN
    ALTER TABLE public.tasks ADD CONSTRAINT tasks_deadline_hours_chk
      CHECK (deadline_hours IS NULL OR (deadline_hours >= 1 AND deadline_hours <= 8760));
  END IF;

  -- 🔴 REJIM XOR: A) hammasi NULL · B) days + time · C) hours — AYNAN BITTASI.
  --    Yolg'iz soat, yolg'iz kun va aralash (days+hours / time+hours) — HAMMASI RAD.
  --    ⚠️ Bu cheklov ESKI (2 ustunli) juftlik cheklovining O'RNINI oladi: NOM
  --       SAQLANADI (mijoz xato matnini nomga qarab taniydi), TANASI kengayadi.
  SELECT pg_get_constraintdef(oid) INTO v_pair
    FROM pg_constraint
   WHERE conname = 'tasks_deadline_rel_pair_chk'
     AND conrelid = 'public.tasks'::regclass;

  IF v_pair IS NULL THEN
    ALTER TABLE public.tasks ADD CONSTRAINT tasks_deadline_rel_pair_chk
      CHECK ((deadline_days IS NULL     AND deadline_time IS NULL     AND deadline_hours IS NULL)
          OR (deadline_days IS NOT NULL AND deadline_time IS NOT NULL AND deadline_hours IS NULL)
          OR (deadline_days IS NULL     AND deadline_time IS NULL     AND deadline_hours IS NOT NULL));
  ELSIF strpos(v_pair, 'deadline_hours') = 0 THEN
    -- Ta'rifda deadline_hours YO'Q → bu ESKI versiya (yoki BEGONA cheklov).
    -- 🔴 Faqat AYNAN taniganimizni almashtiramiz; boshqasiga TEGMAYMIZ.
    IF strpos(v_pair, 'deadline_days') > 0 AND strpos(v_pair, 'deadline_time') > 0 THEN
      ALTER TABLE public.tasks DROP CONSTRAINT tasks_deadline_rel_pair_chk;
      ALTER TABLE public.tasks ADD CONSTRAINT tasks_deadline_rel_pair_chk
        CHECK ((deadline_days IS NULL     AND deadline_time IS NULL     AND deadline_hours IS NULL)
            OR (deadline_days IS NOT NULL AND deadline_time IS NOT NULL AND deadline_hours IS NULL)
            OR (deadline_days IS NULL     AND deadline_time IS NULL     AND deadline_hours IS NOT NULL));
      RAISE NOTICE 'tasks_deadline_rel_pair_chk ESKI (2 ustunli) tanasi bilan turgan edi — REJIM XOR ga kengaytirildi. Mavjud qatorlar buzilmaydi: yangi ta''rif eski YAROQLI holatlarning HAMMASINI (hammasi NULL / days+time) qabul qiladi.';
    ELSE
      RAISE EXCEPTION 'tasks_deadline_rel_pair_chk MAVJUD, lekin ta''rifi BEGONA (deadline_days / deadline_time ga murojaat qilmaydi): %. Skript begona cheklovni O''ZGARTIRMAYDI — qo''lda ko''rib chiqing. HAMMASI QAYTARILDI.', v_pair;
    END IF;
  END IF;
END $chk$;

-- ════════════════════════════════════════════════════════════════════════════
-- 3) TEKSHIRUV — jimgina o'tmasin
--    (a) 3 ustun bor · (b) 4 CHECK bor · (c) CHECK TA'RIFLARI kutilganday
--        (nomi bir xil, tanasi BOSHQA bo'lgan eski cheklov shu yerda tutiladi)
-- ════════════════════════════════════════════════════════════════════════════
DO $ver$
DECLARE
  v_cols int;
  v_chks int;
  v_miss text;
  v_def  text;
BEGIN
  SELECT count(*) INTO v_cols FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'tasks'
     AND column_name IN ('deadline_days', 'deadline_time', 'deadline_hours');
  IF v_cols <> 3 THEN
    RAISE EXCEPTION 'TEKSHIRUV: 3 ustun kutilgandi, % ta topildi. HAMMASI QAYTARILDI.', v_cols;
  END IF;

  SELECT count(*) INTO v_chks FROM pg_constraint
   WHERE contype = 'c' AND conrelid = 'public.tasks'::regclass
     AND conname IN ('tasks_deadline_days_chk', 'tasks_deadline_time_chk',
                     'tasks_deadline_hours_chk', 'tasks_deadline_rel_pair_chk');
  IF v_chks <> 4 THEN
    SELECT string_agg(c, ', ') INTO v_miss FROM unnest(ARRAY[
      'tasks_deadline_days_chk', 'tasks_deadline_time_chk',
      'tasks_deadline_hours_chk', 'tasks_deadline_rel_pair_chk'
    ]) c WHERE NOT EXISTS (SELECT 1 FROM pg_constraint
                            WHERE contype = 'c' AND conname = c
                              AND conrelid = 'public.tasks'::regclass);
    RAISE EXCEPTION 'TEKSHIRUV: 4 CHECK kutilgandi, % ta topildi. Yetishmayapti: %. HAMMASI QAYTARILDI.', v_chks, coalesce(v_miss, '?');
  END IF;

  -- (c) TA'RIFLAR
  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint
   WHERE conname = 'tasks_deadline_days_chk' AND conrelid = 'public.tasks'::regclass;
  IF strpos(coalesce(v_def, ''), '3650') = 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV: tasks_deadline_days_chk MAVJUD, lekin ta''rifi kutilganidan BOSHQA (yuqori chegara 3650 topilmadi). Hozirgi ta''rif: %. Skript begona cheklovni O''ZGARTIRMAYDI — qo''lda ko''rib chiqing. HAMMASI QAYTARILDI.', coalesce(v_def, 'YO''Q');
  END IF;

  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint
   WHERE conname = 'tasks_deadline_time_chk' AND conrelid = 'public.tasks'::regclass;
  IF strpos(coalesce(v_def, ''), '[0-5][0-9]') = 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV: tasks_deadline_time_chk MAVJUD, lekin ta''rifida HH:MM regexi yo''q. Hozirgi ta''rif: %. HAMMASI QAYTARILDI.', coalesce(v_def, 'YO''Q');
  END IF;

  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint
   WHERE conname = 'tasks_deadline_hours_chk' AND conrelid = 'public.tasks'::regclass;
  IF strpos(coalesce(v_def, ''), '8760') = 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV: tasks_deadline_hours_chk MAVJUD, lekin ta''rifi kutilganidan BOSHQA (yuqori chegara 8760 topilmadi). Hozirgi ta''rif: %. Skript begona cheklovni O''ZGARTIRMAYDI — qo''lda ko''rib chiqing. HAMMASI QAYTARILDI.', coalesce(v_def, 'YO''Q');
  END IF;

  -- 🔴 REJIM XOR: ta'rif UCHALA ustunga ham murojaat qilishi SHART.
  --    Eski (2 ustunli) tana bu yerda tutiladi — u deadline_hours ni bilmagani
  --    uchun "hours + days" kabi aralash qatorni JIMGINA o'tkazib yuborardi.
  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint
   WHERE conname = 'tasks_deadline_rel_pair_chk' AND conrelid = 'public.tasks'::regclass;
  IF strpos(coalesce(v_def, ''), 'deadline_days') = 0
     OR strpos(coalesce(v_def, ''), 'deadline_time') = 0
     OR strpos(coalesce(v_def, ''), 'deadline_hours') = 0 THEN
    RAISE EXCEPTION 'TEKSHIRUV: tasks_deadline_rel_pair_chk ta''rifi UCHALA ustunga ham murojaat qilmayapti (rejim XOR ta''minlanmagan). Hozirgi ta''rif: %. HAMMASI QAYTARILDI.', coalesce(v_def, 'YO''Q');
  END IF;

  RAISE NOTICE 'TASKFIX_REL_DEADLINE: struktura OK — 3 ustun + 4 CHECK joyida (rejim XOR).';
END $ver$;

-- ════════════════════════════════════════════════════════════════════════════
-- 4) RLS / GRANT — YANGI POLICY KERAK EMASLIGINI TASDIQLAYMIZ
--    🔴 RLS QATOR darajasida ishlaydi → yangi ustun avtomat qamraladi.
--    ⚠️ LEKIN USTUN darajasidagi GRANT (masalan GRANT SELECT(a,b) ON tasks)
--       MEROS OLINMAYDI — bunday grant bo'lsa yangi ustunlar PostgREST'da
--       ko'rinmasdi. Shuning uchun alohida tekshiriladi.
-- ════════════════════════════════════════════════════════════════════════════
DO $rls$
DECLARE
  v_rls    boolean;
  v_pol    int;
  v_colacl int;
  v_names  text;
  v_dlnull boolean;
BEGIN
  SELECT relrowsecurity INTO v_rls FROM pg_class WHERE oid = 'public.tasks'::regclass;
  SELECT count(*) INTO v_pol FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'tasks';

  IF NOT coalesce(v_rls, false) THEN
    RAISE WARNING 'public.tasks da RLS YOQILMAGAN. Bu skript buni O''ZGARTIRMAYDI (uning ishi emas), lekin holat ochiq aytilsin.';
  END IF;

  -- USTUN darajasidagi GRANT (attacl). Jadval darajasidagi grant bu yerda KO'RINMAYDI.
  SELECT count(*), string_agg(attname, ', ') INTO v_colacl, v_names
    FROM pg_attribute
   WHERE attrelid = 'public.tasks'::regclass
     AND attnum > 0 AND NOT attisdropped AND attacl IS NOT NULL;

  IF coalesce(v_colacl, 0) > 0 THEN
    RAISE WARNING 'public.tasks da USTUN darajasidagi GRANT bor (%). Bunday grant YANGI ustunlarga MEROS O''TMAYDI — deadline_days / deadline_time / deadline_hours PostgREST orqali ko''rinmasligi mumkin. Kerak bo''lsa qo''lda: GRANT SELECT(deadline_days, deadline_time, deadline_hours), UPDATE(deadline_days, deadline_time, deadline_hours) ON public.tasks TO authenticated;', v_names;
  END IF;

  -- tasks.deadline NULLABLE bo'lishi SHART (anchor noma'lum bo'lganda NULL qoladi)
  SELECT (is_nullable = 'YES') INTO v_dlnull FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'deadline';
  IF NOT coalesce(v_dlnull, true) THEN
    RAISE WARNING 'public.tasks.deadline NOT NULL. Nisbiy rejimda anchor NOMA''LUM bo''lganda mijoz deadline ni NULL qoldirishi kerak (yolg''on sana yozmaslik uchun) — NOT NULL bunga yo''l qo''ymaydi va rdlSync 23502 xatosiga uriladi. Bu skript ustunni O''ZGARTIRMAYDI; qo''lda ko''rib chiqing.';
  END IF;

  INSERT INTO pg_temp.rdl_res VALUES
    (30, 'RLS', 'yangi policy', 'QO''SHILMADI (ataylab)',
     'tasks RLS: ' || CASE WHEN coalesce(v_rls, false) THEN 'yoqilgan' ELSE 'YOQILMAGAN' END ||
     ' · mavjud policy: ' || v_pol::text || ' ta. RLS QATOR darajasida ishlaydi → yangi ustunlar mavjud policy''lar bilan allaqachon qoplanadi.'),
    (31, 'GRANT', 'ustun darajasidagi GRANT (attacl)',
     CASE WHEN coalesce(v_colacl, 0) = 0 THEN 'yo''q (yaxshi)' ELSE 'BOR: ' || coalesce(v_names, '?') END,
     CASE WHEN coalesce(v_colacl, 0) = 0
          THEN 'Jadval darajasidagi grant yangi ustunlarni avtomat qamraydi — qo''shimcha GRANT kerak emas.'
          ELSE '⚠️ Ustun grantlari meros o''tmaydi — yangi ustunlar uchun qo''lda GRANT kerak bo''lishi mumkin.' END),
    (32, 'shart', 'tasks.deadline NULLABLE',
     CASE WHEN coalesce(v_dlnull, true) THEN 'ha' ELSE '🔴 YO''Q (NOT NULL)' END,
     'Anchor noma''lum bo''lganda deadline NULL qolishi kerak — yolg''on sana bazaga yozilmasin.');
END $rls$;

-- ════════════════════════════════════════════════════════════════════════════
-- 5) 🔴 TIRIK SINOV — SENTINEL-ROLLBACK bilan
--    (a) deadline_days = 0 + soat            → O'TADI  (0 = "o'sha kuni")
--    (b) deadline_days = 3 + soat NULL       → RAD     (pair CHECK)
--    (c) deadline_time = '25:00'             → RAD     (time CHECK)
--    (d) deadline_days = -1                  → RAD     (days CHECK)
--    (e) hammasi NULL                        → O'TADI  (eski qatorlar)
--    (f) mavjud vazifani oddiy yangilash     → O'TADI  (REGRESSIYA yo'q)
--    (g) deadline_days = 3651                → RAD     (yuqori chegara)
--    🔴 YANGI — SOATLIK REJIM:
--    (h) deadline_hours = 1 YOLG'IZ          → O'TADI  (C rejimi)
--    (i) deadline_hours = 0                  → RAD     (hours CHECK, quyi 1)
--    (j) deadline_hours = 8761               → RAD     (hours CHECK, yuqori 8760)
--    (k) hours + days + time BIRGA           → RAD     (pair CHECK — rejim XOR)
--    (l) hours + time (kunsiz)               → RAD     (pair CHECK — rejim XOR)
--    ⚠️ Yozuv qiladigan qism ichki blokda ATAYLAB EXCEPTION bilan tugatiladi
--       → subtranzaksiya qaytadi, bazada BITTA qator ham qolmaydi. Natijalar
--       xato MATNIDA olib chiqiladi (RDL_PROBE:...).
--    ⚠️ Hukm salbiy bo'lsa BUTUN migratsiya qaytadi (COMMIT bo'lmaydi).
-- ════════════════════════════════════════════════════════════════════════════
DO $live$
DECLARE
  v_ws        uuid;
  v_user      uuid;
  v_prj       text;
  v_prjexpr   text;
  v_real      text;
  v_realsrc   text := 'sentinel qator';
  v_prjnull   boolean;
  v_id_auto   boolean;
  v_has_title boolean;
  v_has_cb    boolean;
  v_has_asg   boolean;
  v_has_flow  boolean;
  v_has_dpp   boolean;
  v_bad       text;
  v_skip      text;
  v_tpl       text;
  v_a         text;
  v_tmp       text;
  v_cn        text;
  v_n         bigint;
  v_probe     text;
  p_a text; p_b text; p_c text; p_d text; p_e text; p_f text; p_g text;
  p_h text; p_i text; p_j text; p_k text; p_l text;
BEGIN
  -- ── (5.0) SINOV UCHUN MA'LUMOT TOPAMIZ ───────────────────────────────────
  --    ⚠️ Loyiha ham, workspace ham YARATMAYMIZ — mavjudidan foydalanamiz
  --       (majburiy ustunlarni taxmin qilib qator yozish xavfli bo'lardi).
  --    ⚠️ A'ZOSI BOR workspace tanlanadi — created_by / assigned_to ni
  --       to'ldirish uchun haqiqiy user kerak (bo'sh ws da sinov o'tmasdi).
  SELECT p.workspace_id, p.id::text INTO v_ws, v_prj
    FROM public.projects p
   WHERE EXISTS (SELECT 1 FROM public.workspace_members m
                  WHERE m.workspace_id = p.workspace_id)
   ORDER BY p.workspace_id, p.id
   LIMIT 1;

  SELECT (is_nullable = 'YES') INTO v_prjnull FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'project_id';

  IF v_ws IS NULL AND coalesce(v_prjnull, false) THEN
    -- loyiha yo'q, lekin loyihasiz vazifa yozish mumkin
    SELECT m.workspace_id INTO v_ws FROM public.workspace_members m
     ORDER BY m.workspace_id LIMIT 1;
  END IF;

  IF v_ws IS NOT NULL THEN
    SELECT m.user_id INTO v_user FROM public.workspace_members m
     WHERE m.workspace_id = v_ws ORDER BY m.user_id LIMIT 1;
  END IF;

  IF v_ws IS NULL THEN
    v_skip := 'bazada loyiha ham, workspace a''zosi ham topilmadi (bo''sh baza)';
  ELSIF v_user IS NULL THEN
    v_skip := 'workspace a''zosi topilmadi — created_by / assigned_to ni to''ldirib bo''lmaydi';
  END IF;

  SELECT (column_default IS NOT NULL OR is_identity = 'YES') INTO v_id_auto
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'id';
  IF v_skip IS NULL AND NOT coalesce(v_id_auto, false) THEN
    v_skip := 'tasks.id da DEFAULT/IDENTITY yo''q — sinov qatorining id sini skript o''ylab topa olmaydi (taxmin bilan yozmaymiz)';
  END IF;

  v_has_title := EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'title');
  v_has_cb    := EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'created_by');
  v_has_asg   := EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'assigned_to');
  v_has_flow  := EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'flow_order');
  v_has_dpp   := EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'depends_on_prev');

  IF v_skip IS NULL AND NOT v_has_title THEN
    v_skip := 'tasks.title ustuni yo''q — sinov qatorini taxmin bilan to''ldirmaymiz';
  END IF;

  -- Bilmaydigan MAJBURIY ustun bo'lsa sinov o'tkazilmaydi (23502 ga urilmasin)
  IF v_skip IS NULL THEN
    SELECT string_agg(column_name, ', ') INTO v_bad
      FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'tasks'
       AND is_nullable = 'NO' AND column_default IS NULL AND is_identity = 'NO'
       AND column_name NOT IN ('id', 'workspace_id', 'title', 'status', 'project_id',
                               'created_by', 'assigned_to', 'flow_order', 'depends_on_prev',
                               'deadline', 'deadline_days', 'deadline_time', 'deadline_hours');
    IF v_bad IS NOT NULL THEN
      v_skip := 'tasks da noma''lum majburiy ustun(lar) bor: ' || v_bad;
    END IF;
  END IF;

  IF v_skip IS NOT NULL THEN
    RAISE WARNING 'TIRIK SINOVLAR O''TKAZIB YUBORILDI — %. Struktura tekshiruvlari BAJARILDI; prodga chiqishdan oldin qo''lda sinang.', v_skip;
    INSERT INTO pg_temp.rdl_res VALUES
      (50, 'sinov', 'TIRIK SINOVLAR', 'o''tkazib yuborildi', v_skip);
    RETURN;
  END IF;

  -- ── (5.1) INSERT SHABLONI ────────────────────────────────────────────────
  --    ⚠️ %L = sarlavha, 1-%s = deadline_days, 2-%s = deadline_time,
  --       3-%s = deadline_hours.
  --       Boshqa marker YO'Q. project_id qiymati id TIPIGA bog'lanmasin deb
  --       subselect bilan beriladi; ehtiyot uchun % qochiriladi (uuid da
  --       bo'lmaydi, lekin u format() shablonining bir qismiga aylanadi).
  IF v_prj IS NOT NULL THEN
    v_prjexpr := replace('(SELECT p.id FROM public.projects p WHERE p.id::text = '
                         || quote_literal(v_prj) || ')', '%', '%%');
  ELSE
    v_prjexpr := 'NULL';
  END IF;

  v_tpl := 'INSERT INTO public.tasks (workspace_id, status, title, project_id, deadline_days, deadline_time, deadline_hours'
        || CASE WHEN v_has_flow THEN ', flow_order'      ELSE '' END
        || CASE WHEN v_has_cb   THEN ', created_by'      ELSE '' END
        || CASE WHEN v_has_asg  THEN ', assigned_to'     ELSE '' END
        || CASE WHEN v_has_dpp  THEN ', depends_on_prev' ELSE '' END
        || ') VALUES (' || quote_literal(v_ws::text) || '::uuid, ''new'', %L, ' || v_prjexpr || ', %s, %s, %s'
        --  ⚠️ flow_order har sinov qatorida BOSHQA bo'lsin: agar bazada
        --     (project_id, flow_order) bo'yicha UNIQUE indeks bo'lsa qattiq
        --     "1" ikkinchi qatordayoq 23505 berib, sinovlar ENV bo'lib
        --     o'tkazib yuborilardi.
        || CASE WHEN v_has_flow
                THEN ', (SELECT coalesce(max(t2.flow_order), 0) + 1 FROM public.tasks t2)'
                ELSE '' END
        || CASE WHEN v_has_cb   THEN ', ' || quote_literal(v_user::text) || '::uuid' ELSE '' END
        || CASE WHEN v_has_asg  THEN ', ' || quote_literal(v_user::text) || '::uuid' ELSE '' END
        || CASE WHEN v_has_dpp  THEN ', false' ELSE '' END
        || ') RETURNING id::text';

  -- ── (5.2) (f) SINOVI UCHUN NISHON — SENTINEL YOZUVDAN OLDIN TANLANADI ────
  --    🔴 Tartib MUHIM: sentinel qatorlar ham AYNAN shu workspace'ga tushadi,
  --       ya'ni keyin tanlansa "mavjud (real) vazifa" deb o'z sentinelimizni
  --       olib, hisobot YOLG'ON gapirardi (regressiya sinovi esa mavjud
  --       ma'lumotni umuman sinamagan bo'lardi).
  SELECT t.id::text INTO v_real FROM public.tasks t
   WHERE t.workspace_id = v_ws LIMIT 1;

  -- ══════════════ SENTINEL BLOK (hammasi qaytariladi) ══════════════
  --  🔴 UCH XIL NATIJA — ULARNI ARALASHTIRMASLIK ENG MUHIM QISM:
  --     'OK'      — qator yozildi
  --     'RAD:<c>' — AYNAN shu migratsiyaning CHECK'i (tasks_deadline%) to'sdi
  --     'ENV:...' — sinov MUHITI to'sdi (begona cheklov, trigger, FK, NOT NULL,
  --                 RLS...). Bu MIGRATSIYA xatosi EMAS va hukm chiqarilmaydi —
  --                 aks holda, masalan, tasks da JWT talab qiladigan trigger
  --                 borligi uchun butunlay TO'G'RI migratsiya qaytarilib
  --                 ketardi (soxta salbiy).
  BEGIN
    -- (a) 🔴 days = 0 + soat → O'TISHI SHART ("o'sha kuni")
    BEGIN
      EXECUTE format(v_tpl, 'RDL-SINOV A (sentinel, o''chadi)', '0', quote_literal('09:00'), 'NULL') INTO v_a;
      p_a := 'OK';
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
        IF coalesce(v_cn, '') LIKE 'tasks_deadline%' THEN
          p_a := 'RAD:' || v_cn;
        ELSE
          p_a := 'ENV:23514:' || coalesce(v_cn, '?');
        END IF;
      WHEN OTHERS THEN
        p_a := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
    END;

    -- (e) UCHOVI ham NULL → O'TISHI SHART (eski qatorlar naqshi)
    BEGIN
      EXECUTE format(v_tpl, 'RDL-SINOV E (sentinel, o''chadi)', 'NULL', 'NULL', 'NULL') INTO v_tmp;
      p_e := 'OK';
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
        IF coalesce(v_cn, '') LIKE 'tasks_deadline%' THEN
          p_e := 'RAD:' || v_cn;
        ELSE
          p_e := 'ENV:23514:' || coalesce(v_cn, '?');
        END IF;
      WHEN OTHERS THEN
        p_e := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
    END;

    -- (b) days bor, soat YO'Q → RAD (pair CHECK)
    BEGIN
      EXECUTE format(v_tpl, 'RDL-SINOV B (sentinel, o''chadi)', '3', 'NULL', 'NULL') INTO v_tmp;
      p_b := 'YOZILDI';
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
        IF coalesce(v_cn, '') LIKE 'tasks_deadline%' THEN
          p_b := 'RAD:' || v_cn;
        ELSE
          p_b := 'ENV:23514:' || coalesce(v_cn, '?');
        END IF;
      WHEN OTHERS THEN
        p_b := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
    END;

    -- (c) noto'g'ri soat 25:00 → RAD (time CHECK)
    BEGIN
      EXECUTE format(v_tpl, 'RDL-SINOV C (sentinel, o''chadi)', '1', quote_literal('25:00'), 'NULL') INTO v_tmp;
      p_c := 'YOZILDI';
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
        IF coalesce(v_cn, '') LIKE 'tasks_deadline%' THEN
          p_c := 'RAD:' || v_cn;
        ELSE
          p_c := 'ENV:23514:' || coalesce(v_cn, '?');
        END IF;
      WHEN OTHERS THEN
        p_c := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
    END;

    -- (d) manfiy kun -1 → RAD (days CHECK)
    BEGIN
      EXECUTE format(v_tpl, 'RDL-SINOV D (sentinel, o''chadi)', '-1', quote_literal('09:00'), 'NULL') INTO v_tmp;
      p_d := 'YOZILDI';
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
        IF coalesce(v_cn, '') LIKE 'tasks_deadline%' THEN
          p_d := 'RAD:' || v_cn;
        ELSE
          p_d := 'ENV:23514:' || coalesce(v_cn, '?');
        END IF;
      WHEN OTHERS THEN
        p_d := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
    END;

    -- (g) yuqori chegaradan oshiq 3651 → RAD (days CHECK)
    BEGIN
      EXECUTE format(v_tpl, 'RDL-SINOV G (sentinel, o''chadi)', '3651', quote_literal('09:00'), 'NULL') INTO v_tmp;
      p_g := 'YOZILDI';
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
        IF coalesce(v_cn, '') LIKE 'tasks_deadline%' THEN
          p_g := 'RAD:' || v_cn;
        ELSE
          p_g := 'ENV:23514:' || coalesce(v_cn, '?');
        END IF;
      WHEN OTHERS THEN
        p_g := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
    END;

    -- (h) 🔴 hours = 1 YOLG'IZ → O'TISHI SHART (C rejimi: anchor + 1 soat)
    BEGIN
      EXECUTE format(v_tpl, 'RDL-SINOV H (sentinel, o''chadi)', 'NULL', 'NULL', '1') INTO v_tmp;
      p_h := 'OK';
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
        IF coalesce(v_cn, '') LIKE 'tasks_deadline%' THEN
          p_h := 'RAD:' || v_cn;
        ELSE
          p_h := 'ENV:23514:' || coalesce(v_cn, '?');
        END IF;
      WHEN OTHERS THEN
        p_h := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
    END;

    -- (i) hours = 0 → RAD (hours CHECK, quyi chegara 1)
    BEGIN
      EXECUTE format(v_tpl, 'RDL-SINOV I (sentinel, o''chadi)', 'NULL', 'NULL', '0') INTO v_tmp;
      p_i := 'YOZILDI';
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
        IF coalesce(v_cn, '') LIKE 'tasks_deadline%' THEN
          p_i := 'RAD:' || v_cn;
        ELSE
          p_i := 'ENV:23514:' || coalesce(v_cn, '?');
        END IF;
      WHEN OTHERS THEN
        p_i := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
    END;

    -- (j) hours = 8761 → RAD (hours CHECK, yuqori chegara 8760 = 1 yil)
    BEGIN
      EXECUTE format(v_tpl, 'RDL-SINOV J (sentinel, o''chadi)', 'NULL', 'NULL', '8761') INTO v_tmp;
      p_j := 'YOZILDI';
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
        IF coalesce(v_cn, '') LIKE 'tasks_deadline%' THEN
          p_j := 'RAD:' || v_cn;
        ELSE
          p_j := 'ENV:23514:' || coalesce(v_cn, '?');
        END IF;
      WHEN OTHERS THEN
        p_j := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
    END;

    -- (k) 🔴 REJIM XOR: hours + days + time BIRGA → RAD (pair CHECK)
    BEGIN
      EXECUTE format(v_tpl, 'RDL-SINOV K (sentinel, o''chadi)', '3', quote_literal('09:00'), '2') INTO v_tmp;
      p_k := 'YOZILDI';
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
        IF coalesce(v_cn, '') LIKE 'tasks_deadline%' THEN
          p_k := 'RAD:' || v_cn;
        ELSE
          p_k := 'ENV:23514:' || coalesce(v_cn, '?');
        END IF;
      WHEN OTHERS THEN
        p_k := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
    END;

    -- (l) 🔴 REJIM XOR: hours + time (kunsiz) → RAD (pair CHECK)
    BEGIN
      EXECUTE format(v_tpl, 'RDL-SINOV L (sentinel, o''chadi)', 'NULL', quote_literal('09:00'), '2') INTO v_tmp;
      p_l := 'YOZILDI';
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
        IF coalesce(v_cn, '') LIKE 'tasks_deadline%' THEN
          p_l := 'RAD:' || v_cn;
        ELSE
          p_l := 'ENV:23514:' || coalesce(v_cn, '?');
        END IF;
      WHEN OTHERS THEN
        p_l := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
    END;

    -- (f) 🔴 REGRESSIYA: MAVJUD (real) vazifani oddiy yangilash AVVALGIDEK o'tadimi?
    --     "SET title = title" — qiymat o'zgarmaydi, lekin qator QAYTA YOZILADI,
    --     ya'ni Postgres UPDATE'da qatorning BARCHA CHECK'larini qayta baholaydi.
    --     Nishon 5.2 da (sentinel yozuvdan OLDIN) tanlangan; topilmagan bo'lsa
    --     sentinel qatorga tushadi (qaysi biri ekani hisobotda ochiq yoziladi).
    IF v_real IS NULL THEN
      v_real    := v_a;
      v_realsrc := 'sentinel qator (bazada boshqa vazifa topilmadi)';
    ELSE
      v_realsrc := 'mavjud (real) vazifa qatori';
    END IF;

    BEGIN
      EXECUTE 'UPDATE public.tasks SET title = title WHERE id::text = $1' USING v_real;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      IF v_n = 1 THEN
        p_f := 'OK';
      ELSE
        -- qator topilmadi = muhit masalasi, bu migratsiyaning aybi emas
        p_f := 'ENV:qator:' || v_n::text;
      END IF;
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_cn = CONSTRAINT_NAME;
        IF coalesce(v_cn, '') LIKE 'tasks_deadline%' THEN
          p_f := 'RAD:' || v_cn;
        ELSE
          p_f := 'ENV:23514:' || coalesce(v_cn, '?');
        END IF;
      WHEN OTHERS THEN
        p_f := 'ENV:' || SQLSTATE || ':' || replace(left(SQLERRM, 60), '|', '/');
    END;

    -- ⚠️ SENTINEL: subtranzaksiyani ATAYLAB qaytaramiz.
    --    ⚠️ Natijalar "|" bilan ajratiladi, shuning uchun ENV matnlaridagi
    --       "|" belgisi yuqorida "/" ga almashtirilgan (split_part siljimasin).
    RAISE EXCEPTION 'RDL_PROBE:%',
      coalesce(p_a, '?') || '|' || coalesce(p_b, '?') || '|' || coalesce(p_c, '?') || '|' ||
      coalesce(p_d, '?') || '|' || coalesce(p_e, '?') || '|' || coalesce(p_f, '?') || '|' ||
      coalesce(p_g, '?') || '|' || coalesce(p_h, '?') || '|' || coalesce(p_i, '?') || '|' ||
      coalesce(p_j, '?') || '|' || coalesce(p_k, '?') || '|' || coalesce(p_l, '?')
      USING ERRCODE = '22000';

  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'RDL_PROBE:%' THEN
      -- Harness xatosi (sinov qatorini yozib bo'lmadi) — migratsiya to'xtatilmaydi,
      -- lekin JIMGINA HAM YUTILMAYDI (CLAUDE.md 6-qoida).
      v_skip := 'sinov qatorini yozib bo''lmadi (' || SQLSTATE || '): ' || left(SQLERRM, 200);
      RAISE WARNING 'TIRIK SINOVLAR O''TKAZIB YUBORILDI — %. Struktura tekshiruvlari BAJARILDI; prodga chiqishdan oldin QO''LDA sinang.', v_skip;
      INSERT INTO pg_temp.rdl_res VALUES
        (50, 'sinov', 'TIRIK SINOVLAR', 'o''tkazib yuborildi', v_skip);
      RETURN;
    END IF;

    v_probe := replace(SQLERRM, 'RDL_PROBE:', '');
    p_a := split_part(v_probe, '|', 1);
    p_b := split_part(v_probe, '|', 2);
    p_c := split_part(v_probe, '|', 3);
    p_d := split_part(v_probe, '|', 4);
    p_e := split_part(v_probe, '|', 5);
    p_f := split_part(v_probe, '|', 6);
    p_g := split_part(v_probe, '|', 7);
    p_h := split_part(v_probe, '|', 8);
    p_i := split_part(v_probe, '|', 9);
    p_j := split_part(v_probe, '|', 10);
    p_k := split_part(v_probe, '|', 11);
    p_l := split_part(v_probe, '|', 12);

    -- ══════════════ 0) MUHIT (ENV) — HUKM CHIQARILMAYDI ══════════════
    --  🔴 Sinov qatorini yozib/yangilab bo'lmagan bo'lsa (begona cheklov,
    --     JWT talab qiladigan trigger, FK, NOT NULL...) qolgan natijalar
    --     MA'NOSIZ: (b)/(c)/(d)/(g) "rad etildi" deb ko'rinardi-yu, aslida
    --     bizning CHECK'imiz umuman ishga tushmagan bo'lardi. Bunday holda
    --     migratsiya QAYTARILMAYDI (u to'g'ri), lekin sabab OCHIQ aytiladi.
    IF p_a LIKE 'ENV:%' OR p_b LIKE 'ENV:%' OR p_c LIKE 'ENV:%' OR p_d LIKE 'ENV:%'
       OR p_e LIKE 'ENV:%' OR p_f LIKE 'ENV:%' OR p_g LIKE 'ENV:%' OR p_h LIKE 'ENV:%'
       OR p_i LIKE 'ENV:%' OR p_j LIKE 'ENV:%' OR p_k LIKE 'ENV:%' OR p_l LIKE 'ENV:%' THEN
      v_skip := 'sinov muhiti qator yozishga/yangilashga imkon bermadi (bu CHECK''lar aybi EMAS) — a=' || p_a
             || ' b=' || p_b || ' c=' || p_c || ' d=' || p_d
             || ' e=' || p_e || ' f=' || p_f || ' g=' || p_g
             || ' h=' || p_h || ' i=' || p_i || ' j=' || p_j
             || ' k=' || p_k || ' l=' || p_l;
      RAISE WARNING 'TIRIK SINOVLAR O''TKAZIB YUBORILDI — %. Struktura tekshiruvlari BAJARILDI; prodga chiqishdan oldin QO''LDA sinang.', v_skip;
      INSERT INTO pg_temp.rdl_res VALUES
        (50, 'sinov', 'TIRIK SINOVLAR', 'o''tkazib yuborildi', v_skip);
      RETURN;
    END IF;

    -- ══════════════ HUKMLAR (biri salbiy bo'lsa HAMMASI QAYTADI) ══════════════
    IF p_a <> 'OK' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (a): deadline_days = 0 + soat qabul QILINMADI (%). 0 = "o''sha kuni" — YAROQLI va eng ko''p ishlatiladigan qiymat; modulning yarmi ishlamasdi. HAMMASI QAYTARILDI.', p_a;
    END IF;

    IF p_e <> 'OK' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (e) 🔴 REGRESSIYA: uchala yangi ustun ham NULL bo''lgan qator YOZILMADI (%). Ya''ni ESKI usuldagi har qanday vazifa yaratish buzilgan bo''lardi. HAMMASI QAYTARILDI.', p_e;
    END IF;

    IF p_f <> 'OK' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (f) 🔴 REGRESSIYA: mavjud vazifani oddiy yangilash (title) ishlamadi (%). Yangi CHECK''lar butun ilovadagi har UPDATE ni yiqitgan bo''lardi. HAMMASI QAYTARILDI.', p_f;
    END IF;

    IF p_b <> 'RAD:tasks_deadline_rel_pair_chk' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (b): deadline_days = 3 + deadline_time = NULL kutilgan CHECK bilan rad etilmadi (natija: %, kutilgan: RAD:tasks_deadline_rel_pair_chk). Soat majburiyligi ta''minlanmagan — mijoz absolut deadline ni hisoblay olmaydigan "yarim" qator bazaga tushardi. HAMMASI QAYTARILDI.', p_b;
    END IF;

    IF p_c <> 'RAD:tasks_deadline_time_chk' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (c): deadline_time = 25:00 rad etilmadi (natija: %, kutilgan: RAD:tasks_deadline_time_chk). Buzuq soat mijozda NaN sanaga aylanardi. HAMMASI QAYTARILDI.', p_c;
    END IF;

    IF p_d <> 'RAD:tasks_deadline_days_chk' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (d): deadline_days = -1 rad etilmadi (natija: %, kutilgan: RAD:tasks_deadline_days_chk). Manfiy kun deadline ni anchor DAN OLDINGA surardi. HAMMASI QAYTARILDI.', p_d;
    END IF;

    IF p_g <> 'RAD:tasks_deadline_days_chk' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (g): deadline_days = 3651 rad etilmadi (natija: %, kutilgan: RAD:tasks_deadline_days_chk). Yuqori chegara (3650 kun) ishlamayapti. HAMMASI QAYTARILDI.', p_g;
    END IF;

    -- 🔴 YANGI — SOATLIK REJIM (C)
    IF p_h <> 'OK' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (h): deadline_hours = 1 YOLG''IZ qabul QILINMADI (%). Bu SOATLIK rejimning o''zi — "1 soat", "4 soat" umuman saqlanmasdi. HAMMASI QAYTARILDI.', p_h;
    END IF;

    IF p_i <> 'RAD:tasks_deadline_hours_chk' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (i): deadline_hours = 0 rad etilmadi (natija: %, kutilgan: RAD:tasks_deadline_hours_chk). 0 soat — ma''nosiz davomiylik: deadline anchor bilan AYNAN bir xil bo''lardi. HAMMASI QAYTARILDI.', p_i;
    END IF;

    IF p_j <> 'RAD:tasks_deadline_hours_chk' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (j): deadline_hours = 8761 rad etilmadi (natija: %, kutilgan: RAD:tasks_deadline_hours_chk). Yuqori chegara (8760 soat = 1 yil) ishlamayapti. HAMMASI QAYTARILDI.', p_j;
    END IF;

    IF p_k <> 'RAD:tasks_deadline_rel_pair_chk' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (k) 🔴 REJIM XOR: deadline_hours + deadline_days + deadline_time BIRGA rad etilmadi (natija: %, kutilgan: RAD:tasks_deadline_rel_pair_chk). Ikki HAR XIL retsept bitta deadline ni da''vo qilardi va mijoz qaysi biri ustunligini bilmasdi. HAMMASI QAYTARILDI.', p_k;
    END IF;

    IF p_l <> 'RAD:tasks_deadline_rel_pair_chk' THEN
      RAISE EXCEPTION 'TIRIK SINOV YIQILDI (l) 🔴 REJIM XOR: deadline_hours + deadline_time (kunsiz) rad etilmadi (natija: %, kutilgan: RAD:tasks_deadline_rel_pair_chk). Soatlik rejimda soat-vaqti MA''NOSIZ — u jimgina e''tiborsiz qolib, foydalanuvchi kiritgan qiymat yo''qolardi. HAMMASI QAYTARILDI.', p_l;
    END IF;

    INSERT INTO pg_temp.rdl_res VALUES
      (50, 'sinov', '(a) deadline_days = 0 + soat', '✅ o''tdi',
       '🔴 0 = "o''sha kuni" — YAROQLI qiymat, CHECK uni to''smaydi'),
      (51, 'sinov', '(b) days = 3, soat NULL', '✅ rad etildi',
       'tasks_deadline_rel_pair_chk — soat MAJBURIY (ikkovi birga to''ladi)'),
      (52, 'sinov', '(c) soat 25:00', '✅ rad etildi', 'tasks_deadline_time_chk (HH:MM regexi)'),
      (53, 'sinov', '(d) days = -1', '✅ rad etildi', 'tasks_deadline_days_chk (quyi chegara 0)'),
      (54, 'sinov', '(g) days = 3651', '✅ rad etildi', 'tasks_deadline_days_chk (yuqori chegara 3650, ~10 yil)'),
      (55, 'sinov', '(e) uchovi ham NULL', '✅ o''tdi', 'Eski qatorlar naqshi — REGRESSIYA yo''q'),
      (56, 'sinov', '(f) oddiy UPDATE (title)', '✅ o''tdi',
       'Nishon: ' || v_realsrc || '. UPDATE da Postgres qatorning BARCHA CHECK''larini qayta baholaydi — ya''ni yangi cheklovlar mavjud ma''lumotga zid emas'),
      (57, 'sinov', '(h) 🔴 deadline_hours = 1 yolg''iz', '✅ o''tdi',
       'SOATLIK REJIM (C): anchor + N soat. Kun ham, soat-vaqti ham kiritilmaydi'),
      (58, 'sinov', '(i) deadline_hours = 0', '✅ rad etildi', 'tasks_deadline_hours_chk (quyi chegara 1 soat)'),
      (59, 'sinov', '(j) deadline_hours = 8761', '✅ rad etildi', 'tasks_deadline_hours_chk (yuqori chegara 8760 = 1 yil)'),
      (60, 'sinov', '(k) hours + days + time birga', '✅ rad etildi',
       'tasks_deadline_rel_pair_chk — REJIM XOR: kun+soat va soatlik davomiylik BIR vaqtda bo''lmaydi'),
      (61, 'sinov', '(l) hours + time (kunsiz)', '✅ rad etildi',
       'tasks_deadline_rel_pair_chk — REJIM XOR: soatlik rejimda soat-vaqti ma''nosiz, jimgina yo''qolmasin'),
      (62, 'sinov', 'SENTINEL-ROLLBACK', '✅ toza',
       'Sinov qatorlari subtranzaksiya bilan QAYTARILDI — bazada bitta qator ham qolmadi (sequence bir necha pog''ona siljigan bo''lishi mumkin, bu ma''lumot emas)');

    RAISE NOTICE 'TIRIK SINOVLAR O''TDI — sentinel-rollback: bazada bitta qator ham QOLMADI.';
  END;
END $live$;

-- ════════════════════════════════════════════════════════════════════════════
-- 6) YAKUNIY HISOBOT
-- ════════════════════════════════════════════════════════════════════════════
DO $rep$
DECLARE
  v_pre_days  boolean;
  v_pre_time  boolean;
  v_pre_hours boolean;
  v_pre_cd    boolean;
  v_pre_ct    boolean;
  v_pre_ch    boolean;
  v_pre_cp    boolean;
  v_pre_cpold boolean;
  v_skipn     int;
BEGIN
  SELECT v INTO v_pre_days  FROM pg_temp.rdl_pre WHERE k = 'col_days';
  SELECT v INTO v_pre_time  FROM pg_temp.rdl_pre WHERE k = 'col_time';
  SELECT v INTO v_pre_hours FROM pg_temp.rdl_pre WHERE k = 'col_hours';
  SELECT v INTO v_pre_cd    FROM pg_temp.rdl_pre WHERE k = 'chk_days';
  SELECT v INTO v_pre_ct    FROM pg_temp.rdl_pre WHERE k = 'chk_time';
  SELECT v INTO v_pre_ch    FROM pg_temp.rdl_pre WHERE k = 'chk_hours';
  SELECT v INTO v_pre_cp    FROM pg_temp.rdl_pre WHERE k = 'chk_pair';
  SELECT v INTO v_pre_cpold FROM pg_temp.rdl_pre WHERE k = 'chk_pair_old';

  INSERT INTO pg_temp.rdl_res VALUES
    (1, 'ustun', 'public.tasks.deadline_days (smallint)',
     CASE WHEN coalesce(v_pre_days, false) THEN 'allaqachon bor edi' ELSE 'QO''SHILDI' END,
     '🔴 MANBA: anchor + N kun. 0 YAROQLI ("o''sha kuni"). NULL = eski (absolut) rejim. Anchor MIJOZDA hisoblanadi.'),
    (2, 'ustun', 'public.tasks.deadline_time (text)',
     CASE WHEN coalesce(v_pre_time, false) THEN 'allaqachon bor edi' ELSE 'QO''SHILDI' END,
     'MANBA: "KUN + SOAT" rejimidagi HH:MM (Asia/Tashkent). Soat MAJBURIY — usiz absolut deadline hisoblanmaydi.'),
    (3, 'ustun', '🔴 public.tasks.deadline_hours (smallint)',
     CASE WHEN coalesce(v_pre_hours, false) THEN 'allaqachon bor edi' ELSE 'QO''SHILDI' END,
     '🔴 YANGI REJIM — SOATLIK DAVOMIYLIK: anchor + N soat ("1 soat", "4 soat"). Kun ham, soat-vaqti ham kiritilmaydi. deadline_days = 0 ("o''sha kuni soat HH:MM") BOSHQA ma''no va u O''ZGARMADI.'),
    (10, 'CHECK', 'tasks_deadline_days_chk',
     CASE WHEN coalesce(v_pre_cd, false) THEN 'allaqachon bor edi' ELSE 'QO''SHILDI' END,
     'IS NULL OR (0 <= deadline_days <= 3650) — 0 KIRADI, manfiy va ~10 yildan oshiq kirmaydi'),
    (11, 'CHECK', 'tasks_deadline_time_chk',
     CASE WHEN coalesce(v_pre_ct, false) THEN 'allaqachon bor edi' ELSE 'QO''SHILDI' END,
     'IS NULL OR HH:MM regexi — mavjud recur_time bilan AYNAN bir xil shakl'),
    (12, 'CHECK', 'tasks_deadline_hours_chk',
     CASE WHEN coalesce(v_pre_ch, false) THEN 'allaqachon bor edi' ELSE 'QO''SHILDI' END,
     'IS NULL OR (1 <= deadline_hours <= 8760) — 1 soatdan 1 yilgacha. 0 KIRMAYDI (ma''nosiz davomiylik).'),
    (13, 'CHECK', '🔴 tasks_deadline_rel_pair_chk (REJIM XOR)',
     CASE WHEN coalesce(v_pre_cpold, false) THEN 'ESKI tanasi KENGAYTIRILDI (DROP + qayta ADD, nom saqlandi)'
          WHEN coalesce(v_pre_cp, false)    THEN 'allaqachon bor edi'
          ELSE 'QO''SHILDI' END,
     'A) hammasi NULL · B) days + time · C) hours — AYNAN BITTASI. Yolg''iz soat, yolg''iz kun va aralash (days+hours / time+hours) TO''SILADI. Mavjud qatorlar buzilmaydi — eski YAROQLI holatlarning hammasi qabul qilinadi.'),
    (20, 'qaror', '🔴 TRIGGER / GENERATED COLUMN', 'YO''Q (ataylab)',
     'Absolut deadline ni SERVER hisoblamaydi: anchor "oldingi bosqich TUGAGANDA" bo''lgani uchun hisob HODISAGA bog''liq, ilovada esa cron/EF YO''Q. Trigger mijozdagi rdlSync bilan poyga qilardi va har UPDATE''ga yuk bo''lardi. Mijoz 3 nuqtada yozadi: yaratish · bosqich tugashi · loyiha ochilishi.'),
    (21, 'qaror', 'tasks.deadline (absolut)', 'TEGILMADI',
     'Backfill YO''Q. U butun ilova uchun yagona haqiqat manbai bo''lib qoladi; nisbiy qiymat — faqat MANBA (retsept).'),
    (22, 'qaror', 'indeks', 'QO''SHILMADI',
     'Bu ustunlar bo''yicha FILTR yo''q — qiymat allaqachon project_id bo''yicha o''qilgan bosqich qatorida keladi.'),
    (23, 'qaror', '🔴 deadline_days = 0 semantikasi', 'O''ZGARMADI',
     '0 = "o''sha kuni soat HH:MM" (B rejimi). Soatlik rejim (C) — BUTUNLAY BOSHQA ma''no: anchor + N soat. Ikkovi bir vaqtda bo''lmaydi (rejim XOR).');

  SELECT count(*) INTO v_skipn FROM pg_temp.rdl_res
   WHERE bosqich = 'sinov' AND qiymat LIKE 'o''tkazib%';

  INSERT INTO pg_temp.rdl_res VALUES
    (99, 'XULOSA',
     CASE WHEN v_skipn = 0 THEN '✅ TIRIK SINOVLAR TO''LIQ BAJARILDI'
          ELSE '🔴 DIQQAT: TIRIK SINOVLAR O''TKAZIB YUBORILDI' END,
     CASE WHEN v_skipn = 0 THEN '12/12' ELSE '0/12' END,
     CASE WHEN v_skipn = 0
          THEN 'Har bir hukm chiqarildi; birortasi salbiy bo''lsa skript COMMIT QILMAGAN bo''lardi. Sinov qatorlari qaytarildi.'
          ELSE '⚠️ Migratsiya COMMIT BO''LDI (struktura to''g''ri), lekin sinovlar bajarilmadi — sabab "sinov" qatorida yozilgan. Prodga chiqishdan oldin QO''LDA sinang.' END);

  IF v_skipn > 0 THEN
    RAISE WARNING 'Tirik sinovlar o''tkazib yuborildi — migratsiya baribir COMMIT bo''ldi. Yakuniy jadvalning XULOSA qatoriga qarang.';
  END IF;

  RAISE NOTICE 'TASKFIX_REL_DEADLINE TUGADI — pastdagi jadvalga qarang.';
END $rep$;

COMMIT;

-- PostgREST sxema keshini yangilash (Supabase'da odatda event trigger o'zi
-- qiladi; bu qator kafolat uchun — zararsiz va idempotent).
NOTIFY pgrst, 'reload schema';


-- ══════════ NATIJA ══════════
SELECT bosqich, nom, qiymat, izoh FROM pg_temp.rdl_res ORDER BY ord;


-- ============================================================================
-- QANDAY O'QISH
-- ============================================================================
--  • Barcha "sinov" qatorlari ✅ bo'lsa ish bitdi.
--  • "allaqachon bor edi" — skript ikkinchi marta RUN qilingan (yoki ustun
--    boshqa yo'l bilan qo'shilgan). Bu XATO emas.
--  • 🔴 ENG MUHIM QATORLAR: (a) 0 yaroqli · (e) va (f) REGRESSIYA yo'q ·
--    (b) soat majburiy · (h) soatlik rejim ishlaydi · (k)/(l) rejim XOR
--    (aralash retsept jimgina yozilib qolmasin).
--    ⚠️ ANIQLIK: hukm chiqarilib salbiy bo'lsa skript COMMIT QILMAYDI. LEKIN
--    sinov UMUMAN o'tkazilmagan bo'lishi ham mumkin (bo'sh baza / tasks da
--    noma'lum majburiy ustun / id da DEFAULT yo'q / sinov qatorini BEGONA
--    cheklov yoki trigger to'sdi = "ENV:") — u holda migratsiya WARNING bilan
--    COMMIT BO'LADI. Shuning uchun ENG OXIRGI "XULOSA" qatoriga qarang: u
--    sinovlar bajarilgan-bajarilmaganini OCHIQ aytadi.
--  • "ENV:" prefiksi — muhit to'sdi, YANGI CHECK'lar emas. Bu farq ataylab
--    qilingan: aks holda tasks dagi begona trigger tufayli mutlaqo to'g'ri
--    migratsiya soxta salbiy bilan qaytarilib ketardi.
--  • WARNING'lar (agar chiqsa): ustun darajasidagi GRANT · tasks.deadline
--    NOT NULL · deadline_time varchar. Ular migratsiyani to'xtatmaydi, lekin
--    e'tibor talab qiladi.
--
-- ── RUN'DAN KEYIN — MIJOZ TOMONIDA (boshqa agent) ───────────────────────────
--   rdlAnchor(t, list, project) → rdlCompute(anchorMs, days, time, hours) → rdlSync()
--   yagona choke-point bo'lib tasks.deadline ni yozadi ({error} + .select()).
--   🔴 UCHINCHI ARGUMENT: deadline_hours bo'lsa natija = anchor + hours*3600000
--   (kun/soat-vaqti umuman qaralmaydi); aks holda eski kun+soat yo'li.
--   Mijoz UCHALA ustunni ham BIRGA yozadi/tozalaydi — rejim almashtirilganda
--   eski rejim ustunlari NULL ga qaytarilishi SHART, aks holda
--   tasks_deadline_rel_pair_chk (23514) qaytaradi va saqlash yiqiladi.
--   Anchor NOMA'LUM bo'lsa deadline NULL qoladi — yolg'on sana yozilmaydi.
--
-- ============================================================================
-- QAYTARISH (kerak bo'lsa — mijoz ularsiz ham ishlaydi, _rdlMissing):
--   ALTER TABLE public.tasks DROP COLUMN IF EXISTS deadline_days;
--   ALTER TABLE public.tasks DROP COLUMN IF EXISTS deadline_time;
--   ALTER TABLE public.tasks DROP COLUMN IF EXISTS deadline_hours;
--   (4 CHECK ustunlar bilan birga o'chadi)
--   ⚠️ Bu nisbiy RETSEPTNI o'chiradi; allaqachon HISOBLANIB tasks.deadline ga
--      yozilgan absolut sanalar JOYIDA QOLADI (ular alohida ustun).
-- ============================================================================
