# HISOBOT — TaskFix HR + keyingi ishlar

Sana: 2026-07-18 (yangilangan 2026-07-20). Branch: `hr-finish-v2v3v4`.

Bosqichlar: (A) V1–V4, (B) BRIEF_KEYINGI Y1–Y8, (C) BRIEF_PROVODKA_KASSA P1–P3.

---

## C. Provodka — Harajat kassa sync (P1–P3) 🆕

Maqsad: TaskFix'da hodimga "Harajat kassa" tick → Provodka (alohida Supabase) da
xarajat kassa ochiladi (nomi = ism, subtitle = "Filial · Lavozim"); tick olinsa → yopiladi.

### P2 — EF `sync-provodka-kassa` ✅ (deploy kutilmoqda)
Yangi fayl: `supabase/functions/sync-provodka-kassa/index.ts`.
- Verify JWT ON; ichkarida chaqiruvchi owner/admin + target a'zoligini tekshiradi.
- TaskFix DB'dan yig'adi: ism (`profiles.full_name` yoki `employee_details` first+last), birinchi filial (`employee_branches`→`branches.name`), lavozim (`positions.name`). `subtitle = [filial, lavozim].join(' · ')`.
- Provodka RPC: `POST {PROVODKA_URL}/rest/v1/rpc/upsert_hodim_kassa` (apikey+Bearer = SERVICE_KEY), body `{p_taskfix_user_id, p_name, p_subtitle, p_active}`.
- Env yo'q → aniq xato; RPC `ok:false` → xato qaytaradi; javobda `v` (VERSION).

### P1 — Jamoa jadval checkbox ✅
- Jadvalga tor **💵** ustuni (Lavozimdan keyin). owner/admin — checkbox; member — statik (💵/—).
- `hkTableToggle` (optimistik): `employee_details.harajat_kassa` yoziladi → `hkSync` (EF). Xato bo'lsa **DB va checkbox qaytariladi** + toast (tick = Provodka'da kassa bor degani).
- Checkbox row-click'ni ochmaydi (stopPropagation).

### P3 — Saqlashda qayta sync ✅
- `empDtlSave`da: harajat_kassa hozir yoqilgan yoki holat o'zgargan bo'lsa → `hkSync` qayta chaqiriladi (ism/filial/lavozim o'zgarishi Provodka'ga o'tadi).

### Yagona handler
`hkSync(uid, active)` — Provodka EF chaqiruvi. Jadval toggle VA detal saqlash ikkalasi shu funksiyani ishlatadi (ikki xil mantiq yo'q). Prefiks `hk*`.

---

## A. V1–V4 (avval bajarilgan, merge + sinovdan o'tgan)
- **V1** loadTasksFull xato yutishi — tuzatilgan.
- **V2** Rasm signed URL (getPhotoUrl/empAvatarUrl/prefetchPhotoUrls).
- **V3** Ish jadvali 3 rejim + `43_schedule_monthly.sql` + "Kunlarni saqlash".
- **V4** Hash-routing (orqaga + F5).

---

## B. BRIEF_KEYINGI — Y1–Y8 (shu commit)

### Y1 — Qidiruv 3 bo'limga ajratish ✅
`buildCmdItems` qayta qurildi. Tartib: **👤 Hodimlar → 🏢 Filiallar → ▦ Bo'limlar → ✓ Vazifalar → 📄 Sahifalar → ⚡ Amallar**. Bo'sh bo'lim ko'rsatilmaydi.
- Hodim natijasida **avatar** (getPhotoUrl keshidan, bloklamaydi) + telefon · lavozim; bosilsa → **hodim detali** (hash-routing).
- **Filiallar qidiruvga qo'shildi** (`branchesCache`); bosilsa → Jamoa + filial filtri o'rnatiladi.
- Klaviatura navigatsiyasi (↑↓ Enter) saqlandi.

### Y2 — Harajat kassa checkbox ✅
- Hodim detali "Ish joyi" blokida **"Harajat kassa kerak"** checkbox (Radius yonida). Faqat owner/admin.
- **`47_harajat_kassa.sql`** (BOOLEAN, default false). Jamoa jadvalida ustun yo'q (faqat detalda).
- Saqlashda 47 yo'q bo'lsa — aniq toast ("Harajat kassa uchun 47-migratsiya"), jimgina yutmaydi.

### Y3 — Rasm hamma avatarda ✅
- `avatarHtml(name, size, url, uid)` — 4-param `uid` qo'shildi; url bo'sh bo'lsa `getPhotoUrl(uid)`dan oladi.
- **Bootstrap prefetch**: `loadCurrentContext` endi barcha `photo_path`larni oldindan signed URL'ga keshlaydi (org uchun) — avatarlar butun ilovada team sahifasini kutmasdan ko'rinadi.
- Ulangan joylar: loyiha a'zolari, hodim statistikasi, izohlar (Telegram'siz), pastki profil bloki (me), org chart site-user nodelar.
- **Cheklov**: vazifa kartalari/kanban `avatarHtml` **ishlatmaydi** (faqat ism matni) — ularга avatar qo'shish alohida markup talab qiladi, bu ishga kirmadi.

### Y6 — Rasm yuklash tugmasi ✅
- Hodim detalida **"📷 Rasm yuklash"** (owner/admin) → `phUploadPhoto`: canvas siqish (max 800px, JPEG 0.8) → `employee-photos/{ws}/{uid}.jpg` upsert → `photo_path` yozildi → kesh yangilandi → avatar darrov almashdi. Prefiks `ph*`.
- 46 o'lik-havolali hodim uchun yechim aynan shu.

### Y5 — "📧 Taklif yuborish" (ulanmaganlarga) ✅ (EF deploy kutilmoqda)
- Jamoa jadvalida sintetik email (`@staff.taskfix.org`) → **"⚠ Ulanmagan" badge** + **"📧 Taklif"** tugmasi (owner/admin).
- `teamInviteConnect`: uiForm haqiqiy email → EF `phase:'connect'` → `updateUserById` (email almashtirish) + `generateLink` (recovery). Havola mavjud modalda ko'rsatiladi (owner qo'lda yuboradi — bulk emas, Resend suppression xavfi yo'q).
- **EF o'zgardi**: `admin-import-staff` ga `connect` action qo'shildi, VERSION `v3.1-connect-email`. ⚠️ **Deploy kerak** — busiz tugma "EF yangilanishi kerak" toast beradi.

### Y4 — Signup'da to'liq profil ✅
- Signup formasiga: **Familiya**, **Telefon**, **Rasm (ixtiyoriy)** (faqat signup rejimida ko'rinadi).
- first_name/last_name/phone signup **metadata**ga yoziladi → birinchi kirishda (bootstrap) `profiles`ga ko'chiriladi (mavjudni bosmaydi).
- Login oqimi buzilmadi.
- **Cheklov**: rasm faqat **darhol session** bo'lsa yuklanadi (auto-confirm). Email tasdiqlash oqimida sahifa qayta yuklanadi va fayl yo'qoladi → rasm keyinga qoladi (hodim keyin detaldan yuklashi mumkin). `employee_details` (first/last) faqat metadata orqali — shaxsiy ws uchun alohida yozilmadi.

### Y7 — Uy tozalash ✅
1. `42→45` rename — **allaqachon bajarilgan** (42 yo'q, `45_staff_phone_lookup.sql` bor).
2. **Yolg'on izoh tuzatildi**: EF izohi "ism solishtirish HALI YOZILMAGAN" deyardi, lekin mijoz preflight (5b, `hrNameKey`) buni **allaqachon qiladi** — izoh haqiqatga moslandi.
3. **EF v3 xususiyatlari tasdiqlandi**: adopt-by-synthetic-email ✅, workspace_members SELECT+INSERT (=DO NOTHING, rolga tegmaydi) ✅, sintetik telefon E.164 (looksE164) ✅, VERSION yangilandi (v3.1). profiles — trigger orqali (EF yozmaydi).
4. **`cleanup_duplicate_staff.sql`**: avto-`dup_pairs` FAQAT telefon mos kelganda topadi → **Akobir topilmaydi** (haqiqiyda telefon yo'q, ism mos emas). **Qo'lda tasdiqlangan juftliklar (`manual` CTE)** qo'shildi: Akobir juftligi `(1bde234c…, e3d0a4fb…)`. `name_match=true, rivals=1` majburlanadi → merge (4-bosqich) uni oladi. dry_run rejimi saqlangan (`v_dry_run := true`).

### Y8 — CLAUDE.md ✅
- Repo ildizida **`CLAUDE.md`** yaratildi: loyiha, qat'iy qoidalar, DB holati, modullar, ochiq masalalar, validatsiya buyrug'i.

---

## Foydalanuvchi BAJARADIGAN qadamlar (tartib bilan)

1. **SQL ishga tushir** (Supabase SQL editor): `43_schedule_monthly.sql`, `45_staff_phone_lookup.sql` (agar hali bo'lmasa), `47_harajat_kassa.sql`.
2. **EF deploy**: `admin-import-staff` (v3.1 — connect action). Busiz "📧 Taklif" ishlamaydi.
3. **Push** + hard refresh (Ctrl+Shift+R).
4. **Dublikat tozalash** (ixtiyoriy, ehtiyotkorlik bilan): `cleanup_duplicate_staff.sql` — avval `<WS_ID>`ni Aros ws bilan almashtir, 1-bosqich SELECT'larни ko'z bilan tekshir, keyin `v_dry_run := false`.

### Provodka — Harajat kassa (C bosqich)
5. **Provodka loyihasida** `PROVODKA_HODIM_KASSA.sql` ishga tushir (1-blok ko'rish → 2-blok) — `accounts.taskfix_user_id/subtitle` + `upsert_hodim_kassa` RPC.
6. **TaskFix EF `sync-provodka-kassa` deploy** (Verify JWT ON) + **Secrets** qo'sh:
   - `PROVODKA_URL` = `https://<provodka-ref>.supabase.co`
   - `PROVODKA_SERVICE_KEY` = Provodka service_role kaliti
7. `47_harajat_kassa.sql` ishga tushgan bo'lishi shart (yuqorida 1-qadam).
8. **Sinov**: Jamoa'da bir hodimga 💵 tick → Provodka Kassa sahifasida "Ism (Filial · Lavozim)" paydo bo'lsin; tick olib tashlash → yo'qolsin.

## Brauzer testi (qo'lda)
Ilova Supabase-auth talab qiladi — men brauzerda ishga tushira olmadim; har o'zgarishdan keyin **node-vm validatsiya OK**.
- Y1: `⌘K` → "ali" → bo'limlar (Hodimlar avatarli, Filiallar) chiqsin; hodim → detal; filial → Jamoa filtri.
- Y2: detalda Harajat kassa belgilanib saqlansin (47 yo'q bo'lsa toast).
- Y3: task/loyiha/izoh/pastki profil/org chartda rasmlar (kesh to'lgach).
- Y6: detalda rasm yuklash → avatar almashsin.
- Y5: sintetik emailli qatorda ⚠ Ulanmagan + 📧 Taklif → email → havola modali (EF deploy'dan keyin).
- Y4: signup'da Familiya/Telefon/Rasm; kirgach profilda ism/telefon.

## Rejaga kirmagani
Vazifa kartalari/kanban avatarlari (yangi markup kerak); signup rasm email-confirm oqimida; employee_details signup'da.
