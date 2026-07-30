#!/usr/bin/env node
/* ============================================================================
 * stress_test.js — TaskFix YUKLAMA TESTI (BRIEF_TASKFIX_STRESS, 2-test)
 * ============================================================================
 * Supabase'ga bir vaqtda N ta parallel so'rov yuboradi va javob vaqti qanday
 * o'sishini o'lchaydi. N = 10 → 50 → 100 → 500.
 *
 * ⚠️⚠️ DIQQAT — PROD LOYIHA ⚠️⚠️
 *   Bu skript FAQAT O'QIYDI (GET). Hech narsa yozmaydi/o'chirmaydi.
 *   Lekin 500 ta parallel so'rov PROD Supabase'ni bir necha soniya band qiladi
 *   va shu payt haqiqiy foydalanuvchilar sekinlik sezishi mumkin.
 *   Shuning uchun:
 *     • ish vaqtidan TASHQARIDA (kechqurun) ishga tushiring
 *     • --ws bilan TEST workspace'ni ko'rsating (prod ws bo'lmasin)
 *     • ishga tushirish uchun --yes SHART (tasodifan ishlamasin)
 *   Xato ulushi 30% dan oshsa — qolgan bosqichlar BEKOR qilinadi.
 *
 * TALAB: Node 18+ (global fetch). Hech qanday npm paket kerak emas.
 *
 * ISHLATISH:
 *   1) Faqat o'lchov rejasini ko'rish (hech narsa yubormaydi):
 *        node stress_test.js --dry
 *
 *   2) Haqiqiy test (tavsiya etilgan — test ws + test foydalanuvchi):
 *        node stress_test.js --yes \
 *          --ws 00000000-57e5-4e55-0000-5723e5500001 \
 *          --email test@example.com --password '...'
 *
 *   3) Login'siz (anon) rejim — RLS hamma narsani to'sadi, shuning uchun
 *      ma'lumot emas, faqat TARMOQ + RLS xarajati va rate-limit o'lchanadi:
 *        node stress_test.js --yes --anon
 *
 *   Qo'shimcha: --stages 10,50,100  --delay 4000  --timeout 20000
 *
 * NATIJA: oxirida markdown jadval chiqadi — o'shani nusxalab bering.
 * ========================================================================== */

'use strict';

const SUPABASE_URL = 'https://nnpsbwsppgxbytlfloth.supabase.co';
const ANON_KEY = 'sb_publishable_ouA6pp3DwJjQkDJrWPi8QQ_30CUo51t';

// ── Argumentlar ─────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
function arg(name, def) {
  const i = argv.indexOf('--' + name);
  if (i === -1) return def;
  const v = argv[i + 1];
  return (v && v.indexOf('--') !== 0) ? v : true;
}
const CFG = {
  yes:      argv.includes('--yes'),
  dry:      argv.includes('--dry'),
  anon:     argv.includes('--anon'),
  ws:       arg('ws', null),
  email:    arg('email', process.env.TF_EMAIL || null),
  password: arg('password', process.env.TF_PASSWORD || null),
  stages:   String(arg('stages', '10,50,100,500')).split(',').map(function (s) { return parseInt(s, 10); }).filter(Boolean),
  delay:    parseInt(arg('delay', '4000'), 10),
  timeout:  parseInt(arg('timeout', '20000'), 10),
  limit:    parseInt(arg('limit', '100'), 10),   // tasks so'rovidagi limit (frontend ham sahifalaydi)
};

// Xato ulushi shundan oshsa — keyingi bosqichlar bekor (prodni ayamaslik xavfi)
const ABORT_ERR_RATE = 0.30;

// ── Yordamchilar ────────────────────────────────────────────────────────────
const sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
function pct(arr, p) {
  if (!arr.length) return 0;
  const a = arr.slice().sort(function (x, y) { return x - y; });
  const i = Math.min(a.length - 1, Math.max(0, Math.ceil(p / 100 * a.length) - 1));
  return a[i];
}
const avg = function (a) { return a.length ? a.reduce(function (x, y) { return x + y; }, 0) / a.length : 0; };
const r1 = function (n) { return Math.round(n * 10) / 10; };

// ── So'rov turlari (frontend haqiqatan yuboradiganlari) ─────────────────────
function queries(ws) {
  const w = ws ? ('&workspace_id=eq.' + ws) : '';
  return [
    { name: 'tasks',   path: '/rest/v1/tasks?select=*' + w + '&order=created_at.desc&limit=' + CFG.limit },
    { name: 'members', path: '/rest/v1/workspace_members?select=user_id,role,created_at' + w },
    { name: 'projects', path: '/rest/v1/projects?select=*' + w },
  ];
}

async function login() {
  const res = await fetch(SUPABASE_URL + '/auth/v1/token?grant_type=password', {
    method: 'POST',
    headers: { 'apikey': ANON_KEY, 'content-type': 'application/json' },
    body: JSON.stringify({ email: CFG.email, password: CFG.password }),
  });
  const body = await res.json().catch(function () { return {}; });
  if (!res.ok || !body.access_token) {
    throw new Error('Login muvaffaqiyatsiz (' + res.status + '): ' + (body.error_description || body.msg || JSON.stringify(body).slice(0, 200)));
  }
  return body.access_token;
}

async function once(q, token) {
  const ctl = new AbortController();
  const t = setTimeout(function () { ctl.abort(); }, CFG.timeout);
  const t0 = performance.now();
  try {
    const res = await fetch(SUPABASE_URL + q.path, {
      headers: {
        'apikey': ANON_KEY,
        'authorization': 'Bearer ' + (token || ANON_KEY),
        'accept': 'application/json',
        'prefer': 'count=none',
      },
      signal: ctl.signal,
    });
    // Javob to'liq o'qilishi kerak — aks holda vaqt yolg'on chiqadi
    const txt = await res.text();
    const ms = performance.now() - t0;
    return { ms: ms, status: res.status, ok: res.ok, bytes: txt.length,
             rows: res.ok ? countRows(txt) : 0 };
  } catch (e) {
    return { ms: performance.now() - t0, status: e.name === 'AbortError' ? 408 : 0,
             ok: false, bytes: 0, rows: 0, err: String(e.message || e) };
  } finally {
    clearTimeout(t);
  }
}
function countRows(txt) {
  try { const j = JSON.parse(txt); return Array.isArray(j) ? j.length : 1; } catch (e) { return 0; }
}

async function stage(n, token, ws) {
  const qs = queries(ws);
  const jobs = [];
  for (let i = 0; i < n; i++) jobs.push(qs[i % qs.length]);
  const t0 = performance.now();
  const res = await Promise.all(jobs.map(function (q) { return once(q, token); }));
  const wall = performance.now() - t0;

  const okMs = res.filter(function (r) { return r.ok; }).map(function (r) { return r.ms; });
  const errs = res.filter(function (r) { return !r.ok; });
  const byStatus = {};
  res.forEach(function (r) { byStatus[r.status] = (byStatus[r.status] || 0) + 1; });

  // Har so'rov turi bo'yicha ham ajratamiz
  const perQ = {};
  qs.forEach(function (q) { perQ[q.name] = []; });
  res.forEach(function (r, i) { if (r.ok) perQ[jobs[i].name].push(r.ms); });

  return {
    n: n, wall: wall, ok: res.length - errs.length, err: errs.length,
    errRate: errs.length / res.length,
    avg: avg(okMs), p50: pct(okMs, 50), p90: pct(okMs, 90), p95: pct(okMs, 95),
    max: okMs.length ? Math.max.apply(null, okMs) : 0,
    min: okMs.length ? Math.min.apply(null, okMs) : 0,
    rps: res.length / (wall / 1000),
    rate429: byStatus['429'] || 0,
    byStatus: byStatus,
    perQ: perQ,
    rows: res.reduce(function (a, r) { return a + r.rows; }, 0),
    sampleErr: errs.length ? (errs[0].err || ('HTTP ' + errs[0].status)) : null,
  };
}

// ── Asosiy oqim ─────────────────────────────────────────────────────────────
(async function main() {
  console.log('════════════════════════════════════════════════════════════');
  console.log(' TaskFix yuklama testi — ' + SUPABASE_URL);
  console.log(' Bosqichlar: ' + CFG.stages.join(', ') + '  ·  kutish: ' + CFG.delay + 'ms  ·  timeout: ' + CFG.timeout + 'ms');
  console.log(' Rejim: ' + (CFG.anon ? 'ANON (RLS to\'sadi — faqat tarmoq/rate-limit o\'lchanadi)' : 'LOGIN qilingan foydalanuvchi'));
  console.log(' Workspace: ' + (CFG.ws || '(filtrsiz — HAMMA ws, prod ham! --ws tavsiya etiladi)'));
  console.log(' So\'rovlar: FAQAT GET (o\'qish). Hech narsa yozilmaydi.');
  console.log('════════════════════════════════════════════════════════════');

  if (!CFG.ws && !CFG.anon) {
    console.log('⚠️  --ws berilmadi: so\'rovlar butun bazadan o\'qiydi (prod ws lar ham).');
    console.log('   Prodga yuk tushmasligi uchun test workspace ID sini bering: --ws <uuid>');
  }
  if (CFG.dry) { console.log('\n--dry: hech narsa yuborilmadi. --yes bilan ishga tushiring.'); return; }
  if (!CFG.yes) {
    console.log('\n⛔ --yes berilmadi — to\'xtatildi (prodga tasodifan yuk tushmasligi uchun).');
    console.log('   Ishga tushirish: node stress_test.js --yes --ws <uuid> [--email ... --password ...]');
    process.exit(1);
  }

  let token = null;
  if (!CFG.anon) {
    if (!CFG.email || !CFG.password) {
      console.log('\n⛔ --email/--password (yoki TF_EMAIL/TF_PASSWORD) kerak, yoki --anon bilan ishga tushiring.');
      process.exit(1);
    }
    process.stdout.write('Login... ');
    try { token = await login(); console.log('✓'); }
    catch (e) { console.log('✗\n' + e.message); process.exit(1); }
  }

  // Bazaviy o'lchov — bitta so'rov, yuklamasiz (taqqoslash nuqtasi)
  const base = await once(queries(CFG.ws)[0], token);
  console.log('\nBazaviy (1 ta so\'rov, yuklamasiz): ' + r1(base.ms) + 'ms · HTTP ' + base.status + ' · ' + base.rows + ' qator');
  if (!base.ok) console.log('  ⚠ bazaviy so\'rov xato berdi: ' + (base.err || base.status));
  if (base.ok && base.rows === 0 && !CFG.anon) {
    console.log('  ⚠ 0 qator qaytdi — ws ID yoki RLS ruxsati noto\'g\'ri bo\'lishi mumkin.');
  }

  const out = [];
  for (const n of CFG.stages) {
    process.stdout.write('\n▶ ' + n + ' parallel so\'rov... ');
    const s = await stage(n, token, CFG.ws);
    out.push(s);
    console.log('tugadi ' + r1(s.wall) + 'ms');
    console.log('   ok=' + s.ok + ' err=' + s.err +
                ' | o\'rtacha=' + r1(s.avg) + 'ms p50=' + r1(s.p50) + ' p95=' + r1(s.p95) + ' max=' + r1(s.max) +
                ' | ' + r1(s.rps) + ' req/s');
    if (s.rate429) console.log('   ⚠ RATE LIMIT: ' + s.rate429 + ' ta 429 — bu "sekin" emas, "cheklangan"');
    if (s.err)     console.log('   ⚠ statuslar: ' + JSON.stringify(s.byStatus) + (s.sampleErr ? ' · namuna: ' + s.sampleErr : ''));

    if (s.errRate > ABORT_ERR_RATE) {
      console.log('\n⛔ Xato ulushi ' + Math.round(s.errRate * 100) + '% — qolgan bosqichlar BEKOR qilindi (prodni ayaymiz).');
      break;
    }
    if (n !== CFG.stages[CFG.stages.length - 1]) await sleep(CFG.delay);
  }

  // ── Markdown natija ───────────────────────────────────────────────────────
  console.log('\n\n══════ NATIJA (nusxalab bering) ══════\n');
  console.log('Rejim: ' + (CFG.anon ? 'anon (RLS to\'sadi)' : 'login qilingan') +
              ' · ws: ' + (CFG.ws || 'filtrsiz') + ' · bazaviy: ' + r1(base.ms) + 'ms\n');
  console.log('| N (parallel) | ok | xato | 429 | o\'rtacha ms | p50 | p95 | max | req/s | jami ms |');
  console.log('|---|---|---|---|---|---|---|---|---|---|');
  out.forEach(function (s) {
    console.log('| ' + s.n + ' | ' + s.ok + ' | ' + s.err + ' | ' + s.rate429 + ' | ' +
      r1(s.avg) + ' | ' + r1(s.p50) + ' | ' + r1(s.p95) + ' | ' + r1(s.max) + ' | ' +
      r1(s.rps) + ' | ' + r1(s.wall) + ' |');
  });

  console.log('\n**So\'rov turi bo\'yicha o\'rtacha (ms):**\n');
  console.log('| N | tasks | members | projects |');
  console.log('|---|---|---|---|');
  out.forEach(function (s) {
    console.log('| ' + s.n + ' | ' + r1(avg(s.perQ.tasks || [])) + ' | ' +
      r1(avg(s.perQ.members || [])) + ' | ' + r1(avg(s.perQ.projects || [])) + ' |');
  });

  // ── Avtomatik talqin ──────────────────────────────────────────────────────
  console.log('\n**Talqin:**\n');
  if (!out.length) { console.log('- bosqich bajarilmadi'); return; }
  const first = out[0], last = out[out.length - 1];
  const growth = first.avg ? (last.avg / first.avg) : 0;
  const nGrowth = first.n ? (last.n / first.n) : 0;
  console.log('- N ' + first.n + ' → ' + last.n + ' (' + r1(nGrowth) + '×) bo\'lganda o\'rtacha javob ' +
              r1(first.avg) + ' → ' + r1(last.avg) + 'ms (' + r1(growth) + '×)');
  if (growth < nGrowth * 0.4) {
    console.log('  → **yaxshi**: javob vaqti so\'rov sonidan sekinroq o\'sdi (parallellikni ko\'taryapti)');
  } else if (growth < nGrowth * 0.9) {
    console.log('  → **chiziqliga yaqin**: navbat hosil bo\'lyapti, lekin yiqilmayapti');
  } else {
    console.log('  → **⚠ to\'yingan**: N ortishi javobni deyarli shuncha marta sekinlashtirdi — bo\'g\'iz bor');
  }
  const anyLimit = out.some(function (s) { return s.rate429 > 0; });
  console.log(anyLimit
    ? '- ⚠ **RATE LIMIT bor** (429). Bu resurs yetishmasligi EMAS — Supabase plan cheklovi. "Sekin" deb hisoblanmasin.'
    : '- Rate limit (429) uchramadi.');
  const anyErr = out.some(function (s) { return s.err > 0 && !s.rate429; });
  if (anyErr) console.log('- ⚠ 429 dan boshqa xatolar ham bor — yuqoridagi statuslarga qarang.');
  console.log('- Bazaviy (yuklamasiz) ' + r1(base.ms) + 'ms — bundan pastga tushib bo\'lmaydi (tarmoq + RLS narxi).');
})().catch(function (e) {
  console.error('\n⛔ Kutilmagan xato:', e && e.message ? e.message : e);
  process.exit(1);
});
