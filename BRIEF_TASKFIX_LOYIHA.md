# TASKFIX — Loyiha tizimi (6 katta ish) + autosave

Fayl: `index.html` (Supabase `nnpsbwsppgxbytlfloth`). 🔴 Eski funksiyalar buzilmasin. UI/UX Apple. SQL additive → `TASKFIX_LOYIHA.sql`. Push Asilbek. Katta ish — bosqichma-bosqich, har qadam alohida commit.

## 1. AUTOSAVE — har harakat eslab qolinsin (yozayotgani yo'qolmasin) 🔴
Muammo: user katta task yozayotganда tasodifan tugma bossa — hammasi uchib ketadi. Oldini ol:
- Task yaratish/tahrir formasi (title, tavsif, izoh) — **har o'zgarishда avtomат saqlansин** (draft) — localStorage yoki DB.
- Modal yopilса / tasodifan bosilса / sahifa yangilanса — draft qoladi, qайta ochганда tiklanади ("Saqlanмаган qoralaмa bор — tiklaysizmi?").
- Yuborilгач (submit) — draft tozalanadi.
- Har muhim forma (task, loyiha, izoh) shундай. Debounce (300-500ms) bilan — har harf emas, to'xtаганда.
- ⚠️ Bu ENG muhим (1-o'rinда) — ma'lumot yo'qolишi jiddiy.

## 2. LOYIHA — deadline, status, recursive, tarix
Loyiha bo'limида loyihалар uchun:
- **Boshlash va tugash** (date + soat) — loyihага alohида.
- **Loyiha ичидаги tasklar** loyiha boshlanганда boshlanади (loyiha vaqtига bog'liq).
- **Recursive loyiha** — takrorlanади (CC moslashuvchan: kunlik/haftalik/oylik tanlanади). Har takror boshlanish vaqtида: loyiha **qайta ochилади**, tasklar **qайta yaratилади/assign** bo'ladi.
- **4 status**: `upcoming` (hali boshlanмаган), `active` (davom etyapti), `ended` (tugаган), `overdue` (muddat o'tди, tugамаган). Avtomат (sana/vaqt bo'yicha).
- **Tarix** — tugаган (ended) loyihалар tarixда saqlanади (ko'риш uchun, o'chмайди).
- SQL: `projects` ga `start_at, end_at, recur_type (none/daily/weekly/monthly), recur_parent_id, status`. Recursive uchun cron yoki loyiha ochилganда tekshiruv (client yoki Edge Function — n8n MINIMAL, iloji bo'lса client/Supabase).

## 3. Loyihани assignee ko'ra olsин
Loyiha ичидаги tasklar kimga assign qilинган bo'lса — o'sha odamlar **loyihani to'liq ko'ра olishي** kerak (loyiha detali, boshqа tasklар). Hozir ehtimol faqат a'zо ko'ради — assignee ham ko'рsин. RLS: loyiha ичida menга assign qilинган task bор bo'lса → loyihани ko'raman.

## 4. Deadline dam olish kuniga tushsa — ogohlantirish
Loyihада (yoки taskда) hodimга deadline belgиланганда:
- O'sha hodim **dam olish kuni** (masalan yakshanba) ga tushса — **ogohlantirish** (belgi/rang, masalan sariq/qizил "dam olish kuni"). Lekin deadline **qoladi** (avtomат surилмайди).
- Dam olish kuni **Aros-staff dump'дан** olinади (jamoада allaqачon yuklаган — profiles yoki staff jadvалida ish/dam kunlari bор). CC o'sha maydonни topsін (masalan `work_days`, `day_off`, yoки Aros dump'даги tegishли ustun).
- ⚠️ CC avval Aros-staff dump'даги dam olish ma'lumotини (qaysi jadval/ustun) topsін, keyin ishlatsін.

## 5. Loyiha ичida tasklar VISUAL detail
Loyiha ичида tasklar **detail ko'ринsін** (chиroyли, batafsil) — hozir ehtimol oddiy ro'yxat. Vizual: har task kartаsи — status rang, assignee avatar, deadline, progress. Apple darajа.

## 6. Loyiha bo'limида loyihалар VISUAL detail
Loyiha bo'limида loyihалар ham **visual detailed** — har loyiha kartаsи: status (upcoming/active/ended/overdue rang), boshlash/tugash, tasklar soni, progress bar, assignee'lар. Chиroyли dashboard ko'риниши.

## Tartib
1 (autosave — eng muhим, ma'lumot yo'qolмаsин) → 2 (loyiha DB: deadline/status/recursive/tarix) → 3 (assignee ko'ради) → 4 (dam olish ogohlantirish — Aros dump'дан) → 5 (task visual) → 6 (loyiha visual).
Har ish alohида commit. 🔴 Eski (task/kanban/HR/namoz) buzилмаsін. SQL additive. n8n MINIMAL (recursive uchun client/Edge Function afzal). CC avval mavjud loyiha (projects) kodini va Aros-staff dump'ни ko'рсин. Push Asilbek.
