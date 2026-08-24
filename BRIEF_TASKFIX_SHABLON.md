# TASKFIX — Loyiha task = SHABLON + kanban sikl filter + taxminiy deadline

Fayl: `index.html`. 🔴 Eski buzilmasin. 🔴 UI/UX Apple professional. 🔴 i18n uz/ru/en. 🔴 Emoji yo'q — Lucide. SQL additive. Push Asilbek. Prod: tasdiqlagach. KATTA (ayniqsa 1) — bosqichma-bosqich.

## 1. Loyiha task = SHABLON (konseptual) 🔴 KATTA
Loyiha ichida task create qilinsa — u TASK EMAS, u SHABLON (task yaratadigan shablon).
- **Logic**:
  1. Loyiha ichidagi har bir "task" = SHABLON (task emas).
  2. Shablon vaqti kelganda (loyiha start / recur sikl) → HAQIQIY task ochiladi (shablondan).
  3. Shablon ustiga bosilганда → TARIX ko'rinadi (bu task tarixi EMAS): shablon qachon ochildi, necha marta task ochirgan, nimalari o'zgardi (shablon tahriri) — shablon meta-tarixi.
- **UI farqi**: shablon oddiy vazifadan FARQ qilsin (ko'rinish, belgi, rang) — bu shablon ekani bilinsin (task emas).
- Oddiy vazifa (loyihasiz) — task (o'zgarmaydi).
- ⚠️ Bu mavjud loyiha bosqich tizimini shablon deb qayta nomlash + shablon→task materializatsiya + shablon tarixi. CC mavjud recur/loyiha mantiqini shunga moslasin (loyiha start / recur sikl → shablondan task).
- ⚠️ CC ehtiyot: mavjud loyiha tasklar buzilmasin — konsept aniq (shablon = reja, task = haqiqiy bajariladigan).

## 2. Kanban — sikl filter (eski/tugallangan)
- Kanban view'да eski/tugallangan sikllarni ko'rish uchun FILTER.
- Loyiha boshlash+tugash vaqti bor (har loyiha kanbani har xil). Recur bo'lsa har sikl alohida.
- Filter: har sikl davri bo'yicha (masalan loyiha 1-5 har oy → filter "1-5 09.2026", "1-5 10.2026"...).
- Filter tanlanганда → O'SHA PAYTDA (o'sha sikl) qilingan loyihaning REJA va FAKT'i ko'rinadi (o'sha davr holati).
- Ya'ni tarixiy sikllarni ko'rish (o'tган oy qanday bo'lган — reja/fakt).
- CC eng qulay filter UI (sikl ro'yxati / sana oralig'i).

## 3. Bajaruvchisiz task create BO'LMASIN
- 🔴 Bajaruvchi (assigned_to) tanlanmasa — task/shablon CREATE bo'lmasin.
- Loyihada ham, boshqa joyda (oddiy vazifa) ham — bajaruvchi majburiy.
- Validatsiya: bajaruvchi yo'q → saqlanmaydi (aniq xabar, uz/ru/en).

## 4. Ketma-ket — taxminiy deadline UI
- Hozir ketma-ket: 2-vazifa deadline 1-vazifaga bog'liq (1 tugagach 2 boshlanadi, counter ketadi).
- 🔴 UI o'zgartir: TAXMINIY deadline ko'rsatsin — 1-vazifa deadline'дan hisoblab, 2-chining TAXMINIY tugash sanasi ko'rinsin.
- Ya'ni user ketma-ket zanjirда har vazifaning taxminiy tugash sanasini oldindan ko'radi (1-chidan hisoblanган).
- "Taxminiy" ekani bilinsin (haqiqiy emas, 1-chi tugашiga bog'liq — o'zgarishi mumkin).
- CC UI'ni to'g'ri qilsin: zanjir bo'yicha taxminiy sanalar (masalan "~15.09 (taxminiy)").

## DB (additive)
- Shablon: mavjud loyiha bosqich jadvalини shablon sifatida (yoki flag is_template). Shablon→task materializatsiya. Shablon tarixi (`template_history`: ochildi, task_id, o'zgarishlar).
- Kanban sikl filter: recur sikl ma'lumotidan (davr).
- Bajaruvchi majburiy: validatsiya (kod + kerak bo'lsa DB NOT NULL yoki CHECK — ehtiyot, eski buzilmasin).
- Taxminiy deadline: hisoblanган (nisbiy zanjir — mavjud rdl*).
- CC eng toza sxema. RLS.

## Fable oqimi
coder (shablon konsept + materializatsiya + tarix, kanban sikl filter, bajaruvchi majburiy, taxminiy deadline UI), designer (shablon UI farqi, kanban filter, taxminiy sana — professional), tester (🔴 shablon vs task aniq, shablon tarixi to'g'ri, kanban sikl reja/fakt, bajaruvchisiz bloklandi, taxminiy hisob, eski loyiha buzilmagan). 🔴 i18n. 🔴 Emoji yo'q. SQL additive (men RUN). Push men. Hisobot. Prod: men tasdiqlagach.

## Tartib
1. Bajaruvchi majburiy (tez) + taxminiy deadline UI (ketma-ket).
2. Kanban sikl filter.
3. 🔴 Shablon konsept (eng katta — loyiha task = shablon, materializatsiya, tarix).
Shablon (1) eng katta/murakkab — konseptual. CC ehtiyot (eski buzilmasin), izohlab bersin.
