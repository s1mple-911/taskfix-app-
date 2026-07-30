-- ============================================================================
-- TASKFIX_SCALE_ROLLBACK.sql — RLS policy'larni ASL holiga qaytarish
-- ============================================================================
-- TASKFIX_SCALE.sql o'zgartirgan policy'larni public.taskfix_rls_backup dagi
-- ASL matndan tiklaydi.
--
-- QACHON KERAK: agar RLS o'zgarishidan keyin kutilmagan xatti-harakat sezsangiz
-- (ilovada "ruxsat yo'q", ma'lumot ko'rinmaslik va h.k.).
--
-- ⚠️ INDEKSLARGA TEGILMAYDI — ular xavfsiz va faqat foyda beradi. Baribir
--    o'chirish kerak bo'lsa, fayl oxiridagi izohga qarang.
--
-- Bitta tranzaksiya: birortasi tiklanmasa hammasi qaytadi.
-- ============================================================================

BEGIN;

DO $rb$
DECLARE
  r        RECORD;
  v_sql    text;
  v_n      int := 0;
  v_batch  timestamptz;
BEGIN
  IF to_regclass('public.taskfix_rls_backup') IS NULL THEN
    RAISE EXCEPTION 'public.taskfix_rls_backup topilmadi — qaytaradigan narsa yo''q (TASKFIX_SCALE.sql ishga tushmagan?)';
  END IF;

  -- Eng oxirgi saqlash to'plamini olamiz
  SELECT max(saqlangan) INTO v_batch FROM public.taskfix_rls_backup;
  IF v_batch IS NULL THEN
    RAISE EXCEPTION 'taskfix_rls_backup bo''sh — qaytaradigan narsa yo''q';
  END IF;
  RAISE NOTICE 'Qaytarilmoqda: % dagi to''plam', v_batch;

  FOR r IN
    SELECT * FROM public.taskfix_rls_backup
     WHERE saqlangan = v_batch
     ORDER BY id
  LOOP
    -- Policy hali ham mavjudmi?
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
       WHERE schemaname = r.schemaname AND tablename = r.tablename AND policyname = r.policyname
    ) THEN
      RAISE WARNING '  ⚠ %.% policy''si topilmadi — o''tkazib yuborildi', r.tablename, r.policyname;
      CONTINUE;
    END IF;

    v_sql := format('ALTER POLICY %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
    IF r.qual IS NOT NULL THEN v_sql := v_sql || format(' USING (%s)', r.qual); END IF;
    IF r.with_check IS NOT NULL THEN v_sql := v_sql || format(' WITH CHECK (%s)', r.with_check); END IF;
    EXECUTE v_sql;
    v_n := v_n + 1;
    RAISE NOTICE '  ↩ %.% tiklandi', r.tablename, r.policyname;
  END LOOP;

  IF v_n = 0 THEN
    RAISE EXCEPTION 'Birorta policy tiklanmadi — qo''lda tekshiring';
  END IF;
  RAISE NOTICE '✅ % ta policy asl holiga qaytarildi', v_n;
END
$rb$;

COMMIT;

-- Nazorat: qaysi policy'larda hamon (SELECT auth.uid()) bor
SELECT tablename, policyname, cmd,
       CASE WHEN coalesce(qual,'') || coalesce(with_check,'') ~ '\(\s*SELECT\s+auth\.uid\(\)\s*\)'
            THEN 'optimallashtirilgan' ELSE 'asl holida' END AS holat
  FROM pg_policies
 WHERE schemaname = 'public'
   AND (coalesce(qual,'') || coalesce(with_check,'')) ~ 'auth\.uid\(\)'
 ORDER BY tablename, policyname;

-- ============================================================================
-- INDEKSLARNI ham o'chirish kerak bo'lsa (odatda SHART EMAS — ular zararsiz):
--   DROP INDEX IF EXISTS public.idx_tasks_ws_created;
--   DROP INDEX IF EXISTS public.idx_tasks_ws_status;
--   DROP INDEX IF EXISTS public.idx_tasks_ws_deadline;
--   DROP INDEX IF EXISTS public.idx_ws_members_user_ws;
-- ============================================================================
