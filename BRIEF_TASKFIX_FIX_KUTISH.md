# TASKFIX — 3 fix + 4 yangi (deadline kun/soat + Kutish dependency)

Fayl: `index.html` (Supabase `nnpsbwsppgxbytlfloth`). 🔴 Eski buzilmasin. 🔴 UI/UX Apple + professional. SQL additive. n8n YO'Q. 🔴 i18n uz/ru/en (har matn). 🔴 Emoji YO'Q — Lucide. Push Asilbek. Prod: tasdiqlagach.

## FIX 1 — Ko'ruvchi counter yo'qolgan
- Task ichига kirган ko'ruvchи counter (bajaruvchи necha marta ko'рди) YO'QOLGAN.
- 🔴 Fix: bajaruvchи task'ни necha marta ochгани (👁 → Lucide eye + son) qайta ishlasин. FAQAT bajaruvchи (assigned_to) hisoblanadi (oldingi mantiq). Regressiya bo'lган — tikла.

## FIX 2 — Loyiha yaratish modali suriladi (scroll yo'q)
- Loyiha yaratish modali pastга surилиб ketyapti, "Saqlash" tugмаsига yetиб bo'lмайапти.
- 🔴 Fix: modalга SCROLL qo'sh (ichи scroll bo'lsин, Saqlash tugмаsи doim ko'ринsін / yetsин). Mobil + desktop.

## FIX 3 — Qabul qiluvchi tanlashда search
- Task create → qo'shимча → "qabul qiluvchи" tanlashда SEARCH yo'q.
- 🔴 Fix: qabul qiluvchи tanlашга qidiruv qo'sh (ism bo'yicha), user search kabi ixcham.

## YANGI 1 — Loyiha deadline task yaratguncha ko'rinsin
- Loyiha ichида task ochгунча ham — loyiha DEADLINE ko'ринsін.
- Ya'ni loyiha ichида (task yaratиш paytида ham) umumiy deadline yuqorида/ko'ринарли.
- (Oldingi "umumiy deadline hamma joyда" bilan bog'liq — task yaratиш modalида ham ko'рsін.)

## YANGI 2 — Task deadline: kun YOKI soat (sana emas)
Hozir deadline sana bilan. Endi kun/soat:
- **Kun tanlansa** → SOAT ham required (masalan "2 kun" → tugash sanasi hisoblanади + soat, masalan 16:00). Pastдан izoh: "Shu sanada tugашi kerak" + soat tanlanadi.
- **Soat o'zини tanlash** ham mumkín (bunda kun required EMAS) — faqат soat.
- Ya'ni: kun → soat majburiy; yoki faqат soat (kun'сиз).
- CC mantiqни toza qilsин: kun (necha kun) → tugash sana avtomат + soat. Yoki faqат soat (bugun shu soatgача).
- ⚠️ Mavjud deadline (sana) bilan integratsiya — buzилмаsін, yangi rejim qo'shilsин.

## YANGI 3 — "Kutish" funksiyasi (dependency) + 3 tur birlashish
🔴 Eng muhim/murakkab. Hozir task ichида "ketma-ket" va "parallel" toggle bор. Endi 3-tur: "Kutish".
- **Kutish**: task create/edit'да "Kutish" tanlanса → o'zидан TEPADA turган barcha tasklar chиqади (multiselect). Qайси tick qилинса → o'sha tasklar BAJARILGUNCHA bu task OCHILMAYDI (kutади, bloklangan).
- Ya'ni: bu task tanlanган tasklarга BOG'LIQ (dependency) — ular bajarилса, bu ochилади.
- 🔴 3 tur birlashsin (CC eng toza mantiq):
  - **Ketma-ket** (sequential) — navbat bilan.
  - **Parallel** — barchаsи birga.
  - **Kutish** (dependency) — tanlangан tasklar bajarилса ochилади.
  - CC bularни bitta toza mantiqга keltirsин (masalan tur tanlash: ketma-ket / parallel / kutish — radio yoki dropdown). Hozirgi toggle o'rniga 3-holatli.
- ⚠️ Kutish "tepадаги tasklar" — loyiha/ro'yxat kontekstида yuqorида turган tasklar. CC aniqласин (loyiha ichидами yoки umumiy).
- DB: task dependency (`task_depends_on` — task_id, depends_on_task_id) yoki jsonb. Kutayotgan task bloklangan (ochilmaydi) tanlanganlар bajarилгунча.
- 🔴 Sikl (loop) bo'lмаsлиги — A kutади B, B kutади A → xato. CC tekshirsин.

## DB (additive)
- Deadline kun/soat: tasks'ga kerakli ustun (masalan deadline_days, deadline_time yoki mavjud deadline'ni kengaytirish).
- Kutish: `task_dependencies` (task_id, depends_on_id) yoki jsonb. RLS.
- Counter fix: mavjud (regressiya — tikla).
- CC eng toza sxema.

## Fable oqimi
coder (counter fix, modal scroll, qabul search, loyiha deadline, deadline kun/soat, Kutish dependency + 3 tur mantiq), designer (modal scroll, search, deadline kun/soat UI, 3-tur tanlash — professional), tester (🔴 counter faqat bajaruvchi, Kutish dependency to'g'ri + sikl yo'q, deadline kun/soat mantiq, RLS, emoji yo'q, i18n). 🔴 i18n uz/ru/en. 🔴 Eski buzilmasin. SQL additive (men RUN). Push men. Hisobot. Prod: men tasdiqlagach.

## Tartib
1. FIX (counter, modal scroll, qabul search) — tez.
2. Loyiha deadline (task yaratguncha).
3. Deadline kun/soat.
4. 🔴 Kutish (dependency) + 3 tur birlashish — eng murakkab, oxirida.
Kutish (dependency) katta — sikl tekshiruvi, bloklangan holat. CC toza mantiq.
