# TASKFIX — Loyiha bosqichi: NISBIY deadline (kun soni, kalendar EMAS)

Fayl: `index.html`. 🔴 Eski buzilmasin. 🔴 i18n uz/ru/en. 🔴 Emoji yo'q — Lucide. Push Asilbek.

## ⚠️ MUAMMO (hali to'g'ri emas)
Loyiha bosqichi (prjAddTask → uiForm) deadline'да hali KALENDAR (sana tanlash) chiqyapti. Bu NOTO'G'RI.
🔴 Loyiha bosqichida deadline = KUN SONI (2 kun, 3 kun) + soat — KALENDAR EMAS.

## 1. UI — kun soni + soat (kalendar yo'q)
- Loyiha bosqichi deadline:
  - **Kun soni** tanlash (masalan 1 kun, 2 kun, 3 kun... — chip yoki input).
  - **Kun tanlansa → soat MAJBURIY** (masalan 18:00 — tezkor chip 09/12/15/18).
  - Yoki **faqat soat** (kun'siz — o'sha kuni shu soatgacha).
- 🔴 KALENDAR (sana tanlash, дд.мм.гггг) OLIB TASHLA — loyiha bosqichida sana yo'q, faqat kun soni.
- (Umumiy vazifada kalendar QOLADI — u boshqa modal.)

## 2. MANTIQ — nisbiy deadline (relative)
Loyiha bosqichi deadline = NISBIY (kun soni), absolut sana emas. Hisoblanadi:
- **Boshlanish nuqtasi**:
  - Agar task hech nimaga bog'liq emas (birinchi/mustaqil) → LOYIHA boshlanishidan.
  - Agar **ketma-ket** yoki **kutish** (boshqa taskka bog'liq) → OLDINGI task(lar) TUGAGACH counter boshlanadi.
- **Deadline** = boshlanish nuqtasi + kun soni (+ soat).
- Misol: loyiha boshlandi → 1-task "2 kun" → loyiha boshlangach 2 kundan keyin (18:00) deadline. 2-task ketma-ket "3 kun" → 1-task tugagach 3 kun.

## 3. KANBAN reja/fakt — nisbiy mantiqqa mos
- Kanban reja/fakt shu nisbiy mantiq bilan:
  - **Reja**: task 2 kun bo'lsa + boshlanish nuqtasidan 2 kun o'tган bo'lsa → REJA bo'yicha "bajarilgan bo'lishi kerak" (muddat o'tди).
  - **Fakt**: haqiqatda bajarilганmi.
- Ya'ni reja = nisbiy kun bo'yicha kutilган holat, fakt = haqiqiy.
- CC oldingi kanban mantiqini shu nisbiy deadline'ga moslasin (agar mos bo'lmasa).

## DB (additive)
- Loyiha bosqichi: kun soni (masalan `deadline_days` int) + soat (`deadline_time`) — nisbiy.
- Absolut sana (mavjud deadline) — umumiy task uchun qoladi.
- Hisoblanган absolut deadline = boshlanish + deadline_days (runtime yoki saqlangan).
- ⚠️ Boshlanish nuqtasi: loyiha start yoki oldingi task tugash — bog'liqlikка qarab. CC eng toza (dependency/ketma-ket bilan integratsiya).
- CC eng toza sxema. RLS.

## ⚠️ Bog'liqlik (dependency) bilan integratsiya
- Ketma-ket / kutish (mavjud task_dependencies) — oldingi task tugash vaqti = keyingi boshlanish.
- Deadline nisbiy shu zanjir bo'yicha hisoblanadi.
- Sikl yo'q (mavjud tekshiruv).

## Fable
coder (loyiha bosqichi: kalendar olib tashla, kun soni + soat, nisbiy deadline mantiq, dependency zanjir, kanban moslash), designer (kun soni + soat UI — kalendarsiz, professional), tester (kalendar yo'q, kun soni to'g'ri, nisbiy hisob — loyiha start / oldingi task, kanban reja/fakt nisbiy, umumiy task tegilmagan). 🔴 i18n uz/ru/en. 🔴 Emoji yo'q. Push men.

## Tartib
1. UI — kalendar olib tashla, kun soni + soat.
2. Nisbiy deadline mantiq (loyiha start / oldingi task tugash).
3. Kanban reja/fakt — nisbiy mantiqqa moslash.
🔴 Umumiy vazifa modaliga TEGMA (u kalendar/sana bilan qoladi). Faqat loyiha bosqichi.
