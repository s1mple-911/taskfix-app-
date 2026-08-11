-- ============================================================================
-- TASKFIX_ORGCHART.sql — Org chart: qo'lda surilgan tugun joyi saqlansin
-- ============================================================================
-- ADDITIVE + IDEMPOTENT: mavjud ustun/ma'lumotga TEGMAYDI, faqat ikkita yangi
-- ustun qo'shadi. Qayta ishga tushirsa ham xavfsiz. RLS o'zgarmaydi —
-- TASKFIX_HR.sql dagi `org_folders_update` / `org_people_update` policy'lari
-- (is_ws_manager) shu ustunlarni ham qamrab oladi.
--
-- MUAMMO: org chart joylashuvi har safar qaytadan hisoblanardi, shuning uchun
--         foydalanuvchi kartani qo'lda surib qo'ya olmasdi (surilsa ham
--         keyingi chizishda avtomatik joyiga qaytardi).
--
-- YECHIM: node_x / node_y — NULL = AVTOMATIK, qiymat = QO'LDA qo'yilgan joy.
--         Avto algoritm faqat NULL li tugunlarni joylaydi; qo'lda surilgan
--         tugun o'z joyida qoladi va avlodi u bilan birga siljiydi.
--
-- ⚠️ IKKALA JADVALGA ham qo'shiladi (`org_people` VA `org_folders`) — chartda
--    papka kartochkasi ham bor (papkada 0 yoki 2+ hodim bo'lganda). Faqat
--    bittasiga qo'shilsa kartalarning bir qismi surilmay qolardi.
--    Birlashgan kartochka (papka·hodim bitta kartada) joyi PAPKA qatorida
--    saqlanadi — tugun kaliti ham papkaniki.
--
-- ⚠️ MA'NO TASHIMAYDI: node_x/node_y — faqat CHIZISH. Daraxt, bo'ysunish va
--    "kim kimga bo'ysunadi" avvalgidek FAQAT parent_id / parent_person_id /
--    folder_id dan hisoblanadi. Ikki ko'rinish (papka daraxti ↔ org chart)
--    shu sababli hech qachon ajralib qolmaydi.
--
-- ⚠️ BU FAYL ISHGA TUSHMASA — ilova YIQILMAYDI: surish o'sha sessiyada
--    ishlaydi, lekin saqlanmaydi va ilova buni ochiq aytadi (toast).
-- ============================================================================

BEGIN;

-- ── 0) Oldindan tekshiruv ───────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'public' AND c.relname = 'org_people') THEN
    RAISE EXCEPTION 'public.org_people topilmadi. Avval TASKFIX_HR.sql ni ishga tushiring.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'public' AND c.relname = 'org_folders') THEN
    RAISE EXCEPTION 'public.org_folders topilmadi. Avval TASKFIX_HR.sql ni ishga tushiring.';
  END IF;
END $$;

-- ── 1) Ustunlar ─────────────────────────────────────────────────────────────
-- double precision: mijoz butun songa yaxlitlab yozadi, lekin kelajakda
-- kasrli masshtab/joylashuv kerak bo'lsa turi cheklamasin.
ALTER TABLE public.org_people  ADD COLUMN IF NOT EXISTS node_x double precision;
ALTER TABLE public.org_people  ADD COLUMN IF NOT EXISTS node_y double precision;
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS node_x double precision;
ALTER TABLE public.org_folders ADD COLUMN IF NOT EXISTS node_y double precision;

COMMENT ON COLUMN public.org_people.node_x  IS 'Org chartda qo''lda qo''yilgan X. NULL = avtomatik joylashuv. Faqat chizish uchun — bo''ysunishga ta''sir qilmaydi.';
COMMENT ON COLUMN public.org_people.node_y  IS 'Org chartda qo''lda qo''yilgan Y. NULL = avtomatik joylashuv.';
COMMENT ON COLUMN public.org_folders.node_x IS 'Org chartda qo''lda qo''yilgan X (papka va birlashgan kartochka). NULL = avtomatik.';
COMMENT ON COLUMN public.org_folders.node_y IS 'Org chartda qo''lda qo''yilgan Y. NULL = avtomatik joylashuv.';

-- ── 2) Yarim to'ldirilgan holat bo'lmasin ───────────────────────────────────
-- Ikkovi ham NULL (avto) yoki ikkovi ham to'la (qo'lda). Mijoz "x bor, y yo'q"
-- ni avto deb hisoblaydi — DB ham shu holatga tushib qolmasin.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'org_people_node_xy_ck') THEN
    ALTER TABLE public.org_people
      ADD CONSTRAINT org_people_node_xy_ck CHECK ((node_x IS NULL) = (node_y IS NULL));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'org_folders_node_xy_ck') THEN
    ALTER TABLE public.org_folders
      ADD CONSTRAINT org_folders_node_xy_ck CHECK ((node_x IS NULL) = (node_y IS NULL));
  END IF;
END $$;

-- ── 3) TEKSHIRUV (jimgina o'tmasin) ─────────────────────────────────────────
DO $$
DECLARE
  t text;
  c text;
  v_typ text;
BEGIN
  FOREACH t IN ARRAY ARRAY['org_people', 'org_folders'] LOOP
    FOREACH c IN ARRAY ARRAY['node_x', 'node_y'] LOOP
      SELECT data_type INTO v_typ
        FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = t AND column_name = c;
      IF v_typ IS NULL THEN
        RAISE EXCEPTION 'TEKSHIRUV: public.%.% ustuni yaratilmadi.', t, c;
      END IF;
      IF v_typ <> 'double precision' THEN
        RAISE EXCEPTION 'TEKSHIRUV: public.%.% turi kutilmagan: %', t, c, v_typ;
      END IF;
      IF EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = t AND column_name = c
                    AND (is_nullable = 'NO' OR column_default IS NOT NULL)) THEN
        RAISE EXCEPTION 'TEKSHIRUV: public.%.% NULL bo''la olishi va defaultsiz bo''lishi kerak (NULL = avto).', t, c;
      END IF;
    END LOOP;
  END LOOP;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'org_people_node_xy_ck') THEN
    RAISE EXCEPTION 'TEKSHIRUV: org_people_node_xy_ck qo''shilmadi.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'org_folders_node_xy_ck') THEN
    RAISE EXCEPTION 'TEKSHIRUV: org_folders_node_xy_ck qo''shilmadi.';
  END IF;

  -- Yozish huquqi: RLS policy'lari o'z joyida turibdimi (yangi policy KERAK EMAS,
  -- lekin ular yo'q bo'lsa surish saqlanmaydi — buni oldindan aytamiz).
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
                  AND tablename = 'org_people' AND cmd = 'UPDATE') THEN
    RAISE EXCEPTION 'TEKSHIRUV: org_people uchun UPDATE policy yo''q — TASKFIX_HR.sql to''liq bajarilmagan.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
                  AND tablename = 'org_folders' AND cmd = 'UPDATE') THEN
    RAISE EXCEPTION 'TEKSHIRUV: org_folders uchun UPDATE policy yo''q — TASKFIX_HR.sql to''liq bajarilmagan.';
  END IF;
END $$;

-- ── 4) TIRIK TEST — ustun ham, CHECK ham haqiqatan ishlaydimi? ──────────────
-- Mavjud (node_x NULL bo'lgan) bitta qatorda sinaymiz va asl holatiga —
-- NULL ga — qaytaramiz. Qator topilmasa test o'tkazib yuboriladi.
DO $$
DECLARE
  v_id  uuid;
  v_x   double precision;
  v_ok  boolean;
BEGIN
  SELECT id INTO v_id FROM public.org_people WHERE node_x IS NULL ORDER BY id LIMIT 1;
  IF v_id IS NULL THEN
    RAISE NOTICE 'TIRIK TEST: org_people da sinash uchun qator yo''q — o''tkazib yuborildi.';
    RETURN;
  END IF;

  UPDATE public.org_people SET node_x = 123.5, node_y = 456.5 WHERE id = v_id;
  SELECT node_x INTO v_x FROM public.org_people WHERE id = v_id;
  IF v_x IS DISTINCT FROM 123.5 THEN
    RAISE EXCEPTION 'TIRIK TEST: node_x yozilmadi (olindi %).', COALESCE(v_x::text, 'NULL');
  END IF;

  -- Yarim to'ldirilgan holat RAD ETILISHI kerak
  v_ok := false;
  BEGIN
    UPDATE public.org_people SET node_y = NULL WHERE id = v_id;
  EXCEPTION WHEN check_violation THEN
    v_ok := true;
  END;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'TIRIK TEST: CHECK ishlamadi — yarim to''ldirilgan (x bor, y yo''q) holat o''tib ketdi.';
  END IF;

  -- Asl holat: avto (ikkovi ham NULL)
  UPDATE public.org_people SET node_x = NULL, node_y = NULL WHERE id = v_id;
  RAISE NOTICE 'TIRIK TEST: OK (%).', v_id;
END $$;

-- ── 5) Hisobot ──────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_p bigint; v_f bigint; v_pm bigint; v_fm bigint;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE node_x IS NOT NULL) INTO v_p, v_pm FROM public.org_people;
  SELECT count(*), count(*) FILTER (WHERE node_x IS NOT NULL) INTO v_f, v_fm FROM public.org_folders;
  RAISE NOTICE '───────────────────────────────────────────';
  RAISE NOTICE 'org_people:  %  (qo''lda joylashgan: %)', v_p, v_pm;
  RAISE NOTICE 'org_folders: %  (qo''lda joylashgan: %)', v_f, v_fm;
  RAISE NOTICE 'TAYYOR: endi chartda kartani surib qo''ysangiz joyi saqlanadi.';
  RAISE NOTICE 'Hammasini avtomatga qaytarish: ilovada "Avto joylashuv" tugmasi';
  RAISE NOTICE '(yoki: UPDATE public.org_people SET node_x=NULL, node_y=NULL; — org_folders ham).';
END $$;

COMMIT;

-- ============================================================================
-- QAYTARISH (kerak bo'lsa — ma'lumot yo'qoladi, faqat joylashuv):
--   ALTER TABLE public.org_people  DROP CONSTRAINT IF EXISTS org_people_node_xy_ck;
--   ALTER TABLE public.org_folders DROP CONSTRAINT IF EXISTS org_folders_node_xy_ck;
--   ALTER TABLE public.org_people  DROP COLUMN IF EXISTS node_x, DROP COLUMN IF EXISTS node_y;
--   ALTER TABLE public.org_folders DROP COLUMN IF EXISTS node_x, DROP COLUMN IF EXISTS node_y;
-- ============================================================================
