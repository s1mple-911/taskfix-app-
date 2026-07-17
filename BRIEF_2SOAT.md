# TaskFix — 2 SOATLIK AVTONOM ISH (tasdiq so'ramasdan)

Foydalanuvchi 2 soatga ketdi. **Hech qanday tasdiq so'rama** — quyidagi chegaralar ichida hammasini o'zing hal qil, o'zing testla, oxirida hisobot yoz.

## Qat'iy chegaralar (bulardan chiqma)

1. ❌ `aros_staff_export.json`ni **commit qilma** (.gitignore'da turibdi — tekshir)
2. ❌ DB'ga o'zing ulana olmaysan — SQL fayllar yozasan, foydalanuvchi qaytgach ishga tushiradi
3. ❌ Ko'r-ko'rona qayta dizayn yo'q — faqat quyida aytilgan UI ishlari
4. ✅ Har `index.html` o'zgarishidan keyin **node validatsiya** (pastda), har vazifadan keyin **testlar**
5. ✅ Hamma yangi SQL — **alohida raqamlangan fayl**, idempotent, xato bo'lsa RAISE EXCEPTION (jimgina o'tmasin)

Validatsiya:
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

---

## Kontekst — bugungi topilmalar (bilishing shart)

1. **RLS dizayn xatosi topildi**: eski `tasks_select` policy member'ga vazifani faqat o'z bo'limida ko'rsatardi. Biriktirilgan odam bo'limga a'zo bo'lmasa — ko'rmasdi. **Migration 46 tayyor** (foydalanuvchi hozir ishga tushiradi) — endi assigned/creator/acceptor DOIM ko'radi, bo'limning boshqa vazifalari esa faqat a'zolarga.
2. **Dublikat akkaunt tasdiqlandi**: Akobir — haqiqiy `akobirxamdamaliyev@gmail.com` (e3d0a4fb-849e-48c8-b5d5-c8086302ec99, telefon NULL) + sintetik `998900660044@staff.taskfix.org` (1bde234c-a278-400f-b6e9-1ac82ea308d0, telefon `998900660044` — `+` YO'Q). **Avtomatik juftlash imkonsiz** (haqiqiylarda telefon yo'q, ismlar mos emas: "Akobir Adaptatsiya" ↔ "Akobirjon Xamdamaliyev").
3. **Haqiqiy odamlar 14 ta** (qolgan 126 — sintetik): abroraxmadov0808, akobirxamdamaliyev, arosnadir2026, cocacolans1984, elasosij, ergashevgiyos144, fayzullayevhavas751 (+998939562921), feruzbek2295002 (admin, full_name=email — buzuq), ilyosbeku7, lazizovichasilbek (owner), saidakbararospm (+998950102550), sherdil8882, urallmaximum, workspaceforpm.
4. Import roli bosgan edi (admin→member) — qo'lda tuzatildi. EF'da endi **DO NOTHING** bo'lishi shart.

---

## VAZIFALAR — ustuvorlik tartibida

### V1 (15 daq) — `loadTasksFull` xato yutishini tuzat 🔴
`const { data } = await sb.from('tasks')...` — **error tekshirilmaydi**. So'rov yiqilsa `tasksCache=[]` bo'lib vazifalar **jimgina** yo'qoladi (bugungi holat, sabab topish 1 soat oldi).

- Har ikkala yo'lda (owner va member) `error`ni tekshir
- Xato bo'lsa: `toast('Vazifalarni yuklashda xato: ' + translateErr(error.message), 'err')` + `console.error`
- Xuddi shu naqshni tekshir: `loadKanbanColumns`, `loadProjects`, `loadBranches` — yutayotgan bo'lsa tuzat

### V2 (30 daq) — Rasm ko'rsatish (signed URLs) 🔴
DB tekshirilgan: 80 rasm Storage'da (`{workspace_id}/{user_id}.jpg`), `photo_path` yozilgan, **44-migratsiya (policy) allaqachon ishga tushgan** ✅. Faqat frontend qoldi:

```js
const paths = rows.filter(r => r.photo_path).map(r => r.photo_path);
const { data } = await sb.storage.from('employee-photos').createSignedUrls(paths, 3600);
// data[i] = { path, signedUrl, error } — HAR BIRINI alohida tekshir
```
- **Batch** — 126 alohida so'rov emas; natijani xotirada keshla (1 soat)
- Xato / `photo_path` NULL (46 ta) → `avatarHtml()` initsiallar (hozirgidek)
- Qayerda: hodim detali (katta) + Jamoa jadvali (avatar ustuni)

### V3 (40 daq) — Ish jadvali UI: 3 rejim (aros_staff'dagidek)
`BRIEF_HR_FINISH.md` §2 to'liq spetsifikatsiya. Qisqacha:
- **Haftalik**: faqat hafta kunlari multi-select (dam kunlari) → `weekend_days INT[]`
- **Oylik**: `Dam olish kunlari hajmi` (raqam, masalan 5) + `turi` radio **Boshlash|Tugash** → yangi ustunlar. Kalendar YO'Q
- **Moslashuvchan**: kalendar (2 oy yonma-yon), tanlangan kunlar yashil, to'g'ridan `employee_schedule_days`
- Hammasida: ish vaqti boshlanishi/tugashi
- **43_schedule_monthly.sql** yoz: `monthly_off_count INT`, `monthly_off_position TEXT` + CHECK ('start','end'). TEXT, ENUM EMAS
- **"Kunlarni saqlash"** tugmasi: naqshdan `employee_schedule_days` qayta hosil qiladi (chunk 500-1000, ON CONFLICT DO UPDATE) + `uiConfirm(danger)` — "N ta ish kuni qayta hisoblanadi"
- ⚠️ 43 hali DB'da YO'Q bo'ladi — saqlashda ustun-yo'q xatosini ushlab, aniq toast ber: "43-migratsiya kerak"

### V4 (30 daq) — Hash-routing (orqaga tugmasi + F5)
`BRIEF_HR_FINISH.md` §3 to'liq spec. Qisqacha:
- `#/dashboard`, `#/tasks`, `#/team`, `#/team/employee/{id}`, `#/projects/{id}`, `#/stats`, `#/logs`…
- `goPage` → pushState; `popstate` → sahifani ochish; `init`da hash'dan tiklash
- Hodim detali: ochilganda hash, brauzer orqaga → Jamoa (saytdan chiqmasin); F5 → o'sha hodim
- Modallar hash'ga yozilmasin; `managerOnlyPages` tekshiruvi ishlashda qolsin
- ID prefiks: `rt*`

### V5 (20 daq) — Jamoa/hodim detali aros_staff bilan bir xillash
Skrinshotlardagi tafovutlarni yop (qayta dizayn EMAS, faqat parity):
- Detal formada maydonlar tartibi/guruhlanishi aros_staff'dagidek: Ism, Familiya, Rasm, Telefon, Manzil(+Manzilsiz), Shartnoma(havola), Rol, Filial va bo'limlar, Lavozim, Ish turi, Radius, Hujjatlar, jadval bloki (V3)
- Grid tekis, label'lar bir xil uslubda, `.ui-*`/mavjud CSS'dan foydalanish
- feruzbek profili: full_name=email bo'lsa — detalda ismni tahrirlash ishlashini tekshir

### V5b (15 daq) — Rasm hamma avatarda ko'rinsin
V2'dagi signed URL mantiqini **bitta umumiy yordamchiga** chiqar (masalan `getPhotoUrl(userId)` — keshli, batch bilan to'ldiriladi) va `avatarHtml()` chaqiriladigan **hamma joyda** ishlat:
- Jamoa jadvali + hodim detali (V2'da bor)
- Vazifa kartalari/jadval (biriktirilgan odam avatari)
- Kanban kartalari, vazifa detali, izohlar
- Loyiha a'zolari, org chart (Tashkilot), hodim statistikasi
- Pastki chapdagi profil bloki (agar joriy userda photo_path bo'lsa)
Qoida: `photo_path` bor → signed URL; yo'q/xato → hozirgi initsiallar. `avatarHtml()` imzosini buzma — ichida kengaytir yoki wrapper qil, 30+ chaqiruv joyini qo'lda o'zgartirib chiqma.

### V5c (20 daq) — Ro'yxatdan o'tishda to'liq profil so'rash
Yangi user o'zi ro'yxatdan o'tganda (signup oqimi) hozir faqat email/parol/ism so'raladi. Kengaytir:
- Qo'shimcha maydonlar: **Familiya, Telefon (+998 format), Rasm (ixtiyoriy)**
- Signup'dan keyin `profiles` + `employee_details` (first_name/last_name) yozilsin
- Agar workspace'ga taklif orqali kelgan bo'lsa — o'sha oqimda ham shu maydonlar
- Rasm yuklansa → `employee-photos/{workspace_id}/{user_id}.jpg` (44-policy owner/admin'ga yozish beradi; oddiy user o'z signup'ida yuklolmasa — rasmni keyinga qoldir, xato ko'rsatma, jimgina o'tkaz — HISOBOTga yoz)
- ⚠️ Signup oqimini BUZMA — yangi maydonlar majburiy bo'lsa ham mavjud login ishlashda qolsin

### V5d (20 daq) — "Email taklif yuborish" — ulanmagan hodimlarga
Import qilingan 126 hodim sintetik email bilan (`998...@staff.taskfix.org`) — ular **hech qachon kira olmaydi** (parol tasodifiy). Jamoa jadvalida:
- Sintetik email'li hodim qatorida **"📧 Taklif yuborish"** tugmasi (faqat owner/admin ko'radi)
- Bosilganda `uiForm`: haqiqiy email kiritiladi → EF orqali:
  1. `auth.users.email`ni yangisiga almashtir (admin updateUserById)
  2. Parol tiklash / magic link yubor (BITTA odamga — bulk emas, Resend suppression xavfi yo'q)
- Buning uchun mavjud `admin-create-employee` yoki EF v3'ga kichik `action: 'invite'` qo'shish mumkin — qaysi biri sodda bo'lsa
- Holat ko'rsatkichi: sintetik email → "⚠ Ulanmagan" badge; haqiqiy email → badge yo'q
- EF o'zgarsa — deploy foydalanuvchi qaytgach (HISOBOTga yoz)

### V5e (15 daq) — Rasm yuklash tugmasi (hodim detali)
Hodim detalida rasm bloki yoniga **"Rasm yuklash"** (faqat owner/admin):
- `<input type="file" accept="image/*">` → client-side siqish (canvas, max 800px, JPEG ~0.8) → `employee-photos/{workspace_id}/{user_id}.jpg` ga `upsert: true`
- Muvaffaqiyatda: `photo_path` ni `employee_details`ga yoz, kesh yangila, avatar darrov almashsin
- 46 ta o'lik-havolali hodim uchun aynan shu yechim — HISOBOTda eslat
- ID prefiks: `ph*`

### V6 (15 daq) — Uy tozalash
1. `42_staff_phone_lookup.sql` → **45** ga qayta nomla (42 band — positions seed, allaqachon DB'da)
2. **Yolg'on izohlarni tuzat** (preflight 5b — qurilmagan funksiyani tasvirlaydi) — EF va mijozda
3. EF **v3** fayli tayyor bo'lsin: adopt-by-phone + `workspace_members` **ON CONFLICT DO NOTHING** (rolga tegmaydi) + `profiles` COALESCE (mavjudni bosmaydi) + sintetik telefon **E.164** (`+998...`). VERSION yangila. Deploy — foydalanuvchi qaytgach
4. `cleanup_duplicate_staff.sql`ni qayta ishla: **aniq juftliklar ro'yxati** bilan ishlasin (avto-juftlash yo'q). Birinchi juftlik:
   `('1bde234c-a278-400f-b6e9-1ac82ea308d0','e3d0a4fb-849e-48c8-b5d5-c8086302ec99')  -- Akobir`
   Ko'chiriladigan: employee_details, employee_branches, employee_schedule_days, staff_import_map, employee_links + tasks(assigned_to/created_by/acceptor_id/submitter_id) + project_members, department_members, dept boshqa refs. Keyin sintetik auth user o'chadi. **dry_run rejimi** bilan. Foydalanuvchi qaytgach qolgan juftliklarni beradi

### V7 (qolgan vaqt) — Test + hisobot
1. Mavjud test to'plamini ishga tushir (45/45 edi) — yangi testlar qo'sh: signed URL fallback, jadval 3 rejim render, routing (hash→page), avatar wrapper (photo_path bor/yo'q), sintetik email badge aniqlash
⚠️ Vaqt yetmasa: V5c/V5d/V5e dan keragini qisqartir, lekin V1–V4 va V6 MAJBURIY — ular bugungi jonli muammolar.
2. **HISOBOT.md** yoz:
   - Nima qilindi / nima qilinmadi (sabab bilan)
   - Foydalanuvchi qaytgach bajaradigan ro'yxat (tartib bilan): qaysi SQL'lar (43, 45, 46 agar hali bo'lmasa), EF v3 deploy, push, hard refresh, nimani sinash
   - Topilgan yangi muammolar

---

## Ish tugagach commit

Hammasi commit + **bitta** aniq commit message. JSON tashqarida ekanini `git status` bilan tasdiqlال.
