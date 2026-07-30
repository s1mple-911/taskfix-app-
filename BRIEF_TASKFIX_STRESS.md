# TASKFIX — to'liq performance / stress test (o'lchov, qayta yozishdan oldin)

Maqsad: "sekinlashyapti, backend qayta yozaylikmi" degan savolga ANIQ RAQAM bilan javob. Sekinlik qayerda — frontend (ketma-ket so'rov), SQL (indeks yo'q), yoki hajm (ko'p ma'lumot)? O'lchaymiz, taxmin qilmaymiz.

Fayl: `index.html` (Supabase ref `nnpsbwsppgxbytlfloth`). Prod ma'lumotга TEGILMAYDI (test alohida).

---

## 1. SAHIFA OCHILISH TEZLIGI (frontend — real ish)
Har asosiy ko'rinish uchun o'lchov qo'sh (vaqtincha yoki doimiy debug rejimда):
- **Ko'rinishlar**: Login/boot, Dashboard, Vazifalar (kanban), Ro'yxat, Kalendar, Jamoa, Loyihalar, Loyiha detali, Bo'lim detali, Hisobot (agar bo'lsa).
- Har biriда `console.time`/`performance.now` bilan:
  - Umumiy: sahifa ochilishidan ma'lumot to'liq ko'ringuncha (ms)
  - Nechta Supabase so'rovi ketdi
  - So'rovlar **ketma-ketmi yoki parallel** (waterfall) — bu eng muhim
  - Eng sekin so'rov qaysi va necha ms
- Natijani jadval qilib chiqar: sahifa · so'rov soni · umumiy vaqt · eng sekin so'rov.
- ⚠️ Ketma-ket so'rovlar topilsa (biri tugab keyingisi) — bu asosiy sekinlik sababi, belgila.

## 2. YUKLAMA TESTI (ko'p foydalanuvchi bir vaqtda)
Alohida test skripti (`stress_test.js` — Node yoki brauzer console):
- Supabase'ga bir vaqtda N ta parallel so'rov (asosiy so'rovlar: tasks list, members, projects).
- N = 10, 50, 100, 500 bosqichma-bosqich.
- Har bosqichда: o'rtacha javob vaqti, eng sekin, xato/rad soni (rate limit?).
- **anon key** bilan (frontend qanday ishlatsa), service_role EMAS.
- Natija: N ortganda javob vaqti qanday o'sadi (chiziqli? keskin?). Supabase qachon " og'riydi".
- ⚠️ Supabase Free/Pro planда rate limit bor — unga urilса, "sekin" emas "cheklangan" — farqla.

## 3. HAJM TESTI (ko'p ma'lumot)
Test ma'lumot generatsiya (alohida test workspace'да, prod'ga tegmasin):
- Skript: test workspace yarat → 1000, 10000, 50000 vazifa qo'sh (bulk insert).
- Har hajmда asosiy so'rovlarni o'lcha: kanban yuklash, ro'yxat, filtr, qidiruv, hisobot.
- Qaysi so'rov hajm oshganда keskin sekinlashadi → o'sha ustunga **indeks** kerak.
- `explain analyze` bilan sekin so'rovni tekshir (Postgres qanday bajaryapti, indeks ishlatyaptimi).
- Natija: har so'rov · 1k · 10k · 50k vaqti · indeks kerakmi.
- ⚠️ Test tugagach test ma'lumotni TOZALA (yoki alohida test workspace o'chir). Prod aralashmasin.

## 4. XULOSA (eng muhim qism)
Test oxirida ANIQ javob:
- Sekinlik bormi? Qayerda (frontend ketma-ketlik / indeks yo'q / hajm / rate limit)?
- Har muammo uchun yechim + taxminiy vaqt:
  - Ketma-ket so'rov → parallel (`Promise.all`) — soatlar
  - Indeks yo'q → `create index` — daqiqalar
  - Ortiqcha ma'lumot → `limit`/pagination — soatlar
- **ASOSIY SAVOL**: bu muammolar frontend/SQL tuzatish bilan hal bo'ladimi, yoki chinakam backend qayta yozish (Python) kerakmi? Har biriга sabab bilan javob.
- Odatda kutiladigan xulosa: Supabase hajmni ko'taradi, sekinlik ketma-ket so'rov + indeksdan — ikkalasi ham arzon tuzatish, Python shart emas. Lekin agar test boshqacha ko'rsatsa — halol ayt.

## Tartib
1 (sahifa o'lchov — darrov, prod'da xavfsiz) → 2 (yuklama) → 3 (hajm — test ws'da). Natijalar jadval + xulosa. SQL/skript alohida faylga. Prod ma'lumot buzilmasin.
Push/RUN Asilbekda. Har test natijasini Asilbekga ko'rsat.
