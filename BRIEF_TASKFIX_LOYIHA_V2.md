# TASKFIX — Loyiha V2 (8 yaxshilanish + professional design)

Fayl: `index.html` (Supabase `nnpsbwsppgxbytlfloth`). 🔴 Eski buzilmasin. 🔴 UI/UX Apple + PROFESSIONAL task manager darajа (design qayta ko'rib chiqilsin). SQL additive. n8n YO'Q. 🔴 i18n MAJBURIY (uz/ru/en — har matn). 🔴 Emoji YO'Q — Lucide. Push Asilbek. Prod: Asilbek tasdiqlagach. KATTA — bosqichma-bosqich.

## 1. Loyiha davr + takrorlash BIRGA (yedirish)
Hozir: loyiha davri (boshlash 1 → tugash 15) VA takrorlash (har hafta dushanba) BIRGA ishlamaydi (ziddiyat — loyiha 2 haftalik deadline).
- 🔴 CC eng mantiqiy yechim TAKLIF QILSIN va izohlab bersin (Asilbek tasdiqlaydi):
  - Variant: davr = bitta sikl uzunligi (masalan 1→15 = 15 kunlik loyiha), takrorlash = qachon qaytadan boshlanadi (masalan har oy 1-kun). Ya'ni loyiha 15 kun davom etadi, keyin har oy qaytadan.
  - Yoki: tepa (davr) tanlansa — takrorlash o'sha davr bo'yicha (har 2 hafta).
- CC ikки-uch mantiqiy variant bersin, Asilbek tanlaydi. Chalkashmasin.
- Har oy tanlansa — unga ham deadline (davr) bog'lansin.

## 2. Loyiha takrorlash MULTISELECT
- Takrorlash tanlanganda ko'p tanlash:
  - **Oy** tanlansa → CALENDAR (kunlar tanlash) — o'sha kunlar loyiha qaytadan start.
  - **Hafta** tanlansa → ko'p kun (Dushanba + Chorshanba...) multiselect.
- Ya'ni takrorlash multiselect (bir necha kun/sana).

## 3. Loyiha umumiy deadline — HAMMA JOYDA ko'rinsin
- Loyihaning umumiy deadline (tugash) DOIM ko'rinsin.
- Loyiha ichida task ochguncha ham — umumiy deadline yuqorida/ko'rinarli.
- Har joyda (loyiha karta, ichида, task ro'yxati) umumiy deadline ko'rinib tursin.

## 4. Checklist (subtask o'rniga)
- "Subtask" emas — **Checklist** deb nomlanadi.
- Har checklist:
  - **Assign** qilish mumkin (kimgadir).
  - **Fayl** yuklash mumkin (checklist uchun).
  - 🔴 Checklist assign qilingan odam task'ni ko'rishi — CC eng MANTIQIY tanlasin (tavsiя: assign qilingan odam checklist bajarishi uchun butun task kontekstini ko'rishi kerak — chunki checklist task ichida ma'noga ega. Lekin faqat o'qish, task egaligiga aralashmaydi. CC eng toza/xavfsiz yo'l).
- Checklist status (bajarildi/yo'q). Task ichида ro'yxat.

## 5. Loyiha KANBAN (Reja / Fact)
- Loyiha kanban view — 🔴 CC mantiqni TO'LIQ ishlab chiqsin.
- Ustunlar (kolonnalar) turaveradi, teng o'rtadan bo'linadi: TEPA = Reja, PAST = Fact.
- Mantiq: task uchun deadline 2 kun berilgan + loyiha 2 kun oldin boshlangan bo'lsa → REJA bo'yicha u tugallangan bo'lishi kerak (reja vaqti o'tgan). Fact = haqiqatda bajarilgani.
- Ya'ni Reja = rejalashtirилган holat (vaqt bo'yicha qanday bo'lishi kerak), Fact = haqiqiy holat.
- CC bu reja/fact mantiqini aniq ishlab, izohlab bersin. Kanban chиroyли (drag, Lucide, status rang).

## 6. Loyiha takrorlash o'chirish tugmasi
- Loyiha ichига kirganда — o'ng yuqori burchakда takrorlash tugmasi bор.
- Uni O'CHIRISH kerak (kerak emas). CC topib olib tashlasin (yoki to'g'ri joyga).

## 7. Loyiha — dam olish kuni hisobga olish
- Loyiha ochguncha (yaratishда) — "dam olish kuni hisobga olinsinmi?" tugma (toggle).
- Bosilган bo'lsa → dam olish kuni hisobga olinadi: task create qilib meni tanlaganда — dam olish kunlarim chiqadi (ogohlantirish/ko'rsatish).
- Mavjud employee_schedule_days (dam olish) — o'shandan.

## 8. Loyihaga mas'ul odam
- Butun loyihaga mas'ul odam biriktirish (required EMAS — ixtiyoriy).
- Odam bo'lsa → u butun loyiha javobgar odami.
- 🔴 Uni "barcha vazifalar" bo'limiga ham chiqarish — loyihaligi bilinib tursin (loyiha belgisi).
- Progress: step ko'rsatsin — masalan "2/6" (6 tadan 2 bajarildi) yoki foiz bar.

## 9. 🔴 DESIGN — professional task manager
- Butun loyiha (project) qismi design QAYTA ko'rib chiqilsin.
- 🔴 Professional task manager darajа (Asana, Linear, ClickUp kabi) — toza, zamonaviy, ideal.
- Kartalar, kanban, checklist, progress, deadline — hammasi professional.
- Lucide, Apple typography, bo'shliq (spacing), rang tizimi. Responsive (mobil + desktop).
- designer ALOHIDA e'tibor — bu asosiy ish.

## DB (additive)
- Takrorlash multiselect: recur kunlari (jsonb array yoki alohida jadval).
- Checklist: `task_checklist` (task_id, matn, assigned_to, file_url, done, tartib).
- Loyiha mas'ul: projects'ga `responsible_id` (nullable).
- Kanban reja/fact: mavjud task ma'lumotidan hisoblanadi (deadline, start, status).
- CC eng toza sxema. RLS.

## Fable oqimi
coder (davr+takror mantiq, multiselect, checklist, kanban reja/fact, mas'ul, dam olish, DB), designer (🔴 PROFESSIONAL task manager remake — kanban, checklist, progress, deadline — Asana/Linear darajа), tester (multiselect to'g'ri, checklist assign+fayl RLS, kanban reja/fact mantiq, mas'ul progress, dam olish, emoji yo'q, i18n). 🔴 i18n uz/ru/en. 🔴 Emoji yo'q. 🔴 Eski loyiha buzilmasin. SQL additive (men RUN). Push men. To'liq hisobot. Prod: men tasdiqlagach.

## Tartib (bosqichma-bosqich)
1. Davr + takrorlash mantiq (CC taklif → Asilbek tasdiq) + multiselect.
2. Umumiy deadline (hamma joyda) + takrorlash o'chirish tugma.
3. Checklist (assign + fayl).
4. Kanban (reja/fact — CC mantiq).
5. Mas'ul odam + progress (barcha vazifalarда).
6. Dam olish hisobga olish.
7. 🔴 DESIGN remake (professional — butun loyiha qismi).
Katta — bittalab. Design (7) asosiy. 1-mantiq CC taklif qilsin, Asilbek tasdiqlaydi.
