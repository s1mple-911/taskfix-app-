-- ============================================================
-- cleanup_duplicate_staff.sql
-- Import yaratgan DUBLIKAT akkauntlarni asl akkauntga birlashtirish.
--
-- ⚠️ BU MIGRATSIYA EMAS — bir martalik tozalash, shuning uchun raqamsiz.
--
-- TALAB QILADI: 45_staff_phone_lookup.sql (norm_phone_digits) — u HALI
--               ISHGA TUSHIRILMAGAN. Avval o'sha, keyin bu.
--
-- MUAMMO:
--   Import mavjud odamni faqat sintetik email bo'yicha qidirgan. Haqiqiy
--   emaili bor odam topilmagan → unga ikkinchi akkaunt yaratilgan:
--     asl:   feruzbek2295002@gmail.com          (roli: admin — TEGILMAGAN)
--     soxta: 998930702425@staff.taskfix.org     (roli: member, HR ma'lumoti shunda)
--
-- ⚠️ ROL HAQIDA: import rolni PASAYTIRMAGAN.
--    Ishga tushgan import v2 edi, u upsert(ignoreDuplicates: true) ishlatgan →
--    PostgREST buni ON CONFLICT DO NOTHING ga aylantiradi, ya'ni mavjud a'zoning
--    qatoriga umuman tegmagan. (v3 buni SELECT+INSERT ga almashtirdi —
--    index.ts:473-489 — xatti-harakat o'sha, lekin endi kodning o'zidan
--    ko'rinib turadi. v3 hali DEPLOY QILINMAGAN.)
--    Bu skript ham asl qatorning roliga TEGMAYDI — faqat soxta qatorni
--    o'chiradi. 2-BOSQICHDAGI B so'rovi buni tekshiradi.
--
-- ISHLATISH:
--   1-BOSQICH — juftliklarni ko'rish       (faqat SELECT, hech narsa o'zgarmaydi)
--   2-BOSQICH — nazorat so'rovlari         (faqat SELECT)
--   3-BOSQICH — to'liq skanerlash          (faqat SELECT — inventarni ISBOTLAYDI)
--   4-BOSQICH — QO'LLASH                   (⚠️ YOZADI — oxirida, alohida)
--   5-BOSQICH — rasm                       (SQL QILA OLMAYDI — pastga qarang)
--
-- Har bosqichni ALOHIDA ishga tushiring va natijasini o'qing.
-- ============================================================

-- ⚠️⚠️ WORKSPACE ID — har bosqichda shu qiymatni qo'ying ⚠️⚠️
--    SELECT id, name FROM workspaces;

-- ============================================================
-- 0) Yordamchi: ism normalizatsiyasi (juftlikni TASDIQLASH uchun)
-- ============================================================
-- Nega kerak: telefon mos bo'lishi YETARLI EMAS. profiles.phone — erkin matn
-- (index.html:3483, 10351, 9836 — faqat .trim()), ya'ni terish xatosi bo'lishi
-- mumkin. Telefon mos + ism boshqa → bu IKKI BOSHQA ODAM. Ularni birlashtirsak,
-- qaytarib ajratib bo'lmaydi.
--
-- index.html:10606 hrNormName ning SODDALASHTIRILGAN varianti:
--   • kichik harfga
--   • kirill homoglif → lotin (HR_CYR_HOMOGLYPH, index.html:10598-10601)
--   • apostrof butunlay tashlanadi (O'ral / Oral / O’ral — bir xil sanalsin)
--   • ortiqcha bo'shliq yig'ishtiriladi
-- Bu FAQAT solishtirish uchun — hech qayerga yozilmaydi.
CREATE OR REPLACE FUNCTION cleanup_norm_name(p TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT btrim(regexp_replace(
    regexp_replace(
      translate(lower(coalesce(p, '')), 'авекмнорстухѕіј', 'abekmhopctyxsij'),
      '[''`‘’ʼʻ՚′]', '', 'g'),
    '\s+', ' ', 'g'));
$$;

-- ============================================================
-- 0b) Juftlik topuvchi — hamma bosqich shunga tayanadi
-- ============================================================
-- Soxta = staff_import_map da bor + emaili @staff.taskfix.org
-- Asl   = SHU workspace ning boshqa a'zosi, telefoni MOS, emaili sintetik EMAS
--
-- Telefon manbai — staff_import_map.phone_e164 (EF yozgan, ishonchli),
-- soxta profilning telefoni EMAS.
CREATE OR REPLACE FUNCTION dup_pairs(p_ws UUID)
RETURNS TABLE (
  source_id   TEXT,
  digits      TEXT,
  fake_uid    UUID,
  fake_email  TEXT,
  fake_name   TEXT,
  real_uid    UUID,
  real_email  TEXT,
  real_name   TEXT,
  real_role   TEXT,
  name_match  BOOLEAN,
  rivals      BIGINT      -- shu soxta akkauntga nechta asl nomzod topildi
)
LANGUAGE sql
STABLE
AS $$
  -- ── Qo'lda TASDIQLANGAN juftliklar ──────────────────────────
  -- Avto-topuvchi (cand, pastda) FAQAT telefon mos kelganda topadi. Ba'zi
  -- juftliklarni u KO'RA OLMAYDI: haqiqiy akkauntda profiles.phone bo'sh, yoki
  -- ism mos emas. Bunday juftliklar shu yerga QO'LDA yoziladi — har birini odam
  -- tasdiqlagan. Format: ('<soxta_uid>'::uuid, '<haqiqiy_uid>'::uuid).
  WITH manual(fake_uid, real_uid) AS (
    VALUES
      ('1bde234c-a278-400f-b6e9-1ac82ea308d0'::uuid, 'e3d0a4fb-849e-48c8-b5d5-c8086302ec99'::uuid)  -- Akobir (haqiqiyda telefon yo'q, ism mos emas)
      -- Keyingi tasdiqlangan juftliklarni shu yerga qo'shing:
      -- , ('<soxta_uid>'::uuid, '<haqiqiy_uid>'::uuid)  -- Izoh
  ),
  fake AS (
    SELECT m.source_id, m.user_id AS uid, m.phone_e164,
           norm_phone_digits(m.phone_e164) AS digits,
           fu.email::TEXT AS email, fp.full_name AS full_name
    FROM staff_import_map m
    JOIN auth.users fu ON fu.id = m.user_id
    LEFT JOIN profiles fp ON fp.id = m.user_id
    -- source_system qattiq yozilgan: bu skript FAQAT aros_staff importi uchun.
    -- PK (workspace_id, source_system, source_id) — 40:83.
    WHERE m.workspace_id = p_ws
      AND m.source_system = 'aros_staff'
      AND fu.email LIKE '%@staff.taskfix.org'
  ),
  cand AS (
    SELECT f.source_id, f.digits, f.uid AS fake_uid, f.email AS fake_email,
           f.full_name AS fake_name,
           rwm.user_id AS real_uid, ru.email::TEXT AS real_email,
           rp.full_name AS real_name, rwm.role::TEXT AS real_role,
           count(*) OVER (PARTITION BY f.uid) AS rivals
    FROM fake f
    JOIN workspace_members rwm
      ON rwm.workspace_id = p_ws AND rwm.user_id <> f.uid
    JOIN auth.users ru ON ru.id = rwm.user_id
    JOIN profiles   rp ON rp.id = rwm.user_id
    WHERE f.digits IS NOT NULL
      AND ru.email NOT LIKE '%@staff.taskfix.org'
      AND norm_phone_digits(rp.phone) = f.digits
  )
  -- ⚠️ Hamma ustun 'cand.' bilan belgilanadi: RETURNS TABLE ustunlari OUT
  -- parametr sifatida shu yerda ko'rinadi, belgilamasak "column reference is
  -- ambiguous" xatosi chiqadi.
  -- Avto-topilgan juftliklar (qo'lda ro'yxatdagilarni CHIQARIB tashlaymiz — takror bo'lmasin)
  SELECT cand.source_id, cand.digits, cand.fake_uid, cand.fake_email, cand.fake_name,
         cand.real_uid, cand.real_email, cand.real_name, cand.real_role,
         cleanup_norm_name(cand.fake_name) = cleanup_norm_name(cand.real_name)
           AND cand.fake_name IS NOT NULL,
         cand.rivals
  FROM cand
  WHERE cand.fake_uid NOT IN (SELECT mm.fake_uid FROM manual mm)
  UNION ALL
  -- Qo'lda tasdiqlangan juftliklar: name_match := true, rivals := 1 (inson tasdiqlagan).
  -- Ikkala uid ham shu workspace'da bo'lishi shart (aks holda JOIN qator qaytarmaydi).
  SELECT fm.source_id, fm.digits, man.fake_uid, fm.email, fm.full_name,
         man.real_uid, ru.email::TEXT, rp.full_name, rwm.role::TEXT,
         TRUE, 1::BIGINT
  FROM manual man
  JOIN fake fm            ON fm.uid = man.fake_uid
  JOIN workspace_members rwm ON rwm.workspace_id = p_ws AND rwm.user_id = man.real_uid
  JOIN auth.users ru      ON ru.id = man.real_uid
  LEFT JOIN profiles rp   ON rp.id = man.real_uid;
$$;


-- ============================================================
-- 1-BOSQICH — Juftliklar (faqat o'qish)
-- ============================================================
-- Har qatorni KO'Z BILAN tekshiring: fake_name va real_name bir odammi?
--
--   name_match = true,  rivals = 1  → xavfsiz, 4-bosqich ko'chiradi
--   name_match = false               → ⚠️ TEGILMAYDI. Ikki boshqa odam bo'lishi mumkin.
--   rivals > 1                       → ⚠️ TEGILMAYDI. Telefon bir necha akkauntda.
SELECT * FROM dup_pairs('<WS_ID>') ORDER BY name_match DESC, rivals, real_name;

-- Juftlik topilmagan soxta akkauntlar (asl akkaunti yo'q — ya'ni haqiqatan
-- yangi hodim, yoki asl akkauntning profiles.phone maydoni bo'sh).
-- Bular NORMAL — 126 dan aksari shunday bo'lishi kerak.
SELECT m.source_id, u.email, p.full_name, p.phone
FROM staff_import_map m
JOIN auth.users u ON u.id = m.user_id
LEFT JOIN profiles p ON p.id = m.user_id
WHERE m.workspace_id = '<WS_ID>'
  AND u.email LIKE '%@staff.taskfix.org'
  AND NOT EXISTS (SELECT 1 FROM dup_pairs('<WS_ID>') d WHERE d.fake_uid = m.user_id)
ORDER BY m.source_id::INT;


-- ============================================================
-- 2-BOSQICH — Nazorat so'rovlari
-- ============================================================

-- A) HAL QILUVCHI: Feruzbekning soxta akkaunti bormi?
--    Qator BOR  → dublikat gipotezasi tasdiqlandi
--    Qator YO'Q → gipoteza QULAYDI, bu skript kerak emas, import hisobotini qayta ko'ring
SELECT id, email, phone, created_at FROM auth.users
WHERE email = '998930702425@staff.taskfix.org';

-- B) Rol zarari BO'LGANMI (kutilgan: 0 qator)
--    Import faqat YANGI akkaunt yaratgan bo'lsa, hammasi 'member' bo'lishi kerak.
--    Bu yerda admin/owner chiqsa — mavjud akkauntga tegilgan, tekshirish kerak.
SELECT wm.user_id, u.email, wm.role
FROM staff_import_map m
JOIN workspace_members wm ON wm.workspace_id = m.workspace_id AND wm.user_id = m.user_id
JOIN auth.users u ON u.id = m.user_id
WHERE m.workspace_id = '<WS_ID>' AND wm.role <> 'member';

-- C) Hech bir MAVJUD akkauntga tegilmaganini ISBOTLAYDI.
--    created_in_run=true va created_at ≈ import vaqti bo'lsa — rol pasayishi
--    fizik jihatdan sodir bo'lmagan (yangi akkauntning eski roli yo'q).
SELECT m.created_in_run, count(*) AS n,
       min(u.created_at) AS eng_eski, max(u.created_at) AS eng_yangi
FROM staff_import_map m JOIN auth.users u ON u.id = m.user_id
WHERE m.workspace_id = '<WS_ID>'
GROUP BY m.created_in_run;


-- ============================================================
-- 3-BOSQICH — To'liq skanerlash (faqat o'qish)
-- ============================================================
-- ⚠️ NEGA BU KERAK: migratsiyalar 1-37 repoda YO'Q. tasks/profiles/
--    workspace_members sxemalari to'liq ma'lum emas. Qo'lda tuzilgan ro'yxatga
--    ishonish o'rniga — public sxemadagi HAR BIR uuid ustunini skanerlaymiz.
--    4-bosqich ro'yxati SHU natija bilan solishtirilishi SHART.
--
-- Kutilgan natija (soxta akkaunt bugun yaratilgan, hech qachon kirmagan):
--   employee_details, employee_branches, employee_schedule_days,
--   staff_import_map, workspace_members, profiles, va EHTIMOL
--   branches.manager_user_id (import 6-fazasi, index.html:11464)
--
-- Boshqa nom chiqsa — 4-bosqichni ISHGA TUSHIRMANG, avval menga ko'rsating.
CREATE OR REPLACE FUNCTION dup_scan(p_ws UUID)
RETURNS TABLE (tbl TEXT, col TEXT, fake_uid UUID, n BIGINT)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  r RECORD;
  f RECORD;
  cnt BIGINT;
BEGIN
  FOR f IN SELECT DISTINCT d.fake_uid AS uid FROM dup_pairs(p_ws) d LOOP
    FOR r IN
      SELECT ic.table_name AS tname, ic.column_name AS cname
      FROM information_schema.columns ic
      JOIN information_schema.tables it
        ON it.table_schema = ic.table_schema
       AND it.table_name   = ic.table_name
       AND it.table_type   = 'BASE TABLE'
      WHERE ic.table_schema = 'public' AND ic.data_type = 'uuid'
    LOOP
      EXECUTE format('SELECT count(*) FROM public.%I WHERE %I = $1', r.tname, r.cname)
        INTO cnt USING f.uid;
      IF cnt > 0 THEN
        tbl := r.tname; col := r.cname; fake_uid := f.uid; n := cnt;
        RETURN NEXT;
      END IF;
    END LOOP;
  END LOOP;
END;
$$;

SELECT tbl, col, count(DISTINCT fake_uid) AS nechta_hodim, sum(n) AS jami_qator
FROM dup_scan('<WS_ID>')
GROUP BY tbl, col
ORDER BY tbl, col;

-- Matn ustunlarida yashiringan uid (uuid tipida emas — skaner ko'rmaydi):
--   activity_logs.entity_id  — entity_type='employee' bo'lganda user uid saqlaydi
SELECT 'activity_logs.entity_id' AS joy, count(*) AS n
FROM activity_logs a
WHERE a.entity_type = 'employee'
  AND a.entity_id IN (SELECT DISTINCT fake_uid::TEXT FROM dup_pairs('<WS_ID>'));

-- Polimorf: org_containers.parent_id faqat parent_kind='user' bo'lganda user uid
SELECT 'org_containers.parent_id' AS joy, count(*) AS n
FROM org_containers o
WHERE o.parent_kind = 'user'
  AND o.parent_id IN (SELECT DISTINCT fake_uid FROM dup_pairs('<WS_ID>'));


-- ============================================================
-- 4-BOSQICH — QO'LLASH  ⚠️ YOZADI
-- ============================================================
-- OLDIN:
--   ✓ 1-bosqich juftliklarini ko'z bilan tasdiqladingiz
--   ✓ 3-bosqich kutilmagan jadval chiqarmadi
--   ✓ DB backup / PITR nuqtasi bor
--
-- Faqat name_match=true VA rivals=1 juftliklar ko'chiriladi. Qolganlariga
-- TEGILMAYDI (kelishilgan: to'qnashuvda to'xtaydi, jimgina tanlamaydi).
--
-- BITTA TRANZAKSIYA: birorta to'qnashuv chiqsa — HAMMASI ORQAGA QAYTADI.
-- v_dry_run = true bo'lsa oxirida ataylab ROLLBACK qilinadi.
--
-- ⚠️ NATIJANI QANDAY O'QISH (Supabase muharriri NOTICE ni ko'rsatmasligi mumkin —
--    shuning uchun XATO MATNIGA qarang, u har doim ko'rinadi):
--
--    "DRY RUN — hech narsa saqlanmadi"  → ✓ TO'QNASHUV YO'Q. Hamma UPDATE
--                                          muvaffaqiyatli o'tdi va qaytarildi.
--                                          Endi v_dry_run := false qilib qayta yurgizing.
--    "TO'QNASHUV: <ism> — ..."          → ✗ O'sha odamni qo'lda hal qiling.
--                                          Hech narsa yozilmadi.
--    Boshqa xato                        → ✗ Menga ko'rsating. Hech narsa yozilmadi.
--
--    Ya'ni dry-run'ning MUVAFFAQIYATI xato ko'rinishida keladi. Bu ataylab:
--    DO bloki natija jadvali qaytara olmaydi, xato esa hech qachon yo'qolmaydi.

DO $$
DECLARE
  v_ws      UUID    := '<WS_ID>';     -- ⚠️ TO'LDIRING
  v_dry_run BOOLEAN := true;          -- ⚠️ false = HAQIQATAN yozadi
  p         RECORD;
  v_moved   INT := 0;
  v_pairs   INT := 0;
BEGIN
  FOR p IN
    SELECT * FROM dup_pairs(v_ws) WHERE name_match AND rivals = 1
  LOOP
    v_pairs := v_pairs + 1;
    RAISE NOTICE '— % : % → %', p.real_name, p.fake_email, p.real_email;

    -- Asl akkauntda ALLAQACHON qator bo'lsa → to'qnashuv → butun tranzaksiya yiqiladi.
    -- ATAYLAB: jimgina tanlash o'rniga to'xtab, odamga ko'rsatamiz.
    -- Uchala jadvalning ham PK'si user_id ni o'z ichiga oladi (39:136, 39:185,
    -- 41:82), ya'ni tekshirmasak UPDATE 23505 bilan tushunarsiz yiqilardi.
    IF EXISTS (SELECT 1 FROM employee_details WHERE workspace_id = v_ws AND user_id = p.real_uid) THEN
      RAISE EXCEPTION 'TO''QNASHUV: % (%) — asl akkauntda employee_details allaqachon bor. Qo''lda hal qiling.',
        p.real_name, p.real_email;
    END IF;
    IF EXISTS (SELECT 1 FROM employee_branches WHERE workspace_id = v_ws AND user_id = p.real_uid) THEN
      RAISE EXCEPTION 'TO''QNASHUV: % (%) — asl akkauntda employee_branches allaqachon bor. Qo''lda hal qiling.',
        p.real_name, p.real_email;
    END IF;
    IF EXISTS (SELECT 1 FROM employee_schedule_days WHERE workspace_id = v_ws AND user_id = p.real_uid) THEN
      RAISE EXCEPTION 'TO''QNASHUV: % (%) — asl akkauntda employee_schedule_days allaqachon bor. Qo''lda hal qiling.',
        p.real_name, p.real_email;
    END IF;
    IF EXISTS (SELECT 1 FROM staff_import_map
                WHERE workspace_id = v_ws AND source_system = 'aros_staff'
                  AND user_id = p.real_uid AND source_id <> p.source_id) THEN
      RAISE EXCEPTION 'TO''QNASHUV: % (%) — asl akkaunt boshqa source_id ga allaqachon bog''langan (UNIQUE, 40:87). Qo''lda hal qiling.',
        p.real_name, p.real_email;
    END IF;

    -- ---- HR ma'lumoti: soxta → asl ----
    UPDATE employee_details       SET user_id = p.real_uid WHERE workspace_id = v_ws AND user_id = p.fake_uid;
    UPDATE employee_branches      SET user_id = p.real_uid WHERE workspace_id = v_ws AND user_id = p.fake_uid;
    UPDATE employee_schedule_days SET user_id = p.real_uid WHERE workspace_id = v_ws AND user_id = p.fake_uid;
    UPDATE employee_links         SET user_id = p.real_uid WHERE workspace_id = v_ws AND user_id = p.fake_uid;

    -- ---- Filial manageri (import 6-fazasi, index.html:11464) ----
    UPDATE branches         SET manager_user_id = p.real_uid WHERE workspace_id = v_ws AND manager_user_id = p.fake_uid;
    UPDATE workspace_members SET manager_user_id = p.real_uid WHERE workspace_id = v_ws AND manager_user_id = p.fake_uid;

    -- ---- Polimorf ustunlar: SHARTSIZ UPDATE begona qatorga tegadi ----
    UPDATE activity_logs SET entity_id = p.real_uid::TEXT
      WHERE workspace_id = v_ws AND entity_type = 'employee' AND entity_id = p.fake_uid::TEXT;
    UPDATE activity_logs SET actor_id = p.real_uid
      WHERE workspace_id = v_ws AND actor_id = p.fake_uid;
    UPDATE org_containers SET parent_id = p.real_uid
      WHERE workspace_id = v_ws AND parent_kind = 'user' AND parent_id = p.fake_uid;

    -- ---- staff_import_map: endi asl akkauntga ishora qilsin ----
    -- Shu tufayli keyingi import uni TOPADI va qayta yaratmaydi (index.ts:343-357).
    -- created_in_run=false — bu akkaunt import tomonidan yaratilmagan, rollback tegmasin.
    UPDATE staff_import_map
       SET user_id = p.real_uid, created_in_run = false
     WHERE workspace_id = v_ws AND source_system = 'aros_staff'
       AND source_id = p.source_id;

    -- ---- profiles: BOSIB O'TMAYMIZ, faqat bo'sh maydonni to'ldiramiz ----
    UPDATE profiles r
       SET full_name = COALESCE(NULLIF(btrim(r.full_name), ''), f.full_name),
           phone     = COALESCE(NULLIF(btrim(r.phone), ''),     f.phone),
           avatar_url= COALESCE(r.avatar_url,                    f.avatar_url)
      FROM profiles f
     WHERE r.id = p.real_uid AND f.id = p.fake_uid;

    -- ---- workspace_members: soxta qator ketadi; ASL QATORNING ROLIGA TEGILMAYDI ----
    DELETE FROM workspace_members WHERE workspace_id = v_ws AND user_id = p.fake_uid;

    v_moved := v_moved + 1;
  END LOOP;

  RAISE NOTICE '=== % juftlikdan % tasi ko''chirildi ===', v_pairs, v_moved;

  IF v_dry_run THEN
    RAISE EXCEPTION 'DRY RUN — hech narsa saqlanmadi (v_dry_run = false qiling). Yuqoridagi NOTICE larni o''qing.';
  END IF;
END $$;

-- ⚠️ auth.users NI BU YERDA O'CHIRMAYMIZ.
--    Sabab: rasm hali soxta uid yo'lida ({ws}/{fake}.jpg). Avval 5-bosqich.
--    O'chirish keyin, qo'lda:
--      SELECT id, email FROM auth.users WHERE email LIKE '%@staff.taskfix.org'
--        AND id NOT IN (SELECT user_id FROM staff_import_map);
--    Bu ro'yxatni TEKSHIRIB, so'ng Supabase Auth panelidan yoki
--    admin.auth.admin.deleteUser() bilan o'chiring.


-- ============================================================
-- 5-BOSQICH — Rasm (SQL QILA OLMAYDI)
-- ============================================================
-- Storage yo'lida uid bor: {workspace_id}/{user_id}.jpg (index.ts:255), va
-- 41-migratsiya policy'si uid ni AYNAN YO'LDAN o'qiydi (41:148-151).
-- Ko'chirmasak — hodim o'z rasmini ko'ra olmaydi (manager ko'radi).
--
-- storage.objects ni to'g'ridan UPDATE qilish YETARLI EMAS (fayl o'zi joyida
-- qoladi, metadata buziladi) → storage API'ning move() si kerak, u esa
-- service_role talab qiladi.
--
-- ⚠️ Bu so'rov dup_pairs() ga TAYANMAYDI — ataylab.
--    4-bosqich staff_import_map ni asl akkauntga ko'chirgach dup_pairs() BO'SH
--    qaytadi (soxta emailli map qatori qolmaydi). Uning o'rniga to'g'ridan
--    employee_details dan izlaymiz: qator endi ASL uid'da, photo_path esa hamon
--    SOXTA uid yo'lini ko'rsatib turadi — nomuvofiqlikning o'zi belgi.
--
--    Foydasi: bu so'rov 4-bosqichdan OLDIN ham, KEYIN ham to'g'ri ishlaydi, va
--    dublikatdan qat'i nazar har qanday "yo'li egasiga mos kelmaydigan" rasmni topadi.
--
-- ⚠️ ::TEXT shart — Postgres'da 'UUID || TEXT' operatori YO'Q.
SELECT ed.user_id                                                   AS real_uid,
       u.email                                                      AS real_email,
       ed.photo_path                                                AS eski_yol,
       ed.workspace_id::TEXT || '/' || ed.user_id::TEXT || '.jpg'   AS yangi_yol
FROM employee_details ed
JOIN auth.users u ON u.id = ed.user_id
WHERE ed.workspace_id = '<WS_ID>'
  AND ed.photo_path IS NOT NULL
  AND ed.photo_path <> ed.workspace_id::TEXT || '/' || ed.user_id::TEXT || '.jpg';
-- Bo'sh qaytsa — ko'chiriladigan rasm yo'q, 5-bosqich tugadi.


-- ============================================================
-- 6) Tozalash — yordamchilarni olib tashlash
-- ============================================================
-- Hammasi tugagach (5-bosqich ham) ishga tushiring.
-- norm_phone_digits() QOLADI — u 45-migratsiyaniki, EF ishlatadi.
--
-- DROP FUNCTION IF EXISTS dup_scan(UUID);
-- DROP FUNCTION IF EXISTS dup_pairs(UUID);
-- DROP FUNCTION IF EXISTS cleanup_norm_name(TEXT);
