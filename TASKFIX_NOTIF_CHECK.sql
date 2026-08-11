-- ============================================================================
-- TASKFIX_NOTIF_CHECK.sql — `public.notifications` DIAGNOSTIKASI
-- ============================================================================
-- 🔴 BU SKRIPT HECH NARSANI O'ZGARTIRMAYDI.
--    Faqat SELECT + RAISE NOTICE. Ichida CREATE TABLE / CREATE POLICY /
--    ALTER / INSERT / UPDATE / DELETE / GRANT **YO'Q** — mavjud prod jadvaliga
--    tegish xavfli (in-app bildirishnomalar bugun ishlab turibdi).
--
-- MAQSAD: "Loyihaga taklif" in-app bildirishnomasi (`notifyProjectAssign`,
--    index.html) BOSHQA a'zo nomiga qator yozadi. Bu allaqachon ishlaydigan
--    `notifyMention` bilan bir xil naqsh — ya'ni yangi SQL kerak emas.
--    Shu skript INSERT policy haqiqatan a'zolar aro yozishga ruxsat berishini
--    ochiq ko'rsatadi (policy matni bilan).
--
-- QAYERDA ISHLATILADI: Supabase SQL Editor. Natija "Messages"/NOTICE panelida.
-- ============================================================================

DO $$
DECLARE
  v_exists    boolean;
  v_rls       boolean;
  v_force     boolean;
  v_n         int;
  r           record;
  v_ins_cnt   int := 0;
  v_sel_cnt   int := 0;
BEGIN
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE 'TASKFIX — notifications diagnostikasi (faqat o''qish)';
  RAISE NOTICE '════════════════════════════════════════════════════════════';

  -- ── 1) Jadval bormi? ──────────────────────────────────────────────────────
  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name = 'notifications'
  ) INTO v_exists;

  IF NOT v_exists THEN
    RAISE NOTICE '❌ public.notifications JADVALI YO''Q.';
    RAISE NOTICE '   In-app bildirishnomalar (mention ham, loyihaga taklif ham) ishlamaydi.';
    RAISE NOTICE '   Mijoz kodi buni jimgina yutmaydi — console.error beradi, ilova buzilmaydi.';
    RETURN;
  END IF;
  RAISE NOTICE '✅ 1) Jadval mavjud: public.notifications';

  -- ── 2) Ustunlar ───────────────────────────────────────────────────────────
  RAISE NOTICE '';
  RAISE NOTICE '── 2) USTUNLAR ──────────────────────────────────────────────';
  FOR r IN
    SELECT column_name, data_type, is_nullable, COALESCE(column_default,'—') AS def
      FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'notifications'
     ORDER BY ordinal_position
  LOOP
    RAISE NOTICE '   % | % | null=% | default=%', rpad(r.column_name,16), rpad(r.data_type,28), r.is_nullable, r.def;
  END LOOP;

  -- Mijoz KUTAYOTGAN ustunlar (index.html): kind (type EMAS), read_at (read EMAS), meta jsonb
  RAISE NOTICE '';
  RAISE NOTICE '── 2b) MIJOZ KUTAYOTGAN USTUNLAR ────────────────────────────';
  FOR r IN
    SELECT c.name,
           EXISTS (SELECT 1 FROM information_schema.columns ic
                    WHERE ic.table_schema='public' AND ic.table_name='notifications'
                      AND ic.column_name = c.name) AS present
      FROM (VALUES ('id'),('user_id'),('workspace_id'),('kind'),('title'),
                   ('body'),('meta'),('read_at'),('created_at')) AS c(name)
  LOOP
    RAISE NOTICE '   % → %', rpad(r.name,14), CASE WHEN r.present THEN 'BOR ✅' ELSE 'YO''Q ❌' END;
  END LOOP;

  -- `meta` jsonb bo'lishi shart: openNotifTask meta.task_id / meta.workspace_id ga qaraydi
  SELECT count(*) INTO v_n
    FROM information_schema.columns
   WHERE table_schema='public' AND table_name='notifications'
     AND column_name='meta' AND data_type IN ('jsonb','json');
  RAISE NOTICE '   meta turi jsonb/json: %', CASE WHEN v_n>0 THEN 'HA ✅ (bosilish meta.task_id + meta.workspace_id bilan ishlaydi)'
                                                  ELSE 'YO''Q ❌ (bildirishnoma bosilmaydi)' END;

  -- `kind` da CHECK bormi? Bo'lsa 'task_assigned' ro'yxatda turishi kerak.
  RAISE NOTICE '';
  RAISE NOTICE '── 2c) kind ustunidagi CHECK (bo''lsa) ───────────────────────';
  v_n := 0;
  FOR r IN
    SELECT con.conname, pg_get_constraintdef(con.oid) AS def
      FROM pg_constraint con
      JOIN pg_class cl ON cl.oid = con.conrelid
      JOIN pg_namespace ns ON ns.oid = cl.relnamespace
     WHERE ns.nspname='public' AND cl.relname='notifications' AND con.contype='c'
  LOOP
    v_n := v_n + 1;
    RAISE NOTICE '   % : %', r.conname, r.def;
    IF r.def ILIKE '%kind%' AND r.def NOT ILIKE '%task_assigned%' THEN
      RAISE NOTICE '   ⚠️  DIQQAT: kind CHECK''ida ''task_assigned'' KO''RINMAYDI — loyihaga taklif INSERT''i rad etilishi mumkin.';
    END IF;
  END LOOP;
  IF v_n = 0 THEN
    RAISE NOTICE '   CHECK yo''q — kind erkin matn (mijoz ''task_assigned'' yozadi, ikonka 🔔 tayyor).';
  END IF;

  -- ── 3) RLS holati ─────────────────────────────────────────────────────────
  SELECT cl.relrowsecurity, cl.relforcerowsecurity INTO v_rls, v_force
    FROM pg_class cl JOIN pg_namespace ns ON ns.oid = cl.relnamespace
   WHERE ns.nspname='public' AND cl.relname='notifications';
  RAISE NOTICE '';
  RAISE NOTICE '── 3) RLS ───────────────────────────────────────────────────';
  RAISE NOTICE '   rowsecurity=%  force=%', v_rls, v_force;
  IF NOT v_rls THEN
    RAISE NOTICE '   ⚠️  RLS O''CHIQ — har qanday authenticated foydalanuvchi hamma qatorni ko''radi/yozadi.';
  END IF;

  -- ── 4) Policy'lar (to'liq matn) ───────────────────────────────────────────
  RAISE NOTICE '';
  RAISE NOTICE '── 4) POLICY''LAR ───────────────────────────────────────────';
  FOR r IN
    SELECT policyname, permissive, cmd, roles::text AS roles,
           COALESCE(qual,'—') AS qual, COALESCE(with_check,'—') AS wc
      FROM pg_policies
     WHERE schemaname='public' AND tablename='notifications'
     ORDER BY cmd, policyname
  LOOP
    RAISE NOTICE '   ▸ % [%] cmd=% roles=%', r.policyname, r.permissive, r.cmd, r.roles;
    RAISE NOTICE '       USING      : %', r.qual;
    RAISE NOTICE '       WITH CHECK : %', r.wc;
    IF r.cmd IN ('INSERT','ALL') THEN v_ins_cnt := v_ins_cnt + 1; END IF;
    IF r.cmd IN ('SELECT','ALL') THEN v_sel_cnt := v_sel_cnt + 1; END IF;
  END LOOP;

  RAISE NOTICE '';
  RAISE NOTICE '── 5) XULOSA (INSERT — eng muhim savol) ─────────────────────';
  RAISE NOTICE '   SELECT policy soni: %   INSERT policy soni: %', v_sel_cnt, v_ins_cnt;
  IF v_ins_cnt = 0 AND v_rls THEN
    RAISE NOTICE '   ❌ INSERT policy YO''Q + RLS yoniq → mijoz hech kimga bildirishnoma yoza olmaydi.';
    RAISE NOTICE '      Lekin @mention bugun ishlayotgan bo''lsa — demak yozuv boshqa yo''l bilan (EF/service key) ketmoqda.';
  ELSE
    RAISE NOTICE '   Yuqoridagi WITH CHECK matnini o''qing:';
    RAISE NOTICE '     • `user_id = auth.uid()` bo''lsa → FAQAT o''ziga yozish mumkin,';
    RAISE NOTICE '       ya''ni "Loyihaga taklif" (boshqa odamga) RLS bilan to''siladi.';
    RAISE NOTICE '     • `is_ws_member(workspace_id)` / `true` kabi shart bo''lsa → a''zolar aro';
    RAISE NOTICE '       yozish OCHIQ, yangi SQL kerak emas (notifyMention shu bilan ishlaydi).';
  END IF;

  -- ── 6) Mavjud ma'lumot: kind bo'yicha (tarixiy dalil) ─────────────────────
  RAISE NOTICE '';
  RAISE NOTICE '── 6) MAVJUD QATORLAR (kind bo''yicha, oxirgi 90 kun) ────────';
  FOR r IN
    EXECUTE 'SELECT kind, count(*) AS c, max(created_at) AS last_at
               FROM public.notifications
              WHERE created_at > now() - interval ''90 days''
              GROUP BY kind ORDER BY c DESC'
  LOOP
    RAISE NOTICE '   % | % ta | oxirgi: %', rpad(COALESCE(r.kind,'(null)'),22), r.c, r.last_at;
  END LOOP;

  -- Boshqa odam nomiga yozilgan qator BORMI? (INSERT policy amalda ishlaganining dalili)
  EXECUTE 'SELECT count(*) FROM public.notifications
            WHERE kind = ''mention'' AND created_at > now() - interval ''180 days''' INTO v_n;
  RAISE NOTICE '';
  RAISE NOTICE '   mention qatorlari (180 kun): % ta', v_n;
  IF v_n > 0 THEN
    RAISE NOTICE '   ✅ Mijoz BOSHQA odam nomiga muvaffaqiyatli yozgan (notifyMention) —';
    RAISE NOTICE '      "Loyihaga taklif" ham aynan shu yo''ldan ketadi, yangi policy SHART EMAS.';
  ELSE
    RAISE NOTICE '   ℹ️  mention qatori yo''q — jonli dalil yo''q, faqat policy matniga qarang.';
  END IF;

  RAISE NOTICE '';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE 'TUGADI — hech narsa o''zgartirilmadi (faqat SELECT).';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
END $$;
