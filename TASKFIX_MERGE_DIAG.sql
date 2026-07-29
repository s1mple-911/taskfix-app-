-- ============================================================================
-- TASKFIX_MERGE_DIAG.sql — 1a: DUBLIKAT XODIM DIAGNOSTIKASI
-- ============================================================================
-- ⚠️ BU FAYL HECH NARSANI O'ZGARTIRMAYDI.
--    Yozmaydi, o'chirmaydi, jadval/funksiya/temp obyekt YARATMAYDI.
--    Bitta SELECT — natijani ko'rasiz va menga ko'rsatasiz.
--
-- NEGA KERAK: 1b (birlashtirish) SQL'ini yozishdan oldin aniq bilish kerak:
--   1) Kim kim bilan dublikat, qaysi biri "qo'lda" qaysi biri "import"
--   2) HAR BIR user_id havolasi qayerda saqlanadi (bitta jadval qolib ketsa —
--      ma'lumot yo'qoladi yoki FK buziladi)
--   3) Qayerda UNIQUE cheklov bor (ikkala profil ham qator egallagan bo'lsa
--      UPDATE 23505 bilan yiqiladi — 1b da ON CONFLICT / DELETE kerak)
--
-- ISHLATISH: butun faylni nusxalab Supabase SQL Editor'ga qo'ying va RUN.
--            Natija — bitta jadval (bo'limlarga bo'lingan). Hammasini bering.
--
-- QANCHA VAQT: ~5-30 soniya (dinamik skanerlash: har uuid ustuni bo'yicha
--              count(*)). Katta jadvallar (>2 mln qator) o'tkazib yuboriladi
--              va E-bo'limda ro'yxatlanadi.
--
-- ESLATMA: mavjud `cleanup_duplicate_staff.sql` FAQAT import juftliklarini
--          (staff_import_map + telefon mos) ko'radi va `norm_phone_digits`
--          (45-migratsiya, hali ishga tushmagan) ga bog'liq. Bu fayl undan
--          MUSTAQIL: hech qanday funksiyaga tayanmaydi va ISM bo'yicha
--          (importmi yoki qo'ldami — farqsiz) hamma dublikatni topadi.
-- ============================================================================

WITH
-- ── 0) Sozlama ──────────────────────────────────────────────────────────────
--    ws_id = NULL  → HAMMA workspace (tavsiya etiladi, hech narsa qolib ketmaydi)
--    Bitta workspace uchun: '12b22aa6-dc45-4197-ae84-2e32e3cd56c2'::uuid
param AS (
  SELECT NULL::uuid AS ws_id
),

-- ── 1) Barcha profillar + auth ma'lumoti + normallashtirilgan ism ───────────
--    Normalizatsiya (cleanup_norm_name bilan bir xil mantiq, lekin INLINE —
--    funksiya yaratmaymiz): kichik harf → kirill homoglif lotinga →
--    apostroflar tashlanadi → ortiqcha bo'shliq yig'ishtiriladi.
prof AS (
  SELECT
    p.id                                   AS uid,
    p.full_name                            AS full_name,
    -- to_jsonb: ustun bo'lmasa ham so'rov yiqilmasin
    nullif(btrim(coalesce(to_jsonb(p) ->> 'email', '')), '') AS prof_email,
    nullif(btrim(coalesce(p.phone,'')), '') AS phone,
    u.email::text                          AS auth_email,
    u.last_sign_in_at                      AS last_sign_in,
    u.created_at                           AS auth_created,
    (to_jsonb(p) ->> 'created_at')         AS prof_created,
    btrim(regexp_replace(
      regexp_replace(
        translate(lower(coalesce(p.full_name, '')),
                  'авекмнорстухѕіј', 'abekmhopctyxsij'),
        '[''`‘’ʼʻ′]', '', 'g'),
      '\s+', ' ', 'g'))                    AS norm,
    -- telefon: faqat raqamlar, oxirgi 9 tasi (operator/kod farqi sanalmasin)
    right(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g'), 9) AS ph9,
    (SELECT string_agg(w.name || ' [' || wm.role::text || ']', ', ' ORDER BY w.name)
       FROM public.workspace_members wm
       JOIN public.workspaces w ON w.id = wm.workspace_id
      WHERE wm.user_id = p.id)             AS ws_list,
    (SELECT count(*) FROM public.workspace_members wm
      WHERE wm.user_id = p.id
        AND ((SELECT ws_id FROM param) IS NULL OR wm.workspace_id = (SELECT ws_id FROM param))
    )                                      AS ws_cnt
  FROM public.profiles p
  LEFT JOIN auth.users u ON u.id = p.id
),

-- Faqat tanlangan workspace(lar) doirasidagi profillar
scoped AS (
  SELECT * FROM prof WHERE ws_cnt > 0
),

-- ── 2) Dublikat guruhlar ────────────────────────────────────────────────────
-- 2a) ISM bo'yicha
dup_name AS (
  SELECT norm FROM scoped WHERE norm <> '' GROUP BY norm HAVING count(*) > 1
),
-- 2b) TELEFON bo'yicha (ismi boshqacha yozilgan bo'lsa ham topiladi)
dup_phone AS (
  SELECT ph9 FROM scoped WHERE ph9 <> '' AND length(ph9) = 9
   GROUP BY ph9 HAVING count(DISTINCT uid) > 1
),
-- Ikkala usulda topilganlar birga
dupprof AS (
  SELECT s.*,
         (s.norm IN (SELECT norm FROM dup_name)) AS by_name,
         (s.ph9  IN (SELECT ph9  FROM dup_phone)) AS by_phone,
         -- guruh kaliti: ism bo'yicha topilgan bo'lsa ism, aks holda telefon
         (CASE WHEN s.norm IN (SELECT norm FROM dup_name)
               THEN s.norm ELSE 'tel:' || s.ph9 END) AS grp
    FROM scoped s
   WHERE s.norm IN (SELECT norm FROM dup_name)
      OR s.ph9  IN (SELECT ph9  FROM dup_phone)
),
ids AS (
  SELECT coalesce(array_agg(DISTINCT uid), '{}'::uuid[]) AS a FROM dupprof
),

-- ── 3) Har profil uchun eng muhim sanoqlar (ustunlari ANIQ mavjud) ──────────
--    Qolgan HAMMA joy — B-bo'limdagi dinamik skanerdan chiqadi.
cnt AS (
  SELECT d.uid,
    (SELECT count(*) FROM public.tasks t WHERE t.assigned_to = d.uid) AS t_asg,
    (SELECT count(*) FROM public.tasks t WHERE t.created_by  = d.uid) AS t_cre,
    (SELECT count(*) FROM public.project_members pm WHERE pm.user_id = d.uid) AS pm_n
  FROM dupprof d
),

-- ── 4) A-BO'LIM: dublikat profillar ro'yxati ────────────────────────────────
secA AS (
  SELECT 10 AS ord,
         (row_number() OVER (ORDER BY d.grp, d.last_sign_in NULLS LAST, d.uid))::int AS sub,
         'A. DUBLIKAT PROFILLAR'::text AS bolim,
         d.grp::text                                                   AS m1,
         coalesce(d.full_name, '(ismsiz)')::text                       AS m2,
         d.uid::text                                                   AS m3,
         (CASE
            WHEN coalesce(d.auth_email, d.prof_email, '') ILIKE '%@staff.taskfix.org'
              THEN 'IMPORT (sintetik email)'
            WHEN d.last_sign_in IS NOT NULL
              THEN 'QO''LDA (login qilgan)'
            ELSE 'NOMA''LUM (haqiqiy email, lekin hech qachon kirmagan)'
          END)::text                                                   AS m4,
         coalesce(d.auth_email, d.prof_email, '—')::text               AS m5,
         coalesce(d.phone, '—')::text                                  AS m6,
         ('yaratilgan=' || coalesce(to_char(d.auth_created, 'YYYY-MM-DD HH24:MI'),
                                    coalesce(left(d.prof_created, 16), '—'))
          || ' · oxirgi_kirish=' || coalesce(to_char(d.last_sign_in, 'YYYY-MM-DD HH24:MI'), 'HECH QACHON')
          || ' · mos=' || (CASE WHEN d.by_name AND d.by_phone THEN 'ism+tel'
                                WHEN d.by_name THEN 'ism' ELSE 'tel' END))::text AS m7,
         ('ws=' || coalesce(d.ws_list, '—')
          || ' · vazifa_biriktirilgan=' || c.t_asg
          || ' · vazifa_yaratgan=' || c.t_cre
          || ' · loyiha_azolik=' || c.pm_n)::text                      AS m8
    FROM dupprof d
    JOIN cnt c ON c.uid = d.uid
),

-- ── 5) B1-BO'LIM: STRUKTURA — auth.users/profiles ga FK bo'lgan HAR ustun ───
--    Bu "qonuniy" inventar: FK bor joylar. FK'siz ustunlar B2 da chiqadi.
fk AS (
  SELECT
    cn.nspname::text AS sch, cl.relname::text AS tbl,
    (SELECT string_agg(a.attname::text, ',' ORDER BY x.ord)
       FROM unnest(con.conkey) WITH ORDINALITY AS x(attnum, ord)
       JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = x.attnum) AS cols,
    fn.nspname::text AS f_sch, fl.relname::text AS f_tbl,
    con.conname::text AS conname,
    (CASE con.confdeltype WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT'
                          WHEN 'c' THEN 'CASCADE'   WHEN 'n' THEN 'SET NULL'
                          WHEN 'd' THEN 'SET DEFAULT' ELSE con.confdeltype::text END) AS on_del,
    (CASE con.confupdtype WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT'
                          WHEN 'c' THEN 'CASCADE'   WHEN 'n' THEN 'SET NULL'
                          WHEN 'd' THEN 'SET DEFAULT' ELSE con.confupdtype::text END) AS on_upd
  FROM pg_constraint con
  JOIN pg_class     cl ON cl.oid = con.conrelid
  JOIN pg_namespace cn ON cn.oid = cl.relnamespace
  JOIN pg_class     fl ON fl.oid = con.confrelid
  JOIN pg_namespace fn ON fn.oid = fl.relnamespace
  WHERE con.contype = 'f'
    AND ( (fn.nspname = 'auth'   AND fl.relname = 'users')
       OR (fn.nspname = 'public' AND fl.relname = 'profiles') )
),
secB1 AS (
  SELECT 20 AS ord,
         (row_number() OVER (ORDER BY f.sch, f.tbl, f.cols))::int AS sub,
         'B1. FK — user_id havolalari (STRUKTURA)'::text AS bolim,
         (f.sch || '.' || f.tbl)::text          AS m1,
         f.cols::text                           AS m2,
         ('→ ' || f.f_sch || '.' || f.f_tbl)::text AS m3,
         ('ON DELETE ' || f.on_del)::text       AS m4,
         ('ON UPDATE ' || f.on_upd)::text       AS m5,
         f.conname                              AS m6,
         ''::text                               AS m7,
         ''::text                               AS m8
    FROM fk f
),

-- ── 6) B2-BO'LIM: MA'LUMOT — dublikat uid'lar AYNAN qayerda uchraydi ────────
--    public/auth/storage sxemalaridagi HAR uuid ustuni skanerlanadi
--    (FK bor-yo'qligidan qat'i nazar). Katta jadvallar o'tkazib yuboriladi.
scan_cols AS (
  SELECT n.nspname::text AS sch, c.relname::text AS tbl, a.attname::text AS col,
         greatest(c.reltuples, 0)::bigint AS approx
    FROM pg_attribute a
    JOIN pg_class     c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE a.atttypid = 'uuid'::regtype
     AND a.attnum > 0 AND NOT a.attisdropped
     AND c.relkind IN ('r', 'p')
     AND n.nspname IN ('public', 'auth', 'storage')
),
scan_ok  AS (SELECT * FROM scan_cols WHERE approx <= 2000000),
scan_big AS (SELECT * FROM scan_cols WHERE approx >  2000000),
scanB AS (
  SELECT s.sch, s.tbl, s.col, s.approx,
         coalesce((xpath('/row/c/text()', query_to_xml(
           format('SELECT count(*) AS c FROM %I.%I WHERE %I = ANY (%L::uuid[])',
                  s.sch, s.tbl, s.col, (SELECT a FROM ids)),
           false, true, '')))[1]::text::bigint, 0) AS n
    FROM scan_ok s
),
scanB2 AS (
  SELECT b.*,
         coalesce((xpath('/row/c/text()', query_to_xml(
           format('SELECT coalesce(string_agg(t.u || ''='' || t.k::text, ''  |  '' ORDER BY t.k DESC), '''') AS c '
                  || 'FROM (SELECT %I::text AS u, count(*) AS k FROM %I.%I '
                  || 'WHERE %I = ANY (%L::uuid[]) GROUP BY 1) t',
                  b.col, b.sch, b.tbl, b.col, (SELECT a FROM ids)),
           false, true, '')))[1]::text, '') AS dist
    FROM scanB b
   WHERE b.n > 0
),
secB2 AS (
  SELECT 30 AS ord,
         (row_number() OVER (ORDER BY b.n DESC, b.sch, b.tbl, b.col))::int AS sub,
         'B2. MA''LUMOT — dublikat uid qayerda yotibdi'::text AS bolim,
         (b.sch || '.' || b.tbl)::text                        AS m1,
         b.col::text                                          AS m2,
         ('mos_qator=' || b.n)::text                          AS m3,
         ('jadval_taxminan=' || b.approx)::text               AS m4,
         (CASE WHEN EXISTS (SELECT 1 FROM fk f
                             WHERE f.sch = b.sch AND f.tbl = b.tbl
                               AND (',' || f.cols || ',') LIKE ('%,' || b.col || ',%'))
               THEN 'FK bor' ELSE '⚠️ FK YO''Q — 1b da qo''lda ko''chirish shart' END)::text AS m5,
         b.dist::text                                         AS m6,
         ''::text                                             AS m7,
         ''::text                                             AS m8
    FROM scanB2 b
),

-- ── 7) C-BO'LIM: UNIQUE cheklovlar — birlashtirishda to'qnashuv joyi ────────
uq AS (
  SELECT n.nspname::text AS sch, c.relname::text AS tbl,
         i.relname::text AS idx, pg_get_indexdef(i.oid)::text AS def,
         x.indisprimary AS is_pk
    FROM pg_index x
    JOIN pg_class     i ON i.oid = x.indexrelid
    JOIN pg_class     c ON c.oid = x.indrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE x.indisunique
     AND n.nspname IN ('public', 'auth', 'storage')
),
secC AS (
  SELECT 40 AS ord,
         (row_number() OVER (ORDER BY u.sch, u.tbl, u.idx))::int AS sub,
         'C. UNIQUE — birlashtirishda TO''QNASHUV xavfi'::text AS bolim,
         (u.sch || '.' || u.tbl)::text                 AS m1,
         u.idx                                         AS m2,
         (CASE WHEN u.is_pk THEN 'PRIMARY KEY' ELSE 'UNIQUE' END)::text AS m3,
         u.def                                         AS m4,
         'ikkala profil ham qator egallagan bo''lsa UPDATE 23505 beradi'::text AS m5,
         ''::text AS m6, ''::text AS m7, ''::text AS m8
    FROM uq u
   WHERE u.def ~* '(user_id|assigned_to|created_by|actor_id|author_id|manager_user_id|acceptor_id|submitter_id|linked_user_id|bajardi_user_id|changed_by|owner_id|member_id|parent_id)'
     -- shu ustunlarda dublikat uid haqiqatan bor bo'lsagina qiziq
     AND EXISTS (SELECT 1 FROM scanB2 b WHERE b.sch = u.sch AND b.tbl = u.tbl)
),

-- ── 8) D-BO'LIM: uid MATN ichida (uuid ustuni emas — skaner ko'rmaydi) ──────
--    Misollar: activity_logs.entity_id (text, polimorf),
--              storage.objects.name = '{ws}/{uid}.jpg',
--              employee_details.photo_path
txt_cols AS (
  SELECT n.nspname::text AS sch, c.relname::text AS tbl, a.attname::text AS col,
         greatest(c.reltuples, 0)::bigint AS approx
    FROM pg_attribute a
    JOIN pg_class     c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE a.atttypid IN ('text'::regtype, 'varchar'::regtype)
     AND a.attnum > 0 AND NOT a.attisdropped
     AND c.relkind IN ('r', 'p')
     AND n.nspname IN ('public', 'storage')
     AND greatest(c.reltuples, 0) <= 500000
     AND (a.attname ~* '(id|path|url|name|key)$')
),
scanD AS (
  SELECT t.sch, t.tbl, t.col,
         coalesce((xpath('/row/c/text()', query_to_xml(
           format('SELECT count(*) AS c FROM %I.%I s '
                  || 'WHERE EXISTS (SELECT 1 FROM unnest(%L::uuid[]) z(u) '
                  || 'WHERE s.%I = z.u::text OR s.%I LIKE ''%%'' || z.u::text || ''%%'')',
                  t.sch, t.tbl, (SELECT a FROM ids), t.col, t.col),
           false, true, '')))[1]::text::bigint, 0) AS n
    FROM txt_cols t
),
secD AS (
  SELECT 50 AS ord,
         (row_number() OVER (ORDER BY d.n DESC, d.sch, d.tbl, d.col))::int AS sub,
         'D. uid MATN ustunida (FK yo''q, e''tibor bering!)'::text AS bolim,
         (d.sch || '.' || d.tbl)::text        AS m1,
         d.col::text                          AS m2,
         ('mos_qator=' || d.n)::text          AS m3,
         '⚠️ 1b da qo''lda ko''chirish/ko''rib chiqish kerak'::text AS m4,
         ''::text AS m5, ''::text AS m6, ''::text AS m7, ''::text AS m8
    FROM scanD d
   WHERE d.n > 0
),

-- ── 9) E-BO'LIM: xulosa + skanerdan chetda qolganlar ────────────────────────
secE AS (
  SELECT 60 AS ord, 1::int AS sub, 'E. XULOSA'::text AS bolim,
         'dublikat_profil'::text AS m1,
         (SELECT count(*)::text FROM dupprof) AS m2,
         'dublikat_guruh'::text AS m3,
         (SELECT count(DISTINCT grp)::text FROM dupprof) AS m4,
         'skanerlangan_uuid_ustun'::text AS m5,
         (SELECT count(*)::text FROM scan_ok) AS m6,
         'mos_topilgan_ustun'::text AS m7,
         (SELECT count(*)::text FROM scanB2) AS m8
  UNION ALL
  SELECT 60, 2, 'E. XULOSA',
         'dublikat_uid_royxati (1b uchun)'::text,
         (SELECT coalesce(array_to_string(a, ', '), '(yo''q)') FROM ids),
         ''::text, ''::text, ''::text, ''::text, ''::text, ''::text
  UNION ALL
  SELECT 60, 3, 'E. XULOSA',
         '⚠️ SKANERDAN CHETDA (juda katta jadval)'::text,
         (SELECT coalesce(string_agg(sch || '.' || tbl || '.' || col || ' (~' || approx || ')', ', '), '(yo''q — hammasi skanerlandi)')
            FROM scan_big),
         ''::text, ''::text, ''::text, ''::text, ''::text, ''::text
  UNION ALL
  SELECT 60, 4, 'E. XULOSA',
         (CASE WHEN (SELECT count(*) FROM dupprof) = 0
               THEN '✅ Dublikat topilmadi — 1b kerak emas'
               ELSE '➡️ Natijani to''liq nusxalab bering — 1b (TASKFIX_MERGE.sql) shunga qarab yoziladi' END)::text,
         ''::text, ''::text, ''::text, ''::text, ''::text, ''::text, ''::text
),

-- ── 10) Bo'lim sarlavhalari (ustun nomlari) ─────────────────────────────────
heads AS (
  SELECT 10 AS ord, 0::int AS sub, 'A. DUBLIKAT PROFILLAR'::text AS bolim,
         'GURUH'::text AS m1, 'ISM'::text AS m2, 'PROFIL_ID'::text AS m3, 'TUR'::text AS m4,
         'EMAIL'::text AS m5, 'TELEFON'::text AS m6, 'VAQTLAR'::text AS m7, 'BOG''LIQLIK'::text AS m8
  UNION ALL SELECT 20, 0, 'B1. FK — user_id havolalari (STRUKTURA)',
         'JADVAL', 'USTUN(LAR)', 'KIMGA', 'O''CHIRISHDA', 'YANGILASHDA', 'CHEKLOV_NOMI', '', ''
  UNION ALL SELECT 30, 0, 'B2. MA''LUMOT — dublikat uid qayerda yotibdi',
         'JADVAL', 'USTUN', 'MOS_QATOR', 'JADVAL_HAJMI', 'FK_HOLATI', 'TAQSIMOT (uid=nechta)', '', ''
  UNION ALL SELECT 40, 0, 'C. UNIQUE — birlashtirishda TO''QNASHUV xavfi',
         'JADVAL', 'INDEKS', 'TUR', 'TA''RIF', 'IZOH', '', '', ''
  UNION ALL SELECT 50, 0, 'D. uid MATN ustunida (FK yo''q, e''tibor bering!)',
         'JADVAL', 'USTUN', 'MOS_QATOR', 'IZOH', '', '', '', ''
  UNION ALL SELECT 60, 0, 'E. XULOSA',
         'KO''RSATKICH', 'QIYMAT', 'KO''RSATKICH', 'QIYMAT', 'KO''RSATKICH', 'QIYMAT', 'KO''RSATKICH', 'QIYMAT'
)

SELECT ord, sub, bolim, m1, m2, m3, m4, m5, m6, m7, m8
FROM (
  SELECT * FROM heads
  UNION ALL SELECT * FROM secA
  UNION ALL SELECT * FROM secB1
  UNION ALL SELECT * FROM secB2
  UNION ALL SELECT * FROM secC
  UNION ALL SELECT * FROM secD
  UNION ALL SELECT * FROM secE
) z
ORDER BY ord, sub;

-- ============================================================================
-- NATIJANI QANDAY O'QISH
-- ============================================================================
-- A-bo'lim  — har dublikat guruhida 2+ qator. "TUR" ustuni qaysi biri import
--             qaysi biri qo'lda ekanini aytadi; "oxirgi_kirish=HECH QACHON"
--             bo'lgan profil login qilmagan (auth.users'ni o'chirish xavfsizroq).
--             "BOG'LIQLIK" — qaysi profilda ko'proq vazifa borligini ko'rsatadi.
--
-- B1        — FK bor joylar. ON DELETE CASCADE bo'lsa: profilni o'chirsak
--             u yerdagi qatorlar HAM O'CHADI → 1b da AVVAL ko'chirish shart.
--
-- B2        — dublikat uid'lar HAQIQATAN yotgan joylar. "FK YO'Q" deb
--             belgilangan ustunlar eng xavflisi: DB o'zi hech narsa qilmaydi,
--             1b qo'lda ko'chirmasa ma'lumot yetim qoladi.
--
-- C         — bu jadvallarda UPDATE ... SET user_id = keep to'g'ridan-to'g'ri
--             ishlamaydi: avval keep'da qator bor-yo'qligini tekshirish
--             (yoki remove qatorini o'chirish) kerak.
--
-- D         — uid matn ichida (activity_logs.entity_id, storage.objects.name
--             = rasm yo'li). Rasm ko'chirish SQL bilan bo'lmaydi — Storage API.
--
-- E         — xulosa + dublikat uid ro'yxati (1b shu ro'yxatdan foydalanadi).
--
-- ============================================================================
-- AGAR XATO CHIQSA
-- ============================================================================
--   "canceling statement due to statement timeout"
--       → 0-bo'limdagi param.ws_id ga Aros workspace ID sini yozing:
--         SELECT NULL::uuid AS ws_id  →  SELECT '12b22aa6-dc45-4197-ae84-2e32e3cd56c2'::uuid AS ws_id
--
--   "permission denied for schema auth" (odatda bo'lmaydi — SQL Editor postgres roli)
--       → 1-bo'limdagi "LEFT JOIN auth.users u ON u.id = p.id" ni olib tashlang
--         va scan_cols/uq dagi IN ('public','auth','storage') dan 'auth' ni chiqaring.
--         Bunda "TUR" ustuni faqat profiles.email ga tayanadi.
--
--   Boshqa xato — matnini menga yuboring, hech narsa yozilmagan (bu SELECT).
-- ============================================================================
