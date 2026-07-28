# TASKFIX — Universal global search (tepadagi umumiy qidiruv)

Fayl: `index.html`. Tepada (header) umumiy qidiruv maydoni bor — bir necha marta so'ralган, lekin to'liq ishlamayapti. Bu safar: AVVAL audit (nima bor, nega ishlamaydi), KEYIN to'liq ishlaydigan universal search.

Prod ishlab turibdi (real mijozlar). Qoidalar: `{error}` doim tekshirilsin; `translateErr()`; `boot()` modul oxirida; sintaksis validatsiya; `isArosWs()` bilan Aros'ga xoslar; SQL kerak bo'lsa additive alohida faylga.

---

## 1. AVVAL AUDIT
Tepadagi mavjud search maydonini top va tushuntir:
- Qayerda (element id, qaysi funksiya)?
- Hozir nima qidiradi (yoki umuman ulanмaganmi)?
- Nega ishlamaydi — event ulanmagan / natija ko'rsatilmaydi / faqat bitta narsa qidiradi / boshqa sabab?
Auditni qisqa yoz, keyin tuzatishga o't.

## 2. UNIVERSAL SEARCH — nima qidiriladi
Bitta qidiruv maydoni butun TaskFix bo'ylab qidirsin. Manbalar (workspace ichida, RLS bo'yicha ko'rinadigan):

- **Xodimlar** — ism, familiya (full_name), email, telefon (profiles + workspace_members). Natijada: avatar, ism, lavozim/filial, email/telefon.
- **Vazifalar (tasks)** — nom, tavsif. Natijada: vazifa nomi, status, bajaruvchi, deadline, qaysi bo'lim/loyiha.
- **Loyihalar (projects)** — nom, tavsif. Natijada: loyiha nomi, tur, progress.
- **Bo'limlar (departments)** — nom. Natijada: bo'lim nomi, a'zolar soni.
- **Filiallar (branches)** — nom (agar workspace'da filiallar bo'lsa). 
- **Lavozimlar (positions)** — nom (agar mavjud bo'lsa).
- Boshqa mavjud entity'lar bo'lsa (izohlar? fayllar nomi?) — o'zing aniqla va qo'sh (audit paytida ro'yxat chiqar).

Har manba workspace'ga tegishli bo'lsin (`workspace_id` filtri yoki RLS) — boshqa mijoz ma'lumoti chiqmasin.

## 3. QANDAY ISHLASIN (UX — senior daraja)
- **Jonli qidiruv**: yozgan sari natijalar (debounce ~200-300ms). Kamida 2 belgidan boshlab.
- **Guruhlangan natijalar**: "Xodimlar (3)", "Vazifalar (12)", "Loyihalar (2)", "Bo'limlar (1)" — bo'limlarga ajratilgan dropdown/panel. Har guruhda eng ko'pi 5 ta, "yana N ta" bilan.
- **Har natija bosilsa** — tegishli joyga o'tsin:
  - Xodim → jamoa/xodim profili (yoki modal)
  - Vazifa → vazifa detali (openDetail)
  - Loyiha → loyiha sahifasi
  - Bo'lim → bo'lim detali
- **Klaviatura**: ↑↓ bilan natijalar orasida yurish, Enter — ochish, Esc — yopish. (⌘K / Ctrl+K bilan ochilsa zo'r bo'ladi — mavjud bo'lsa qoldir, yo'q bo'lsa qo'sh.)
- **Bo'sh holat**: "Hech narsa topilmadi" (aniq, do'stona).
- **Yuklanish**: qidiruv davomida kichik spinner/skeleton.
- **Highlight**: topilgan matnda qidiruv so'zi ajratib ko'rsatilsin (bold/rang).
- **Mobil**: qidiruv to'liq ekran yoki katta panel — telefonда qulay.

## 4. TEXNIK
- Qidiruv klient tomonда keshlangan ma'lumotdan (tez) YOKI Supabase so'rovi bilan (ilike). Katta workspace'да server qidiruv yaxshiroq — `ilike '%term%'` bir necha jadvalga. O'zing hal qil: agar ma'lumot allaqachon keshда bo'lsa (tasksCache, membersCache) — klientда filtrla (darrov); bo'lmasa server so'rovi.
- Bir necha jadvalga qidiruv: parallel `Promise.all` (ketma-ket emas — tez bo'lsin).
- Har so'rov `{error}` tekshirilsin; biri yiqilsa boshqalari ko'rinsin (butun search yiqilmasin).
- Telefon qidiruvда: raqamlarni normallashtir (masalan +998, probel, qavs — hammasini olib tashlab solishtir), aks holda "998 90" topilmaydi.
- Debounce + eski so'rovni bekor qilish (yangi harf yozilsa oldingi natija kelib chalkashtirmasin).

## 5. AUDIT NATIJASI
Oxirida ayt:
- Mavjud search nima edi, nega ishlamаган.
- Endi qaysi manbalar qidiriladi (ro'yxat).
- Qanday sinash: har manbага misol (xodim ismi, vazifa nomi, telefon raqami, loyiha nomi).

## Tartib
Audit → universal search qurish. Bitta yaxlit ish, lekin audit qismini alohida yoz. SQL kerak bo'lsa (masalan qidiruv indeksi) alohida faylga. Push Asilbekda.
