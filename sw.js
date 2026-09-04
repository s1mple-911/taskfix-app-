/* ============================================================================
   TaskFix — Service Worker (PWA)
   ----------------------------------------------------------------------------
   🔴 TAMOYIL: ESKI KOD HECH QACHON "YOPISHIB" QOLMASIN.
   index.html ~1.2 MB va tez-tez yangilanadi. Shuning uchun HTML uchun
   NETWORK-FIRST: har ochilishda tarmoqdan so'raladi, javob keshga yoziladi.
   Kesh faqat (a) internet yo'q yoki (b) tarmoq NAV_TIMEOUT dan sekin bo'lganda
   ishlatiladi — bunday holatda ham fon so'rovi davom etadi va kesh yangilanadi,
   sahifaga 'tf-updated' xabari yuboriladi.

   🔴 SUPABASE HECH QACHON KESHLANMAYDI. fetch handler faqat:
     - shu origin'dagi GET so'rovlar (HTML, ikonka, manifest)
     - ALLOW_HOSTS ro'yxatidagi CDN/shrift
   qolgan hamma narsa (supabase.co API/auth/storage, telegram, n8n...) SW ga
   umuman kirmaydi — brauzer o'zi hal qiladi.

   ⚠️ Deploy qilganda CACHE_VER ni oshiring (eski keshlar activate'da o'chadi).
   ============================================================================ */

const CACHE_VER  = 'v2';
const SHELL      = 'tf-shell-' + CACHE_VER;   // HTML (navigatsiya)
const ASSET      = 'tf-asset-' + CACHE_VER;   // ikonka, manifest, CDN, shrift
const KEEP       = [SHELL, ASSET];

// Tarmoq shu vaqtdan sekin bo'lsa — keshdan beramiz (mobil 3G uchun).
// Fon so'rovi bekor QILINMAYDI: keshni baribir yangilaydi.
const NAV_TIMEOUT = 4500;

// Faqat shu tashqi hostlar keshlanadi. supabase.co ATAYLAB yo'q.
const ALLOW_HOSTS = [
  'cdn.jsdelivr.net',
  'cdnjs.cloudflare.com',
  'fonts.googleapis.com',
  'fonts.gstatic.com',
];

const U = (p) => new URL(p, self.registration.scope).href;

// 🔴 `index.html` (1.2 MB) va `./` ATAYLAB oldindan keshlanMAYDI.
// SW landing.html dan ham ro'yxatga olinadi, ya'ni HAR marketing mehmoni uchun
// o'rnatish paytida ~2.5 MB yuklanardi — bu landing'ni alohida faylga ajratish
// sababiga (CLAUDE.md: "marketing mehmoni 1.2 MB ilovani yuklamasligi kerak")
// to'g'ridan-to'g'ri zid. Ilova qobig'i baribir network-first: birinchi haqiqiy
// ochilishda tabiiy keshlanadi va offline shundan keyin ishlaydi.
const PRECACHE_SHELL = [U('landing.html')];
const PRECACHE_ASSET = [
  U('manifest.json'),
  U('icons/icon-192.png'),
  U('icons/icon-512.png'),
  U('icons/icon-maskable-192.png'),
  U('icons/icon-maskable-512.png'),
  U('icons/apple-touch-icon.png'),
];

// addAll() bitta xatoda HAMMASINI yiqitadi — bittalab, xatoga chidamli qo'yamiz.
// `cache:'reload'` — brauzerning HTTP keshidan eski nusxa olinmasin.
async function precache(cacheName, urls) {
  const cache = await caches.open(cacheName);
  await Promise.all(urls.map(async (u) => {
    try {
      const res = await fetch(new Request(u, { cache: 'reload' }));
      if (res && res.ok) await cache.put(u, res);
    } catch (e) {
      // Bitta fayl tushmasa ham o'rnatish davom etadi (offline sifati pasayadi, xolos).
      console.error('[sw] precache tushdi:', u, e);
    }
  }));
}

self.addEventListener('install', (e) => {
  e.waitUntil((async () => {
    await precache(SHELL, PRECACHE_SHELL);
    await precache(ASSET, PRECACHE_ASSET);
    // Yangi SW darrov faollashsin — HTML network-first bo'lgani uchun
    // "yarim eski / yarim yangi" holat xavfi yo'q.
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.map((n) => {
      // Faqat O'ZIMIZNING eski keshlarimizni o'chiramiz (begonasiga tegmaymiz).
      if (n.indexOf('tf-') === 0 && KEEP.indexOf(n) === -1) return caches.delete(n);
      return Promise.resolve(false);
    }));
    await self.clients.claim();
  })());
});

self.addEventListener('message', (e) => {
  if (e.data && e.data.type === 'SKIP_WAITING') self.skipWaiting();
});

async function notifyUpdated() {
  const list = await self.clients.matchAll({ type: 'window' });
  list.forEach((c) => {
    try { c.postMessage({ type: 'tf-updated' }); }
    catch (e) { console.error('[sw] postMessage tushdi:', e); }
  });
}

function offlineHtml() {
  return new Response(
    '<!doctype html><html lang="uz"><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<title>Internet yo\'q</title><style>' +
    'html,body{margin:0;height:100%;font-family:system-ui,-apple-system,"Segoe UI",sans-serif;' +
    'background:#FAF7F0;color:#1C1F24;display:flex;align-items:center;justify-content:center;padding:24px}' +
    '.b{max-width:340px;text-align:center}h1{font-size:19px;margin:0 0 8px}' +
    'p{font-size:14px;line-height:1.55;color:#6B7280;margin:0 0 20px}' +
    'button{font:inherit;font-weight:600;font-size:14px;padding:12px 20px;border:none;border-radius:11px;' +
    'background:#0F1417;color:#FAF7F0;cursor:pointer;min-height:44px}' +
    '</style></head><body><div class="b">' +
    '<h1>Internet aloqasi yo\'q</h1>' +
    '<p>TaskFix ni ochish uchun internetga ulaning. Ulangach sahifa o\'zi yuklanadi.</p>' +
    '<button onclick="location.reload()">Qayta urinish</button>' +
    '</div></body></html>',
    { status: 200, headers: { 'Content-Type': 'text/html; charset=utf-8' } }
  );
}

// ---- Navigatsiya (HTML): network-first + timeout, keyin kesh ----------------
// 🔴 `e` (FetchEvent) ATAYLAB uzatiladi, faqat `req` emas: NAV_TIMEOUT o'tib
// keshdan javob berganimizda fon so'rovi HALI TUGAMAGAN bo'ladi. `waitUntil`
// bo'lmasa brauzer `respondWith` hal bo'lgach SW ni to'xtatishi mumkin va
// `cache.put` bajarilmay qoladi — ya'ni doimiy sekin tarmoqda (3G) kesh HECH
// QACHON yangilanmasdi. Aynan shu faylning sarlavhasida ogohlantirilgan
// "eski kod yopishib qoladi" holati.
function handleNavigate(e) {
  const req = e.request;
  const url = new URL(req.url);
  // Kesh kaliti — QUERY'SIZ. `?app=1`, `?perf=1`, UTM va h.k. har biri uchun
  // 1.2 MB nusxa saqlanib qolmasin.
  const key = url.origin + url.pathname;

  let served = false;
  const net = fetch(req).then(async (res) => {
    // ⚠️ redirected javob navigatsiya uchun keshlanmaydi (brauzer rad etadi).
    if (res && res.ok && !res.redirected && (res.type === 'basic' || res.type === 'default')) {
      try {
        const c = await caches.open(SHELL);
        await c.put(key, res.clone());
      } catch (err) { console.error('[sw] navigatsiya keshga yozilmadi:', key, err); }
      if (served) await notifyUpdated();   // kesh bilan xizmat qilgan edik — yangilandi
    }
    return res;
  });

  // ⚠️ `waitUntil` birinchi `await` DAN OLDIN, sinxron chaqiriladi — hodisa hali
  // "faol" bo'lishi shart.
  try { e.waitUntil(net.catch(() => null)); }
  catch (err) { console.error('[sw] waitUntil rad etildi:', err); }

  return (async () => {
    const cache = await caches.open(SHELL);
    const cached = await cache.match(key);

    if (cached) {
      // Kesh bor: tarmoqni NAV_TIMEOUT gacha kutamiz, sekin bo'lsa keshni beramiz.
      const winner = await Promise.race([
        net.catch(() => null),
        new Promise((r) => setTimeout(() => r(null), NAV_TIMEOUT)),
      ]);
      if (winner && winner.ok) return winner;
      served = true;
      return cached;
    }

    // Kesh yo'q: tarmoqni to'liq kutamiz.
    try {
      const res = await net;
      if (res) return res;
    } catch (err) { console.error('[sw] navigatsiya tarmoqdan olinmadi:', key, err); }

    // Oxirgi umid: boshqa keshlangan HTML (masalan index.html so'ralgan, lekin
    // faqat landing keshlangan — hech bo'lmasa oq ekran chiqmasin).
    const fb = (await cache.match(U('./'))) ||
               (await cache.match(U('index.html'))) ||
               (await cache.match(U('landing.html')));
    return fb || offlineHtml();
  })();
}

// ---- Statik (ikonka, manifest, CDN, shrift): stale-while-revalidate --------
// Bu yerda ham `waitUntil` shart: keshdan darrov javob berilganda fon
// yangilanishi tugamay SW to'xtab qolishi mumkin.
function handleAsset(e) {
  const req = e.request;
  const net = fetch(req).then(async (res) => {
    // opaque (no-cors CDN skripti) ham keshlanadi — status 0 bo'ladi, `ok` emas.
    if (res && (res.ok || res.type === 'opaque')) {
      try {
        const c = await caches.open(ASSET);
        await c.put(req, res.clone());
      } catch (err) { console.error('[sw] aktiv keshga yozilmadi:', req.url, err); }
    }
    return res;
  }).catch((err) => { console.error('[sw] aktiv tarmoqdan olinmadi:', req.url, err); return null; });

  try { e.waitUntil(net); }
  catch (err) { console.error('[sw] waitUntil rad etildi:', err); }

  return (async () => {
    const cache = await caches.open(ASSET);
    const cached = await cache.match(req);
    if (cached) return cached;          // darrov beramiz, fon yangilaydi
    const res = await net;
    return res || Response.error();
  })();
}

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;                       // POST/PATCH — tegmaymiz
  if (req.headers.has('range')) return;                   // media Range — tegmaymiz

  let url;
  try { url = new URL(req.url); }
  catch (err) { console.error('[sw] URL o\'qilmadi:', req.url, err); return; }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return;

  const sameOrigin = url.origin === self.location.origin;

  if (req.mode === 'navigate' || (sameOrigin && req.destination === 'document')) {
    e.respondWith(handleNavigate(e));
    return;
  }

  if (sameOrigin) {
    // Faqat statik fayllar. (Shu origin'da API yo'q — hammasi Supabase'da.)
    if (/\.(png|jpg|jpeg|svg|webp|ico|json|webmanifest|css|js|woff2?)$/i.test(url.pathname)) {
      e.respondWith(handleAsset(e));
    }
    return;
  }

  // Tashqi: FAQAT ro'yxatdagi hostlar. Supabase va boshqalar — tegilmaydi.
  if (ALLOW_HOSTS.indexOf(url.hostname) !== -1) {
    e.respondWith(handleAsset(e));
  }
});
