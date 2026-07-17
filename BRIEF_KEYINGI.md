# TaskFix — KEYINGI ISHLAR (V1–V4 tugadi, davomi)

V1–V4 merge bo'ldi, sinovdan o'tdi (rasm, jadval 3 rejim, routing ishlayapti). Endi qolganlari + 3 ta yangi vazifa.

Qoidalar o'zgarmagan: node-vm validatsiya har o'zgarishdan keyin; escapeHtml; toza Uzbek Latin; TEXT+CHECK; `aros_staff_export.json` commit qilinmaydi; yangi ID'larga prefiks.

**Migratsiya raqamlari**: 38–44, 46 ishga tushgan. 45 — rename kutilmoqda. Yangi raqam: **47**dan.

---

## Y1 (30 daq) — Qidiruv: 3 bo'limga ajratish + avatar 🆕

Hozir cmd-palette (global qidiruv) hamma natijani **bitta ro'yxatda** aralash beradi. Bo'limlarga ajrat:

```
🔍 "ali" yozilganda:
── 👤 Hodimlar ──────────
  [avatar] Alisher Ruyiddinov · +998906751161 · Sotuvchi
  [avatar] Asilbek Aliyorov · Filial boshliq
── 🏢 Filiallar ─────────
  Malika · Andijon
── ▦ Bo'limlar ──────────
  (mos kelsa)
── ✓ Vazifalar ──────────
  (mavjud mantiq)
── 📄 Sahifalar ─────────
  (mavjud mantiq)
```

- Har bo'lim sarlavha bilan; bo'sh bo'lim ko'rsatilmaydi
- **Filiallar qidiruvga QO'SHILSIN** (hozir yo'q) — `branchesCache` nom bo'yicha; bosilsa → Jamoa, filial filtri o'rnatilgan holda
- Hodim natijasida **avatar**: `getPhotoUrl()` keshidan (V2'da yaratilgan). Kesh bo'sh bo'lsa — initsiallar, palette'ni **kutdirma** (async to'ldirilsa keyin chiqadi, blocking yo'q)
- Hodim bosilsa → hodim detali sahifasi (hash-routing bilan)
- Klaviatura navigatsiyasi (↑↓ Enter) bo'limlar orasida ishlashda qolsin

## Y2 (15 daq) — "Harajat kassa" checkbox 🆕

Hodim detali sahifasiga checkbox: **"Harajat kassa kerakmi"** (Aros Provodka integratsiyasi uchun ishlatiladi).

**47_harajat_kassa.sql**:
```sql
ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS harajat_kassa BOOLEAN NOT NULL DEFAULT false;
```

- Detal formada joyi: Radius / Ish turi bloki yonida
- Saqlash: mavjud "Saqlash" tugmasi bilan birga (`employee_details` upsert)
- Faqat owner/admin o'zgartiradi (mavjud RLS yetarli — yangi policy kerak emas)
- Jamoa jadvalida ustun QO'SHMA — faqat detalda
- ⚠️ 47 hali DB'da yo'q bo'ladi — ustun-yo'q xatosini ushlab "47-migratsiya kerak" toast

## Y3 — V5b: Rasm HAMMA avatarda (oldingi brief'dan)

`getPhotoUrl()` keshini `avatarHtml()` ishlatiladigan hamma joyga: vazifa kartalari/jadval, kanban, vazifa detali, izohlar, loyiha a'zolari, org chart (Tashkilot), hodim statistikasi, pastki profil bloki. `avatarHtml()` ichida kengaytir — 30+ chaqiruvni qo'lda o'zgartirma. photo_path yo'q → initsiallar.

## Y4 — V5c: Signup'da to'liq profil

Familiya + Telefon (+998) + Rasm (ixtiyoriy). `profiles` + `employee_details` yoziladi. Mavjud login oqimini BUZMA. Rasm yuklashda ruxsat muammosi bo'lsa — jimgina o'tkaz, HISOBOTga yoz.

## Y5 — V5d: "📧 Taklif yuborish" (ulanmaganlarga)

Sintetik email (`%@staff.taskfix.org`) → "⚠ Ulanmagan" badge + "📧 Taklif" tugmasi (owner/admin). uiForm'da haqiqiy email → EF: `updateUserById` email almashtirish + parol tiklash/magic link (BITTALAB, bulk emas). EF o'zgarishi deploy talab qiladi — HISOBOTga yoz.

## Y6 — V5e: "Rasm yuklash" tugmasi

Hodim detalida: file input → canvas siqish (max 800px, JPEG 0.8) → `employee-photos/{ws}/{user}.jpg` upsert → `photo_path` yangila → kesh yangila. 46 o'lik-havolali hodim uchun yechim. Prefiks `ph*`.

## Y7 — V6: Uy tozalash

1. `42_staff_phone_lookup.sql` → **45**ga rename
2. Preflight 5b yolg'on izohlarni tuzat (EF + mijoz)
3. EF **v3** fayli: adopt-by-phone + workspace_members **DO NOTHING** + profiles COALESCE + sintetik telefon **E.164** (+998...). VERSION yangila
4. `cleanup_duplicate_staff.sql`: aniq juftliklar ro'yxati bilan, dry_run rejimi. Birinchi juftlik: `('1bde234c-a278-400f-b6e9-1ac82ea308d0','e3d0a4fb-849e-48c8-b5d5-c8086302ec99') -- Akobir`. Ko'chiriladigan: employee_details, employee_branches, employee_schedule_days, staff_import_map, employee_links, tasks (assigned_to/created_by/acceptor_id/submitter_id), project_members, department_members → keyin sintetik auth user o'chadi

## Y8 — CLAUDE.md yarat (doimiy xotira)

Repo ildizida — har sessiyada birinchi o'qiladi:
- Loyiha: TaskFix, Supabase ref nnpsbwsppgxbytlfloth, bitta index.html (~520KB), GitHub Pages, build yo'q
- Qat'iy qoidalar (yuqoridagi ro'yxat)
- DB holati: migratsiyalar 38–44, 46 (40 bo'sh o'tgan — 42 to'ldirgan), Aros ws `12b22aa6-dc45-4197-ae84-2e32e3cd56c2`, 126 hodim, 80 rasm Storage, legacy_id_map + staff_import_map ikkalasi kerak (har xil vazifa)
- Ochiq: dublikatlar (Akobir tasdiqlangan, 14 haqiqiy odam), EF v3 deploy, 45/47 SQL
- **Har katta o'zgarishdan keyin CLAUDE.md'ni o'zing yangila**

---

## Tartib va test

Y1 → Y2 → Y3 → Y6 → Y5 → Y4 → Y7 → Y8. Har biridan keyin validatsiya + testlar (qidiruv bo'limlari, harajat_kassa saqlash-mock, avatar wrapper). Oxirida HISOBOT.md: qilingan/qilinmagan + foydalanuvchi ro'yxati (45, 47 SQL; EF v3 deploy; push; sinash).
