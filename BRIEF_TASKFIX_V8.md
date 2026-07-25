# TASKFIX — bajaruvchi ismi + xodim bo'yicha filter

Fayl: `index.html` (yagona fayl). Prod ishlab turibdi — real mijozlar bor (Aros + tashqi kompaniyalar).

Qoidalar:
- Supabase `{ error }` doim tekshirilsin; muvaffaqiyat xabari faqat haqiqatan muvaffaqiyatli bo'lganda (CLAUDE.md 6-qoida).
- Xatolar `translateErr()` orqali, o'zbekcha.
- Aros'ga xos narsalar boshqa mijozga ko'rinmasin (`isArosWs()` naqshi).
- Har o'zgarishdan keyin sintaksis validatsiya.
- `boot()`/init modul oxirida (TDZ).

---

## 1. Vazifada "kim bajardi" ko'rinsin
Hozirgi oqim: qabul qiluvchi (`acceptor_id`) bo'lgan vazifada bajaruvchi "Bajarildi" qiladi → vazifa qabul qiluvchiga o'tadi, status **kutilmoqda**. Bu oqim to'g'ri ishlayapti, **o'zgartirilmaydi**.

Muammo: qabul qiluvchi vazifani ochganda **kim bajarganini ko'rmaydi**.

Kerak:
- Vazifa detal ko'rinishida (modal/panel) aniq joyda: **"Bajardi: {to'liq ism}"** + bajarilgan vaqt (masalan "Bajardi: Kamola Shoniyozova · 23.07.2026 14:32").
- Ism manbai: vazifani bajarilgan deb belgilagan foydalanuvchi (`assigned_to` yoki holat o'zgartirgan kishi — mavjud maydonlardan qaysi biri to'g'ri bo'lsa, tekshirib aniqla; agar hech biri saqlanmasa — yangi ustun qo'sh: `tasks.bajardi_user_id uuid`, `tasks.bajardi_at timestamptz`, "Bajarildi" bosilganda to'ldiriladi. SQL additive, alohida faylga).
- Ism `profiles.full_name` dan; bo'sh bo'lsa email yoki "Noma'lum".
- Qabul qiluvchi uchun ko'zga tashlanadigan joyda bo'lsin (statusga yaqin) — u shu asosda qabul/rad qaror qiladi.
- Kanban/list kartochkasida ham kichik ko'rsatkich bo'lsa yaxshi (avatar yoki ism) — agar joy bo'lsa.

## 2. Xodim bo'yicha filter — hamma ko'rinishlarda
Hozir xodim bo'yicha filtrlab bo'lmaydi.

Kerak: **"Xodim"** filtri qo'shilsin va **barcha ko'rinishlarda** ishlasin:
- Kanban
- Ro'yxat (list)
- Kalendar / jurnal / boshqa mavjud ko'rinishlar (qaysilari bo'lsa — hammasi)

Talablar:
- Tanlagich: xodim ro'yxati (workspace a'zolari), avatar + to'liq ism, qidiruv bilan (ko'p xodimda kerak).
- "Barcha xodimlar" — default.
- **Bir nechta xodim** tanlash mumkin bo'lsin (multiselect) — bo'lim boshlig'i o'z jamoasini ko'rmoqchi bo'ladi.
- Filtr nimaga tegishli: `assigned_to` (bajaruvchi). Agar qabul qiluvchi bo'yicha ham kerak bo'lsa — kichik tanlov qo'sh ("Bajaruvchi / Qabul qiluvchi / Ikkalasi"), o'zing sodda variantni tanla va izohla.
- **Tanlangan filtr ko'rinishlar orasida saqlansin** (kanban→list o'tganda yo'qolmasin) va sahifa yangilanganda ham (URL hash yoki sessionStorage — mavjud naqshga mos).
- Mavjud filtrlar (loyiha, status, sana va h.k.) bilan birga ishlasin — biri ikkinchisini bekor qilmasin.
- Faol filtr ko'rinib tursin (chip: "Kamola ×") va bir bosishda tozalash mumkin.
- Bo'sh natija: "Bu xodimda vazifa yo'q" + filtrni tozalash tugmasi.

## 3. UI/UX
Ikkala ish ham senior darajada: mobil-first, aniq matnlar, bo'sh/xato holatlari ko'rinadi, hech qayerda qotib qolmaydi.

## Tartib
1 (kim bajardi — kichik) → 2 (xodim filtri). Har biri alohida commit. SQL kerak bo'lsa alohida faylga (`TASKFIX_V8.sql`), Asilbek RUN qiladi.

Oxirida: o'zgargan joylar + sinov ssenariysi.
