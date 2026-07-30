-- ============================================================================
-- TASKFIX_STRESS_CLEANUP.sql — hajm testidan keyin TOZALASH
-- ============================================================================
-- TASKFIX_STRESS_VOLUME.sql dan keyin ISHGA TUSHIRING. Test workspace'ni va
-- undagi HAMMA narsani o'chiradi, so'ng jadval statistikasini tiklaydi.
--
-- ⚠️ HIMOYA: faqat aynan v_ws (test uuid) VA nomi test belgisiga mos ws
--    o'chiriladi. Nomi boshqacha bo'lsa → RAISE EXCEPTION, hech narsa o'chmaydi.
--    Boshqa hech bir workspace'ga TEGILMAYDI.
-- ============================================================================

DO $cleanup$
DECLARE
  v_ws      CONSTANT uuid := 'a57e5511-0000-4d00-9000-000057e55001';
  v_ws_name CONSTANT text := 'ZZZ STRESS TEST — o''chirish uchun';
  v_name    text;
  v_tasks   bigint;
  v_del     bigint;
BEGIN
  SELECT name INTO v_name FROM public.workspaces WHERE id = v_ws;

  IF v_name IS NULL THEN
    -- Ws yo'q, lekin yetim vazifa qolgan bo'lishi mumkin
    SELECT count(*) INTO v_tasks FROM public.tasks WHERE workspace_id = v_ws;
    IF v_tasks > 0 THEN
      DELETE FROM public.tasks WHERE workspace_id = v_ws;
      GET DIAGNOSTICS v_del = ROW_COUNT;
      RAISE NOTICE 'Ws yo''q edi, % ta yetim test vazifa o''chirildi', v_del;
    ELSE
      RAISE NOTICE 'Tozalanadigan narsa yo''q (test ws allaqachon o''chirilgan)';
    END IF;
    RETURN;
  END IF;

  IF v_name <> v_ws_name THEN
    RAISE EXCEPTION 'TO''XTATILDI: % ws nomi "%" — test belgisiga mos emas. Bu PROD ws bo''lishi mumkin, HECH NARSA o''chirilmadi.', v_ws, v_name;
  END IF;

  SELECT count(*) INTO v_tasks FROM public.tasks WHERE workspace_id = v_ws;
  RAISE NOTICE 'Test ws topildi: "%" — % ta vazifa o''chiriladi', v_name, v_tasks;

  -- Vazifalarni aniq o'chiramiz (FK CASCADE bo'lmasa ham qolib ketmasin)
  DELETE FROM public.tasks WHERE workspace_id = v_ws;
  GET DIAGNOSTICS v_del = ROW_COUNT;
  RAISE NOTICE '  ✓ % ta vazifa o''chirildi', v_del;

  DELETE FROM public.workspace_members WHERE workspace_id = v_ws;
  DELETE FROM public.workspaces WHERE id = v_ws;
  RAISE NOTICE '  ✓ test workspace o''chirildi';

  -- Tekshiruv — jimgina o'tmasin
  IF EXISTS (SELECT 1 FROM public.tasks WHERE workspace_id = v_ws)
     OR EXISTS (SELECT 1 FROM public.workspaces WHERE id = v_ws) THEN
    RAISE EXCEPTION 'Tozalash to''liq bo''lmadi — qo''lda tekshiring';
  END IF;
  RAISE NOTICE '✅ Tozalandi. Endi VACUUM ANALYZE (pastda).';
END
$cleanup$;

-- ⚠️ VACUUM tranzaksiya ichida ishlamaydi — ALOHIDA ishga tushiring.
--    50k qator o'chgandan keyin statistikani tiklaydi (prod so'rovlari
--    eskirgan statistika bilan noto'g'ri rejalashtirilmasin).
VACUUM ANALYZE public.tasks;

-- Nazorat (0 qaytishi kerak)
SELECT
  (SELECT count(*) FROM public.tasks WHERE workspace_id = 'a57e5511-0000-4d00-9000-000057e55001') AS qolgan_vazifa,
  (SELECT count(*) FROM public.workspaces WHERE id = 'a57e5511-0000-4d00-9000-000057e55001') AS qolgan_ws,
  (SELECT count(*) FROM public.tasks) AS jami_vazifa_prod;
