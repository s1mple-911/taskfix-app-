# TaskFix — aros_staff import (126 hodim)

## Vazifa

`aros_staff` tizimidan **126 hodim**ni TaskFix'ga ko'chirish: profil, filial/bo'lim, shartnoma, ish jadvali (to'liq kunlar), rasm.

Ma'lumot **fayl orqali** keladi (`aros_staff_export.json`, **5.7 MB** — eksport bajarilgan, §0 ga qarang). Ilova `aros_staff` API'siga **hech qachon o'zi bormaydi** — token yo'q, tashqi bog'liqlik yo'q.

**Eksport skripti tayyor:** `aros_staff_export.js` — brauzer console'da ishlaydi, faylni yuklab beradi. Uni o'zgartirish shart emas.

---

## 0. ✅ EKSPORT BAJARILDI — haqiqiy raqamlar

Fayl tayyor: `aros_staff_export.json` (**5.7 MB**). Tahlil natijasi:

| Ko'rsatkich | Qiymat | Holat |
|---|---|---|
| Hodimlar | **126 / 126** | ✅ xatosiz |
| Dublikat telefon | 0 | ✅ |
| Telefonsiz | 0 | ✅ |
| Email to'qnashuvi (telefondan) | 0 | ✅ |
| Telefon formati (`+998XXXXXXXXX`) | 126/126 to'g'ri | ✅ |
| Shartnoma havolasi yo'q | 0 | ✅ |
| Filiallar | **31** | id 12 va 13 — bir xil nom |
| Rollar | **1** (`DEVELOPER`) | 11 hodimda, 115 tasida `null` |
| Lavozimlar | id 1–30 oralig'ida | import `legacy_id_map` orqali bog'laydi |
| Ish kunlari | **40 412 qator** | 2024-12-01 → 2026-09-01 |
| Rasmi yo'q | 0 (URL hammasida bor) | ⚠️ lekin **46 tasi 404** — "Rasm" bo'limiga qarang |
| `documents` | **0 ta** (hamma bo'sh) | ✅ import shart emas |
| Filialsiz hodim | 0 | ✅ |
| Bir xil ism-familiya | yo'q | ✅ |

### ⚠️ Muhim: ish vaqti QAT'IY EMAS

`vacation_type`: `weekly` **67**, **`custom` 58**, `monthly` 1.

> ⚠️ **`custom` — TaskFix'da bunday qiymat YO'Q.**
> `39:147` — `CHECK (schedule_type IS NULL OR schedule_type IN ('weekly','monthly','flexible'))`.
> To'g'ridan-to'g'ri yozsak **58 hodim yiqiladi**. Ustiga `index.html:10147`
> (`HR_SCHEDULE_TYPES`) faqat shu uch qiymatni radio sifatida ko'rsatadi — `custom`
> yozilsa hech biri tanlanmaydi va manager o'sha hodimni saqlaganda `schedule_type`
> **jimgina `null` ga aylanadi** (`10363`).
>
> **Qaror:** `custom` → **`flexible`** deb xaritalanadi (STUB #1 da). Migratsiya
> ham, UI ham o'zgarmaydi. Yo'qotish yo'q — haqiqat manbai baribir `days`.

Ish vaqti variantlari (eng ko'p uchraganlari):

| Vaqt | Kunlar |
|---|---|
| 08:30–20:00 | 9 535 |
| 08:30–19:00 | 7 009 |
| 08:30–19:30 | 4 252 |
| 09:00–18:00 | 3 849 |
| 08:00–17:00 | 3 309 |
| 09:00–21:00 | 3 057 |

**Xulosa:** "naqshdan chiqarish" (weekend_days + bitta ish vaqti) ma'lumotning katta qismini yo'qotardi.
**To'liq `days` import qilish — to'g'ri qaror.** `employees[].schedule` faqat UI'da qisqa ko'rsatish uchun, haqiqat manbai — `days`.

### ⚠️ Tozalanishi kerak (aniq ro'yxat — hammasi shu)

**Kirill harf (2 ta):**
- `user_id: 15` → `"Bаhodir Abdullayev"` — `а` kirilcha (U+0430)
- Filial `id: 24` → `"Маrketing bo'limi"` — `М` (U+041C) va `а` (U+0430) kirilcha

**Typografik apostrof `’` (U+2019) — 4 ta ism:**
- `user_id: 11` → `"Saydullo To’xtasinov"`
- `user_id: 28` → `"O’ral Ro’ziyev"`
- `user_id: 40` → `"O’ktam Ro’ziyev"`
- `user_id: 48` → `"Rustam Ro’ziyev"`

**Boshqa e'tibor:**
- Filial `id: 12` va `id: 13` — ikkalasi `"Qarshi Bahor"`, turli `lat/lng`/`manager` → **`legacy_id` bo'yicha ajrating**
- `radius` odatda 100, lekin bittasida **1999**, yana: 30, 102, 150, 200, 500 — bu normal ma'lumot, tegmang
- 3 ta rasm URL'i **URL-encoded** (kirill fayl nomi): `.../%D0%94%D0%B8%D0%BB...jpg` — `fetch` o'zi hal qiladi
- Bitta hodimda **5 tagacha filial** bo'lishi mumkin
- Kunlar soni: eng kam **31**, eng ko'p **640**

### 📷 Rasm — O'LCHANDI (2026-07-17), taxmin emas

Eksport `image_publicly_fetchable: "cors_blocked"` degan edi. **126 URL ham server
tomondan tekshirildi** (auth'siz `HEAD`). Natija:

| Ko'rsatkich | Qiymat |
|---|---|
| **200 OK** | **80 / 126** |
| **404** | **46 / 126** ⚠️ |
| Auth kerakmi | **YO'Q** — 401/403 umuman chiqmadi |
| Hajm (80 ta) | **18.8 MB**, o'rtacha 240 KB, eng katta 3.4 MB |
| content-type | `image/jpeg` **va** `application/octet-stream` |

**Ikki xulosa — ikkalasi ham brief'ning oldingi taxminini bekor qiladi:**

1. **`cors_blocked` auth degani emas edi.** Rasmlar ochiq. Brauzer `fetch()` ni CORS
   to'sadi, lekin `<img src>` ni **to'smaydi** — ya'ni oddiy havola sifatida ham
   ko'rinardi. "Rasmlar auth ortida bo'lishi mumkin" degan xavf **yo'q**.

2. **Lekin 46 ta URL o'lik (404).** §0 jadvali "Rasmi yo'q: 0" deydi — URL hammasida
   bor, faqat ularning **36%** ishlamaydi.

**Storage nima uchun kerak — sabab O'ZGARDI:**
Auth uchun emas (u yo'q ekan), balki **o'lik havolalar uchun**:

| Yo'l | 46 ta o'lik rasm nima bo'ladi |
|---|---|
| `photo_url` (havola) | `<img src>` **siniq rasm ikonkasi** ko'rsatadi. `photo_url` NULL emas, shuning uchun `avatarHtml` initsiallarga **tushmaydi**. Jimgina buzuq UI. |
| **`photo_path`** (Storage) | Import paytida 404 **ushlanadi**, hisobotga tushadi, `photo_path` NULL qoladi → `avatarHtml` **initsiallarga toza tushadi**. |

Ya'ni Storage 46 ta jimgina siniq rasmni — 46 ta hisobot qatoriga va toza
initsiallarga aylantiradi.

⚠️ **`content-type` bo'yicha oq ro'yxat qilmang.** Ishlaydigan 80 ta rasmning bir
qismi `application/octet-stream` qaytaradi. `if (!ctype.startsWith('image/')) throw`
— ularni rad etardi. Qora ro'yxat ishlating: faqat `text/*` va `application/json`
rad etilsin (login sahifasi, xato javobi).

Baribir: rasm `fetch`i muvaffaqiyatsiz bo'lsa — **import to'xtamasin**, hisobotga yozilsin.

---

## 0b. Tasdiqlangan qarorlar

| Savol | Qaror |
|-------|-------|
| Ish jadvali (`days`) | **To'liq kunlar** import qilinadi (**40 412** qator — o'lchangan) |
| Rasmlar | **Supabase Storage**ga ko'chiriladi (~25 MB) |
| Filial va bo'lim | **Ikkalasi ham** TaskFix'ga |
| Email | Soxta: `<telefon_raqamlari>@staff.taskfix.org` |
| Telefon | `auth.users.phone` ga ham yoziladi (E.164) — kelajakda telefon-login uchun |

---

## 1. Eksport fayli tuzilishi

```jsonc
{
  "exported_at": "2026-07-16T...",
  "counts": { "employees": 126, "branches": 30, "roles": 1, "duplicate_phones": 0,
              "no_phone": 0, "total_day_rows": 40412, ... },
  "image_publicly_fetchable": true,          // rasmlar auth'siz olinadimi
  "warnings": { "duplicate_phones": [...], "errors": [...] },
  "branches": [ { "id": 1, "name": "IT bo'limi", "address": "...", "lat": 41.35, "lng": 69.30, "manager": "..." } ],
  "roles":    [ { "id": 3, "name": "DEVELOPER" } ],
  "employees": [
    {
      "employment_id": 2,
      "user_id": 3,
      "first_name": "Saidakbar",
      "last_name": "Muhiddinov",
      "phone": "+998950102550",
      "address": "",
      "image_url": "https://api.staff.aros.uz/media/.../photo.jpg",
      "role_id": 3, "role_name": "DEVELOPER",
      "position_id": 2, "position_name": "Loyiha boshqaruvchisi",
      "branches": [ { "id": 1, "name": "IT bo'limi", ... } ],
      "contract_url": "https://docs.google.com/document/d/.../edit",
      "contract_start": "2025-02-28",
      "contract_end": "2026-09-01",
      "vacation_type": "weekly",
      "work_type": "offline",
      "radius": 100,
      "lat": null, "lng": null,
      "no_address": false,
      "documents": [],                          // hamma hodimda BO'SH — import shart emas
      "created_at": "2024-09-25T11:40:51+05:00",
      "schedule": { "weekend_days": [0,6], "work_start": "08:00", "work_end": "17:00", ... },
      "days": [ { "date": "2025-02-28", "day_type": "on", "start_time": "08:00", "end_time": "17:00" }, ... ]
    }
  ]
}
```

---

## 2. ⚠️ Manbadagi tuzoqlar (eksport skripti allaqachon hal qilgan, lekin biling)

### 2.1 `contract` — manbada IKKI XIL TUR
`aros_staff` ro'yxatida `contract` = **obyekt** (`{start_date, end_date}`), detalda = **matn** (Google Docs havolasi).
Eksport skripti ularni ajratib bergan: `contract_url`, `contract_start`, `contract_end`. **Import faylda muammo yo'q.**

### 2.2 Kirill harflar MA'LUMOT ichida
Manbada Lotin so'zlar orasida kirilcha harflar bor:
- `"Bаhodir"` — `а` **kirilcha** (U+0430)
- `"Маrketing bo'limi"` — `М` (U+041C) va `а` **kirilcha**

Va typografik apostrof:
- `"To’xtasinov"`, `"O’ral"`, `"Ro’ziyev"` — bu **U+2019**, oddiy `'` (U+0027) emas
- Ba'zilarida esa oddiy: `"Abrorxo'ja"`, `"Turg'un"`

**Kerak:** `normalizeName()` yordamchisi — import paytida ismni tozalaydi:
- Kirill homoglif → Lotin (`а→a`, `М→M`, `о→o`, `е→e`, `р→p`, `с→c`, `х→x`, `у→y`, `В→B`, `Н→H`, `К→K`, `Т→T`)
- `’` (U+2019) va `‘` → `'`
- Ortiqcha bo'shliqlarni olib tashlash

⚠️ Ismning **asl holatini ham saqlang** (`legacy_name_raw`) — moslashtirish/tekshirish uchun.
⚠️ Bu faqat **ism/filial nomlari** uchun. Lavozim nomlariga tegmang — ular manbadan qanday kelsa, shunday.
(Eslatma: `positions` da faqat `name` ustuni bor. `name_ru` degan ustun **yo'q** — 39-migratsiyaga qarang.)

### 2.3 Dublikat nomlar — ID bo'yicha ishlang, nom bo'yicha emas
- Filial `id: 12` va `id: 13` — ikkalasi **"Qarshi Bahor"**, lekin turli `lat/lng` va `manager`
- Lavozim `id: 28` va `id: 29` — bir xil nom. `positions` da `UNIQUE (workspace_id, name)` bor, ya'ni
  ikkalasi **bitta** qatorga tushadi. `legacy_id_map` da esa **ikkita** yozuv bo'ladi:
  `('position','28') → uuid-X` va `('position','29') → uuid-X`. Bu ruxsat etilgan — `legacy_id_map` da
  `target_id` bo'yicha UNIQUE ataylab yo'q (`40:56-58`)

### 2.4 `employment_id` ≠ `user_id`
Ikki xil ID. Odam = `user_id`. **Idempotentlik kaliti sifatida `user_id` ishlatiladi.**
(Masalan: employment 106 → user 115; employment 107 → user 116 — ular mos kelmaydi.)

### 2.5 `role` ko'pincha `null`
126 hodimning aksariyatida `role: null`. Faqat bir nechtasida `DEVELOPER`. Bu **normal** — `role_id` NULL bo'la oladi.
Bu `aros_staff`ning ichki roli — **TaskFix `workspace_members.role` (owner/admin/member) bilan aralashtirmang.**

---

## 3. Migratsiya 41 — `41_staff_import_data.sql`

> **Nom `41_staff_import.sql` EMAS** — `40_staff_import.sql` allaqachon shu nomda.

Repoda bor:
- **39** — `positions`, `employee_roles`, `employee_details`, `employee_branches`
- **40** — `legacy_id_map`, `staff_import_map`, `auth_user_id_by_email()`

> ⚠️ Brief'ning oldingi versiyasi "40-migratsiyada: `positions` seed + `legacy_ids`"
> degan edi — **bu noto'g'ri edi**. `40_staff_import.sql` hech narsa seed qilmaydi va
> `legacy_ids` ustunini qo'shmaydi. Bunday ustun umuman mavjud emas.

### Bog'lash: FAQAT 40 dagi jadvallar orqali

`legacy_id` / `legacy_ids` **ustunlari yozilmaydi**. Sabab `40:28-34` da asoslangan:
`branches.external_id` boshqa id maydoni uchun (Aros `warehouse_id`), `positions` va
`employee_roles` da bunday ustun umuman yo'q, va domen jadvallari import
tafsilotlaridan toza qolishi kerak.

| Nima | Qayerda | Kalit |
|---|---|---|
| Filial, lavozim, rol, bo'lim | `legacy_id_map` (40) | `(ws, source_system, entity_type, legacy_id)` → `target_id` |
| **Hodim** | `staff_import_map` (40) | `(ws, source_system, source_id)` → `user_id`, `source_id` = aros **`user_id`** |

**Hodim uchun `legacy_id_map` ISHLATILMAYDI.** Ikki sabab:
1. `40:50` — `CHECK (entity_type IN ('branch','position','role','department'))`.
   `'employee'` bu CHECK'ni buzadi.
2. `staff_import_map` bu ishni allaqachon, va **yaxshiroq** qiladi — unda
   `import_run_id` + `created_in_run` (**rollback**), `phone_e164`, va
   `UNIQUE (ws, source_system, user_id)` bor. `legacy_id_map` da `target_id`
   bo'yicha UNIQUE ataylab yo'q (`40:56-58`) — filial uchun to'g'ri, hodim uchun
   xavfli.

Idempotentlik oqimi allaqachon yozilgan (`admin-import-staff/index.ts:189-234`):
`staff_import_map` dan qidirish → topilmasa email bo'yicha **adopt** →
topilmasa **create**.

### 41 nima qo'shadi

```sql
-- 1) employee_details: MA'LUMOT ustunlari (bog'lash EMAS — qidirilmaydi)
ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS legacy_name_raw      TEXT;
ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS legacy_employment_id INT;
ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS photo_path           TEXT;
ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS hired_at             TIMESTAMPTZ;
ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS lat                  DOUBLE PRECISION;
ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS lng                  DOUBLE PRECISION;

-- 2) Ish jadvali: to'liq kunlar (~40 412 qator)
CREATE TABLE IF NOT EXISTS employee_schedule_days (
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL,
  date         DATE NOT NULL,
  day_type     TEXT NOT NULL,   -- on | off
  start_time   TIME,
  end_time     TIME,
  PRIMARY KEY (workspace_id, user_id, date)
);
-- TEXT + CHECK, ENUM emas (39:139 saboqi)
ALTER TABLE employee_schedule_days ADD CONSTRAINT employee_schedule_days_day_type_chk
  CHECK (day_type IN ('on', 'off'));
-- RLS: emp_sched_days_select / emp_sched_days_write

-- 3) Storage bucket (private) + storage.objects SELECT policy
```

`legacy_user_id` ustuni **yozilmaydi** — hodim kaliti `staff_import_map.source_id`.
`legacy_employment_id` esa qoladi: u kalit emas, manba bilan solishtirish uchun fakt.

`sched_days_user_idx` **kerak emas** — `PRIMARY KEY (workspace_id, user_id, date)`
o'zi shu prefiksni qoplaydi.

> **RLS:** `is_ws_manager()` — 35-migratsiyada. Policy ichida inline
> `workspace_members` subquery **yozmang** — rekursiya (`42P17`, bir marta 500 xato
> bergan). Faqat `is_ws_manager()` / `is_ws_member()` (`39:28-29`).

### Storage bucket

```sql
INSERT INTO storage.buckets (id, name, public)
VALUES ('employee-photos', 'employee-photos', false)
ON CONFLICT (id) DO NOTHING;
```

> ⚠️ **Bu 38/39 dagi qoidadan ONGLI CHEKINISH.** `38:3` — "Hodim hujjatlari — FAYL
> EMAS, faqat Google Drive LINKLARI", `39:5` — "fayl saqlanmaydi".
> Sabab (o'lchangan, §0 ga qarang): manba URL'larining **46/126 tasi 404**. Havola
> sifatida qoldirsak — 46 ta jimgina siniq rasm; Storage esa ularni import
> hisobotiga va toza initsiallar fallback'iga aylantiradi.
> **Shartnoma va `employee_links` — HAVOLA bo'lib qoladi.**

**Private bucket.** Yo'l: `{workspace_id}/{user_id}.jpg`.

`employee_details` da endi **ikkita** rasm ustuni: `photo_url` (39, qo'lda kiritilgan
havola) va `photo_path` (41, Storage). Ustuvorlik:
`photo_path` (signed URL) → `photo_url` → `profiles.avatar_url` → initsiallar.
Mavjud zanjir `index.html:9867` va `10265` da.

Ko'rsatishda `createSignedUrls(paths[], 3600)` — **massiv bilan bitta chaqiruv**
(126 ta alohida so'rov qilmang). ⚠️ Bu plumbing ilovada hali **yo'q** —
`createSignedUrl` hech qayerda ishlatilmagan, yangi yoziladi.

Storage RLS: **yozish policy'si yo'q** — faqat service_role (Edge Function) yozadi,
u RLS'ni chetlab o'tadi. O'qish — ws manageri yoki o'z rasmi (`createSignedUrl`
chaqiruvchi JWT bilan ishlaydi, shuning uchun SELECT policy shart).

---

## 4. Import Edge Function: `admin-import-staff`

**Nega Edge Function:** `auth.users` yaratish `service_role` talab qiladi + rasmlarni server tomondan yuklab olish kerak (brauzerda CORS to'sadi).

⚠️ **Deploy'da "Verify JWT" — ON** (default). Brief'ning oldingi versiyasi OFF degan
edi (`admin-create-employee` dan ko'chirilgan) — lekin `admin-import-staff` ataylab
ON bilan yozilgan (`index.ts:14,17`). Kod baribir **o'zi ham** tekshiradi: chaqiruvchi
shu workspace'ning owner/admin'imi (`index.ts:145-154`). Ikki qatlam — ataylab.

### ⚠️ Qamrov: EF hamma narsani QILMAYDI

Brief'ning oldingi versiyasi EF filial, bo'lim, rol, hodim, ish kunlari va rasmni —
hammasini qilsin degan edi. **Yozilgan kod boshqacha, va shunday qoladi:**

| Kim | Nima |
|---|---|
| **EF** (`service_role`) | `auth.users` yaratish, `workspace_members`, `staff_import_map`, **rasm** |
| **Mijoz** (RLS, owner sifatida) | `branches`, `departments`, `employee_roles`, `positions`, `employee_details`, `employee_branches`, `employee_schedule_days`, `legacy_id_map` |

Sabab: EF ga faqat `service_role` **majburan** talab qiladigan ish beriladi —
`auth.users` yaratish va rasm yuklash (brauzerda CORS to'sadi). Qolgani mijozda
owner huquqi bilan RLS orqali o'tadi. Shunda `service_role` sirti kichik qoladi va
150s limitga urilmaydi.

### Kirish

⚠️ **Butun `data` (5.7 MB) EF ga YUBORILMAYDI.** Brief'ning oldingi versiyasi
`{ data, offset, limit }` degan edi — u har chaqiruvda 5.7 MB ko'taradi (7 chaqiruv
× 5.7 MB). Yozilgan kod boshqacha: JSON'ni **mijoz** parse qiladi, normallashtiradi
va chaqiruvga **faqat 25 ta tayyor qator** yuboradi.

```jsonc
{
  "workspace_id": "...",
  "source_system": "aros_staff",
  "dry_run": true,              // true = hech narsa yozilmaydi, faqat hisobot
  "import_run_id": "uuid",      // dry_run bo'lmasa MAJBURIY (rollback kaliti)
  "rows": [                     // ≤ 25 (MAX_ROWS_PER_CALL, index.ts:35)
    { "source_id": "3", "phone_e164": "+998950102550",
      "email": "998950102550@staff.taskfix.org", "full_name": "Saidakbar Muhiddinov" }
  ]
}
```

Rasm fazasi alohida chaqiriladi:
```jsonc
{ "workspace_id": "...", "phase": "photos",
  "rows": [ { "user_id": "uuid", "image_url": "https://api.staff.aros.uz/..." } ] }
```

### Bosqichlar (shu tartibda)

**1) Auth tekshiruvi** — chaqiruvchi owner/admin emasmi → 403.

**2) Filiallar** (`data.branches` → `branches`) — **mijozda**
- `legacy_id_map` (`entity_type='branch'`) bo'yicha upsert
- Nom **normalizatsiya** qilinadi (kirill → lotin)
- `lat/lng/address` saqlanadi
- ⚠️ Dublikat nom (id 12/13 "Qarshi Bahor") — **ikkalasi ham alohida qator**,
  `legacy_id_map` da ikki yozuv, ikki `target_id`

**3) Bo'limlar** (`departments`)
- Nomi `bo'limi` bilan tugaydigan filiallar (`IT bo'limi`, `HR bo'limi`, `Buxgalteriya bo'limi`, `Marketing bo'limi`) uchun **`departments` qatori ham** ta'minlanadi (nom bo'yicha, mavjud bo'lsa qayta yaratmang — TaskFix'da allaqachon `IT`, `HR` bor bo'lishi mumkin)
- Hodim shu bo'limga `department_members` orqali bog'lanadi (rol: `member`)

**4) Rollar** (`data.roles` → `employee_roles`) — **mijozda**
- `legacy_id_map` (`entity_type='role'`) bo'yicha upsert. Ko'pchilikda `role: null` — normal.
- ⚠️ `employee_roles` da `code` **UNIQUE** (`39:91`), `name` emas. Manba `role_name`
  (`DEVELOPER`) → `code`. `positions` dagi `teamAddPosition()` kabi get-or-create
  helper roll uchun **yo'q** — yoziladi.

**5) Hodimlar** — har biri uchun (a–d **EF da**, e–i **mijozda**):

  a. **Email:** `phone.replace(/\D/g, '') + '@staff.taskfix.org'`
     → `998950102550@staff.taskfix.org`
     ⚠️ Telefonsiz hodim bo'lsa — **o'tkazib yuboring**, hisobotga yozing (`no_phone`).

  b. **Auth user:**
   - Avval `legacy_user_id` bo'yicha `employee_details`dan qidiring → bor bo'lsa **yangilash** (idempotent)
   - Yo'q bo'lsa email bo'yicha qidiring (`listUsers` sahifalab yoki RPC)
   - Yo'q bo'lsa **`createUser`** bilan yarating:
     ```ts
     admin.auth.admin.createUser({
       email, phone,                  // E.164: +998950102550
       email_confirm: true,
       phone_confirm: true,
       password: crypto.randomUUID(), // tasodifiy — kirish keyin parol tiklash orqali
       user_metadata: { legacy_user_id, source: 'aros_staff' }
     })
     ```
   - ❌ **`inviteUserByEmail` ISHLATMANG** — 126 ta email yuboradi. Bu Resend suppression muammosini keltiradi (o'tgan safar bo'lgan).
   - ⚠️ `auth.users.phone` **UNIQUE** — dublikat telefon bo'lsa xato beradi. Eksport hisobotidagi `duplicate_phones`ni oldindan tekshiring.

  c. **`profiles`** upsert: `full_name` (normalizatsiya qilingan `first_name + ' ' + last_name`), `phone`, `email`

  d. **`workspace_members`** upsert: rol = **`member`** (hech kimni admin qilmang)

  e. **`employee_details`** upsert (`workspace_id`, `user_id` bo'yicha):
     `legacy_user_id`, `legacy_employment_id`, `legacy_name_raw`, `first_name`, `last_name`,
     `address`, `no_address`, `contract_url`, `contract_start`, `contract_end`,
     `role_id`, `position_id`, `work_type`, `radius`, `lat`, `lng`,
     `schedule_type` ← `vacation_type`, `weekend_days` ← `schedule.weekend_days`,
     `work_start` ← `schedule.work_start`, `work_end` ← `schedule.work_end`,
     `hired_at` ← `created_at`

  f. **`employee_branches`** — `branches[].id` → `legacy_id` orqali TaskFix branch UUID

  g. **`position_id`** — `legacy_id_map` orqali:
     ```sql
     SELECT target_id FROM legacy_id_map
     WHERE workspace_id = $1 AND source_system = 'aros_staff'
       AND entity_type = 'position' AND legacy_id = '7';
     ```
     ⚠️ Brief'ning oldingi versiyasi `= ANY(legacy_ids)` degan edi — bunday ustun
     **yo'q**, o'sha so'rov xato beradi. Mijozda buni `hrLegacyResolve('position', 7)`
     qiladi (`index.html:10627`), xarita `hrLoadLegacyMap()` da oldindan yuklanadi.

  h. **Ish kunlari** — `employee_schedule_days`ga **bo'lak-bo'lak** (chunk) yozing:
     - **500–1000 qator/chunk** (bitta katta insert timeout beradi)
     - `ON CONFLICT (workspace_id, user_id, date) DO UPDATE`
     - Bitta hodimda ~550 kun

  i. **Rasm:**
     - `image_url`ni server tomondan `fetch` qiling (Edge Function'da CORS yo'q)
     - Storage'ga: `employee-photos/{workspace_id}/{user_id}.jpg`
     - `upsert: true`, `contentType: 'image/jpeg'`
     - `photo_path` ni `employee_details`ga yozing
     - ⚠️ Rasm xatosi **butun importni to'xtatmasin** — hisobotga yozing, davom eting

**6) Hisobot** qaytariladi:
```jsonc
{
  "ok": true, "dry_run": false,
  "created_users": 120, "updated_users": 6,
  "branches_created": 30, "positions_matched": 126, "positions_missing": 0,
  "schedule_days_inserted": 40412,
  "photos_ok": 124, "photos_failed": 2,
  "skipped": [ { "phone": null, "name": "...", "reason": "no_phone" } ],
  "errors": [ { "legacy_user_id": 42, "step": "createUser", "error": "..." } ]
}
```

### Idempotentlik (majburiy)
Ikki marta ishga tushirilsa — **dublikat bo'lmasin**. Kalit: `legacy_user_id`. Hamma yozuv `upsert`.

### Timeout — allaqachon hal qilingan

Edge Function ~150s bilan cheklangan. 126 hodim × (createUser + rasm + 550 kun)
bitta chaqiruvga **sig'maydi**.

**Yozilgan yechim — `offset/limit` EMAS, qator bo'laklash:**

- Mijoz JSON'ni o'zi parse va normalizatsiya qiladi
- `hrImportInvoke()` (`index.html:10832`) `HR_IMP_CHUNK = 25` bo'yicha bo'lakka bo'ladi
- Har chaqiruvda **faqat 25 ta tayyor qator** ketadi (`{source_id, phone_e164, email, full_name}`)
- EF `MAX_ROWS_PER_CALL = 25` dan ko'pini **rad etadi** (`index.ts:128-131`, `too_many_rows`)
- 126 hodim → 6 chaqiruv; progress `onProgress` orqali jonli

**Nega `offset/limit` emas:** u har chaqiruvga butun `data` (5.7 MB) ni qo'shardi —
6 chaqiruv × 5.7 MB = 34 MB ortiqcha trafik, hech qanday foydasiz.

Ish kunlari (~40 412 qator) EF ga umuman bormaydi — mijoz `employee_schedule_days`
ga RLS orqali **500–1000 qator/chunk** yozadi.

Rasm — alohida `phase: 'photos'` chaqiruvi (service_role + CORS talab qiladi).

---

## 5. Import UI (Jamoa sahifasida)

Faqat **owner/admin** ko'radi.

1. **Fayl yuklash** (`<input type="file" accept=".json">`)
   ⚠️ **Textarea'ga paste QILMANG** — fayl 5.7 MB, brauzer qotadi. Faqat `FileReader`.

   > ✅ **BAJARILDI** (2026-07-17). Qurilgan UI avval textarea edi — ya'ni kod shu
   > qoidaning aynan o'zini buzardi. Endi `<input type="file" id="hrImpFile">` +
   > `hrImportFilePicked()`, matn `_hrImpFileText` da. Fayl tanlangach darrov qisqa
   > xulosa ko'rsatiladi ("✓ aros_staff_export.json · 5.7 MB · 126 hodim ·
   > 40 412 ish kuni · 31 filial") — noto'g'ri fayl darrov bilinadi.

2. **Pre-flight** (`dry_run: true`) — hisobot ko'rsatiladi:
   - Nechta yangi / nechta mavjud (yangilanadi)
   - Topilmagan lavozim / filial (bo'lsa — **qizil**, avval 40-migratsiyani tekshiring)
   - Dublikat telefon, telefonsizlar
   - Jami ish kunlari soni
   - `image_publicly_fetchable: false` bo'lsa — ogohlantirish

3. **Tasdiq** — `uiConfirm()`, aniq son bilan:
   > "126 hodim import qilinadi (120 yangi, 6 yangilanadi). ~40 412 ish kuni yoziladi. Davom etamizmi?"

4. **Progress** — bo'lak-bo'lak, jonli: `"42 / 126 ..."`

5. **Yakuniy hisobot** — jadval + xatolar ro'yxati (nusxalash mumkin)

6. `logActivity('staff_imported', { details: { count, created, updated } })`

---

## 6. Sinov tartibi (MAJBURIY)

1. **`dry_run: true`** — hech narsa yozilmaydi, hisobot to'g'rimi
2. **`limit: 2`** — 2 hodim. Tekshiring: auth user, profil, lavozim bog'landimi, rasm, ish kunlari
3. **O'sha 2 tani qayta** import qiling → **dublikat bo'lmasligi** shart (idempotentlik)
4. Hammasi to'g'ri bo'lsa — **to'liq 126**

---

## 7. Kod qoidalari (o'zgarmagan)

1. **Validatsiya** — har `index.html` o'zgarishidan keyin
   (brief oldin `app.html` degan edi — repoda bunday fayl **yo'q**):
   ```bash
   node -e "
   const fs=require('fs'), vm=require('vm');
   const h=fs.readFileSync('index.html','utf8');
   const re=/<script(?![^>]*src=)[^>]*>([\s\S]*?)<\/script>/g;
   let m, code=null;
   while((m=re.exec(h))){ if(m[1].indexOf('async function init')!==-1) code=m[1]; }
   try { new vm.Script(code); console.log('OK', code.length); }
   catch(e){ console.log('XATO:', e.message); process.exit(1); }
   "
   ```
2. Yangi element ID'lariga **`hrImp*`** prefiksi (o'tgan `empPhone` to'qnashuvi
   takrorlanmasin). Brief oldin `imp*` degan edi — qurilgan kod `hrImp*` ishlatadi
   (`hrImpJson`, `hrImpRunBtn`, `hrImpPreflight` …). Shu davom etsin.
3. Arrow function yo'q inline handler ichida; `escapeHtml()` har doim
4. UI matnlari **toza Uzbek Latin**
5. Mavjud helper'lar: `uiForm`, `uiConfirm`, `toast`, `logActivity`, `isOwnerLike`, `$`, `.xtbl`
6. Edge Function xatolari: `String(e)` / `e.status` / `e.code` — **`JSON.stringify(e)` emas**
   (Supabase `AuthApiError.message` — non-enumerable, `{}` chiqadi. Bu bizda bo'lgan.)

---

## 8. Migratsiya tartibi

`35` → `38` → `39` → `40` → **`41_staff_import_data.sql`** (bucket shu faylning
ichida yaratiladi) → Edge Function deploy (**Verify JWT ON**) → `index.html` push

⚠️ SQL fayllar git'da **kuzatilmaydi** (`git ls-files` hech qanday `.sql` ko'rsatmaydi) —
ular faqat lokal va Supabase loyihasida. 35-migratsiya repoda umuman yo'q, shuning
uchun `is_ws_manager()` tanasini bu yerdan ko'rib bo'lmaydi; 39/40/41 dagi old-guard
uni himoya qiladi.
