# TASKFIX — Vazifa 4 filter + 3 regression fix

Fayl: `index.html` (Supabase `nnpsbwsppgxbytlfloth`). 🔴 Eski funksiyalar buzilmasin. UI/UX Apple. SQL kerak bo'lsa additive. Push Asilbek.

## YANGI FEATURE — Rejalashtiruvchida vazifa 4 filter
Planner (rejalashtirgich) section'да vazifalar uchun 4 filter. CC eng chiroyli ko'rinishni tanlasin (tab/segment/chip — Apple darajа).

1. **Men topshirganlar** — men create qilgan tasklar (creator = men).
2. **Men qabul qiluvchiman** — men qabul qilishim kerak (acceptor = men, hali qabul qilinmagan / mening tasdiqimni kutayotgan).
3. **Men bajaruvchiman** — bajaruvchi menman (assignee = men).
4. **Bajarilganlar** — men create qilgan (topshirgan) + status='bajarildi'. Bu filter **date range** so'raydi:
   - Bosilganda date range picker chiqadi (UI CHIROYLI — Apple darajа, ikки sana yoki kalendar range).
   - Range tanlangач → aynан o'sha kunlar orasида **bajarilgan** (status bajarildi bo'lган) tasklar keladi.
   - Bajarildi sanasi bo'yicha filter (qachon bajarildi — status o'zgargan/completed_at sana range ичида).

⚠️ Faqat 4-filter (bajarilganlar) date range so'raydi. Qolgan 3 tasi DARROV (range yo'q).
⚠️ Field nomlari (creator/acceptor/assignee) — CC mavjud schema'дан aniqlasин (tasks jadvали qanday: created_by, assigned_to, acceptor...). Mavjud kodдаgi task so'rovlarини ko'риб, to'g'ри field.
⚠️ "Qabul qiluvchi" (acceptor) — TaskFix'да task qabul qilиш oqimи bор (assign → acceptor tasdiqлайди). O'sha field.

## REGRESSION FIX (oldin ishlagan, endi buzilgan) 🔴

### 1. Tarix ko'rinmayapti (task ичida)
Task ичida **tarix** (history — kim qachon nima o'zgартди) qilган edik, endi **ko'ринмайapti**. Tekshир — nega yo'qolган (render, so'rov, yoки yashiрилган). Qайtar — task ичида tarix ko'ринsін.

### 2. Boshlanish/tugash vaqti ko'rinmayapti (task ичida, planner)
Task **planner ичида** bo'lса, task ичида **boshlanish va tugash vaqti** qo'shган edik — endi **ko'ринмайapti**. Tekshир — nega yo'qolган. Qайtar — planner task'ида boshlanish/tugash vaqti ko'ринsин.

### 3. Namoz vaqtlari — refresh kerak (bir marta)
Namoz vaqtlari planner'ga **bir marta refresh berмаса qo'йилмайapti** (ko'ринмайapti). Ya'ni planner ochilганда namoz darrov chиqмайди — refresh (F5) kerak. Tuzat — planner ochilганda namoz **avtomат** chиqсин (refresh'sиз), toggle yoniq bo'lса.

## Tartib
Avval 3 regression (ishlаган narsa qайtsин — muhimroq), keyin 4 filter. Har ish alohида commit. 🔴 Eski funksiя buzилмаsин. CC avval mavjud kodни ko'риб (tarix, vaqt, namoz render), nega yo'qolганини topsін. Push Asilbek.
