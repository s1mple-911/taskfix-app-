-- ============================================================================
-- TASKFIX_SHABLON_TRIGGER_FIX.sql — public.sync_flow_locks() ni SHABLON/SIKLGA
-- moslashtirish (TASKFIX_SHABLON.sql dan OLDIN ishga tushiriladi)
-- ============================================================================
-- Asilbek RUN qiladi (Supabase SQL Editor, postgres roli).
--
-- 🔴🔴 KAM TRAFIK VAQTIDA RUN QILING — bu fayl `public.tasks` ga
--      ACCESS EXCLUSIVE QULF oladi (`ALTER TABLE ... ADD COLUMN`) va uni
--      COMMIT gacha ushlab turadi. `is_template boolean NOT NULL DEFAULT false`
--      PG11+ da "fast default" (jadval QAYTA YOZILMAYDI), `cycle_id uuid`
--      ham shunday — ya'ni qulf qisqa, LEKIN tirik sinovlar ham shu
--      tranzaksiya ichida bo'lgani uchun bir necha soniya davom etadi.
--
-- ── NIMA BO'LGAN ────────────────────────────────────────────────────────────
--   TASKFIX_SHABLON.sql RUN qilinganda uning 0e-bo'limi `public.tasks` dagi
--   `trg_sync_flow_locks` → `public.sync_flow_locks()` ni XAVFLI deb topib
--   RAISE EXCEPTION bilan TO'XTATDI (to'g'ri himoya; bazada bir belgi ham
--   o'zgarmadi). Sabab — funksiya tanasi tartib raqami (flow_order) va
--   `is_locked` bilan ishlaydi, lekin `is_template` haqida HECH NARSA bilmaydi:
--
--     (1) `UPDATE tasks t ... WHERE t.project_id = NEW.project_id` loyihaning
--         HAR qatoriga `is_locked` yozadi — SHABLON qatorlariga ham. Shablon
--         ish emas, TA'RIF; u hech qachon qulflanmasligi kerak.
--     (2) Voris qidiruvi (`p` / `p2`) loyihaning HAMMA qatorini ko'radi:
--         • SHABLON `status = 'new'` bo'lib HECH QACHON tugamaydi, shablon va
--           instansiya esa bir xil `flow_order` ga ega → `MAX(...)` o'sha
--           qiymatni beradi va `EXISTS (... p.status <> 'completed')` shablon
--           tufayli DOIM rost bo'ladi → keyingi bosqich ABADIY QULFLANGAN.
--         • Teskarisi: boshqa SIKLNING `completed` qatori `EXISTS` ni yolg'on
--           qilib, hali kutishi kerak bo'lgan bosqichni NOTO'G'RI OCHIB
--           yuboradi.
--
-- ── BU FAYL NIMA QILADI ─────────────────────────────────────────────────────
--   1) `public.tasks` ga IKKI ustun qo'shadi — `is_template` va `cycle_id`.
--      🔴 NIMA UCHUN AYNAN SHU FAYL QO'SHADI: PL/pgSQL KECH BOG'LANADI —
--         ustunlarga murojaat qiladigan funksiya ular YO'Q bazada o'rnatilsa,
--         xato faqat ISHLASH paytida (har status o'zgarishida) chiqadi va
--         PROD DARROV BUZILADI. Shuning uchun ustunlar funksiyadan OLDIN,
--         AYNI tranzaksiyada yaratiladi.
--      ⚠️ Ta'rif TASKFIX_SHABLON.sql dagi bilan HARFMA-HARF bir xil:
--           ADD COLUMN IF NOT EXISTS is_template boolean NOT NULL DEFAULT false
--           ADD COLUMN IF NOT EXISTS cycle_id uuid
--         SHABLON keyin qayta RUN qilinganda `ADD COLUMN` no-op bo'ladi,
--         FK'lar (`tasks_cycle_fk`) va CHECK esa alohida `ADD CONSTRAINT`
--         bilan baribir qo'shiladi. ZIDDIYAT YO'Q.
--      ⚠️ `template_id` ga TEGILMAYDI — uni SHABLON katalogdan olingan
--         `tasks.id` TIPI bilan qo'shadi (bu yerda tip taxmin qilinmaydi).
--   2) Mavjud funksiya ta'rifini `public.taskfix_trigger_backup` ga SAQLAYDI
--      (qaytarish bir so'rov bilan — fayl oxirida).
--   3) 🔴 QOROVUL: o'rnatishdan OLDIN mavjud tanani KUTILGAN ASL ta'rif bilan
--      solishtiradi (izoh/bo'shliq normallashtirilgandan keyin). Mos emas
--      bo'lsa — RAISE EXCEPTION (FAIL-CLOSED), tanani NOTICE bilan chop etadi.
--      Begona funksiya KO'R-KO'RONA BOSIB KETILMAYDI.
--   4) Tuzatilgan ta'rifni o'rnatadi (`CREATE OR REPLACE`). Trigger'ning
--      O'ZIGA (`trg_sync_flow_locks`) TEGILMAYDI — faqat funksiya almashadi,
--      ya'ni egasi (owner), ruxsatlar va trigger bog'lanishi saqlanadi.
--   5) 🔴 TIRIK SINOVLAR (L1..L8) — sentinel-rollback. Bittasi kutilgandek
--      chiqmasa RAISE EXCEPTION → HAMMASI QAYTADI (funksiya ham eski holida
--      qoladi, ustunlar ham qo'shilmaydi).
--      🔴 (L8) — SHABLON va INSTANSIYA ikkalasi ham `cycle_id` NULL bo'lgan
--         sahna: `p.is_template` / `p2.is_template` qorovullarini FAQAT SHU
--         sahna tekshiradi (qolganlarida ularni sikl qorovuli "bekor qiladi").
--   6) Hisobot + `(99) XULOSA`.
--
--   ⚠️ Bulardan TASHQARI, DDL DAN OLDIN (0 / 0b / 0d / 0e-bo'limlar) faqat
--      O'QIYDIGAN qorovullar bor:
--        • funksiyaning MAVJUD atributlari — `prosecdef` (SECURITY INVOKER
--          bo'lsa TO'XTAYDI: `CREATE OR REPLACE` uni jimgina DEFINER ga
--          aylantirib yuborardi, tana solishtiruvi esa buni KO'RMAYDI),
--          `lanname`, `proconfig` (search_path farqi → WARNING).
--        • `is_template`/`cycle_id` ustunlarining TIPI (0b).
--        • `public.tasks` dagi UNIQUE indekslar (0e) — sentinel sahnada
--          `flow_order` ATAYLAB takrorlanadi, indeks bo'lsa sinovlar 23505
--          bilan ENV ga tushardi; sabab OLDINDAN aytiladi.
--
-- ── NIMA QILMAYDI (ATAYLAB) ─────────────────────────────────────────────────
--   • `trg_sync_flow_locks` trigger'ini DROP/CREATE QILMAYDI (vaqti/hodisasi/
--     WHEN sharti bazada qanday bo'lsa shundayligicha qoladi).
--   • `tasks` ning RLS policy'lariga, boshqa triggerlariga, `template_id` ga,
--     `project_cycles` / `template_history` jadvallariga TEGMAYDI — ular
--     TASKFIX_SHABLON.sql ning ishi.
--   • Hech qanday qatorni O'CHIRMAYDI va mavjud `is_locked` qiymatlarini
--     qo'lda qayta hisoblamaydi (buni trigger keyingi status o'zgarishida
--     o'zi qiladi — mavjud xatti-harakat).
--
-- ── EKVIVALENTLIK (eski ma'lumot buzilmasligining isboti) ──────────────────
--   Shablon YO'Q va hamma `cycle_id` NULL bo'lgan bazada:
--     `false IS NOT TRUE`              → true
--     `NULL IS NOT DISTINCT FROM NULL` → true
--   ya'ni har qator yangi qorovullardan o'tadi va natija ASL funksiya bilan
--   AYNAN bir xil bo'ladi. `= false` / `=` EMAS, aynan `IS NOT TRUE` va
--   `IS NOT DISTINCT FROM` ishlatilgani shu sababdan (NULL xavfsizligi).
--   Buni 5-bo'limdagi (L1), (L2), (L3), (L7) sinovlari TIRIK tasdiqlaydi.
--
-- ── 🔴 `p2` HAM QOROVULLANADI ───────────────────────────────────────────────
--   Faqat `p` qorovullansa, ichki `MAX(p2.flow_order)` shablonda yoki BOSHQA
--   SIKLDA mavjud `flow_order` ni tanlab qolishi mumkin; keyin `p` o'sha
--   qiymat bo'yicha o'z siklida hech narsa topmaydi, `EXISTS` yolg'on bo'ladi
--   va bosqich NOTO'G'RI OCHILADI. Ikkalasi BIRGA qorovullanadi.
--   (L6a) sinovi aynan shu holatni tirik ko'rsatadi.
--
-- ── RUN TARTIBI ─────────────────────────────────────────────────────────────
--   1) BU FAYL            (TASKFIX_SHABLON_TRIGGER_FIX.sql)
--   2) TASKFIX_SHABLON.sql  — endi uning 0e-bo'limi funksiyada `is_template`
--      qorovulini ko'radi va XAVFLI hukmini CHIQARMAYDI, 8b tirik sinovi
--      (t1..t4) esa o'tadi.
--   Boshqa TASKFIX_*.sql fayllariga bog'liq emas.
--
-- ── QAYTARISH ───────────────────────────────────────────────────────────────
--   Fayl oxiridagi "QAYTARISH" bo'limiga qarang (bitta DO bloki).
-- ============================================================================

BEGIN;

-- ════════════════════════════════════════════════════════════════════════════
-- 0) OLD SHARTLAR — noto'g'ri/yarim bazada ishga tushmasin (FAIL-CLOSED)
--    🔴 Bu bo'lim HAR QANDAY DDL DAN OLDIN turadi.
-- ════════════════════════════════════════════════════════════════════════════
DO $pre$
DECLARE
  v_c    text;
  v_lang text;
  v_sec  boolean;
  v_cfg  text[];
BEGIN
  IF to_regclass('public.tasks') IS NULL THEN
    RAISE EXCEPTION 'public.tasks topilmadi — bu TaskFix bazasi emasmi? Hech narsa o''zgartirilmadi.';
  END IF;
  IF to_regclass('public.projects') IS NULL THEN
    RAISE EXCEPTION 'public.projects topilmadi — sync_flow_locks() faqat loyiha bosqichlari uchun. Hech narsa o''zgartirilmadi.';
  END IF;

  -- Funksiyaning O'ZI bormi? (yo'q bo'lsa bu fayl NOTO'G'RI bazaga tushgan)
  IF to_regprocedure('public.sync_flow_locks()') IS NULL THEN
    RAISE EXCEPTION 'public.sync_flow_locks() funksiyasi topilmadi. Bu fayl MAVJUD funksiyani TUZATADI, noldan yaratmaydi — noto''g''ri baza yoki funksiya allaqachon o''chirilgan. Hech narsa o''zgartirilmadi.';
  END IF;

  SELECT l.lanname INTO v_lang
    FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
   WHERE p.oid = 'public.sync_flow_locks()'::regprocedure;
  IF coalesce(v_lang, '') <> 'plpgsql' THEN
    RAISE EXCEPTION 'public.sync_flow_locks() tili "%" (kutilgan: plpgsql) — tanasini o''qib bo''lmaydi, ya''ni uni ko''r-ko''rona bosib ketmaymiz. Hech narsa o''zgartirilmadi.', coalesce(v_lang, '?');
  END IF;

  -- 🔴 ATRIBUTLAR — 3-bo'limdagi solishtiruv FAQAT TANANI (pg_proc.prosrc)
  --    ko'radi. Xavfsizlik konteksti (prosecdef) va search_path esa tanada
  --    KO'RINMAYDI: bazadagi funksiya SECURITY INVOKER bo'lsa ham tanasi
  --    ASL bilan mos chiqib, 4-bo'limdagi `CREATE OR REPLACE` uni JIMGINA
  --    SECURITY DEFINER ga aylantirib yuborardi (huquq darajasining sezilmay
  --    o'zgarishi). Shuning uchun farq RUN DAN OLDIN aytiladi.
  SELECT p.prosecdef, p.proconfig INTO v_sec, v_cfg
    FROM pg_proc p WHERE p.oid = 'public.sync_flow_locks()'::regprocedure;

  IF NOT coalesce(v_sec, false) THEN
    RAISE EXCEPTION 'public.sync_flow_locks() hozir SECURITY INVOKER, asl ta''rifda esa SECURITY DEFINER edi. Bu fayl 4-bo''limda uni SECURITY DEFINER bilan qayta yozadi — ya''ni funksiyaning HUQUQ DARAJASI jimgina o''zgarardi. FAIL-CLOSED: to''xtatildi, hech narsa o''zgartirilmadi. Agar INVOKER ATAYLAB qo''yilgan bo''lsa: 4-bo''limdagi `SECURITY DEFINER` qatorini va 4b-bo''limdagi prosecdef tekshiruvini mos ravishda o''zgartiring, so''ng qayta RUN qiling.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM unnest(coalesce(v_cfg, ARRAY[]::text[])) AS x
                  WHERE lower(replace(replace(x, '"', ''), ' ', '')) = 'search_path=public') THEN
    RAISE WARNING 'public.sync_flow_locks() da hozir `SET search_path TO ''public''` YO''Q yoki boshqacha (proconfig: %). 4-bo''lim uni AYNAN `search_path = public` bilan o''rnatadi — bu QATTIQLASHTIRISH (SECURITY DEFINER funksiya uchun majburiy), shuning uchun to''xtatilmaydi, LEKIN farq ochiq aytiladi.', coalesce(array_to_string(v_cfg, ', '), '(bo''sh)');
  END IF;

  -- Funksiya tanasi AYNAN shu ustunlarga murojaat qiladi. Biri yo'q bo'lsa
  -- yangi ta'rif ham ishlash paytida yiqilardi (PL/pgSQL kech bog'lanadi).
  FOREACH v_c IN ARRAY ARRAY['id','project_id','status','is_locked','flow_order','depends_on_prev'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='tasks' AND column_name=v_c) THEN
      RAISE EXCEPTION 'public.tasks.% ustuni yo''q — sync_flow_locks() tanasi aynan shu ustunga murojaat qiladi, ya''ni funksiya HOZIR ham buzuq. To''xtatildi (hech narsa o''zgartirilmadi).', v_c;
    END IF;
  END LOOP;
END $pre$;


-- ════════════════════════════════════════════════════════════════════════════
-- 0b) TIP MOSLIGI — ustun ALLAQACHON boshqa tipda bo'lsa TO'XTAYMIZ
--     (jimgina davom etsak `IS NOT TRUE` / `IS NOT DISTINCT FROM` boshqa
--      ma'no kasb etardi va TASKFIX_SHABLON.sql ham shu yerda yiqilardi)
-- ════════════════════════════════════════════════════════════════════════════
DO $typ$
DECLARE
  v_isT text;
  v_cyc text;
BEGIN
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_isT
    FROM pg_attribute a
   WHERE a.attrelid='public.tasks'::regclass AND a.attname='is_template' AND NOT a.attisdropped;
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_cyc
    FROM pg_attribute a
   WHERE a.attrelid='public.tasks'::regclass AND a.attname='cycle_id' AND NOT a.attisdropped;

  IF v_isT IS NOT NULL AND v_isT <> 'boolean' THEN
    RAISE EXCEPTION 'public.tasks.is_template ALLAQACHON mavjud, lekin tipi "%" (kutilgan: boolean). Skript uni O''ZGARTIRMAYDI. Qo''lda ko''rib chiqing. Hech narsa o''zgartirilmadi.', v_isT;
  END IF;
  IF v_cyc IS NOT NULL AND v_cyc <> 'uuid' THEN
    RAISE EXCEPTION 'public.tasks.cycle_id ALLAQACHON mavjud, lekin tipi "%" (kutilgan: uuid — project_cycles.id tipi). Skript uni O''ZGARTIRMAYDI. Hech narsa o''zgartirilmadi.', v_cyc;
  END IF;
END $typ$;


-- ════════════════════════════════════════════════════════════════════════════
-- 0c) HISOBOT JADVALLARI + NORMALLASHTIRISH YORDAMCHISI
--     🔴 Solishtiruv IZOH va BO'SHLIQdan xoli bo'lishi shart — aks holda
--        bir bo'shliq farqi "begona funksiya" hukmini berardi.
-- ════════════════════════════════════════════════════════════════════════════
DROP TABLE IF EXISTS pg_temp.trgfix_res;
CREATE TEMP TABLE pg_temp.trgfix_res (ord int, bosqich text, nom text, qiymat text, izoh text);

DROP TABLE IF EXISTS pg_temp.trgfix_ref;
CREATE TEMP TABLE pg_temp.trgfix_ref (k text PRIMARY KEY, v text, izoh text);

DROP TABLE IF EXISTS pg_temp.trgfix_src;
CREATE TEMP TABLE pg_temp.trgfix_src (k text PRIMARY KEY, v text);

CREATE OR REPLACE FUNCTION pg_temp.trgfix_norm(p_src text) RETURNS text
LANGUAGE sql IMMUTABLE AS $norm$
  SELECT btrim(
           regexp_replace(
             lower(
               regexp_replace(
                 regexp_replace(coalesce(p_src, ''), '/\*.*?\*/', ' ', 'gs'),
                 '--[^\n]*', ' ', 'g')
             ),
             '\s+', ' ', 'g')
         );
$norm$;


-- ════════════════════════════════════════════════════════════════════════════
-- 0d) INVENTAR — `public.tasks` da sync_flow_locks() ni ishlatadigan triggerlar
--     ⚠️ Bu bo'lim hech narsani O'ZGARTIRMAYDI — faqat O'QIYDI va hisobotga
--        yozadi. Trigger topilmasa/o'chiq bo'lsa 5-bo'lim tirik sinovlari
--        ENV bilan o'tkaziladi (soxta salbiy bo'lmasin).
-- ════════════════════════════════════════════════════════════════════════════
DO $inv$
DECLARE
  r        RECORD;
  v_n      int  := 0;
  v_on     int  := 0;
  v_names  text := '';
  v_other  text := '';
  v_tim    text;
  v_evt    text;
BEGIN
  RAISE NOTICE '── public.sync_flow_locks() ni ishlatadigan triggerlar ──';

  FOR r IN
    SELECT tg.tgname::text AS trg, tg.tgenabled AS en, tg.tgtype::int AS typ,
           (quote_ident(n.nspname) || '.' || quote_ident(c.relname)) AS tbl
      FROM pg_trigger tg
      JOIN pg_class     c ON c.oid = tg.tgrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE tg.tgfoid = 'public.sync_flow_locks()'::regprocedure
       AND NOT tg.tgisinternal
     ORDER BY n.nspname, c.relname, tg.tgname
  LOOP
    v_n := v_n + 1;

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

    IF r.en <> 'D' AND r.tbl = 'public.tasks' THEN
      v_on := v_on + 1;
      v_names := v_names || CASE WHEN v_names = '' THEN '' ELSE ', ' END || r.trg;
    END IF;

    RAISE NOTICE '  • % | % | % % | holat: %',
      r.trg, r.tbl, v_tim, v_evt,
      CASE WHEN r.en = 'D' THEN 'O''CHIQ' ELSE 'yoqilgan' END;
  END LOOP;

  IF v_n = 0 THEN
    RAISE WARNING 'sync_flow_locks() ni ishlatadigan TRIGGER topilmadi — funksiya baribir tuzatiladi, lekin 5-bo''lim tirik sinovlari ENV bilan o''tkaziladi (trigger ishga tushmasa qulf qiymatlari o''zgarmaydi).';
  END IF;

  -- `is_locked` ga tegishi mumkin bo'lgan BOSHQA triggerlar — sinov natijasi
  -- kutilmagan chiqsa sabab shular bo'lishi mumkin (hisobotda ko'rsatiladi).
  SELECT string_agg(tg.tgname::text, ', ' ORDER BY tg.tgname) INTO v_other
    FROM pg_trigger tg
   WHERE tg.tgrelid = 'public.tasks'::regclass
     AND NOT tg.tgisinternal
     AND tg.tgenabled <> 'D'
     AND tg.tgfoid <> 'public.sync_flow_locks()'::regprocedure;

  INSERT INTO pg_temp.trgfix_ref VALUES
    ('trg_n',     v_n::text,  'sync_flow_locks() ga bog''langan trigger soni (tgisinternal EMAS)'),
    ('trg_on',    v_on::text, 'shundan public.tasks da YOQILGANLARI (tirik sinov shunga qaraydi)'),
    ('trg_names', CASE WHEN v_names = '' THEN '-' ELSE v_names END, 'yoqilgan trigger nomlari'),
    ('trg_other', coalesce(v_other, '-'), 'public.tasks dagi BOSHQA yoqilgan triggerlar');

  INSERT INTO pg_temp.trgfix_res VALUES
    (30, 'trigger', 'sync_flow_locks() ga bog''langan triggerlar',
     v_n::text || ' ta (yoqilgan: ' || v_on::text || ')',
     'Trigger''ning O''ZIGA TEGILMAYDI — faqat funksiya almashadi (CREATE OR REPLACE), ya''ni vaqti/hodisasi/WHEN sharti, egasi (owner) va ruxsatlari saqlanadi. Nomlari: ' || CASE WHEN v_names = '' THEN '-' ELSE v_names END
       || ' · public.tasks dagi boshqa yoqilgan triggerlar: ' || coalesce(v_other, '-'));
END $inv$;


-- ═════════════════════════════════════════════════════════════════════════════
-- 0e) 🔴 UNIQUE INDEKS TO'QNASHUVI + FUNKSIYANING OLDINGI ATRIBUTLARI
--     ⚠️ Bu bo'lim hech narsani O'ZGARTIRMAYDI — faqat pg_index/pg_proc ni O'QIYDI.
--
--     5-bo'limdagi sentinel sahnalarda BITTA loyihada `flow_order` (va bo'lsa
--     `order_index`) ATAYLAB TAKRORLANADI: shablon va instansiya AYNAN bir xil
--     tartib raqamida turadi — qorovullarni tekshiradigan holat aynan shu.
--     Agar `public.tasks` da QISMAN BO'LMAGAN UNIQUE indeks bo'lsa va uning
--     HAMMA kalit ustunlari sinov qatorlarida takrorlansa, INSERT 23505
--     (unique_violation) bilan yiqilardi — u holda tirik sinovlar "ENV" bilan
--     o'tkazib yuborilar, funksiya esa BARIBIR COMMIT bo'lardi. Ya'ni sabab
--     jimgina "muhit xatosi" bo'lib qolardi. Shuning uchun OLDINDAN aytiladi.
--     (Naqsh: TASKFIX_SHABLON.sql 477–503.)
--
--     ⚠️ `indkey` — int2vector; uni int[] GA cast qilib bo'lmaydi, faqat int2[].
--     ⚠️ Kalit ustunlari orasida `id` yoki `title` bo'lgan indeks XAVFSIZ:
--        sinovda ular har qatorda BOSHQACHA (id — DEFAULT/IDENTITY,
--        title — 'TRGFIX A0', 'TRGFIX B1', …).
--     🔴 Bu TO'XTATUVCHI xato EMAS (WARNING): indeks bo'lsa ham funksiya
--        tuzatiladi; faqat tirik sinovlar o'tmay qolishi mumkin.
-- ═════════════════════════════════════════════════════════════════════════════
DO $uq$
DECLARE
  v_uq   text;
  v_expr text;
  v_sec  boolean;
  v_cfg  text[];
BEGIN
  -- (a) oddiy (ifodasiz), qisman BO'LMAGAN UNIQUE indekslar — KALIT ustunlari
  --     orasida `id` ham, `title` ham bo'lmasa, sinov qatorlari to'qnashishi
  --     MUMKIN (klassik holat: UNIQUE (project_id, flow_order)).
  --     ⚠️ `indnkeyatts` — faqat KALIT ustunlar soni: INCLUDE ustunlari
  --        yagonalikda qatnashmaydi, ya'ni ular hisobga OLINMAYDI.
  SELECT string_agg(x.idx || ' (' || coalesce(x.cols, '?') || ')', ', ' ORDER BY x.idx) INTO v_uq
    FROM (
      SELECT i.indexrelid::regclass::text AS idx,
             (SELECT string_agg(a.attname, ', ' ORDER BY k.ord)
                FROM unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
                JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
               WHERE k.ord <= i.indnkeyatts) AS cols
        FROM pg_index i
       WHERE i.indrelid = 'public.tasks'::regclass
         AND i.indisunique
         AND i.indpred IS NULL
         AND array_position(i.indkey::int2[], 0::int2) IS NULL
         AND NOT EXISTS (
               SELECT 1
                 FROM unnest(i.indkey::int2[]) WITH ORDINALITY AS ik(attnum, ord)
                 JOIN pg_attribute a2 ON a2.attrelid = i.indrelid AND a2.attnum = ik.attnum
                WHERE ik.ord <= i.indnkeyatts
                  AND a2.attname IN ('id', 'title'))
    ) x;

  -- (b) IFODALI (expression) UNIQUE indekslarni tahlil qila olmaymiz
  SELECT string_agg(i.indexrelid::regclass::text, ', ') INTO v_expr
    FROM pg_index i
   WHERE i.indrelid = 'public.tasks'::regclass
     AND i.indisunique
     AND i.indpred IS NULL
     AND array_position(i.indkey::int2[], 0::int2) IS NOT NULL;

  IF v_uq IS NOT NULL THEN
    RAISE WARNING '🔴 public.tasks da UNIQUE indeks(lar) bor va ularning HAMMA kalit ustunlari sentinel sahnada takrorlanishi mumkin: %. Sinov qatorlari ATAYLAB bir xil (project_id, flow_order) bilan kiritiladi; INSERT 23505 (unique_violation) bilan yiqilsa, TIRIK SINOVLAR "ENV" bilan o''tkazib yuboriladi (funksiya baribir tuzatiladi). Sabab AYNAN shu bo''lishi mumkin — (49) qatoridagi ENV matnini shu ro''yxat bilan solishtiring.', v_uq;
  END IF;
  IF v_expr IS NOT NULL THEN
    RAISE WARNING 'public.tasks da IFODALI (expression) UNIQUE indeks bor: %. Skript uning sentinel qatorlar bilan to''qnashishini oldindan ayta olmaydi — sinovlar ENV bilan o''tkazib yuborilsa, sabab shu bo''lishi mumkin.', v_expr;
  END IF;

  INSERT INTO pg_temp.trgfix_ref VALUES
    ('uq_risk', coalesce(v_uq,   '-'), 'sentinel sahna bilan to''qnashishi mumkin bo''lgan UNIQUE indekslar'),
    ('uq_expr', coalesce(v_expr, '-'), 'ifodali (expression) UNIQUE indekslar — tahlil qilinmaydi');

  INSERT INTO pg_temp.trgfix_res VALUES
    (4, 'qorovul', '🔴 UNIQUE indeks to''qnashuvi (sentinel sahna uchun)',
     CASE WHEN v_uq IS NULL AND v_expr IS NULL THEN 'xavf yo''q'
          WHEN v_uq IS NOT NULL THEN 'DIQQAT: ' || v_uq
          ELSE 'ifodali indeks: ' || v_expr END,
     'Sinov sahnalarida bitta loyihada `flow_order` (va `order_index`) ATAYLAB takrorlanadi — shablon va instansiya bir xil tartib raqamida turadi. Qisman BO''LMAGAN UNIQUE indeksning hamma kalit ustunlari shu qatorlarda takrorlansa INSERT 23505 bilan yiqilib, tirik sinovlar ENV bilan o''tkazib yuborilardi (sabab jimgina qolmasin deb ochiq aytiladi). Kalitida `id` yoki `title` bo''lgan indeks XAVFSIZ. Bu TO''XTATUVCHI xato emas — funksiya baribir tuzatiladi. Ifodali indekslar: '
       || coalesce(v_expr, '-') || '.');

  -- (c) funksiyaning O'ZGARISHDAN OLDINGI atributlari (0-bo'limda tekshirilgan)
  SELECT p.prosecdef, p.proconfig INTO v_sec, v_cfg
    FROM pg_proc p WHERE p.oid = 'public.sync_flow_locks()'::regprocedure;

  INSERT INTO pg_temp.trgfix_res VALUES
    (12, 'funksiya', 'o''zgarishdan OLDINGI atributlar',
     CASE WHEN coalesce(v_sec, false) THEN 'SECURITY DEFINER' ELSE 'SECURITY INVOKER' END
       || ' · ' || coalesce(array_to_string(v_cfg, ', '), '(proconfig bo''sh)'),
     '🔴 3-bo''limdagi solishtiruv FAQAT TANANI (pg_proc.prosrc) ko''radi — xavfsizlik konteksti va search_path unda KO''RINMAYDI. Bazadagi funksiya SECURITY INVOKER bo''lsa, tanasi ASL bilan mos chiqib `CREATE OR REPLACE` uni JIMGINA SECURITY DEFINER ga aylantirib yuborardi; shuning uchun 0-bo''lim buni FAIL-CLOSED tekshiradi (INVOKER → RAISE EXCEPTION, search_path farqi → WARNING, chunki u qattiqlashtirish).');
END $uq$;



-- ════════════════════════════════════════════════════════════════════════════
-- 1) 🔴 USTUNLAR — is_template va cycle_id
--    ⚠️ 🔴 SHU YERDA `public.tasks` GA ACCESS EXCLUSIVE QULF OLINADI va u
--       COMMIT gacha USHLAB TURILADI.
--    ⚠️ Ta'rif TASKFIX_SHABLON.sql (922 / 924-qatorlar) bilan HARFMA-HARF
--       bir xil → u qayta RUN qilinganda `ADD COLUMN` no-op bo'ladi, FK va
--       CHECK esa alohida `ADD CONSTRAINT` bilan baribir qo'shiladi.
--    ⚠️ `template_id` ATAYLAB QO'SHILMAYDI — uni SHABLON `tasks.id` TIPI
--       bilan qo'shadi; bu yerda tipni taxmin qilsak FK mos kelmay qolardi.
-- ════════════════════════════════════════════════════════════════════════════
DO $col$
DECLARE
  v_had_t boolean;
  v_had_c boolean;
  v_nulls bigint;
BEGIN
  v_had_t := EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema='public' AND table_name='tasks' AND column_name='is_template');
  v_had_c := EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema='public' AND table_name='tasks' AND column_name='cycle_id');

  ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS is_template boolean NOT NULL DEFAULT false;
  ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS cycle_id uuid;

  -- Yarim o'rnatilgan holat: ustun bor-u NULLABLE. Buni TUZATMAYMIZ (mavjud
  -- ma'lumot bosilmasin) — `IS NOT TRUE` NULL ni ham to'g'ri qamraydi.
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='tasks'
                AND column_name='is_template' AND is_nullable='YES') THEN
    SELECT count(*) INTO v_nulls FROM public.tasks WHERE is_template IS NULL;
    RAISE WARNING 'public.tasks.is_template NULLABLE (NULL qatorlar: %). Bu fayl uni O''ZGARTIRMAYDI — yangi funksiya `IS NOT TRUE` ishlatgani uchun NULL ham "shablon EMAS" deb to''g''ri qaraladi. NOT NULL ni TASKFIX_SHABLON.sql qo''yadi.', v_nulls;
  END IF;

  INSERT INTO pg_temp.trgfix_res VALUES
    (1, 'ustun', 'public.tasks.is_template (boolean NOT NULL DEFAULT false)',
     CASE WHEN v_had_t THEN 'allaqachon bor edi' ELSE 'QO''SHILDI' END,
     '🔴 Yangi funksiya tanasi unga murojaat qiladi — PL/pgSQL KECH BOG''LANADI, ya''ni ustunsiz o''rnatilsa xato faqat ishlash paytida (har status o''zgarishida) chiqib prod darrov buzilardi. Ta''rif TASKFIX_SHABLON.sql dagi bilan HARFMA-HARF bir xil (fast default — jadval qayta yozilmaydi).'),
    (2, 'ustun', 'public.tasks.cycle_id (uuid)',
     CASE WHEN v_had_c THEN 'allaqachon bor edi' ELSE 'QO''SHILDI' END,
     'FK (tasks_cycle_fk → project_cycles) va CHECK (tasks_template_flags_chk) BU YERDA QO''YILMAYDI — ular TASKFIX_SHABLON.sql ning alohida ADD CONSTRAINT qadamlari. Ziddiyat yo''q.'),
    (3, 'ustun', 'public.tasks.template_id', 'TEGILMADI (ataylab)',
     'Uni TASKFIX_SHABLON.sql katalogdan olingan `tasks.id` TIPI bilan qo''shadi. Bu yerda tipni taxmin qilsak FK mos kelmay qolardi; yangi funksiya esa unga murojaat QILMAYDI.');
END $col$;

COMMENT ON COLUMN public.tasks.is_template IS
  '🔴 SHABLON belgisi: true = bu qator ISH EMAS, loyiha bosqichining TA''RIFI. sync_flow_locks() bunday qatorga is_locked YOZMAYDI va uni "oldingi bosqich" deb HISOBLAMAYDI. Izohning to''liq versiyasini TASKFIX_SHABLON.sql yozadi.';
COMMENT ON COLUMN public.tasks.cycle_id IS
  'INSTANSIYA → o''zi tegishli SIKL (project_cycles.id; FK ni TASKFIX_SHABLON.sql qo''yadi). sync_flow_locks() voris qidiruvini AYNAN shu ustun bilan chegaralaydi — o''tgan siklning `completed` qatori yangi sikl bosqichini ochib yubormasin.';


-- ════════════════════════════════════════════════════════════════════════════
-- 2) ZAXIRA NUSXA + KLASSIFIKATSIYA
--    🔴 IDEMPOTENTLIK: qayta RUN qilinganda zaxira ALLAQACHON TUZATILGAN
--       ta'rifni BOSIB KETMAYDI (asl nusxa yo'qolmaydi) — jadvaldan hech
--       qachon DELETE qilinmaydi va bir xil matn ikkinchi marta yozilmaydi.
--    ⚠️ Jadval `anon`/`authenticated` dan REVOKE qilinadi va RLS yoqiladi
--       (policy YO'Q) — Supabase'da public sxemadagi yangi jadval sukut
--       bo'yicha PostgREST orqali ochilib qolmasin.
-- ════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.taskfix_trigger_backup (
  id       bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  fn       text        NOT NULL,
  def      text        NOT NULL,
  saved_at timestamptz NOT NULL DEFAULT now(),
  izoh     text
);

COMMENT ON TABLE public.taskfix_trigger_backup IS
  'Trigger funksiyalarining O''ZGARTIRISHDAN OLDINGI to''liq ta''rifi (pg_get_functiondef). TASKFIX_SHABLON_TRIGGER_FIX.sql yozadi. Qaytarish: shu faylning oxiridagi "QAYTARISH" blokiga qarang. Qatorlar HECH QACHON o''chirilmaydi/yangilanmaydi.';

ALTER TABLE public.taskfix_trigger_backup ENABLE ROW LEVEL SECURITY;

DO $rvk$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    REVOKE ALL ON TABLE public.taskfix_trigger_backup FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    REVOKE ALL ON TABLE public.taskfix_trigger_backup FROM authenticated;
  END IF;
END $rvk$;

DO $bak$
DECLARE
  v_def  text;
  v_cur  text;
  v_asl  text;
  v_new  text;
  v_cls  text;
  v_bak  text;
BEGIN
  -- ── KUTILGAN ASL TANA (Asilbek 2026-08-24 da bazadan dump qilgan) ────────
  v_asl := $asl$
BEGIN
  IF NEW.project_id IS NOT NULL AND NEW.status IS DISTINCT FROM OLD.status THEN
    UPDATE tasks t SET is_locked = (
      COALESCE(t.depends_on_prev, false) = true
      AND t.status NOT IN ('completed','cancelled')
      AND EXISTS (
        SELECT 1 FROM tasks p
        WHERE p.project_id = t.project_id
          AND p.flow_order = (SELECT MAX(p2.flow_order) FROM tasks p2
                              WHERE p2.project_id = t.project_id AND p2.flow_order < t.flow_order)
          AND p.status <> 'completed'
      )
    )
    WHERE t.project_id = NEW.project_id;
  END IF;
  RETURN NEW;
END;
$asl$;

  -- ── TUZATILGAN TANA (4-bo'limda AYNAN shu o'rnatiladi) ───────────────────
  --    ⚠️ Bu NUSXA. 4b-bo'lim o'rnatilgandan KEYIN bazadan qayta o'qib shu
  --       matn bilan solishtiradi — ikki nusxa bir-biridan siljib ketmasin.
  v_new := $new$
BEGIN
  IF NEW.project_id IS NOT NULL AND NEW.status IS DISTINCT FROM OLD.status THEN
    UPDATE tasks t SET is_locked = (
      COALESCE(t.depends_on_prev, false) = true
      AND t.status NOT IN ('completed','cancelled')
      AND EXISTS (
        SELECT 1 FROM tasks p
        WHERE p.project_id = t.project_id
          -- 🔴 SHABLON bosqich EMAS (u hech qachon 'completed' bo'lmaydi)
          AND p.is_template IS NOT TRUE
          -- 🔴 faqat O'Z SIKLI (NULL = eski, siklsiz ma'lumot)
          AND p.cycle_id IS NOT DISTINCT FROM t.cycle_id
          AND p.flow_order = (SELECT MAX(p2.flow_order) FROM tasks p2
                              WHERE p2.project_id = t.project_id
                                AND p2.is_template IS NOT TRUE
                                AND p2.cycle_id IS NOT DISTINCT FROM t.cycle_id
                                AND p2.flow_order < t.flow_order)
          AND p.status <> 'completed'
      )
    )
    WHERE t.project_id = NEW.project_id
      -- 🔴 SHABLONGA is_locked YOZILMAYDI (u ish emas, ta'rif)
      AND t.is_template IS NOT TRUE;
  END IF;
  RETURN NEW;
END;
$new$;

  INSERT INTO pg_temp.trgfix_src VALUES ('asl', v_asl), ('new', v_new);

  SELECT pg_get_functiondef('public.sync_flow_locks()'::regprocedure) INTO v_def;
  SELECT p.prosrc INTO v_cur
    FROM pg_proc p WHERE p.oid = 'public.sync_flow_locks()'::regprocedure;

  -- ── KLASSIFIKATSIYA (hukmni 3-bo'lim chiqaradi) ──────────────────────────
  IF pg_temp.trgfix_norm(v_cur) = pg_temp.trgfix_norm(v_new) THEN
    v_cls := 'FIX';      -- allaqachon tuzatilgan → 2-RUN, bu NORMAL
  ELSIF pg_temp.trgfix_norm(v_cur) = pg_temp.trgfix_norm(v_asl) THEN
    v_cls := 'ASL';      -- kutilgan asl ta'rif
  ELSE
    v_cls := 'BEGONA';   -- 🔴 kimdir o'zgartirgan / boshqa versiya
  END IF;

  -- ── ZAXIRA ───────────────────────────────────────────────────────────────
  --    Tuzatilgan ta'rif SAQLANMAYDI (2-RUN da asl nusxa ustiga yozilmasin).
  IF v_cls = 'FIX' THEN
    v_bak := 'saqlanmadi (2-RUN)';
  ELSIF EXISTS (SELECT 1 FROM public.taskfix_trigger_backup b
                 WHERE b.fn = 'public.sync_flow_locks()'
                   AND pg_temp.trgfix_norm(b.def) = pg_temp.trgfix_norm(v_def)) THEN
    v_bak := 'allaqachon saqlangan';
  ELSE
    INSERT INTO public.taskfix_trigger_backup (fn, def, izoh)
    VALUES ('public.sync_flow_locks()', v_def,
            'TASKFIX_SHABLON_TRIGGER_FIX.sql o''zgartirishidan OLDINGI ta''rif (klassifikatsiya: ' || v_cls || ')');
    v_bak := 'SAQLANDI';
  END IF;

  INSERT INTO pg_temp.trgfix_ref VALUES
    ('cls', v_cls, 'mavjud ta''rifning klassifikatsiyasi: ASL | FIX | BEGONA'),
    ('bak', v_bak, 'zaxira nusxa holati');

  INSERT INTO pg_temp.trgfix_res VALUES
    (10, 'zaxira', 'public.taskfix_trigger_backup', v_bak,
     'O''zgartirishdan OLDINGI to''liq pg_get_functiondef() matni. Qatorlar HECH QACHON o''chirilmaydi/yangilanmaydi va TUZATILGAN ta''rif saqlanmaydi — ya''ni qayta RUN asl nusxani BOSIB KETMAYDI. Jadval anon/authenticated dan REVOKE qilingan, RLS yoqilgan (policy yo''q).');

  RAISE NOTICE 'Klassifikatsiya: % · zaxira: %', v_cls, v_bak;
END $bak$;


-- ════════════════════════════════════════════════════════════════════════════
-- 3) 🔴 QOROVUL — FAIL-CLOSED
--    Mavjud tana KUTILGAN ASL ta'rif bilan mosmi (izoh/bo'shliq
--    normallashtirilgandan keyin)? Mos EMAS bo'lsa — kimdir oradan
--    o'zgartirgan yoki bu boshqa versiya → TO'XTAYMIZ va tanani NOTICE bilan
--    chop etamiz. Begona funksiya KO'R-KO'RONA BOSIB KETILMAYDI.
--    ⚠️ ALLAQACHON TUZATILGAN ta'rif (2-RUN) — bu NORMAL: NOTICE + davom.
-- ════════════════════════════════════════════════════════════════════════════
DO $guard$
DECLARE
  v_cls text;
  v_cur text;
  v_asl text;
BEGIN
  SELECT v INTO v_cls FROM pg_temp.trgfix_ref WHERE k='cls';
  SELECT v INTO v_asl FROM pg_temp.trgfix_src WHERE k='asl';

  IF v_cls = 'FIX' THEN
    RAISE NOTICE 'public.sync_flow_locks() ALLAQACHON tuzatilgan ta''rifda (2-RUN) — CREATE OR REPLACE baribir bajariladi (natija bir xil), tirik sinovlar esa qayta o''tkaziladi.';
    INSERT INTO pg_temp.trgfix_res VALUES
      (11, 'qorovul', '🔴 mavjud ta''rif kutilganmi?', 'ALLAQACHON TUZATILGAN (2-RUN)',
       'Normallashtirilgan (izoh/bo''shliq tozalangan, kichik harf) solishtiruv. Bu XATO emas — skript idempotent.');
    RETURN;
  END IF;

  IF v_cls = 'ASL' THEN
    INSERT INTO pg_temp.trgfix_res VALUES
      (11, 'qorovul', '🔴 mavjud ta''rif kutilganmi?', 'HA — ASL ta''rif',
       'Bazadagi tana Asilbek dump qilgan ASL ta''rif bilan AYNAN mos (izoh/bo''shliq normallashtirilgandan keyin). Faqat shundan keyin ustiga yozildi — begona funksiya ko''r-ko''rona bosilmaydi.');
    RETURN;
  END IF;

  -- ── BEGONA ───────────────────────────────────────────────────────────────
  SELECT p.prosrc INTO v_cur
    FROM pg_proc p WHERE p.oid = 'public.sync_flow_locks()'::regprocedure;

  RAISE NOTICE '── BAZADAGI HOZIRGI TANA (public.sync_flow_locks) ──%',
    chr(10) || left(pg_get_functiondef('public.sync_flow_locks()'::regprocedure), 4000);
  RAISE NOTICE '── KUTILGAN ASL TANA ──%', chr(10) || v_asl;
  -- Farq faqat bo'shliq/izohda emasligini ko'rish uchun (solishtiruv AYNAN
  -- shu ikki matn ustida bo'ladi):
  RAISE NOTICE '── NORMALLASHTIRILGAN (hozirgi) ──%', chr(10) || left(pg_temp.trgfix_norm(v_cur), 2000);
  RAISE NOTICE '── NORMALLASHTIRILGAN (kutilgan ASL) ──%', chr(10) || left(pg_temp.trgfix_norm(v_asl), 2000);

  RAISE EXCEPTION '🔴 public.sync_flow_locks() ning bazadagi tanasi KUTILGAN ASL ta''rif bilan MOS EMAS (va tuzatilgan ta''rif ham emas) — kimdir uni oradan o''zgartirgan yoki bu boshqa versiya. FAIL-CLOSED: begona funksiyani KO''R-KO''RONA BOSIB KETMAYMIZ. Ikkala tana yuqorida NOTICE bilan to''liq chop etildi — farqni ko''rib chiqing va (a) yangi qorovullarni (`AND p.is_template IS NOT TRUE`, `AND p.cycle_id IS NOT DISTINCT FROM t.cycle_id`, `p2` uchun ham, hamda `WHERE ... AND t.is_template IS NOT TRUE`) mavjud tanaga QO''LDA qo''shing, yoki (b) shu fayldagi 2-bo''limning `v_asl` matnini bazadagi haqiqiy tana bilan yangilang. 🔴 HECH NARSA O''ZGARMADI — hammasi qaytarildi (ustunlar ham qo''shilmadi).';
END $guard$;


-- ════════════════════════════════════════════════════════════════════════════
-- 4) 🔴 TUZATILGAN TA'RIFNI O'RNATISH
--    ⚠️ TRIGGER'GA TEGILMAYDI (u DROP/CREATE qilinmaydi) — faqat funksiya
--       almashadi, ya'ni EGASI (owner), ruxsatlar, trigger vaqti/hodisasi/
--       WHEN sharti O'ZGARMAYDI.
--    ⚠️ SECURITY DEFINER · SET search_path TO 'public' · LANGUAGE plpgsql —
--       hammasi ASL ta'rifdagidek saqlangan.
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.sync_flow_locks()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $sfl$
BEGIN
  IF NEW.project_id IS NOT NULL AND NEW.status IS DISTINCT FROM OLD.status THEN
    UPDATE tasks t SET is_locked = (
      COALESCE(t.depends_on_prev, false) = true
      AND t.status NOT IN ('completed','cancelled')
      AND EXISTS (
        SELECT 1 FROM tasks p
        WHERE p.project_id = t.project_id
          -- 🔴 SHABLON bosqich EMAS (u hech qachon 'completed' bo'lmaydi)
          AND p.is_template IS NOT TRUE
          -- 🔴 faqat O'Z SIKLI (NULL = eski, siklsiz ma'lumot)
          AND p.cycle_id IS NOT DISTINCT FROM t.cycle_id
          AND p.flow_order = (SELECT MAX(p2.flow_order) FROM tasks p2
                              WHERE p2.project_id = t.project_id
                                AND p2.is_template IS NOT TRUE
                                AND p2.cycle_id IS NOT DISTINCT FROM t.cycle_id
                                AND p2.flow_order < t.flow_order)
          AND p.status <> 'completed'
      )
    )
    WHERE t.project_id = NEW.project_id
      -- 🔴 SHABLONGA is_locked YOZILMAYDI (u ish emas, ta'rif)
      AND t.is_template IS NOT TRUE;
  END IF;
  RETURN NEW;
END;
$sfl$;


-- ════════════════════════════════════════════════════════════════════════════
-- 4b) O'RNATILGANINI TASDIQLASH
--     🔴 2-bo'limdagi `v_new` NUSXASI bilan bazadagi haqiqiy tana solishtiriladi
--        — ikki nusxa bir-biridan siljib ketgan bo'lsa (birini tahrirlab
--        ikkinchisi unutilgan) SKRIPT SHU YERDA TO'XTAYDI.
-- ════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_cur   text;
  v_new   text;
  v_sec   boolean;
  v_lang  text;
  v_cfg   text[];
  v_miss  text := '';
  v_g     text;
BEGIN
  SELECT v INTO v_new FROM pg_temp.trgfix_src WHERE k='new';

  SELECT p.prosrc, p.prosecdef, l.lanname, p.proconfig
    INTO v_cur, v_sec, v_lang, v_cfg
    FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
   WHERE p.oid = 'public.sync_flow_locks()'::regprocedure;

  IF pg_temp.trgfix_norm(v_cur) IS DISTINCT FROM pg_temp.trgfix_norm(v_new) THEN
    RAISE EXCEPTION '🔴 O''rnatilgan tana 2-bo''limdagi `v_new` NUSXASI bilan mos emas — fayldagi IKKI nusxa bir-biridan siljib ketgan (birini tahrirlab ikkinchisi unutilgan). Hammasi qaytarildi.';
  END IF;

  IF NOT coalesce(v_sec, false) THEN
    RAISE EXCEPTION '🔴 public.sync_flow_locks() SECURITY DEFINER emas — asl ta''rifda u SECURITY DEFINER edi. Hammasi qaytarildi.';
  END IF;
  IF coalesce(v_lang, '') <> 'plpgsql' THEN
    RAISE EXCEPTION '🔴 public.sync_flow_locks() tili "%" (kutilgan: plpgsql). Hammasi qaytarildi.', coalesce(v_lang, '?');
  END IF;
  -- ⚠️ Qiymat qanday saqlanishi (qo'shtirnoq/bo'shliq) PG versiyasiga bog'liq
  --    bo'lishi mumkin — solishtiruv normallashtirilgan, aks holda KOSMETIK
  --    farq butun migratsiyani yiqitardi.
  IF NOT EXISTS (SELECT 1 FROM unnest(coalesce(v_cfg, ARRAY[]::text[])) AS x
                  WHERE lower(replace(replace(x, '"', ''), ' ', '')) = 'search_path=public') THEN
    RAISE EXCEPTION '🔴 public.sync_flow_locks() da `SET search_path TO ''public''` yo''q — SECURITY DEFINER funksiya uchun bu MAJBURIY. Hammasi qaytarildi.';
  END IF;

  -- Qorovullar ROSTDAN tanada turibdimi (izohlar tozalangandan keyin)
  FOREACH v_g IN ARRAY ARRAY[
      't.is_template is not true',
      'p.is_template is not true',
      'p2.is_template is not true',
      'p.cycle_id is not distinct from t.cycle_id',
      'p2.cycle_id is not distinct from t.cycle_id'] LOOP
    IF position(v_g IN pg_temp.trgfix_norm(v_cur)) = 0 THEN
      v_miss := v_miss || CASE WHEN v_miss = '' THEN '' ELSE ', ' END || v_g;
    END IF;
  END LOOP;
  IF v_miss <> '' THEN
    RAISE EXCEPTION '🔴 O''rnatilgan tanada QOROVUL(lar) yo''q: %. Hammasi qaytarildi.', v_miss;
  END IF;

  INSERT INTO pg_temp.trgfix_res VALUES
    (20, 'funksiya', 'public.sync_flow_locks()', 'TUZATILGAN TA''RIF O''RNATILDI',
     '5 ta qorovul tanada tasdiqlandi: t.is_template · p.is_template · p2.is_template · p.cycle_id · p2.cycle_id. SECURITY DEFINER, LANGUAGE plpgsql va SET search_path TO ''public'' saqlangan; CREATE OR REPLACE egasini (owner) va ruxsatlarini o''zgartirmaydi.'),
    (21, 'qaror', 'trg_sync_flow_locks (trigger''ning O''ZI)', 'TEGILMADI',
     'Trigger DROP/CREATE qilinmaydi — vaqti (BEFORE/AFTER), hodisasi va WHEN sharti bazada qanday bo''lsa shundayligicha qoldi. Faqat u chaqiradigan funksiya almashdi.'),
    (22, 'qaror', '🔴 `p2` HAM qorovullandi', 'ha',
     'Faqat `p` qorovullansa, ichki MAX(p2.flow_order) shablonda yoki BOSHQA SIKLDA mavjud flow_order ni tanlab qolishi mumkin; keyin `p` o''sha qiymat bo''yicha o''z siklida hech narsa topmaydi, EXISTS yolg''on bo''ladi va bosqich NOTO''G''RI OCHILADI. (L6a) sinovi aynan shuni tekshiradi.'),
    (23, 'qaror', '`IS NOT TRUE` / `IS NOT DISTINCT FROM` (`= false` / `=` EMAS)', 'ha',
     'NULL xavfsizligi va ESKI MA''LUMOT UCHUN EKVIVALENTLIK: shablonsiz va cycle_id NULL bo''lgan bazada `false IS NOT TRUE` = true, `NULL IS NOT DISTINCT FROM NULL` = true → har qator qorovuldan o''tadi va natija ASL funksiya bilan AYNAN bir xil. (L1), (L2), (L3), (L7) buni tirik tasdiqlaydi.');
END $verify$;


-- ════════════════════════════════════════════════════════════════════════════
-- 5) 🔴 TIRIK SINOVLAR (L1..L8) — SENTINEL-ROLLBACK
--    Sahna butunlay sentinel: 5 loyiha + 24 bosqich/shablon. Oxirida ichki
--    blok ATAYLAB EXCEPTION bilan tugatiladi → subtranzaksiya qaytadi va
--    bazada BITTA QATOR HAM QOLMAYDI.
--
--    (L1) ESKI MANTIQ BUZILMAGAN — ketma-ket bosqichlar (depends_on_prev),
--         shablonsiz, cycle_id NULL: 1-bosqich `completed` bo'lgach 2-chi
--         OCHILADI (L1a), 3-chi esa QULFLANGAN qoladi (L1b).
--    (L2) Parallel (depends_on_prev = false) hech qachon qulflanmaydi.
--    (L3) BIRINCHI bosqich (vorisi/oldingisi yo'q) qulflanmaydi.
--    (L4) SHABLON BLOKLAMAYDI — o'sha flow_order da status='new' shablon
--         bo'lsa ham 1-chi tugagach 2-chi OCHILADI (ASL da abadiy qulflangan
--         qolardi).
--    (L5) SHABLONGA is_locked YOZILMAYDI — TA (is_locked = TRUE, dop = false)
--         true bo'lib QOLADI, TB (is_locked = FALSE, dop = true) false bo'lib
--         QOLADI. Ikki yo'nalish ham tekshiriladi.
--    (L6) BOSHQA SIKL ochib yubormaydi (a/b/c).
--    (L7) `cancelled` voris `completed` EMAS → keyingisi qulflangan qoladi
--         (ASL mantiqda ham shunday — REGRESSIYA tekshiruvi).
--    (L8) 🔴 SHABLON + SIKLSIZ INSTANSIYA BIR LOYIHADA (hamma qatorda
--         cycle_id NULL) — `p.is_template` va `p2.is_template` qorovullarini
--         YAGONA tekshiradigan sahna. A/B/C/D da shablon doim cycle_id NULL,
--         instansiyalar esa sikl bilan → ularni SIKL qorovuli allaqachon
--         chetlatib qo'yadi va shablon qorovuli "ishlamaydi". Prodda esa bu
--         holat erishiladi: SHABLON migratsiyasi mavjud qatorlarga cycle_id
--         yozadi, lekin keyin mijoz cycle_id SIZ yangi bosqich yaratsa —
--         shablon ham, instansiya ham cycle_id NULL bo'lib bir loyihada
--         uchrashadi. (a) shablon keyingisini BLOKLAMAYDI, (b) shablon
--         MAX(flow_order) ni O'G'IRLAMAYDI, (c) siklsiz sahnada ham shablonga
--         is_locked YOZILMAYDI (ikki yo'nalish: TE1 va TE2).
--
--    🔴 QOROVUL ↔ HUKM XARITASI (mutatsiya sinovi bilan tasdiqlangan —
--       qorovul olib tashlansa AYNAN shu hukm yiqiladi):
--         p.is_template  IS NOT TRUE ................. (L8a) E2
--         p2.is_template IS NOT TRUE ................. (L8b) E6
--         p.cycle_id  IS NOT DISTINCT FROM t.cycle_id  (L4)  B2
--         p2.cycle_id IS NOT DISTINCT FROM t.cycle_id  (L6a) D5
--         t.is_template IS NOT TRUE (UPDATE ... WHERE) (L5) TA + (L8c) TE1/TE2
--       (L1), (L2), (L3), (L6b), (L6c), (L7) — REGRESSIYA/EKVIVALENTLIK
--       hukmlari: ular hech bir qorovulga bog'liq emas va ASL funksiyada ham
--       o'tadi; ular yiqilsa sabab TANA yoki BOSHQA trigger.
--
--    🔴 HAR ASSERTSIYA HAQIQIY YOZUVNI TALAB QILADI: har qator ataylab
--       KUTILGANNING TESKARISI bilan INSERT qilinadi, ya'ni trigger umuman
--       ishlamasa sinov ham yiqiladi.
--    ⚠️ Muhit to'sgan holat (ENV) hukmlardan OLDIN ajratiladi — soxta salbiy
--       bo'lmasin (bo'sh baza / noma'lum majburiy ustun / trigger yo'q).
-- ════════════════════════════════════════════════════════════════════════════
DO $live$
DECLARE
  v_ws       uuid;
  v_usr      uuid;
  v_on       int  := 0;
  v_skip     text;
  v_bad      text;
  v_pname    text;
  v_projtyp  text;
  v_has_cyc  boolean;
  v_has_cmpl boolean;
  v_pcols    text := '';
  v_pvals    text := '';
  v_ordcols  text := '';
  v_ordvals  text := '';
  v_tcols    text := '';
  v_tvals    text := '';
  v_pins     text;
  v_ins      text;
  v_sel      text;
  v_updc     text;
  v_updx     text;
  v_pexpr    text;
  v_pa       text;
  v_pb       text;
  v_pc       text;
  v_pd       text;
  v_pe       text;
  v_g1       uuid;
  v_g2       uuid;
  v_g3       uuid;
  v_g4       uuid;
  v_tmp      text;
  v_a1       text;
  v_b1       text;
  v_c1       text;
  v_d1       text;
  v_d2       text;
  v_e1       text;
  i_a0 text; i_a2 text; i_a3 text; i_a4 text;
  i_b2 text; i_b4 text; i_ta text; i_tb text;
  i_c2 text; i_d3 text; i_d5 text;
  i_te1 text; i_te2 text; i_e2 text; i_e6 text;
  q_a0 text; q_a2 text; q_a3 text; q_a4 text; q_b2 text; q_tb1 text;
  q_tb2 text; q_b4 text; q_d5 text; q_d3 text; q_c2 text;
  q_e2 text; q_e6 text; q_te1 text; q_te2 text;
  v_probe text;
  v_err   text;
  v_state text;
  v_fail  text := '';
  v_msg   text;
  v_other text;
BEGIN
  SELECT coalesce(v, '0')::int INTO v_on    FROM pg_temp.trgfix_ref WHERE k='trg_on';
  SELECT v                     INTO v_other FROM pg_temp.trgfix_ref WHERE k='trg_other';

  -- ── (5.0) SHART-SHAROIT ──────────────────────────────────────────────────
  IF coalesce(v_on, 0) = 0 THEN
    v_skip := 'public.tasks da sync_flow_locks() ga bog''langan YOQILGAN trigger yo''q — UPDATE hech narsani qayta hisoblamaydi, ya''ni kutiladigan natija YO''Q';
  END IF;

  IF v_skip IS NULL AND to_regclass('public.workspace_members') IS NULL THEN
    v_skip := 'public.workspace_members topilmadi — sentinel loyiha uchun haqiqiy workspace/user kerak';
  END IF;

  IF v_skip IS NULL AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='tasks' AND column_name='title') THEN
    v_skip := 'public.tasks da title ustuni yo''q — sinov qatorini taxmin bilan to''ldirmaymiz';
  END IF;

  -- tasks.id / projects.id o'zi to'lanadimi
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

  IF v_skip IS NULL THEN
    SELECT m.workspace_id, m.user_id INTO v_ws, v_usr
      FROM public.workspace_members m
     ORDER BY m.workspace_id, m.user_id
     LIMIT 1;
    IF v_ws IS NULL THEN
      v_skip := 'workspace_members bo''sh — sentinel loyiha yaratib bo''lmaydi (bo''sh baza)';
    END IF;
  END IF;

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
    RAISE WARNING 'TIRIK SINOVLAR (L1..L8) O''TKAZIB YUBORILDI — %. Funksiya BARIBIR tuzatildi va 4b-bo''lim uning tanasini tasdiqladi; prodga chiqishdan oldin loyiha bosqichlari navbatini QO''LDA sinang.', v_skip;
    INSERT INTO pg_temp.trgfix_res VALUES
      (49, 'sinov', 'TIRIK SINOVLAR (L1..L8)', 'ENV: o''tkazib yuborildi', v_skip);
    RETURN;
  END IF;

  -- ── (5.1) INSERT shablonlari ─────────────────────────────────────────────
  SELECT format_type(a.atttypid, a.atttypmod) INTO v_projtyp
    FROM pg_attribute a
   WHERE a.attrelid='public.projects'::regclass AND a.attname='id' AND NOT a.attisdropped;

  v_has_cyc  := to_regclass('public.project_cycles') IS NOT NULL;
  v_has_cmpl := EXISTS (SELECT 1 FROM information_schema.columns
                         WHERE table_schema='public' AND table_name='tasks' AND column_name='completed_at');

  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='projects' AND column_name='created_by') THEN
    v_pcols := v_pcols || ', created_by';
    v_pvals := v_pvals || ', ' || quote_literal(v_usr::text) || '::uuid';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='projects' AND column_name='status'
                AND is_nullable='NO' AND column_default IS NULL) THEN
    v_pcols := v_pcols || ', status';
    v_pvals := v_pvals || ', ' || quote_literal('active');
  END IF;

  v_pins := 'INSERT INTO public.projects (workspace_id, ' || quote_ident(v_pname) || v_pcols
         || ') VALUES (' || quote_literal(v_ws::text) || '::uuid, '
         || quote_literal('TRGFIX SINOV (sentinel)') || v_pvals || ') RETURNING id::text';

  -- tartib ustuni: flow_order MAJBURIY (0-bo'limda tekshirilgan);
  -- order_index bo'lsa unga ham AYNI qiymat yoziladi.
  v_ordcols := ', flow_order';
  v_ordvals := ', %6$s';
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='tasks' AND column_name='order_index') THEN
    v_ordcols := v_ordcols || ', order_index';
    v_ordvals := v_ordvals || ', %6$s';
  END IF;

  v_tcols := ', depends_on_prev';
  v_tvals := ', %7$s';
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='tasks' AND column_name='created_by') THEN
    v_tcols := v_tcols || ', created_by';
    v_tvals := v_tvals || ', ' || quote_literal(v_usr::text) || '::uuid';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='tasks' AND column_name='assigned_to') THEN
    v_tcols := v_tcols || ', assigned_to';
    v_tvals := v_tvals || ', ' || quote_literal(v_usr::text) || '::uuid';
  END IF;

  v_sel := 'SELECT is_locked::text FROM public.tasks WHERE id::text = $1';

  v_updc := 'UPDATE public.tasks SET status = ' || quote_literal('completed');
  IF v_has_cmpl THEN
    v_updc := v_updc || ', completed_at = now()';
  END IF;
  v_updc := v_updc || ' WHERE id::text = $1';
  v_updx := 'UPDATE public.tasks SET status = ' || quote_literal('cancelled') || ' WHERE id::text = $1';

  -- ══════════════ SENTINEL BLOK (hammasi qaytariladi) ══════════════
  BEGIN
    -- ── SAHNA A: eski mantiq (shablonsiz, cycle_id NULL) ──────────────────
    EXECUTE v_pins INTO v_pa;
    v_pexpr := replace('(SELECT p.id FROM public.projects p WHERE p.id::text = '
                       || quote_literal(v_pa) || ')', '%', '%%');
    v_ins := 'INSERT INTO public.tasks (workspace_id, project_id, title, is_template, cycle_id, status, is_locked'
          || v_ordcols || v_tcols
          || ') VALUES (' || quote_literal(v_ws::text) || '::uuid, ' || v_pexpr
          || ', %1$L, %2$s, %3$s, %4$L, %5$s' || v_ordvals || v_tvals || ') RETURNING id::text';

    --  markerlar: %1$L sarlavha · %2$s is_template · %3$s cycle_id ·
    --             %4$L status · %5$s is_locked · %6$s tartib · %7$s dop
    --  🔴 har qator KUTILGANNING TESKARISI bilan kiritiladi
    EXECUTE format(v_ins, 'TRGFIX A0', 'false', 'NULL', 'new', 'true',  '1', 'true')  INTO i_a0;
    EXECUTE format(v_ins, 'TRGFIX A1', 'false', 'NULL', 'new', 'false', '2', 'false') INTO v_a1;
    EXECUTE format(v_ins, 'TRGFIX A2', 'false', 'NULL', 'new', 'true',  '3', 'true')  INTO i_a2;
    EXECUTE format(v_ins, 'TRGFIX A3', 'false', 'NULL', 'new', 'false', '4', 'true')  INTO i_a3;
    EXECUTE format(v_ins, 'TRGFIX A4', 'false', 'NULL', 'new', 'true',  '5', 'false') INTO i_a4;

    EXECUTE v_updc USING v_a1;            -- A1 → completed (trigger ishga tushadi)

    EXECUTE v_sel INTO q_a0 USING i_a0;   -- (L3) kutilgan: false
    EXECUTE v_sel INTO q_a2 USING i_a2;   -- (L1a) kutilgan: false
    EXECUTE v_sel INTO q_a3 USING i_a3;   -- (L1b) kutilgan: true
    EXECUTE v_sel INTO q_a4 USING i_a4;   -- (L2)  kutilgan: false

    -- ── SAHNA B: shablon + 2 sikl ─────────────────────────────────────────
    EXECUTE v_pins INTO v_pb;
    v_pexpr := replace('(SELECT p.id FROM public.projects p WHERE p.id::text = '
                       || quote_literal(v_pb) || ')', '%', '%%');
    v_ins := 'INSERT INTO public.tasks (workspace_id, project_id, title, is_template, cycle_id, status, is_locked'
          || v_ordcols || v_tcols
          || ') VALUES (' || quote_literal(v_ws::text) || '::uuid, ' || v_pexpr
          || ', %1$L, %2$s, %3$s, %4$L, %5$s' || v_ordvals || v_tvals || ') RETURNING id::text';

    IF v_has_cyc THEN
      -- TASKFIX_SHABLON.sql allaqachon RUN qilingan bo'lsa FK bor → haqiqiy sikl
      EXECUTE 'INSERT INTO public.project_cycles (workspace_id, project_id, cycle_no)'
           || ' VALUES ($1, $2::' || v_projtyp || ', 1) RETURNING id' INTO v_g1 USING v_ws, v_pb;
      EXECUTE 'INSERT INTO public.project_cycles (workspace_id, project_id, cycle_no)'
           || ' VALUES ($1, $2::' || v_projtyp || ', 2) RETURNING id' INTO v_g2 USING v_ws, v_pb;
    ELSE
      v_g1 := '00000000-0000-4000-8000-0000000000c1'::uuid;
      v_g2 := '00000000-0000-4000-8000-0000000000c2'::uuid;
    END IF;

    -- SHABLONLAR (is_template = true, cycle_id NULL)
    --   TA: dop = false, is_locked = TRUE  → qayta hisoblansa FALSE bo'lardi.
    --       🔴 (L5) ni AYNAN TA tutadi — ASL funksiyada HAM, yangi
    --       funksiyadan `t.is_template` olib tashlanganda HAM u false bo'ladi.
    --   TB: dop = true,  is_locked = FALSE → FAQAT ASL funksiyada TRUE bo'lardi.
    --       Yangi funksiyadan `t.is_template` olib tashlansa TB baribir FALSE
    --       bo'lib qoladi: uning cycle_id si NULL, instansiyalarniki esa g1/g2
    --       → `p2.cycle_id IS NOT DISTINCT FROM t.cycle_id` hech qanday
    --       "oldingi bosqich" topmaydi. Ya'ni TB — ASL ga qarshi
    --       differensiator, MUTATSIYAGA qarshi emas; ikkinchi yo'nalishni
    --       siklsiz sahnada (L8c) TE2 tekshiradi.
    EXECUTE format(v_ins, 'TRGFIX TA (shablon)', 'true', 'NULL', 'new', 'true',  '1', 'false') INTO i_ta;
    EXECUTE format(v_ins, 'TRGFIX TB (shablon)', 'true', 'NULL', 'new', 'false', '2', 'true')  INTO i_tb;

    -- 1-SIKL instansiyalari
    EXECUTE format(v_ins, 'TRGFIX B1', 'false', quote_literal(v_g1::text) || '::uuid', 'new', 'false', '1', 'false') INTO v_b1;
    EXECUTE format(v_ins, 'TRGFIX B2', 'false', quote_literal(v_g1::text) || '::uuid', 'new', 'true',  '2', 'true')  INTO i_b2;
    -- 2-SIKL instansiyalari
    EXECUTE format(v_ins, 'TRGFIX B3', 'false', quote_literal(v_g2::text) || '::uuid', 'new', 'false', '1', 'false') INTO v_tmp;
    EXECUTE format(v_ins, 'TRGFIX B4', 'false', quote_literal(v_g2::text) || '::uuid', 'new', 'false', '2', 'true')  INTO i_b4;

    EXECUTE v_updc USING v_b1;            -- 1-siklning 1-bosqichi → completed

    EXECUTE v_sel INTO q_b2  USING i_b2;  -- (L4)  kutilgan: false
    EXECUTE v_sel INTO q_tb1 USING i_ta;  -- (L5a) kutilgan: true (O'ZGARMAGAN)
    EXECUTE v_sel INTO q_tb2 USING i_tb;  -- (L5b) kutilgan: false (O'ZGARMAGAN)
    EXECUTE v_sel INTO q_b4  USING i_b4;  -- (L6c) kutilgan: true

    -- ── SAHNA C: cancelled voris (REGRESSIYA) ─────────────────────────────
    EXECUTE v_pins INTO v_pc;
    v_pexpr := replace('(SELECT p.id FROM public.projects p WHERE p.id::text = '
                       || quote_literal(v_pc) || ')', '%', '%%');
    v_ins := 'INSERT INTO public.tasks (workspace_id, project_id, title, is_template, cycle_id, status, is_locked'
          || v_ordcols || v_tcols
          || ') VALUES (' || quote_literal(v_ws::text) || '::uuid, ' || v_pexpr
          || ', %1$L, %2$s, %3$s, %4$L, %5$s' || v_ordvals || v_tvals || ') RETURNING id::text';

    EXECUTE format(v_ins, 'TRGFIX C1', 'false', 'NULL', 'new', 'false', '1', 'false') INTO v_c1;
    EXECUTE format(v_ins, 'TRGFIX C2', 'false', 'NULL', 'new', 'false', '2', 'true')  INTO i_c2;

    EXECUTE v_updx USING v_c1;            -- C1 → cancelled

    EXECUTE v_sel INTO q_c2 USING i_c2;   -- (L7) kutilgan: true (qulflangan qoladi)

    -- ── SAHNA D: ikki sikl, 2-siklda bosqich TUSHIB QOLGAN ────────────────
    --    🔴 ASL funksiya bu yerda D5 ni NOTO'G'RI OCHIB yuborardi: MAX(...)
    --       butun loyiha bo'ylab 2 ni tanlardi (u faqat 1-siklda bor va
    --       `completed`), tuzatilganida esa MAX faqat O'Z SIKLI ichida
    --       hisoblanadi → 1 (D4, 'new') → bosqich QULFLANGAN qoladi.
    EXECUTE v_pins INTO v_pd;
    v_pexpr := replace('(SELECT p.id FROM public.projects p WHERE p.id::text = '
                       || quote_literal(v_pd) || ')', '%', '%%');
    v_ins := 'INSERT INTO public.tasks (workspace_id, project_id, title, is_template, cycle_id, status, is_locked'
          || v_ordcols || v_tcols
          || ') VALUES (' || quote_literal(v_ws::text) || '::uuid, ' || v_pexpr
          || ', %1$L, %2$s, %3$s, %4$L, %5$s' || v_ordvals || v_tvals || ') RETURNING id::text';

    IF v_has_cyc THEN
      EXECUTE 'INSERT INTO public.project_cycles (workspace_id, project_id, cycle_no)'
           || ' VALUES ($1, $2::' || v_projtyp || ', 1) RETURNING id' INTO v_g3 USING v_ws, v_pd;
      EXECUTE 'INSERT INTO public.project_cycles (workspace_id, project_id, cycle_no)'
           || ' VALUES ($1, $2::' || v_projtyp || ', 2) RETURNING id' INTO v_g4 USING v_ws, v_pd;
    ELSE
      v_g3 := '00000000-0000-4000-8000-0000000000d3'::uuid;
      v_g4 := '00000000-0000-4000-8000-0000000000d4'::uuid;
    END IF;

    EXECUTE format(v_ins, 'TRGFIX D1', 'false', quote_literal(v_g3::text) || '::uuid', 'new', 'false', '1', 'false') INTO v_d1;
    EXECUTE format(v_ins, 'TRGFIX D2', 'false', quote_literal(v_g3::text) || '::uuid', 'new', 'false', '2', 'true')  INTO v_d2;
    EXECUTE format(v_ins, 'TRGFIX D3', 'false', quote_literal(v_g3::text) || '::uuid', 'new', 'true',  '3', 'true')  INTO i_d3;
    EXECUTE format(v_ins, 'TRGFIX D4', 'false', quote_literal(v_g4::text) || '::uuid', 'new', 'false', '1', 'false') INTO v_tmp;
    -- 2-siklda flow_order = 2 YO'Q (bosqich tushib qolgan / bekor qilingan)
    EXECUTE format(v_ins, 'TRGFIX D5', 'false', quote_literal(v_g4::text) || '::uuid', 'new', 'false', '3', 'true')  INTO i_d5;

    EXECUTE v_updc USING v_d1;
    EXECUTE v_updc USING v_d2;

    EXECUTE v_sel INTO q_d5 USING i_d5;   -- (L6a) kutilgan: true
    EXECUTE v_sel INTO q_d3 USING i_d3;   -- (L6b) kutilgan: false

    -- ── SAHNA E: SHABLON + SIKLSIZ INSTANSIYA (HAMMA qatorda cycle_id NULL)
    --    🔴 `p.is_template` / `p2.is_template` qorovullarini YAGONA
    --       tekshiradigan sahna: A/B/C/D da shablonni SIKL qorovuli allaqachon
    --       chetlatib qo'yadi, ya'ni shablon qorovullari olib tashlansa ham
    --       hukmlar o'tib ketardi. Bu yerda sikl qorovuli YORDAM BERMAYDI
    --       (hamma qatorda cycle_id NULL) — faqat shablon qorovuli ushlab
    --       turadi. Prodda erishiladigan holat: SHABLON migratsiyasi mavjud
    --       qatorlarga cycle_id yozadi, keyin mijoz cycle_id SIZ yangi bosqich
    --       yaratadi.
    --       E1 (fo 1) tugagach:
    --         E2 (fo 2) OCHILISHI kerak — TE1 (shablon, fo 1, 'new') uni
    --            ushlab qolmasin ..................... `p.is_template`  (L8a)
    --         E6 (fo 6) QULFLANGAN qolishi kerak — TE2 (shablon, fo 5) ni
    --            "oldingi bosqich" deb tanlab olmasin (haqiqiy oldingisi —
    --            E4, fo 4, hali 'new') .............. `p2.is_template` (L8b)
    --         TE1/TE2 ning is_locked i O'ZGARMASIN .. `t.is_template`  (L8c)
    EXECUTE v_pins INTO v_pe;
    v_pexpr := replace('(SELECT p.id FROM public.projects p WHERE p.id::text = '
                       || quote_literal(v_pe) || ')', '%', '%%');
    v_ins := 'INSERT INTO public.tasks (workspace_id, project_id, title, is_template, cycle_id, status, is_locked'
          || v_ordcols || v_tcols
          || ') VALUES (' || quote_literal(v_ws::text) || '::uuid, ' || v_pexpr
          || ', %1$L, %2$s, %3$s, %4$L, %5$s' || v_ordvals || v_tvals || ') RETURNING id::text';

    --  🔴 har qator KUTILGANNING TESKARISI bilan kiritiladi:
    --     TE1 true  → qayta hisoblansa false bo'lardi (dop = false)
    --     TE2 false → qayta hisoblansa true  bo'lardi (dop = true, E4 'new')
    --     E2  true  → kutilgan false · E6 false → kutilgan true
    EXECUTE format(v_ins, 'TRGFIX TE1 (shablon)', 'true',  'NULL', 'new', 'true',  '1', 'false') INTO i_te1;
    EXECUTE format(v_ins, 'TRGFIX E1',            'false', 'NULL', 'new', 'false', '1', 'false') INTO v_e1;
    EXECUTE format(v_ins, 'TRGFIX E2',            'false', 'NULL', 'new', 'true',  '2', 'true')  INTO i_e2;
    EXECUTE format(v_ins, 'TRGFIX E4',            'false', 'NULL', 'new', 'false', '4', 'false') INTO v_tmp;
    EXECUTE format(v_ins, 'TRGFIX TE2 (shablon)', 'true',  'NULL', 'new', 'false', '5', 'true')  INTO i_te2;
    EXECUTE format(v_ins, 'TRGFIX E6',            'false', 'NULL', 'new', 'false', '6', 'true')  INTO i_e6;

    EXECUTE v_updc USING v_e1;            -- E1 → completed (trigger ishga tushadi)

    EXECUTE v_sel INTO q_e2  USING i_e2;  -- (L8a) kutilgan: false
    EXECUTE v_sel INTO q_e6  USING i_e6;  -- (L8b) kutilgan: true
    EXECUTE v_sel INTO q_te1 USING i_te1; -- (L8c) kutilgan: true  (O'ZGARMAGAN)
    EXECUTE v_sel INTO q_te2 USING i_te2; -- (L8c) kutilgan: false (O'ZGARMAGAN)

    -- ⚠️ SENTINEL: subtranzaksiyani ATAYLAB qaytaramiz.
    RAISE EXCEPTION 'TRGFIX:%',
      coalesce(q_a0, '?') || '~' || coalesce(q_a2, '?') || '~' || coalesce(q_a3, '?') || '~' ||
      coalesce(q_a4, '?') || '~' || coalesce(q_b2, '?') || '~' || coalesce(q_tb1, '?') || '~' ||
      coalesce(q_tb2, '?') || '~' || coalesce(q_b4, '?') || '~' || coalesce(q_d5, '?') || '~' ||
      coalesce(q_d3, '?') || '~' || coalesce(q_c2, '?') || '~' ||
      coalesce(q_e2, '?') || '~' || coalesce(q_e6, '?') || '~' ||
      coalesce(q_te1, '?') || '~' || coalesce(q_te2, '?')
      USING ERRCODE = '22000';

  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;

    -- 🔴 ENV BAIL-OUT — HUKMLARDAN OLDIN (muhit xatosi soxta salbiy bermasin)
    IF v_err NOT LIKE 'TRGFIX:%' THEN
      v_skip := 'sinov sahnasini qurib bo''lmadi (' || v_state || '): ' || left(v_err, 240)
             || CASE WHEN v_state = '23505'
                     THEN ' ← 🔴 UNIQUE indeks to''qnashuvi: sentinel sahnada bitta loyihada flow_order ATAYLAB takrorlanadi. (4) qatoridagi "UNIQUE indeks to''qnashuvi" ro''yxatiga qarang — o''sha indeksni QISMAN qilish kerak.'
                     ELSE '' END;
      RAISE WARNING 'TIRIK SINOVLAR (L1..L8) O''TKAZIB YUBORILDI — %. Funksiya BARIBIR tuzatildi va 4b-bo''lim uning tanasini tasdiqladi; prodga chiqishdan oldin QO''LDA sinang.', v_skip;
      INSERT INTO pg_temp.trgfix_res VALUES
        (49, 'sinov', 'TIRIK SINOVLAR (L1..L8)', 'ENV: o''tkazib yuborildi', v_skip);
      RETURN;
    END IF;

    v_probe := replace(v_err, 'TRGFIX:', '');
    q_a0  := split_part(v_probe, '~', 1);
    q_a2  := split_part(v_probe, '~', 2);
    q_a3  := split_part(v_probe, '~', 3);
    q_a4  := split_part(v_probe, '~', 4);
    q_b2  := split_part(v_probe, '~', 5);
    q_tb1 := split_part(v_probe, '~', 6);
    q_tb2 := split_part(v_probe, '~', 7);
    q_b4  := split_part(v_probe, '~', 8);
    q_d5  := split_part(v_probe, '~', 9);
    q_d3  := split_part(v_probe, '~', 10);
    q_c2  := split_part(v_probe, '~', 11);
    q_e2  := split_part(v_probe, '~', 12);
    q_e6  := split_part(v_probe, '~', 13);
    q_te1 := split_part(v_probe, '~', 14);
    q_te2 := split_part(v_probe, '~', 15);

    RAISE NOTICE 'Sinov natijalari (is_locked): A0=% A2=% A3=% A4=% | B2=% TA=% TB=% B4=% | D5=% D3=% | C2=% | E2=% E6=% TE1=% TE2=%',
      q_a0, q_a2, q_a3, q_a4, q_b2, q_tb1, q_tb2, q_b4, q_d5, q_d3, q_c2,
      q_e2, q_e6, q_te1, q_te2;

    -- ══════════ HUKMLAR ══════════
    IF q_a2 <> 'false' THEN
      v_fail := v_fail || chr(10)
        || '  (L1a) ESKI MANTIQ BUZILDI: oldingi bosqich `completed` bo''lgach keyingisi OCHILMADI (is_locked = ' || q_a2 || ', kutilgan false).';
    END IF;
    IF q_a3 <> 'true' THEN
      v_fail := v_fail || chr(10)
        || '  (L1b) ESKI MANTIQ BUZILDI: oldingisi hali `new` bo''lgan 3-bosqich QULFLANMADI (is_locked = ' || q_a3 || ', kutilgan true).';
    END IF;
    IF q_a4 <> 'false' THEN
      v_fail := v_fail || chr(10)
        || '  (L2) PARALLEL bosqich (depends_on_prev = false) QULFLANDI (is_locked = ' || q_a4 || ', kutilgan false).';
    END IF;
    IF q_a0 <> 'false' THEN
      v_fail := v_fail || chr(10)
        || '  (L3) BIRINCHI bosqich (oldingisi yo''q) QULFLANDI (is_locked = ' || q_a0 || ', kutilgan false).';
    END IF;
    IF q_b2 <> 'false' THEN
      v_fail := v_fail || chr(10)
        || '  (L4) OLDINGI BOSQICH NOTO''G''RI TOPILDI: 1-siklning 1-bosqichi `completed` bo''lgan bo''lsa ham 2-bosqich OCHILMADI (is_locked = ' || q_b2 || ', kutilgan false) — o''sha flow_order da BOSHQA SIKLNING ''new'' qatori (yoki shablon) "oldingi bosqich" bo''lib ushlab qoldi. 🔴 Bu hukmni AYNAN `AND p.cycle_id IS NOT DISTINCT FROM t.cycle_id` qorovuli ushlab turadi (mutatsiya sinovi: shu qorovul olib tashlansa (L4) yiqiladi). Shablon qorovulini esa (L8a) tekshiradi.';
    END IF;
    IF q_tb1 <> 'true' OR q_tb2 <> 'false' THEN
      v_fail := v_fail || chr(10)
        || '  (L5) SHABLONGA is_locked YOZILDI: TA=' || q_tb1 || ' (kutilgan true, O''ZGARMASLIGI kerak edi), TB=' || q_tb2
        || ' (kutilgan false, O''ZGARMASLIGI kerak edi). Qorovul: UPDATE ning `WHERE ... AND t.is_template IS NOT TRUE` qismi — mutatsiya sinovida uni AYNAN TA tutadi (TB bu sahnada faqat ASL funksiyaga qarshi differensiator, chunki uning cycle_id si NULL, instansiyalarniki esa g1/g2). Ikkinchi yo''nalish — (L8c) TE2.';
    END IF;
    IF q_b4 <> 'true' THEN
      v_fail := v_fail || chr(10)
        || '  (L6c) BOSHQA SIKL OCHIB YUBORILDI: 1-siklning `completed` bosqichi 2-siklning 2-bosqichini ochdi (is_locked = ' || q_b4 || ', kutilgan true).';
    END IF;
    IF q_d5 <> 'true' THEN
      v_fail := v_fail || chr(10)
        || '  (L6a) BOSHQA SIKL OCHIB YUBORILDI: 2-siklda tushib qolgan bosqich sababli MAX(flow_order) BOSHQA SIKLDAN olindi (is_locked = ' || q_d5 || ', kutilgan true). Qorovul: `p2.cycle_id IS NOT DISTINCT FROM t.cycle_id` — aynan `p2` ham qorovullanishi shart.';
    END IF;
    IF q_d3 <> 'false' THEN
      v_fail := v_fail || chr(10)
        || '  (L6b) O''Z SIKLI ichidagi voris tugagan bo''lsa ham bosqich OCHILMADI (is_locked = ' || q_d3 || ', kutilgan false).';
    END IF;
    IF q_c2 <> 'true' THEN
      v_fail := v_fail || chr(10)
        || '  (L7) REGRESSIYA: `cancelled` voris `completed` EMAS, ya''ni keyingisi qulflangan qolishi kerak edi (is_locked = ' || q_c2 || ', kutilgan true).';
    END IF;
    IF q_e2 <> 'false' THEN
      v_fail := v_fail || chr(10)
        || '  (L8a) SHABLON SIKLSIZ INSTANSIYANI BLOKLADI: hamma qatorda cycle_id NULL bo''lgan loyihada shablon (fo 1, status ''new'') "oldingi bosqich" bo''lib qoldi va E1 tugagan bo''lsa ham E2 OCHILMADI (is_locked = ' || q_e2 || ', kutilgan false) — ya''ni bosqich ABADIY QULFLANGAN bo''lardi. 🔴 Qorovul: `AND p.is_template IS NOT TRUE` (bu sahnada SIKL qorovuli yordam bermaydi — hamma cycle_id NULL).';
    END IF;
    IF q_e6 <> 'true' THEN
      v_fail := v_fail || chr(10)
        || '  (L8b) SHABLON MAX(flow_order) NI O''G''IRLADI: siklsiz shablon (fo 5) ichki MAX(...) da tanlanib qoldi, keyin tashqi qidiruv o''sha tartib raqamida hech narsa topmadi va hali kutishi kerak bo''lgan bosqich NOTO''G''RI OCHILDI (is_locked = ' || q_e6 || ', kutilgan true — haqiqiy oldingi bosqich E4 hamon ''new''). 🔴 Qorovul: `AND p2.is_template IS NOT TRUE`.';
    END IF;
    IF q_te1 <> 'true' OR q_te2 <> 'false' THEN
      v_fail := v_fail || chr(10)
        || '  (L8c) SIKLSIZ SAHNADA SHABLONGA is_locked YOZILDI: TE1=' || q_te1 || ' (kutilgan true), TE2=' || q_te2
        || ' (kutilgan false) — ikkovi ham O''ZGARMASLIGI kerak edi. 🔴 Qorovul: UPDATE ning `WHERE ... AND t.is_template IS NOT TRUE` qismi. Bu (L5) ning IKKINCHI yo''nalishi: TE2 (dop = true) qayta hisoblansa TRUE bo''lardi.';
    END IF;

    IF v_fail <> '' THEN
      v_msg := '🔴 TIRIK SINOVLAR (L1..L8) YIQILDI — yangi sync_flow_locks() kutilgandek ishlamadi:'
        || v_fail
        || chr(10) || 'MUMKIN BO''LGAN SABAB: public.tasks da `is_locked` ga tegadigan BOSHQA trigger ham bor (' || coalesce(v_other, '-') || ') yoki funksiya tanasi kutilganidan boshqa.'
        || chr(10) || 'HAMMASI QAYTARILDI — funksiya ESKI holida qoldi, ustunlar ham qo''shilmadi, bazada bir belgi ham o''zgarmadi.';
      RAISE EXCEPTION '%', v_msg;
    END IF;

    INSERT INTO pg_temp.trgfix_res VALUES
      (50, 'sinov', '(L1) ESKI MANTIQ BUZILMAGAN (ketma-ket, shablonsiz)', 'o''tdi',
       '1-bosqich `completed` bo''lgach 2-chi OCHILDI (is_locked = ' || q_a2 || '), 3-chi esa QULFLANGAN qoldi (' || q_a3 || '). Ikkala qator KUTILGANNING TESKARISI bilan kiritilgan edi — ya''ni trigger ROSTDAN yozdi.'),
      (51, 'sinov', '(L2) PARALLEL bosqich qulflanmadi', 'o''tdi',
       'depends_on_prev = false → is_locked = ' || q_a4 || ' (qator `true` bilan kiritilgan edi).'),
      (52, 'sinov', '(L3) BIRINCHI bosqich qulflanmadi', 'o''tdi',
       'Oldingisi yo''q (MAX(flow_order) = NULL) → is_locked = ' || q_a0 || ' (qator `true` bilan kiritilgan edi).'),
      (53, 'sinov', '(L4) 🔴 OLDINGI BOSQICH FAQAT O''Z SIKLIDAN TOPILDI', 'o''tdi',
       'O''sha flow_order da status = ''new'' SHABLON ham, BOSHQA SIKLNING qatori ham turgan holda 1-siklning 1-bosqichi tugagach 2-chi OCHILDI (is_locked = ' || q_b2 || '). ASL funksiyada u ABADIY qulflangan qolardi. Mutatsiya sinovi: bu hukmni AYNAN `p.cycle_id IS NOT DISTINCT FROM t.cycle_id` ushlab turadi; shablon qorovulini (L8a) tekshiradi.'),
      (54, 'sinov', '(L5) 🔴 SHABLONGA is_locked YOZILMADI', 'o''tdi',
       'TA (is_locked = true, dop = false) → ' || q_tb1 || ' · TB (is_locked = false, dop = true) → ' || q_tb2
       || '. 🔴 Mutatsiya sinovi: `t.is_template` qorovuli olib tashlansa buni AYNAN TA tutadi; TB esa faqat ASL funksiyada teskari qiymat olardi (uning cycle_id si NULL, instansiyalarniki g1/g2 — sikl qorovuli hech qanday "oldingi bosqich" topmaydi). Ikkinchi yo''nalish siklsiz sahnada (L8c) TE2 da tekshiriladi.'),
      (55, 'sinov', '(L6) 🔴 BOSHQA SIKL ochib yubormadi', 'o''tdi',
       '(a) 2-siklda bosqich tushib qolganda MAX(flow_order) BOSHQA SIKLDAN olinmadi → ' || q_d5
       || ' · (b) o''z sikli ichidagi voris tugagach bosqich ochildi → ' || q_d3
       || ' · (c) 1-siklning `completed` bosqichi 2-sikl bosqichini ochmadi → ' || q_b4 || '.'),
      (56, 'sinov', '(L7) REGRESSIYA: `cancelled` voris', 'o''tdi',
       '`cancelled` — `completed` EMAS, ya''ni keyingisi qulflangan qoldi (is_locked = ' || q_c2 || '). ASL mantiqda ham shunday edi.'),
      (58, 'sinov', '(L8) 🔴 SHABLON + SIKLSIZ INSTANSIYA BIR LOYIHADA', 'o''tdi',
       '🔴 `p.is_template` va `p2.is_template` qorovullarini YAGONA tekshiradigan sahna (A/B/C/D da shablonni SIKL qorovuli allaqachon chetlatadi, ya''ni u yerda shablon qorovullari olib tashlansa ham hukmlar o''tib ketardi). Hamma qatorda cycle_id NULL: (a) shablon keyingi bosqichni bloklamadi → E2 = ' || q_e2
       || ' (ASL da ABADIY QULF bo''lardi) · (b) shablon MAX(flow_order) ni o''g''irlamadi, kutishi kerak bo''lgan bosqich qulflangan qoldi → E6 = ' || q_e6
       || ' · (c) shablonlarning is_locked i o''zgarmadi → TE1 = ' || q_te1 || ', TE2 = ' || q_te2
       || '. Prodda erishiladigan holat: SHABLON migratsiyasi mavjud qatorlarga cycle_id yozadi, keyin mijoz cycle_id SIZ yangi bosqich yaratadi.'),
      (57, 'sinov', 'SENTINEL-ROLLBACK', 'toza',
       '5 sentinel loyiha, 24 vazifa/shablon qatori va (jadval bo''lsa) 4 sikl qatori subtranzaksiya bilan QAYTARILDI — bazada bitta qator ham qolmadi (sahna E ham).');

    RAISE NOTICE 'TIRIK SINOVLAR (L1..L8) O''TDI — sentinel-rollback: bazada bitta qator ham QOLMADI.';
  END;
END $live$;


-- ════════════════════════════════════════════════════════════════════════════
-- 6) YAKUNIY HISOBOT
-- ════════════════════════════════════════════════════════════════════════════
DO $rep$
DECLARE
  v_skipn int;
  v_cls   text;
  v_bak   text;
  v_trgn  text;
  v_trgon text;
  v_trgnm text;
  v_uq    text;
  v_uqx   text;
BEGIN
  SELECT v INTO v_cls   FROM pg_temp.trgfix_ref WHERE k='cls';
  SELECT v INTO v_bak   FROM pg_temp.trgfix_ref WHERE k='bak';
  SELECT v INTO v_trgn  FROM pg_temp.trgfix_ref WHERE k='trg_n';
  SELECT v INTO v_trgon FROM pg_temp.trgfix_ref WHERE k='trg_on';
  SELECT v INTO v_trgnm FROM pg_temp.trgfix_ref WHERE k='trg_names';
  SELECT v INTO v_uq    FROM pg_temp.trgfix_ref WHERE k='uq_risk';
  SELECT v INTO v_uqx   FROM pg_temp.trgfix_ref WHERE k='uq_expr';

  SELECT count(*) INTO v_skipn FROM pg_temp.trgfix_res
   WHERE bosqich = 'sinov' AND qiymat LIKE 'ENV:%';

  INSERT INTO pg_temp.trgfix_res VALUES
    (24, 'qaror', 'mavjud is_locked qiymatlari', 'QAYTA HISOBLANMADI (ataylab)',
     'Skript hech qanday qatorni yangilamaydi/o''chirmaydi. Qulflar keyingi status o''zgarishida trigger tomonidan o''zi qayta hisoblanadi — mavjud xatti-harakat, ommaviy UPDATE esa 20k qatorli jadvalda keraksiz qulf va tarix shovqini bo''lardi.'),
    (25, 'qaror', 'template_id / project_cycles / template_history / RLS', 'TEGILMADI',
     'Ular TASKFIX_SHABLON.sql ning ishi. Bu fayl faqat funksiya ishlashi uchun ZARUR bo''lgan minimumni (2 ustun) qo''shadi.');

  INSERT INTO pg_temp.trgfix_res VALUES
    (98, 'XULOSA', '🔴 sync_flow_locks() SHABLON/SIKLGA MOSLASHTIRILDI',
     'qorovul: ' || CASE WHEN v_cls = 'ASL' THEN 'ASL ta''rif tasdiqlandi'
                         WHEN v_cls = 'FIX' THEN 'allaqachon tuzatilgan (2-RUN)'
                         ELSE coalesce(v_cls, '?') END
       || ' · zaxira: ' || coalesce(v_bak, '?')
       || ' · tirik sinov: ' || CASE WHEN v_skipn > 0 THEN 'BAJARILMADI (ENV)' ELSE 'L1..L8 BAJARILDI' END
       || CASE WHEN coalesce(v_uq, '-') <> '-' THEN ' · ⚠️ UNIQUE indeks: ' || v_uq ELSE '' END,
     'Tartib: (1) ustunlar → (2) zaxira + klassifikatsiya → (3) FAIL-CLOSED qorovul → (4) CREATE OR REPLACE → (4b) tasdiqlash → (5) tirik sinovlar. Bittasi salbiy bo''lsa skript COMMIT QILMAGAN bo''lardi. Triggerlar: ' || coalesce(v_trgn, '?') || ' ta (yoqilgan ' || coalesce(v_trgon, '?') || ': ' || coalesce(v_trgnm, '-') || ') — trigger''ning O''ZIGA tegilmadi.');

  INSERT INTO pg_temp.trgfix_res VALUES
    (99, 'XULOSA',
     CASE WHEN v_skipn = 0 THEN 'TIRIK SINOVLAR TO''LIQ BAJARILDI'
          ELSE '🔴 DIQQAT: TIRIK SINOVLAR O''TKAZIB YUBORILDI' END,
     CASE WHEN v_skipn = 0 THEN 'L1..L8 = 8/8' ELSE 'L1..L8 = 0/8 (ENV)' END,
     CASE WHEN v_skipn = 0
          THEN 'Eski mantiq buzilmagani (L1, L2, L3, L7) va yangi qorovullar ishlayotgani (L4, L5, L6a/b/c, L8a/b/c) sentinel sahnada TIRIK tasdiqlandi; sinov qatorlari qaytarildi. Har 5 qorovulning HAR BIRI kamida bitta hukm bilan qoplangan: p.is_template→L8a, p2.is_template→L8b, p.cycle_id→L4, p2.cycle_id→L6a, t.is_template→L5/L8c. '
          ELSE '⚠️ Funksiya COMMIT bo''ldi (qorovul va 4b tasdiqlash o''tdi), lekin tirik sinovlar bajarilmadi — sabab "sinov" (49) qatorida. Prodga chiqishdan oldin loyiha bosqichlari navbatini QO''LDA sinang. '
            || CASE WHEN coalesce(v_uq, '-') <> '-' OR coalesce(v_uqx, '-') <> '-'
                    THEN '🔴 EHTIMOLIY SABAB — UNIQUE INDEKS: ' || coalesce(v_uq, '-')
                         || CASE WHEN coalesce(v_uqx, '-') <> '-' THEN ' (ifodali: ' || v_uqx || ')' ELSE '' END
                         || '. Sentinel sahnada bitta loyihada flow_order ATAYLAB takrorlanadi (shablon + instansiya) — (4) qatoriga qarang; o''sha indeksni QISMAN qilish kerak. '
                    ELSE '' END END
     || '🔴 KEYINGI QADAM: endi `TASKFIX_SHABLON.sql` ni QAYTA RUN qiling — uning 0e-bo''limi endi funksiyada `is_template` qorovulini ko''radi va XAVFLI hukmini chiqarmaydi, 8b tirik sinovi (t1..t4) esa o''tadi.');

  IF v_skipn > 0 THEN
    RAISE WARNING 'Tirik sinovlar o''tkazib yuborildi — funksiya baribir COMMIT bo''ldi. Yakuniy jadvalning XULOSA qatorlariga (98, 99) qarang.';
  END IF;

  RAISE NOTICE 'TASKFIX_SHABLON_TRIGGER_FIX TUGADI — pastdagi jadvalga qarang. Keyingi qadam: TASKFIX_SHABLON.sql ni qayta RUN qiling.';
END $rep$;

COMMIT;

-- PostgREST sxema keshini yangilash (yangi ustunlar ko'rinsin).
NOTIFY pgrst, 'reload schema';


-- ══════════ NATIJA ══════════
SELECT bosqich, nom, qiymat, izoh FROM pg_temp.trgfix_res ORDER BY ord;


-- ============================================================================
-- QANDAY O'QISH
-- ============================================================================
--  • Barcha "qorovul" va "sinov" qatorlari OK bo'lsa ish bitdi →
--    endi `TASKFIX_SHABLON.sql` ni QAYTA RUN qiling.
--  • "allaqachon bor edi" / "2-RUN" — skript ikkinchi marta ishga tushirilgan.
--    Bu XATO emas: ustunlar qayta yaratilmaydi va zaxira nusxa ASL ta'rifni
--    saqlab qoladi (tuzatilgan ta'rif ustiga YOZILMAYDI).
--  • 🔴 ENG MUHIM QATORLAR:
--      (4)  UNIQUE indeks to'qnashuvi xavfi (sinov ENV ga tushsa — sabab)
--      (11) qorovul — bazadagi tana KUTILGAN ASL ta'rif bilan mos edimi
--      (12) funksiyaning O'ZGARISHDAN OLDINGI atributlari (DEFINER/INVOKER,
--           search_path) — tana solishtiruvi bularni KO'RMAYDI
--      (20) funksiya o'rnatildi va 5 ta qorovul TANADA tasdiqlandi
--      (L1)(L2)(L3)(L7) ESKI MANTIQ BUZILMAGANI — regressiya yo'q
--      (L4)(L5)(L6)(L8) yangi qorovullar ROSTDAN ishlayotgani — 🔴 (L8)
--          `p.is_template`/`p2.is_template` ni YAGONA qoplaydigan hukm
--      (98)/(99) XULOSA — tirik sinov bajarildimi va keyingi qadam
--  • "ENV:" prefiksi — muhit to'sdi (bo'sh baza / trigger yo'q / noma'lum
--    majburiy ustun), bu skriptning aybi EMAS. U holda funksiya baribir
--    COMMIT bo'ladi (qorovul va 4b tasdiqlash o'tgan), lekin qulf mantiqini
--    QO'LDA sinash kerak.
--
-- ── RUN'DAN OLDIN CHIQISHI MUMKIN BO'LGAN TO'XTATUVCHI XATO ────────────────
--   🔴 "bazadagi tanasi KUTILGAN ASL ta'rif bilan MOS EMAS"
--   Sabab: kimdir funksiyani oradan o'zgartirgan yoki bu boshqa versiya.
--   Skript ikkala tanani NOTICE bilan to'liq chop etadi. Yechim xato matnida.
--   Bu FAIL-CLOSED: begona funksiya ko'r-ko'rona bosib ketilmaydi.
--
--   🔴 "TIRIK SINOVLAR (L1..L8) YIQILDI"
--   Sabab: yangi funksiya kutilgandek ishlamadi yoki `public.tasks` da
--   `is_locked` ga tegadigan BOSHQA trigger ham bor. Hammasi qaytariladi.
--
--   🔴 "hozir SECURITY INVOKER, asl ta'rifda esa SECURITY DEFINER edi"
--   Sabab: bazadagi funksiyaning xavfsizlik konteksti kutilganidan boshqa.
--   Tana solishtiruvi buni ko'ra olmaydi, `CREATE OR REPLACE` esa uni jimgina
--   DEFINER ga o'tkazib yuborardi — shuning uchun FAIL-CLOSED. Yechim xato
--   matnida (4 va 4b-bo'limlarni mos ravishda o'zgartirish).
--
--   ⚠️ WARNING (to'xtatmaydi): "UNIQUE indeks(lar) bor …" — sentinel
--   sahnada bitta loyihada `flow_order` ataylab takrorlanadi; bunday indeks
--   bo'lsa sinovlar 23505 bilan ENV ga tushishi mumkin. (4) va (99) qatorlari
--   sababni ochiq aytadi; yechim — o'sha indeksni QISMAN qilish.
--
-- ============================================================================
-- QAYTARISH (kerak bo'lsa) — BITTA SO'ROV
--   Zaxiradagi ENG ESKI (ya'ni ASL) ta'rif qaytariladi. `def` — to'liq
--   `CREATE OR REPLACE FUNCTION ...` matni, shuning uchun uni EXECUTE qilish
--   kifoya; trigger'ga tegilmagani uchun bog'lanish o'z-o'zidan tiklanadi.
--
--   DO $$
--   DECLARE v_def text;
--   BEGIN
--     SELECT def INTO v_def FROM public.taskfix_trigger_backup
--      WHERE fn = 'public.sync_flow_locks()'
--      ORDER BY saved_at, id LIMIT 1;
--     IF v_def IS NULL THEN
--       RAISE EXCEPTION 'zaxira topilmadi';
--     END IF;
--     EXECUTE v_def;
--   END $$;
--
--   ⚠️ Ustunlar (`is_template`, `cycle_id`) ATAYLAB qaytarilmaydi — ular
--      additive va zararsiz; TASKFIX_SHABLON.sql baribir ularni talab qiladi.
--      Rostdan kerak bo'lsa (SHABLON ham RUN qilinmagan bo'lsa):
--        ALTER TABLE public.tasks DROP COLUMN IF EXISTS cycle_id;
--        ALTER TABLE public.tasks DROP COLUMN IF EXISTS is_template;
--      🔴 LEKIN AVVAL funksiyani ASL holiga qaytaring — aks holda tuzatilgan
--         funksiya yo'q ustunlarga murojaat qilib PROD DARROV BUZILADI.
-- ============================================================================
