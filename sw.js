/* ============================================================================
   TaskFix — Service Worker KILL-SWITCH (maintenance / cutover, 2026-09-04)
   ----------------------------------------------------------------------------
   Eski taskfix.org muzlatildi. Bu SW eski ('tf-shell-*' / 'tf-asset-*')
   keshlarni o'chiradi, o'zini ro'yxatdan chiqaradi va ochiq oynalarni
   qayta yuklaydi — o'rnatilgan PWA ham faqat maintenance sahifasini ko'rsin.
   Hech narsani keshlamaydi, fetch'ga aralashmaydi.
   ============================================================================ */
self.addEventListener('install', function () { self.skipWaiting(); });

self.addEventListener('activate', function (e) {
  e.waitUntil((async function () {
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map(function (k) { return caches.delete(k); }));
    } catch (err) { console.error('[sw] kesh tozalanmadi:', err); }
    try { await self.registration.unregister(); } catch (err) { console.error('[sw] unregister:', err); }
    try {
      const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      clients.forEach(function (c) { try { c.navigate(c.url); } catch (_) {} });
    } catch (err) { console.error('[sw] clients:', err); }
  })());
});
