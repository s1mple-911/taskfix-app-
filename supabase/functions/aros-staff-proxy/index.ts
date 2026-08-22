// ============================================================
// aros-staff-proxy — v1-2026-08-22
//
// Aros'ning tashqi HR tizimidan (api.staff.aros.uz) hodim ro'yxatini,
// hodim kartochkasini va ish jadvalini FAQAT O'QIB beradigan proxy.
//
// 🔴 NEGA EF: manba API kaliti (`Authorization: Api-Key <token>`) mijozga
//    TUSHMASLIGI shart — index.html GitHub Pages'da ochiq turadi, ya'ni
//    kalit u yerga yozilsa uni hamma ko'radi. Kalit EF secret'ida
//    (`AROS_STAFF_TOKEN`) yashaydi va faqat shu funksiya ishlatadi.
//    Qo'shimcha sabab: manbani brauzerdan to'g'ridan-to'g'ri chaqirib
//    bo'lmaydi (CORS).
//
// 🔴 BU FUNKSIYA DB GA HECH NARSA YOZMAYDI. U faqat o'qish proxysi:
//    yagona DB murojaati — chaqiruvchining rolini bilish uchun
//    `workspace_members` dan SELECT. Import yozuvlari (auth user,
//    workspace_members, employee_details, staff_import_map, rasm…) mavjud
//    `admin-import-staff` EF'ida va mijozda qoladi. Bu yerga import
//    mantiqini QO'SHMANG — aks holda ikki joyda ikki xil import bo'ladi.
//
// KONTRAKT (mijoz aynan shunga tayanadi) — POST, JSON body:
//   { action:'list',          workspace_id, search?, page?, page_size? }
//        → { ok:true, count, page, page_size, has_next, results:[…] }
//   { action:'detail',        workspace_id, source_id }
//        → { ok:true, employee:{…} }
//   { action:'schedule',      workspace_id, source_id, date_from?, date_to? }
//        → { ok:true, schedule:{…} }
//   { action:'schedule_bulk', workspace_id, source_ids:[…≤25], date_from?, date_to? }
//        → { ok:true, schedules:{ "<id>":{…} }, failed:[{source_id, error}] }
//        ⚠️ `schedules` KALITI = mijoz YUBORGAN xom id (normallashgani emas) —
//           mijoz javobni o'zi yuborgan qiymat bo'yicha qidiradi.
//        ⚠️ Umumiy muddat 60s: ulgurmagan id'lar `failed` ga 'upstream_timeout'
//           bilan tushadi, olingan jadvallar SAQLANADI (qisman natija).
//   Xato: { ok:false, error:'<kod>', message:"<o'zbekcha>", detail, v } + mos HTTP status
//
// MANBA API (jonli tekshirilgan, 2026-08-22):
//   Auth  : `Authorization: Api-Key <token>`  ⚠️ Token/Bearer/Basic — 401 beradi
//           (server WWW-Authenticate: Api-Key qaytaradi)
//   Base  : https://api.staff.aros.uz/external/v1/employment
//   GET /employees/?search=&page=&page_size=   → {next, previous, count, page_size, results:[…]}
//        ⚠️ page_size serverda 100 ga cheklangan (200 so'ralsa ham 100 keladi), jami ~135 hodim
//   GET /employees/{id}/                       → + branches:[{id,name,address,is_primary}] (ko'plik;
//        ro'yxatda esa bitta `branch` keladi — shuning uchun detail alohida kerak)
//   GET /employees/{id}/schedule/?date_from=&date_to=
//                                              → {employee_id, date_from, date_to, days:[…]}
//        (manbada ma'lumot ~2026-09-01 gacha)
//
// 🔴 QOROVULLAR (o'zgartirishdan oldin o'qing):
//   1) Verify JWT — ON (admin-import-staff naqshi). Ustiga kod chaqiruvchi
//      shu workspace'da owner/admin ekanini ALOHIDA tekshiradi: service_role
//      RLS'ni chetlab o'tadi, ya'ni bu tekshiruvsiz istalgan foydalanuvchi
//      Aros HR ma'lumotini o'qib olardi.
//   2) FAQAT AROS: `workspace_id` `AROS_WORKSPACE_ID` ga TENG bo'lishi shart.
//      Boshqa workspace — rad (Asilbek qarori: bu integratsiya faqat Aros uchun).
//   3) OCHIQ PROXY EMAS: mijozdan URL/host/yo'l QABUL QILINMAYDI. Faqat 4 ta
//      `action` va qattiq yozilgan yo'llar. `source_id` — faqat butun son,
//      sanalar — YYYY-MM-DD (haqiqiy sana), `search` — uzunligi cheklangan,
//      `page_size` ≤ 100. So'rov URL'i qurilgach origin/prefiks BASE bilan
//      solishtiriladi (boshqa hostga yoki yo'ldan tashqariga chiqish yo'q).
//   4) SIR: token javobga, `detail` ga, xato matniga va logga HECH QACHON
//      tushmaydi. Asosiy kafolat — upstream javob TANASI xato yo'lida
//      umuman qaytarilmaydi (faqat status kodi): manba xatoda so'rov
//      sarlavhalarini aks-sado qilsa ham kalit sizib chiqmaydi.
//      `redact()` — TOR qatlam: faqat `unexpected` xatosining `detail` iga
//      va `console.error` ga qo'llanadi (muvaffaqiyatli javob tanasiga
//      EMAS — u manbadan kelgan sof HR ma'lumoti va yo'llar qattiq
//      yozilgani uchun unga token qaytib kela olmaydi).
//
// ENV:
//   AROS_STAFF_TOKEN   — MAJBURIY. ArosStaff API kaliti (faqat Supabase secret'da).
//   AROS_STAFF_BASE    — ixtiyoriy. Default: https://api.staff.aros.uz/external/v1/employment
//   AROS_WORKSPACE_ID  — ixtiyoriy. Default: 12b22aa6-dc45-4197-ae84-2e32e3cd56c2 (Aros)
//   SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY — Supabase o'zi beradi.
//
// DEPLOY: EF_AROS_STAFF_DEPLOY.txt
// ============================================================

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

const VERSION = 'v1-2026-08-22';

const CORS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const DEFAULT_BASE = 'https://api.staff.aros.uz/external/v1/employment';
const DEFAULT_AROS_WS = '12b22aa6-dc45-4197-ae84-2e32e3cd56c2';

// Osilib qolgan upstream butun chaqiruvni yemasin (EF limiti 150s).
const UPSTREAM_TIMEOUT_MS = 20_000;
// Javob hajmi cheklovi — manba kutilmaganda katta javob bersa xotira yemasin.
const MAX_UPSTREAM_BYTES = 4 * 1024 * 1024;

const MAX_PAGE_SIZE = 100;      // manba o'zi ham 100 da kesadi
const DEFAULT_PAGE_SIZE = 100;
const MAX_PAGE = 1000;
const MAX_SEARCH_LEN = 64;

// Bir chaqiruvda nechta jadval — baxtli yo'lda 25 × ~0.5s ≈ 13s.
const MAX_BULK_IDS = 25;
// Manbani ko'mib tashlamaslik uchun bir vaqtda 6 ta so'rov.
const BULK_CONCURRENCY = 6;
// 🔴 schedule_bulk uchun UMUMIY muddat. Bo'laklar ketma-ket ketadi, ya'ni
// eng yomon holatda ceil(25/6)=5 bo'lak × 20s ≈ 105s bo'lardi — EF ning 150s
// limitiga urilib chaqiruv opaque 504 bilan o'lardi va 25 ta jadvalning
// HAMMASI yo'qolardi. Muddat tugagach qolgan id'lar SO'RALMAYDI, `failed` ga
// 'upstream_timeout' bilan tushadi — ya'ni qisman natija SAQLANADI.
const BULK_DEADLINE_MS = 60_000;

type ActionName = 'list' | 'detail' | 'schedule' | 'schedule_bulk';
const ACTIONS: ActionName[] = ['list', 'detail', 'schedule', 'schedule_bulk'];

// Upstream xato kodlari → mijozga ko'rinadigan matn + HTTP status.
// ⚠️ Matnlarda kalit ham, upstream javob tanasi ham YO'Q.
const UP_ERR: Record<string, { status: number; message: string }> = {
  upstream_auth: {
    status: 502,
    message: "ArosStaff kaliti noto'g'ri yoki muddati o'tgan — AROS_STAFF_TOKEN yangilanishi kerak",
  },
  not_found: {
    status: 404,
    message: "ArosStaff'da bunday hodim topilmadi",
  },
  upstream_down: {
    status: 502,
    message: "ArosStaff serveri hozir ishlamayapti — birozdan keyin urinib ko'ring",
  },
  upstream_busy: {
    status: 429,
    message: "ArosStaff so'rovlarni vaqtincha cheklab qo'ydi — birozdan keyin urinib ko'ring",
  },
  upstream_timeout: {
    status: 504,
    message: "ArosStaff 20 soniyada javob bermadi",
  },
  upstream_unreachable: {
    status: 502,
    message: "ArosStaff serveriga ulanib bo'lmadi (tarmoq)",
  },
  upstream_bad_status: {
    status: 502,
    message: "ArosStaff kutilmagan javob qaytardi",
  },
  upstream_bad_json: {
    status: 502,
    message: "ArosStaff javobini o'qib bo'lmadi (JSON emas)",
  },
  upstream_too_large: {
    status: 502,
    message: "ArosStaff javobi juda katta",
  },
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

// Mavjud EF'lardagi shakl + `message` (mijoz uni to'g'ridan-to'g'ri
// ko'rsatadi, shuning uchun DOIM o'zbekcha va texnik tafsilotsiz).
function fail(error: string, message: string, status = 400, detail?: string): Response {
  return json({ ok: false, error, message, detail: detail ?? null, v: VERSION }, status);
}

function failUp(code: string, detail?: string): Response {
  const m = UP_ERR[code] || UP_ERR.upstream_bad_status;
  return fail(code, m.message, m.status, detail);
}

function isUuid(s: unknown): boolean {
  return typeof s === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

// source_id — FAQAT butun son. Mijoz raqam ham, satr ham yuborishi mumkin;
// ikkalasi ham shu yerda bir xil qat'iy shaklga keltiriladi. Bu — URL yo'l
// bo'lagiga tushadigan yagona qiymat, shuning uchun regex qattiq.
function normId(v: unknown): string | null {
  if (typeof v === 'number') {
    return Number.isInteger(v) && v > 0 && v <= 999999999999 ? String(v) : null;
  }
  if (typeof v === 'string' && /^[0-9]{1,12}$/.test(v)) {
    const n = Number(v);
    return n > 0 ? String(n) : null;
  }
  return null;
}

// YYYY-MM-DD + HAQIQIY sana (2026-13-45 o'tmasin).
function isIsoDate(s: unknown): boolean {
  if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const d = new Date(s + 'T00:00:00Z');
  return !isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}

// Oxirgi qatlam: nima bo'lganda ham token matnga tushmasin.
function redact(s: string, token: string): string {
  let out = s;
  if (token) out = out.split(token).join('***');
  return out.replace(/Api-Key\s+\S+/gi, 'Api-Key ***');
}

// Javobni hajm cheklovi bilan o'qiymiz — `resp.text()` cheklovsiz yutardi.
async function readCapped(resp: Response, max: number): Promise<string> {
  const cl = Number(resp.headers.get('content-length') || '0');
  if (cl && cl > max) throw new Error('too_large');
  if (!resp.body) return await resp.text();

  const reader = resp.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (!value) continue;
    total += value.byteLength;
    if (total > max) {
      await reader.cancel().catch(() => {});
      throw new Error('too_large');
    }
    chunks.push(value);
  }
  const buf = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) { buf.set(c, off); off += c.byteLength; }
  return new TextDecoder().decode(buf);
}

type UpRes =
  | { ok: true; data: Record<string, unknown> }
  | { ok: false; code: string; detail?: string };

// 🔴 YAGONA tashqi chiqish nuqtasi. `path` — kodda QATTIQ yozilgan
// (mijozdan kelmaydi), `params` — allaqachon validatsiyadan o'tgan qiymatlar.
async function arosGet(
  base: string,
  token: string,
  path: string,
  params: Record<string, string>,
): Promise<UpRes> {
  let url: URL;
  let baseUrl: URL;
  try {
    baseUrl = new URL(base);
    url = new URL(base.replace(/\/+$/, '') + path);
  } catch (_) {
    return { ok: false, code: 'upstream_bad_status', detail: "AROS_STAFF_BASE noto'g'ri URL" };
  }
  // Ochiq proxy bo'lib qolmasligining oxirgi tekshiruvi: qurilgan URL
  // baribir BASE bilan bir xil origin va bir xil prefiksda bo'lsin.
  const basePath = baseUrl.pathname.replace(/\/+$/, '');
  if (url.origin !== baseUrl.origin || !url.pathname.startsWith(basePath)) {
    return { ok: false, code: 'upstream_bad_status', detail: 'URL BASE dan chiqib ketdi' };
  }
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);

  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), UPSTREAM_TIMEOUT_MS);
  let resp: Response;
  try {
    resp = await fetch(url.toString(), {
      method: 'GET',
      headers: {
        // ⚠️ AYNAN 'Api-Key' — Token/Bearer/Basic 401 beradi (jonli tekshirilgan).
        'Authorization': `Api-Key ${token}`,
        'Accept': 'application/json',
      },
      signal: ctl.signal,
    });
  } catch (e) {
    clearTimeout(timer);
    const aborted = (e as Error).name === 'AbortError' || /abort/i.test(String((e as Error).message || ''));
    return { ok: false, code: aborted ? 'upstream_timeout' : 'upstream_unreachable' };
  }

  try {
    // 🔴 Upstream javob TANASI mijozga HECH QACHON qaytarilmaydi — faqat
    // status kodi. Manba xato javobida so'rov sarlavhalarini aks-sado qilsa
    // ham kalit sizib chiqmaydi.
    if (resp.status === 401 || resp.status === 403) {
      await resp.body?.cancel().catch(() => {});
      return { ok: false, code: 'upstream_auth' };
    }
    if (resp.status === 404) {
      await resp.body?.cancel().catch(() => {});
      return { ok: false, code: 'not_found' };
    }
    if (resp.status === 429) {
      await resp.body?.cancel().catch(() => {});
      return { ok: false, code: 'upstream_busy' };
    }
    if (resp.status >= 500) {
      await resp.body?.cancel().catch(() => {});
      return { ok: false, code: 'upstream_down', detail: `status ${resp.status}` };
    }
    if (!resp.ok) {
      await resp.body?.cancel().catch(() => {});
      return { ok: false, code: 'upstream_bad_status', detail: `status ${resp.status}` };
    }

    let text: string;
    try {
      text = await readCapped(resp, MAX_UPSTREAM_BYTES);
    } catch (e) {
      if ((e as Error).message === 'too_large') return { ok: false, code: 'upstream_too_large' };
      // Ulanish tez bo'lib TANA sekin oqishi mumkin: bunda abort signali
      // yonadi va bu "tarmoq xatosi" emas, aynan TIMEOUT.
      if (ctl.signal.aborted) return { ok: false, code: 'upstream_timeout' };
      return { ok: false, code: 'upstream_unreachable' };
    }

    let parsed: unknown;
    try { parsed = JSON.parse(text); } catch (_) { return { ok: false, code: 'upstream_bad_json' }; }
    if (!parsed || typeof parsed !== 'object') return { ok: false, code: 'upstream_bad_json' };

    return { ok: true, data: parsed as Record<string, unknown> };
  } finally {
    clearTimeout(timer);
  }
}

// date_from / date_to — ikkala jadval amali uchun bir xil tekshiruv.
// Xato bo'lsa Response qaytadi (chaqiruvchi darrov return qiladi).
function readDateRange(body: Record<string, unknown>, params: Record<string, string>): Response | null {
  if (body.date_from != null && body.date_from !== '') {
    if (!isIsoDate(body.date_from)) return fail('bad_body', "date_from YYYY-MM-DD shaklida bo'lsin");
    params.date_from = String(body.date_from);
  }
  if (body.date_to != null && body.date_to !== '') {
    if (!isIsoDate(body.date_to)) return fail('bad_body', "date_to YYYY-MM-DD shaklida bo'lsin");
    params.date_to = String(body.date_to);
  }
  // ISO sana satri leksikografik solishtirishga mos — Date kerak emas.
  if (params.date_from && params.date_to && params.date_to < params.date_from) {
    return fail('bad_body', "date_to date_from dan oldin bo'lmasin");
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return fail('method_not_allowed', 'Faqat POST', 405);

  const TOKEN = Deno.env.get('AROS_STAFF_TOKEN') || '';

  try {
    // ---- 0) ENV ----
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
    const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') || '';
    const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    if (!SUPABASE_URL || !SERVICE_KEY) {
      return fail('config', 'SUPABASE_URL yoki SERVICE_ROLE_KEY sozlanmagan', 500);
    }
    // ANON_KEY bo'sh bo'lsa createClient throw qilib tushunarsiz 500 berardi —
    // sababni aniq aytamiz.
    if (!ANON_KEY) return fail('config', 'SUPABASE_ANON_KEY sozlanmagan', 500);
    if (!TOKEN) {
      return fail('config',
        "ArosStaff kaliti sozlanmagan — Supabase Secrets'ga AROS_STAFF_TOKEN qo'shilishi kerak", 500);
    }
    const BASE = (Deno.env.get('AROS_STAFF_BASE') || DEFAULT_BASE).replace(/\/+$/, '');
    const AROS_WS = (Deno.env.get('AROS_WORKSPACE_ID') || DEFAULT_AROS_WS).trim().toLowerCase();

    // ---- 1) Chaqiruvchi JWT (Verify JWT ON bo'lsa ham o'zimiz tekshiramiz) ----
    const authHeader = req.headers.get('Authorization') || '';
    if (!authHeader.startsWith('Bearer ')) {
      return fail('unauthorized', "Avtorizatsiya yo'q — qayta kiring", 401);
    }
    const asCaller: SupabaseClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userRes, error: uErr } = await asCaller.auth.getUser();
    if (uErr || !userRes?.user) return fail('unauthorized', 'Sessiya eskirgan — qayta kiring', 401);
    const callerId = userRes.user.id;

    // ---- 2) Body ----
    const body = await req.json().catch(() => null);
    if (!body) return fail('bad_body', "JSON o'qib bo'lmadi");

    // ⚠️ `String(x)` bir elementli MASSIVNI ham qabul qilardi (["list"] → "list").
    // Chetlab o'tish emas, lekin tip qat'iyligi buzilardi — satr bo'lmasa darrov 400.
    if (typeof body.action !== 'string') return fail('bad_action', "Noma'lum amal");
    const action = body.action as ActionName;
    if (!ACTIONS.includes(action)) {
      return fail('bad_action', "Noma'lum amal (kutilgan: " + ACTIONS.join(', ') + ')');
    }

    if (typeof body.workspace_id !== 'string') return fail('bad_body', 'workspace_id majburiy');
    const workspaceId = body.workspace_id.trim();
    if (!isUuid(workspaceId)) return fail('bad_body', 'workspace_id majburiy');

    // ---- 3) 🔴 FAQAT AROS ----
    // Bu integratsiya boshqa workspace'larga kerak emas. Cheklov eng boshda —
    // pastda hech qanday "istisno" shoxi bo'lmasin.
    if (workspaceId.toLowerCase() !== AROS_WS) {
      return fail('forbidden_workspace', 'ArosStaff integratsiyasi faqat Aros workspace uchun', 403);
    }

    // ---- 4) Ruxsat: chaqiruvchi shu workspace owner/admin'imi ----
    // service_role RLS'ni chetlab o'tadi — bu tekshiruv MAJBURIY, aks holda
    // istalgan a'zo Aros HR ma'lumotini o'qib olardi.
    const admin: SupabaseClient = createClient(SUPABASE_URL, SERVICE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: mem, error: mErr } = await admin
      .from('workspace_members').select('role')
      .eq('workspace_id', workspaceId).eq('user_id', callerId).maybeSingle();
    if (mErr) return fail('db', "Ruxsatni tekshirib bo'lmadi", 500, mErr.message);
    if (!mem || (mem.role !== 'owner' && mem.role !== 'admin')) {
      return fail('forbidden', 'Faqat workspace owner yoki admin', 403);
    }

    // ---- 5) Amallar: qat'iy validatsiya → qattiq yozilgan yo'l → upstream ----

    if (action === 'list') {
      const search = typeof body.search === 'string' ? body.search.trim() : '';
      if (search.length > MAX_SEARCH_LEN) {
        return fail('bad_body', `Qidiruv matni juda uzun (${MAX_SEARCH_LEN} belgigacha)`);
      }
      let page = Number(body.page ?? 1);
      if (!Number.isInteger(page) || page < 1) page = 1;
      if (page > MAX_PAGE) return fail('bad_body', `page juda katta (${MAX_PAGE} gacha)`);

      let pageSize = Number(body.page_size ?? DEFAULT_PAGE_SIZE);
      if (!Number.isInteger(pageSize) || pageSize < 1) pageSize = DEFAULT_PAGE_SIZE;
      // Manba o'zi ham 100 da kesadi — mijoz 200 so'raganda 100 kelgani uchun
      // sahifalash "yo'qolgan"dek ko'rinardi. Shuning uchun shu yerda cheklaymiz.
      if (pageSize > MAX_PAGE_SIZE) pageSize = MAX_PAGE_SIZE;

      const params: Record<string, string> = { page: String(page), page_size: String(pageSize) };
      if (search) params.search = search;   // URLSearchParams o'zi kodlaydi

      const r = await arosGet(BASE, TOKEN, '/employees/', params);
      if (!r.ok) return failUp(r.code, r.detail);

      const d = r.data;
      const results = Array.isArray(d.results) ? d.results : [];
      return json({
        ok: true, v: VERSION,
        count: typeof d.count === 'number' ? d.count : results.length,
        page,
        page_size: typeof d.page_size === 'number' ? d.page_size : pageSize,
        has_next: !!d.next,
        results,
      });
    }

    if (action === 'detail') {
      const sid = normId(body.source_id);
      if (!sid) return fail('bad_body', "source_id butun son bo'lishi kerak");

      const r = await arosGet(BASE, TOKEN, `/employees/${sid}/`, {});
      if (!r.ok) return failUp(r.code, r.detail);

      return json({ ok: true, v: VERSION, employee: r.data });
    }

    if (action === 'schedule') {
      const sid = normId(body.source_id);
      if (!sid) return fail('bad_body', "source_id butun son bo'lishi kerak");

      const params: Record<string, string> = {};
      const dErr = readDateRange(body, params);
      if (dErr) return dErr;

      const r = await arosGet(BASE, TOKEN, `/employees/${sid}/schedule/`, params);
      if (!r.ok) return failUp(r.code, r.detail);

      return json({ ok: true, v: VERSION, schedule: r.data });
    }

    // ---- action === 'schedule_bulk' ----
    // Nega bor: 130+ hodim uchun bittalab chaqirish 130 round-trip degani.
    // Bu yerda serverda parallel bajariladi, mijoz bitta javob oladi.
    {
      const raw = Array.isArray(body.source_ids) ? body.source_ids : null;
      if (!raw || !raw.length) return fail('bad_body', "source_ids bo'sh");
      if (raw.length > MAX_BULK_IDS) {
        return fail('too_many_ids',
          `Bir chaqiruvda ${MAX_BULK_IDS} tadan ko'p bo'lmasin (keldi: ${raw.length})`,
          400, "Mijoz tomonda bo'laklarga bo'ling");
      }

      const params: Record<string, string> = {};
      const dErr = readDateRange(body, params);
      if (dErr) return dErr;

      const schedules: Record<string, unknown> = {};
      const failed: { source_id: string; error: string }[] = [];

      // Dublikat id bir marta so'raladi; noto'g'ri id darrov `failed` ga
      // tushadi (jimgina tashlab ketilmaydi).
      // 🔴 KALIT — mijoz YUBORGAN xom id (`key`), normallashgani emas: mijoz
      // javobni o'zi yuborgan qiymat bo'yicha qidiradi ("007" → "007", "7" emas).
      // `sid` faqat URL yo'li uchun ishlatiladi.
      // ⚠️ Xom qiymat 64 belgigacha KESILADI — aks holda mijoz yuborgan katta
      // satr javobda aks-sado bo'lardi (QA: 200 KB javob).
      const ids: { sid: string; key: string }[] = [];
      for (const v of raw) {
        const key = String(v).slice(0, 64);
        const sid = normId(v);
        if (!sid) { failed.push({ source_id: key, error: 'bad_id' }); continue; }
        if (!ids.some((x) => x.sid === sid)) ids.push({ sid, key });
      }

      // 🔴 UMUMIY MUDDAT: bo'laklar ketma-ket ketgani uchun eng yomon holatda
      // 5 × 20s ≈ 105s bo'lib EF limitiga urilardi va BUTUN javob (25 ta jadval)
      // yo'qolardi. Endi muddat tugasa qolganlari umuman so'ralmaydi.
      const deadline = Date.now() + BULK_DEADLINE_MS;

      // Bo'laklab parallel — manbaga bir vaqtda 6 tadan ko'p so'rov ketmasin.
      for (let i = 0; i < ids.length; i += BULK_CONCURRENCY) {
        const chunk = ids.slice(i, i + BULK_CONCURRENCY);
        if (Date.now() >= deadline) {
          // Qolganlari FETCH QILINMAYDI — sabab ochiq ko'rsatiladi, allaqachon
          // olingan jadvallar esa saqlanadi (jimgina bo'sh javob emas).
          for (const it of chunk) failed.push({ source_id: it.key, error: 'upstream_timeout' });
          continue;
        }
        const res = await Promise.all(chunk.map(async (it) => {
          const r = await arosGet(BASE, TOKEN, `/employees/${it.sid}/schedule/`, params);
          return { it, r };
        }));
        for (const { it, r } of res) {
          // 🔴 Bitta id yiqilsa BUTUN chaqiruv yiqilmaydi — qolganlari qaytadi,
          // yiqilgani `failed` da sabab kodi bilan ko'rinadi.
          if (r.ok) schedules[it.key] = r.data;
          else failed.push({ source_id: it.key, error: r.code });
        }
      }

      return json({ ok: true, v: VERSION, schedules, failed });
    }

  } catch (e) {
    // 🔴 Log MAJBURIY `redact` dan o'tadi — Edge Function Logs'ga token
    // tushmasin. Deploy hujjati `unexpected` da aynan shu logga yo'naltiradi,
    // shuning uchun bu yagona `console.*` chaqiruvi ATAYLAB bor.
    const msg = redact((e as Error).message || String(e), TOKEN);
    console.error('aros-staff-proxy unexpected:', msg);
    return fail('unexpected', 'Kutilmagan xato', 500, msg);
  }
});
