# BRIEF — Namoz vaqtlari (Planner) · 2026-08-08

Prefiks: **`nmz*`** (funksiya, ID, CSS). Eski planner (`pln*`) mantig'iga
TEGILMAYDI — namoz bloklari faqat **chizish** qatlami, `pointer-events:none`,
localStorage'dagi `planner_*` jadvaliga yozilmaydi.

---

## CORS tekshiruvi — natija (2026-08-08)

| Manba | Holat | CORS |
|---|---|---|
| `islomapi.uz` | **502 Bad Gateway** (barcha endpoint, http va https, 3 urinish) | tekshirib bo'lmadi (server o'lik) |
| `namoz-vaqtlari.more-info.uz` | ulanmadi (DNS/502) | — |
| `api.aladhan.com` | **200 OK**, oylik kalendar bitta so'rovda | `access-control-allow-origin: *` ✅ |

**Xulosa: n8n proxy HOZIR KERAK EMAS.** Ilova ikki manbali:

1. **islomapi.uz** — birinchi (O'zbekiston musulmonlari idorasi vaqtlari, hanafiy).
   Hozir 502 → mijoz xatoni ushlaydi va zaxiraga o'tadi. Server tuzalganda
   o'z-o'zidan asosiy manba bo'lib qaytadi (kod o'zgarmaydi).
2. **api.aladhan.com** — zaxira: `calendar?latitude&longitude&method=3&school=1`
   (MWL burchaklari + **hanafiy asr**). CORS ochiq, oylik ma'lumot bitta so'rovda.

⚠️ Ikki manba vaqti 1–3 daqiqa farq qilishi mumkin, shuning uchun UI **manbani
ochiq yozadi** ("Manba: islomapi.uz" / "Manba: aladhan.com — zaxira").
Jimgina boshqa manbaga o'tib, foydalanuvchi buni bilmay qolishi mumkin emas.

**n8n kerak bo'ladigan yagona holat**: islomapi tuzalib, lekin `Access-Control-
Allow-Origin` bermasa. U holda `nmzFetchIslom()` ichidagi URL n8n webhook'iga
almashtiriladi (bitta qator) — qolgan kod o'zgarmaydi.

---

## Qadamlar (har biri alohida commit)

### 1. DB — `TASKFIX_NAMOZ.sql` (additive, idempotent)
- `profiles.namoz_enabled boolean NOT NULL DEFAULT false` — "Musulmon" toggle'i
  (har foydalanuvchi uchun shaxsiy, workspace'ga bog'liq emas).
- `profiles.namoz_region text` + **CHECK** (14 qiymat: 12 viloyat + Qoraqalpog'iston
  + Toshkent shahri). ENUM emas (3-qoida).
- `public.namoz_times` — kunlik kesh: PK `(region, date)`, 5 vaqt + `sunrise`
  (chizilmaydi, faqat ma'lumot), `source`, `fetched_at`. Har vaqt uchun
  **format CHECK** (`^([01][0-9]|2[0-3]):[0-5][0-9]$`).
- RLS: o'qish — har `authenticated` (vaqtlar ochiq ma'lumot); yozish/yangilash —
  har `authenticated` (kesh birinchi ko'rgan odam to'ldiradi); **o'chirish yopiq**.
  ⚠️ Bu shuni anglatadiki, yomon niyatli a'zo keshga noto'g'ri vaqt yoza oladi.
  Shuning uchun **mijoz keshdan o'qiganini ham tekshiradi** (`nmzValidTimes`:
  format + o'sish tartibi + mantiqiy oyna); tekshiruvdan o'tmasa kesh
  e'tiborsiz qoldiriladi va API'dan qayta olinadi.

### 2. Toggle + viloyat tanlash
- Planner sarlavhasida `☾ Muslim` toggle (`nmzToggle`).
- Birinchi yoqilganda: `navigator.geolocation` (bir marta) → eng yaqin viloyat
  **taxmin** qilinadi (haversine) → foydalanuvchi tasdiqlaydi yoki o'zgartiradi
  (`uiForm` + **`search`** maydoni — 7-qoida: har tanlash qidiruvli).
- Ruxsat berilmasa/xato bo'lsa — o'sha oyna, faqat taxminsiz (Toshkent tanlangan).
- Saqlanadi (`profiles`), keyin **boshqa so'ralmaydi**; viloyatni keyin
  o'zgartirish — o'sha paneldagi "Viloyat" tugmasi.

### 3. API qatlami + kesh
- `nmzEnsureMonth(y, m)`: 1) xotira → 2) `namoz_times` (DB) → 3) API (oylik,
  bitta so'rov) → DB'ga upsert.
- Provayder tartibi: islomapi → aladhan. Ikkalasi ham yiqilsa: bloklar
  chizilmaydi, panel sababni **ochiq yozadi** (jimgina bo'sh qolmaydi).
- Kesh yozuvi best-effort: yozib bo'lmasa (RLS/tarmoq) `console.error` +
  vaqtlar baribir ko'rsatiladi (foydalanuvchi kutayotgan amal — vaqt, kesh emas).

### 4. Planner bloklari + jonli panel
- Har kunga **5 blok** (bomdod/peshin/asr/shom/xufton — **quyosh chiqishi
  NAMOZ EMAS, blok qilinmaydi**), har biri **30 daqiqa**: 12:07 → 12:07–12:37.
- Blok `.nmz-blk` — vazifa bloklaridan ajralib turadi (yashil, ingichka chap
  urg'u, pastel fon), `pointer-events:none` → planner'ning surish/yaratish
  mexanikasi **buzilmaydi**.
- ⚠️ Planner setkasi `PLN_H_START=7` dan boshlanadi: bomdod ko'pincha undan
  oldin (03:47). Bunday vaqt **kesilib yo'qolmaydi** — panelda ko'rsatiladi va
  blok setkaning eng tepasiga "· erta" belgisi bilan qo'yiladi.
- Tepada jonli panel: bugungi 5 vaqt, joriy namoz ajratilgan, keyingisiga
  **countdown** (`nmzTick`, 1s). ⚠️ Interval bitta (`_nmzTick`), planner
  ko'rinmasa to'xtaydi (sizib chiqmasin).

---

## Eski planner buzilmasligi uchun

- Namoz bloklari `plnGetSchedule()` ga **yozilmaydi** (localStorage o'zgarmaydi).
- `renderPlanner()` ichida faqat qo'shimcha HTML — mavjud blok/drag/resize
  hisob-kitobi (`plnYToMin`, `plnDayMouseDown`, `plnMoveMove`) tegilmagan.
- `pointer-events:none` — namoz bloki ustidan ham vazifa yaratish/sudrash ishlaydi.
- Toggle o'chiq bo'lsa (`namoz_enabled=false`) — **hech qanday** namoz kodi
  ishlamaydi: so'rov ham, blok ham, interval ham yo'q.
- SQL ishga tushmagan bo'lsa (`_nmzMissing`) — toggle "sozlanmagan" deb aytadi,
  planner avvalgidek ishlayveradi.


---

## Tuzatishlar · 2026-08-09

1. **"Bajarilganlarni yashirish" — kalendar ko'rinishidan olindi.** Planner'ning
   "Mening jadvalim" (setka) tabida bu tugma ma'nosiz edi (u yerda vazifa
   ro'yxati emas, vaqt bloklari). Endi `plnSetTab` uni faqat setka tabida
   yashiradi; qolgan tablar va boshqa sahifalar (jadval/list) o'zgarmadi,
   `hideCompleted` holatiga ham tegilmadi.

2. **Blok = namoz vaqti + 10 daqiqa, 25 daqiqa davom etadi.**
   `NMZ_LAG = 10`, `NMZ_DUR = 25` (avval: vaqtning o'zidan 30 daqiqa).
   Peshin 12:07 → blok **12:17–12:42**. Blokda blok boshlanish vaqti yoziladi,
   tooltip'da esa "Peshin 12:07 · blok 12:17–12:42" — namoz vaqti ham yo'qolmaydi.
   "Erta" chipi ham blok boshlanishiga qarab hisoblanadi (bomdod 03:47+10).

3. **Toggle nomi "Musulmon" → "Muslim"** (faqat matn).

4. **Shahar aniqligi (viloyat markazi emas).** `profiles.namoz_lat/namoz_lon`
   qo'shildi: geolokatsiya bergan **aniq koordinata** saqlanadi va aynan u
   aladhan'ga yuboriladi → Qarshi'da Qarshi vaqti (Qashqadaryo markazi emas).
   - Viloyat **qoladi**: ko'rsatish uchun va islomapi (faqat viloyat bilan
     ishlaydi) uchun.
   - **Manba tartibi endi aniqlikka qarab**: koordinata bor → avval aladhan
     (shahar aniq), zaxira islomapi; koordinata yo'q → avval islomapi
     (rasmiy), zaxira aladhan.
   - **Kesh kaliti** `namoz_times` da `geo` ustuni bilan kengaydi
     (PK `(region, geo, date)`): `''` = viloyat markazi, `'38.85,65.80'` =
     aniq joylashuv (0.05° ≈ 5.5 km ≈ 12 soniya). Busiz Qarshi'dagi odamning
     vaqti butun Qashqadaryoga tarqalib ketardi.
   - Viloyat oynasida **"Aniq joylashuvim bo'yicha hisoblansin"** toggle'i:
     o'chirilsa koordinata tozalanadi va viloyat markazi ishlatiladi.
   - ⚠️ `TASKFIX_NAMOZ.sql` **qayta ishga tushirilishi kerak** (idempotent):
     yangi ustunlar + `geo` + birlamchi kalitni ko'chirish shu faylda.
