# HISOBOT — HR modulini yakunlash (V2 → V3 → V4)

Sana: 2026-07-18. Ish: `BRIEF_HR_FINISH.md` / `BRIEF_2SOAT.md` dagi qolgan frontend vazifalari.

## Bajarilgan ishlar

### V1 — loadTasksFull xato yutishi ✅ (avval tugagan)
Kod tekshirildi — allaqachon tuzatilgan (`if (error) throw error`, izohlar bor). Qayta ish qilinmadi.

### V2 — Rasm ko'rsatish (signed URL) ✅
Muammo: `photo_url` (Google Drive havolasi) to'g'ridan ishlatilardi, import Storage'ga yozgan `photo_path` esa **umuman o'qilmasdi**.

Qo'shildi (`index.html`, `loadHrData` yonida):
- `prefetchPhotoUrls(rows)` — barcha `photo_path`larni **bitta** `createSignedUrls(paths, 3600)` chaqirig'i bilan oladi (126 alohida so'rov EMAS), keshga 59 daqiqaga yozadi.
- `getPhotoUrl(uid)` — yaroqli signed URL yoki `null`.
- `empAvatarUrl(uid, d, p)` — `signed URL → photo_url (Drive) → avatar_url → initsiallar` tartibida fallback.
- `refreshPhotoUrl(uid)` — bitta hodimni qayta yuklash (kelajakda rasm yuklash uchun tayyor).
- `loadHrData` HR ma'lumotini yuklaganda avtomatik prefetch qiladi (xato bo'lsa jimgina initsiallarga tushadi).
- Ulangan joylar: **Jamoa jadvali** avatari + **hodim detali** katta avatari.

Cheklov: kengroq avatar rollout (vazifa kartalari, kanban, org chart — brief V5b) bu ishga KIRMADI. Ular hozircha eski holatda (photo_url/initsiallar).

### V3 — Ish jadvali: 3 rejim ✅
Yangi fayl: **`43_schedule_monthly.sql`** (foydalanuvchi ishga tushiradi):
- `employee_details.monthly_off_count INT` (CHECK 0..31)
- `employee_details.monthly_off_position TEXT` (CHECK 'start' | 'end') — **TEXT + CHECK, ENUM emas**
- Idempotent + tekshiruv (`RAISE EXCEPTION` jimgina o'tmasin).

`index.html` (renderEmployee / empDtlSave / yangi funksiyalar):
- Jadval turi radiosiga `onchange="schOnModeChange()"` — rejim almashganda mos maydon bloklari ko'rinadi.
- **Haftalik** — mavjud hafta kunlari (dam) checkboxlari (`schWeeklyBox`).
- **Oylik** — `schMonthlyCount` (hajmi) + `schPosStart/schPosEnd` radio (Boshlash/Tugash). Kalendar yo'q.
- **Moslashuvchan** — mustaqil HR kalendari (2 oy yonma-yon, oldinga/orqaga), kun bosilsa dam kuni **yashil**. `employee_schedule_days`dan `off` kunlari yuklanadi.
- Ish vaqti boshlanishi/tugashi — hamma rejimda.
- Saqlash (`empDtlSave`): weekend faqat weekly'da; monthly ustunlar monthly'da. **43 hali ishga tushmagan bo'lsa** — `monthly_off` ustunsiz qayta urinadi + aniq toast ("43-migratsiya kerak"), jimgina yutmaydi.
- **"Kunlarni saqlash"** tugmasi (`schSaveDays`): `uiConfirm(danger)` bilan tasdiq → naqshdan `employee_schedule_days` ni **chunk (800)** bilan `ON CONFLICT (workspace_id,user_id,date) DO UPDATE`:
  - weekly → shartnoma davri (yoki joriy oy → +1 yil) bo'yicha `weekend_days`.
  - monthly → har oyning boshi/oxiridan N kun.
  - flexible → kalendardan (deselect qilingan kunlar `on`ga qaytadi).
  - `day_type` faqat `'on'`/`'off'` (41-migratsiya CHECK'iga mos, tasdiqlangan).
  - Oraliq 800 kundan oshsa — bloklaydi (xato naqsh 40k qatorni buzmasin).

### V4 — Hash-routing (orqaga tugmasi + F5) ✅
Muammo: hodim detalida brauzer "orqaga" → saytdan chiqib ketardi; F5 → bosh sahifa.

`index.html`:
- `rtSetHash(h)` — `history.pushState` (idempotent; pushState hashchange/popstate qo'zg'atmaydi → loop yo'q).
- `rtRouteFromHash()` — `location.hash`ni pars qiladi va mos funksiyani chaqiradi.
- Marshrutlar: `#/dashboard #/tasks #/planner #/team #/team/employee/{uid} #/projects/{id} #/department/{id} #/stats #/logs #/settings ...`
- `goPage(p)` oxirida oddiy sahifa hashini yozadi; `openEmployee`/`openProject`/`goDept` parametrli hash yozadi.
- `window.addEventListener('popstate', ...)` — orqaga/oldinga → sahifani tiklaydi (faqat `#/` app hashlari; auth recovery/invite hashlariga tegmaydi).
- `bootstrap()` oxirida F5'da hashdan tiklash (taklif-vazifa oqimi ustuvor).
- Modallar (task detali, uiForm, *Bd) hashga **yozilmaydi**.
- `managerOnlyPages` himoyasi saqlangan — member `#/logs` ochsa dashboardga tushadi.

## Foydalanuvchi qaytgach BAJARADIGAN qadamlar (tartib bilan)

1. **`43_schedule_monthly.sql` ishga tushir** (Supabase SQL editor). Busiz Oylik jadval saqlanmaydi (aniq toast chiqadi).
2. **Hard refresh** (Ctrl+Shift+R).
3. Brauzer testlari (pastda).

> Eslatma: `admin-import-staff/index.ts`, `45_staff_phone_lookup.sql`, `cleanup_duplicate_staff.sql` — bu sessiyadan **oldingi** ishlardan (import EF v3, dublikat tozalash). Men ularga tegmadim; commit'ga kiritmadim. Kerak bo'lsa alohida ko'rib chiqing (EF deploy, cleanup dry_run).

## Brauzer testi (qo'lda tekshirish kerak)

Bu ilova Supabase-auth talab qiladi — men brauzerda ishga tushira olmadim, faqat **sintaksis validatsiya** (node-vm, har o'zgarishdan keyin OK) va mantiq tekshiruvi qildim.

- **V2:** Jamoa jadvali + hodim detalida 80 rasm ko'rinsin; rasmsiz 46 hodim initsiallar bilan; Network'da **bitta** `createSignedUrls`.
- **V3:** Rejim almashganda mos maydonlar; Saqlash → employee_details; 43 yo'q bo'lsa Oylik'da aniq toast; "Kunlarni saqlash" → uiConfirm(danger) → employee_schedule_days yangilansin (dam kunlari sonini tekshiring).
- **V4:** Hodim detali → orqaga → Jamoa (saytdan chiqmasin); hodim detalida F5 → o'sha hodim; loyihada F5 → o'sha loyiha; member `#/logs` → dashboard.

## Rejaga kirmagan (kelajak)
V5b (kengroq avatar), V5c (signup profil), V5d (email taklif), V5e (rasm yuklash tugmasi), V6 (uy tozalash), cleanup_duplicate_staff.
