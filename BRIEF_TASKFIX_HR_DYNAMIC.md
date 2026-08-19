# TASKFIX — HR Recruiting DYNAMIC (maydon konstruktor) + loyiha auto-start + Lucide

Fayl: `index.html` + `hr-apply.html` (Supabase `nnpsbwsppgxbytlfloth`). 🔴 Eski buzilmasin. UI/UX Apple. SQL additive. n8n YO'Q. 🔴 i18n MAJBURIY (uz/ru/en — har matn, CLAUDE.md qoida). Push Asilbek. Katta — bosqichma-bosqich.

## 1. DYNAMIC maydon konstruktor (HR sozlaydi)
Hozir HR forma qat'iy (passport, telefon...). Endi HR maydonlarni O'ZI boshqaradi.
- **HR sozlash paneli**: maydon qo'shish / o'chirish / tahrirlash / tartib.
- Har maydon uchun HR belgilaydi:
  - **Nom** (masalan "Passport seria") — 🔴 uz/ru/en (3 til).
  - **Tur**: CC kerakli turlarni qo'shsin — matn, raqam, sana, telefon, email, fayl (upload), tanlash (dropdown), ko'p qatorli matn, checkbox. (Kerakli barchasini CC qamrasin.)
  - **Majburiymi** (required toggle).
  - **Kim to'ldiradi** (box): **HR** / **Hodim** — ikkovi belgilansa ikkalasi ham to'ldira oladi. Faqat HR → hodim apply'да ko'rinmaydi. Faqat hodim → HR formada ko'rinmaydi.
  - **Fayl bo'lsa** — yuklash (rasm/PDF). Dropdown bo'lsa — variantlar (uz/ru/en).
- 🔴 To'liq erkin: HR istagan maydonni qo'shadi (masalan "Sudlanganlik hujjati" = fayl, "Kredit tarixi" = fayl, "Ish tajribasi" = matn).
- Standart maydonlar (passport, telefon, email...) — default shablon sifatida, HR o'zgartira/o'chira oladi.

## 2. Apply link dynamic — HR sozlaganini so'raydi
- Hodimga boradigan apply link (hr-apply.html) — HR sozlagan maydonlarni (kim to'ldiradi=hodim yoki ikkovi) so'raydi.
- Ya'ni: HR maydon qo'shsa → apply link avtomat o'sha maydonni ko'rsatadi (agar hodim to'ldiradigan bo'lsa).
- HR-only maydonlar apply'да YO'Q.
- 🔴 apply — uz/ru/en (nomzod tilni tanlaydi).

## 3. Fayl yuklash dynamic
- Qaysi maydon fayl talab qilishi — HR belgilaydi (dynamic).
- Masalan: Sudlanganlik hujjati (fayl), Kredit tarixi (fayl), Passport rasm (fayl), Diplom (fayl) — HR yoqadi.
- Fayl → Supabase Storage (private, RLS — mavjud hr-docs bucket). Limit (10 MB).

## 4. Loyiha tanlash + AUTO-START
- HR "Hodim ishga olish" ichida — **loyiha tanlash** (ixtiyoriy, org/loyiha ro'yxatidan).
- 🔴 Tanlangan bo'lsa: hodim ISHGA OLINISHI BILAN o'sha loyiha START oladi (active) — loyihadagi tasklar kimga assign bo'lsa, ular ishga tushadi (o'sha paytda).
- Tanlanmasa — hech narsa (ixtiyoriy).
- ⚠️ Loyiha start = mavjud loyiha status tizimi (active). Hodim hired bo'lganda → loyiha active + tasklar (sequential/parallel mantiq, oldingi ish).
- Idempotent: ikki marta start bo'lmasin.

## 5. 🔴 LUCIDE ICON (emoji YO'Q)
- Hozir CC ko'p joyda EMOJI ishlatyapti (👁, 📥, 🔍, 💰...). Bu NOTO'G'RI.
- 🔴 HAMMA JOYDA Lucide icon (inline SVG, CDN'siz) — emoji o'rniga.
- HR, apply, dashboard, task, AI — hamma emoji → Lucide SVG.
- CLAUDE.md'ga qoida: "Emoji ISHLATILMAYDI — Lucide inline SVG. Har icon Lucide."
- designer hamma emojini topib Lucide'ga almashtirsin (mavjud ICON_PATHS yoki lucide vendor).

## DB (additive)
- `hr_fields` (id, nom_uz/ru/en, tur, required, fill_by[hr/employee/both], options jsonb, tartib, active) — dynamic maydonlar.
- `hr_candidate_values` (candidate_id, field_id, value/file_url) — to'ldirilgan qiymatlar.
- Loyiha: hr_candidates ga project_id (nullable). Hired → loyiha start.
- CC eng toza sxema. RLS: HR/audit ko'radi, shaxsiy sizmaydi.

## Fable oqimi
coder (dynamic konstruktor, apply dynamic, fayl, loyiha auto-start, DB), designer (konstruktor UI + apply + Lucide almashtirish — Apple), tester (🔴 dynamic to'g'ri render, fill_by hr/hodim/both, fayl Storage RLS sizmaydi, loyiha idempotent start, emoji qolmagan). 🔴 i18n uz/ru/en har matn. 🔴 Eski HR buzilmasin. SQL additive (men RUN). Push men. To'liq hisobot.

## Tartib
1 (dynamic konstruktor — HR sozlaydi) → 2 (apply dynamic) → 3 (fayl dynamic) → 4 (loyiha auto-start) → 5 (Lucide — emoji almashtirish, butun ilova).
Katta — bosqichma-bosqich. Lucide (5) alohida ham qilса bo'ladi (butun ilova skani).
