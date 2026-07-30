-- ============================================================================
-- TASKFIX_STRESS_VOLUME.sql — HAJM TESTI (BRIEF_TASKFIX_STRESS, 3-test)
-- ============================================================================
-- Alohida TEST workspace'da 1 000 → 10 000 → 50 000 vazifa hosil qiladi va
-- har hajmda ilovaning HAQIQIY so'rovlarini EXPLAIN (ANALYZE) bilan o'lchaydi.
--
-- ⚠️⚠️ PROD XAVFSIZLIGI ⚠️⚠️
--   • HAMMA yozuv FAQAT bitta test workspace ichida (v_ws, pastda qattiq yozilgan).
--     Har INSERT/DELETE `workspace_id = v_ws` bilan cheklangan.
--   • Ishga tushishdan oldin TEKSHIRADI: v_ws mavjud ws'lardan biri bo'lsa va
--     nomi test belgisiga mos kelmasa → RAISE EXCEPTION, hech narsa qilinmaydi.
--   • Aros prod ws (12b22aa6-…) qora ro'yxatda — tasodifan ham tegmaydi.
--   • Boshqa hech bir workspace'ning bironta qatoriga TEGILMAYDI.
--
--   Shunga qaramay bu PROD BAZA. Hisobga oling:
--     – tasks jadvali ~50k qatorga o'sadi (keyin tozalanadi + VACUUM ANALYZE)
--     – Realtime WAL'ni qayta ishlaydi (prod mijozlarga YETIB BORMAYDI —
--       obuna `workspace_id=eq.<o'z ws>` bilan filtrlangan, index.html:4580)
--     – ish vaqtidan TASHQARIDA ishga tushirish tavsiya etiladi
--
--   TUGAGACH: TASKFIX_STRESS_CLEANUP.sql ni ISHGA TUSHIRING.
--
-- ⚠️ v_add_member = true bo'lsa test ws egasining ilovasida KO'RINADI
--    (workspace almashtirgichda "ZZZ STRESS TEST"). Bu 2-test (yuklama) va
--    RLS o'lchovi uchun kerak. Tozalashdan keyin yo'qoladi.
--
-- NATIJA: oxirgi SELECT — jadval (hajm · so'rov · ms · plan · indeks).
-- ============================================================================

-- ── Natija jadvali (vaqtinchalik — sessiya tugasa o'zi yo'qoladi) ───────────
DROP TABLE IF EXISTS pg_temp.stress_res;
CREATE TEMP TABLE pg_temp.stress_res (
  hajm        int,
  sorov       text,
  raw_ms      numeric,   -- postgres roli (RLS'siz) — toza SQL narxi
  rls_ms      numeric,   -- authenticated roli (RLS bilan) — ilova sezadigan narx
  qator       bigint,
  plan_node   text,
  seq_scan    boolean,   -- TRUE = indeks ishlatilmadi (to'liq skanerlash)
  izoh        text,
  ord         int
);

DO $stress$
DECLARE
  -- ══════════ SOZLAMALAR ══════════
  v_ws         CONSTANT uuid := 'a57e5511-0000-4d00-9000-000057e55001';  -- TEST ws (qattiq yozilgan)
  v_ws_name    CONSTANT text := 'ZZZ STRESS TEST — o''chirish uchun';
  v_add_member CONSTANT boolean := true;   -- egasini a'zo qilish (RLS o'lchovi + yuklama testi uchun)
  v_volumes    CONSTANT int[]  := ARRAY[1000, 10000, 50000];
  v_owner      uuid := NULL;               -- NULL = auth.users dan birinchisi olinadi

  -- Prod ws'lar — qora ro'yxat (tasodifan nishonga aylanmasin)
  v_blacklist  CONSTANT uuid[] := ARRAY['12b22aa6-dc45-4197-ae84-2e32e3cd56c2'::uuid];  -- Aros

  v_vol        int;
  v_have       bigint;
  v_need       int;
  v_json       jsonb;
  v_raw        numeric;
  v_rls        numeric;
  v_rows       bigint;
  v_node       text;
  v_seq        boolean;
  v_note       text;
  v_ord        int := 0;
  q            RECORD;
  v_sql        text;
BEGIN
  -- ══════════ 0) HIMOYA ══════════
  IF v_ws = ANY (v_blacklist) THEN
    RAISE EXCEPTION 'TO''XTATILDI: nishon ws qora ro''yxatda (prod!) — %', v_ws;
  END IF;
  IF EXISTS (SELECT 1 FROM public.workspaces WHERE id = v_ws AND name <> v_ws_name) THEN
    RAISE EXCEPTION 'TO''XTATILDI: % ws allaqachon bor va nomi test belgisiga mos emas. Bu PROD ws bo''lishi mumkin — hech narsa qilinmadi.', v_ws;
  END IF;

  IF v_owner IS NULL THEN
    SELECT id INTO v_owner FROM auth.users ORDER BY created_at LIMIT 1;
  END IF;
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'auth.users bo''sh — test ma''lumot uchun egasi kerak';
  END IF;
  RAISE NOTICE 'Test ws: %  ·  egasi: %', v_ws, v_owner;

  -- ══════════ 1) TEST WORKSPACE ══════════
  INSERT INTO public.workspaces (id, kind, name, owner_id)
  VALUES (v_ws, 'organization', v_ws_name, v_owner)
  ON CONFLICT (id) DO NOTHING;

  IF v_add_member THEN
    INSERT INTO public.workspace_members (workspace_id, user_id, role)
    VALUES (v_ws, v_owner, 'owner')
    ON CONFLICT DO NOTHING;
  END IF;

  -- ══════════ 2) HAJM BO'YICHA: to'ldirish + o'lchash ══════════
  FOREACH v_vol IN ARRAY v_volumes LOOP
    SELECT count(*) INTO v_have FROM public.tasks WHERE workspace_id = v_ws;
    v_need := v_vol - v_have;

    IF v_need > 0 THEN
      RAISE NOTICE '→ % ta vazifa qo''shilmoqda (hozir %, kerak %)...', v_need, v_have, v_vol;
      -- ⚠️ TIP MASALASI: generate_series(bigint, bigint) → g BIGINT.
      --    Shu sababli avvalgi variant yiqilgan edi:
      --      repeat('...', 1 + (g % 5))        → repeat(text, INTEGER) kutadi,
      --                                          bigint bilan mos funksiya yo'q
      --      (ARRAY[...])[1 + (g % 4)]         → massiv indeksi INTEGER bo'lishi kerak
      --      (g % 120) * interval '1 day'      → bigint * interval operatori yo'q
      --    Endi: massiv indekslash umuman ishlatilmaydi (CASE), har bir
      --    arifmetika ::int ga keltirilgan, interval make_interval() bilan.
      INSERT INTO public.tasks (workspace_id, title, description, status, priority_level,
                                created_by, assigned_to, deadline, created_at)
      SELECT
        v_ws,
        'Stress test vazifa #' || g::text || ' ' || substr(md5(g::text), 1, 8),
        'Avtomatik hosil qilingan test ma''lumot ' || substr(md5((g * 7)::text), 1, 24),
        CASE (g % 4)::int
          WHEN 0 THEN 'new'
          WHEN 1 THEN 'in_progress'
          WHEN 2 THEN 'completed'
          ELSE 'qabul_kutilyapti'
        END,
        (g % 11)::int,
        v_owner,
        CASE WHEN (g % 3)::int = 0 THEN v_owner ELSE NULL END,
        now() + make_interval(days => ((g % 120) - 60)::int),
        now() - make_interval(days => (g % 365)::int)
      FROM generate_series((v_have + 1)::bigint, v_vol::bigint) AS s(g);
    END IF;

    -- Rejalashtiruvchi yangi hajmni ko'rishi uchun
    ANALYZE public.tasks;

    -- ── O'lchanadigan so'rovlar (ilova haqiqatan yuboradiganlari) ──
    FOR q IN
      SELECT * FROM (VALUES
        -- ⚠️ 1-so'rov: loadTasksFull() AYNAN shunday qiladi — LIMITSIZ (index.html)
        ('1_royxat_limitsiz',  format('SELECT * FROM public.tasks WHERE workspace_id = %L ORDER BY created_at DESC', v_ws)),
        ('2_royxat_limit100',  format('SELECT * FROM public.tasks WHERE workspace_id = %L ORDER BY created_at DESC LIMIT 100', v_ws)),
        ('3_bajaruvchi',       format('SELECT * FROM public.tasks WHERE workspace_id = %L AND assigned_to = %L', v_ws, v_owner)),
        ('4_holat',            format('SELECT * FROM public.tasks WHERE workspace_id = %L AND status = ''new''', v_ws)),
        ('5_qidiruv_ilike',    format('SELECT * FROM public.tasks WHERE workspace_id = %L AND title ILIKE ''%%vazifa #7%%'' LIMIT 20', v_ws)),
        ('6_hisobot_group',    format('SELECT status, count(*) FROM public.tasks WHERE workspace_id = %L GROUP BY status', v_ws)),
        ('7_kalendar_oraliq',  format('SELECT * FROM public.tasks WHERE workspace_id = %L AND deadline >= now() - interval ''15 days'' AND deadline < now() + interval ''15 days''', v_ws))
      ) AS t(nom, sql)
    LOOP
      v_ord := v_ord + 1;
      v_note := NULL;

      -- (a) RLS'SIZ — toza SQL narxi (postgres roli)
      EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || q.sql INTO v_json;
      v_raw  := (v_json -> 0 ->> 'Execution Time')::numeric;
      v_node := v_json -> 0 -> 'Plan' ->> 'Node Type';
      v_rows := (v_json -> 0 -> 'Plan' ->> 'Actual Rows')::bigint;
      v_seq  := (v_json::text LIKE '%"Node Type": "Seq Scan"%');

      -- (b) RLS BILAN — ilova (authenticated roli) sezadigan haqiqiy narx
      v_rls := NULL;
      BEGIN
        PERFORM set_config('request.jwt.claims',
                 json_build_object('sub', v_owner::text, 'role', 'authenticated')::text, true);
        EXECUTE 'SET LOCAL ROLE authenticated';
        EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || q.sql INTO v_json;
        v_rls := (v_json -> 0 ->> 'Execution Time')::numeric;
        IF v_json::text LIKE '%"Node Type": "Seq Scan"%' THEN v_seq := true; END IF;
        EXECUTE 'RESET ROLE';
      EXCEPTION WHEN OTHERS THEN
        BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
        v_note := 'RLS o''lchovi bajarilmadi: ' || SQLERRM;
      END;

      INSERT INTO pg_temp.stress_res
        VALUES (v_vol, q.nom, round(v_raw, 1), round(v_rls, 1), v_rows, v_node, v_seq, v_note, v_ord);
    END LOOP;

    RAISE NOTICE '   ✓ % hajmda o''lchandi', v_vol;
  END LOOP;

  RAISE NOTICE '════ TUGADI. Natija uchun pastdagi SELECT. Keyin TASKFIX_STRESS_CLEANUP.sql! ════';
END
$stress$;

-- ── Mavjud indekslar (nima bor, nima yo'q) ─────────────────────────────────
INSERT INTO pg_temp.stress_res (hajm, sorov, izoh, ord)
SELECT 0, 'INDEKS: ' || i.relname, pg_get_indexdef(i.oid), 9000 + row_number() OVER (ORDER BY i.relname)
  FROM pg_index x
  JOIN pg_class i ON i.oid = x.indexrelid
  JOIN pg_class c ON c.oid = x.indrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relname = 'tasks';

-- ══════════ NATIJA ══════════
SELECT hajm, sorov, raw_ms, rls_ms,
       CASE WHEN raw_ms IS NULL OR raw_ms = 0 OR rls_ms IS NULL THEN NULL
            ELSE round(rls_ms / raw_ms, 1) END AS rls_narxi_x,
       qator, plan_node,
       CASE WHEN seq_scan THEN '⚠️ SEQ SCAN — indeks kerak' ELSE 'indeks ✓' END AS indeks,
       izoh
  FROM pg_temp.stress_res
 ORDER BY ord;

-- ============================================================================
-- QANDAY O'QISH
-- ============================================================================
-- raw_ms      — RLS'siz (toza SQL). Ma'lumot hajmining o'zi qancha turadi.
-- rls_ms      — authenticated roli, RLS policy'lari bilan. ILOVA SHUNI SEZADI.
-- rls_narxi_x — rls_ms / raw_ms. 3× dan katta bo'lsa RLS policy'si qimmat
--               (odatda policy ichidagi subquery — is_ws_member() bilan
--               almashtirilishi kerak, CLAUDE.md 7-qoida).
-- indeks      — "SEQ SCAN" chiqsa o'sha so'rov uchun indeks yo'q. Hajm oshganda
--               ayni shu qatorlar keskin sekinlashadi.
--
-- Kutilgan xulosa: 1_royxat_limitsiz hajm bilan CHIZIQLI o'sadi (50k qator
-- brauzerga tashiladi) — bu indeks bilan hal bo'lmaydi, LIMIT/pagination kerak.
-- Qolganlari indeks bilan tekis qolishi kerak.
-- ============================================================================
