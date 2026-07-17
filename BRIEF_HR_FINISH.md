# TaskFix — HR modulini yakunlash (import'dan keyingi 4 ish)

Import **muvaffaqiyatli**: 126/126 hodim, xatosiz. Endi kamchiliklar.

Ustuvorlik tartibi: **1 → 2 → 3 → 4**.

---

## 1. 🔴 Rasm ko'rinmayapti (buzuq)

Hodim detalida rasm o'rniga **initsiallar** chiqyapti. Sen `80 uploaded, 46 error` kutgan eding.

**Avval diagnostika** (men SQL natijasini beraman):

| `photo_path` | Storage fayllar | Sabab |
|---|---|---|
| 0 | 0 | Rasm fazasi umuman ishlamagan |
| 0 | 80 | Yuklangan, lekin `photo_path` yozilmagan |
| 80 | 80 | Yuklangan → muammo **ko'rsatishda** (signed URL) |

**Agar 80/80 bo'lsa** — ko'rsatish qismini yoz:

```js
// ⚠️ Bitta chaqiruvda hammasi — 126 ta alohida so'rov QILMA
const paths = rows.map(r => r.photo_path).filter(Boolean);
const { data } = await sb.storage
  .from('employee-photos')
  .createSignedUrls(paths, 3600);
// data[i].signedUrl → <img src>
```

- Natijani **keshla** (1 soat) — har render'da qayta so'rama
- `photo_path` NULL yoki signed URL xato → **`avatarHtml()`** (initsiallar) — hozirgi holat, to'g'ri fallback
- 46 ta o'lik havola — **normal**, ular doim initsiallar bilan qoladi

**Qayerda ko'rinsin:** hodim detali + Jamoa jadvali (avatar ustuni).

---

## 2. 🟠 Ish jadvali UI — 3 xil rejim

Hozir uchala rejimda **bir xil** forma chiqyapti. `aros_staff`dagidek bo'lishi kerak — har rejim **o'z maydonlarini** ko'rsatadi.

Barcha rejimlarda umumiy: **Ish vaqti boshlanishi** + **Ish vaqti tugashi**.

### 2.1 Haftalik (`weekly`)
Faqat **hafta kunlari** tanlanadi (dam olish kunlari).

- Ko'rinadi: `Haftalik dam olish kunlari` — multi-select (Yakshanba…Shanba)
- Saqlanadi: `weekend_days INT[]` (0=Yak … 6=Shan)
- Kalendar **yo'q**

### 2.2 Oylik (`monthly`)
Oyiga **N kun ketma-ket** dam, oy **boshida** yoki **oxirida**.

- Ko'rinadi:
  - `Dam olish kunlari hajmi` — raqam (masalan **5**)
  - `Dam olish kunlari turi` — radio: **Boshlash** | **Tugash**
- Saqlanadi: **yangi ustunlar** (pastda)
- Kalendar **yo'q**, alohida kun tanlab bo'lmaydi
- Ma'nosi: `turi=Tugash, hajmi=5` → har oyning **oxirgi 5 kuni** dam

### 2.3 Moslashuvchan (`flexible`)
**Kalendar** ochiladi, xohlagan kunlar tanlanadi.

- Ko'rinadi: `Dam olish kunlari: N kun` + bosilganda **kalendar**
- Tanlangan kunlar **yashil** (aros_staff'dagidek)
- 2 oy yonma-yon ko'rinadi, oldinga/orqaga o'tish
- To'g'ridan `employee_schedule_days` bilan ishlaydi
- `weekend_days`, `hajmi`, `turi` — **yo'q**

### 2.4 Migratsiya 43

```sql
-- 43_schedule_monthly.sql
ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS monthly_off_count    INT;
ALTER TABLE employee_details ADD COLUMN IF NOT EXISTS monthly_off_position TEXT;

ALTER TABLE employee_details DROP CONSTRAINT IF EXISTS employee_details_monthly_pos_chk;
ALTER TABLE employee_details ADD CONSTRAINT employee_details_monthly_pos_chk
  CHECK (monthly_off_position IS NULL OR monthly_off_position IN ('start', 'end'));
```

⚠️ TEXT + CHECK, **ENUM emas** (30/32-migratsiyalardagi saboq).

### 2.5 "Kunlarni saqlash" tugmasi

`aros_staff`da **"Saqlash"**dan alohida **"Kunlarni saqlash"** bor. Bizda ham shunday:

- **Saqlash** → `employee_details` (profil maydonlari)
- **Kunlarni saqlash** → naqshdan `employee_schedule_days` **qayta hosil qiladi**:
  - `weekly` → `weekend_days` bo'yicha, shartnoma davri uchun
  - `monthly` → har oyning boshi/oxiridan N kun
  - `flexible` → kalendar to'g'ridan yozadi (bu tugma kerak emas)

⚠️ **Tasdiq so'ra**: "Bu hodimning N ta ish kuni qayta hisoblanadi. Davom etamizmi?" — `uiConfirm(..., { danger: true })`.
Sabab: import qilingan 40 412 qatorni jimgina o'chirib yuborish xavfli.

⚠️ Chunk bilan yoz (500–1000 qator), `ON CONFLICT (workspace_id, user_id, date) DO UPDATE`.

---

## 3. 🟠 Orqaga tugmasi va sahifa yangilanishi

**Muammo:** hodim detalida brauzer "orqaga" bosilsa — **TaskFix'dan butunlay chiqib ketadi**. Sahifa yangilansa — bosh sahifaga qaytadi.

**Sabab:** URL yo'naltirishi yo'q. `goPage()` faqat ichki holatni o'zgartiradi, URL o'zgarmaydi.

**Yechim: hash-routing** — ikkala muammoni birdan hal qiladi.

```
#/dashboard
#/tasks
#/planner
#/team
#/team/employee/{user_id}      ← hodim detali
#/projects
#/projects/{project_id}
#/departments/{dept_id}
#/stats
#/positions
#/logs
#/settings
```

**Amalga oshirish:**

1. `goPage(p)` ichida: `history.pushState(null, '', '#/' + p)`
2. `window.addEventListener('popstate', ...)` → hash'ni o'qib, tegishli sahifani ochadi
3. Yuklashda (`init`): hash bor bo'lsa — o'sha sahifani tikla, yo'q bo'lsa `#/dashboard`
4. Hodim detali ochilganda: `#/team/employee/{user_id}`; yopilganda `history.back()` yoki `#/team`
5. Noma'lum hash → `#/dashboard` (jimgina)
6. Ruxsati yo'q sahifa (masalan member `#/logs` ochsa) → mavjud `managerOnlyPages` tekshiruvi ishlasin

**Modallar** (task detali, uiForm) — hash'ga **yozilmasin**. Faqat sahifalar.

**Test:**
- Hodim detali → brauzer orqaga → **Jamoa**ga qaytsin (saytdan chiqmasin)
- Hodim detalida F5 → **o'sha hodim** ochilib qolsin
- Loyiha ichida F5 → o'sha loyiha

---

## 4. 🟡 UI tuzatish

Foydalanuvchi "UI to'g'rilash kerak" dedi, lekin **aniq nima ekani noma'lum**.

⚠️ **O'zboshimchalik bilan qayta dizayn qilma.** Buning o'rniga:
- Hodim detali sahifasini ko'rib chiq, **aniq muammolarni ro'yxat qil** (masalan: maydonlar tekislanmagan, bo'shliq notekis, mobil ekranda buziladi)
- Ro'yxatni menga ber — foydalanuvchi tasdiqlasin
- Faqat kelishilganini o'zgartir

Aniq bilingan narsalar (bularni qilsa bo'ladi):
- Hodim detali `aros_staff`ga qaraganda zichroq/tartibsiz bo'lsa — grid tekislansin
- `.ui-*` va `.xtbl` mavjud uslublardan foydalan, yangi uslub tizimi yaratma

---

## Kod qoidalari (o'zgarmagan)

1. **Validatsiya** — har o'zgarishdan keyin:
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
2. Yangi element ID'lariga **`sch*`** (jadval) / **`rt*`** (routing) prefiksi — `empPhone` to'qnashuvi takrorlanmasin
3. Arrow function yo'q inline handler ichida; `escapeHtml()` har doim
4. UI matnlari **toza Uzbek Latin**
5. Mavjud helper'lar: `uiForm`, `uiConfirm`, `toast`, `logActivity`, `isOwnerLike`, `$`, `.xtbl`, `.ui-*`
6. TEXT + CHECK, **ENUM emas**

---

## Tartib

1. Rasm diagnostikasi → tuzatish
2. Migratsiya 43 + ish jadvali UI (3 rejim)
3. Hash-routing
4. UI muammolari ro'yxati → tasdiq → tuzatish
