# TASKFIX — 4 ish (task ismlar + deadline + counter + i18n 3 til)

Fayl: `index.html` (Supabase `nnpsbwsppgxbytlfloth`). 🔴 Eski buzilmasin. UI/UX Apple. SQL additive. n8n YO'Q (mustaqil). Push Asilbek. Katta ish (ayniqsa 4) — bosqichma-bosqich.

## 1. Task description — 3 ism ketma-ket
Task detalида (description ostида yoki tepasида) DOIM 3 qator ketma-ket:
- **Yaratgan odam:** [ism]
- **Bajaruvchi:** [ism]
- **Qabul qiluvchi:** [ism]
- ⚠️ Agar qabul qiluvchi belgилаnmagan → "Qabul qiluvchi" qatorini UMUMAN yozma (bo'sh emas — yo'q).
- Ketма-ket, toza (designer chиroyли). Ism-familiya (mavjud profiles).

## 2. Deadline + yaratilgan vaqt — tartib + rejam + deadline tarixi
Hozir chalkash: tepada deadline, pastda yaratilgan — aralash. Tartibga sol:
- **Tepada: Yaratilgan vaqt** (qachon yaratildi).
- **Pastda: Deadline** (muddat).
- **Rejam qatori**: agar task rejalashtirgichда (planner) bo'lsa — "⏱ 09:00–10:30" ko'rinsin. Agar rejada YO'Q bo'lsa — "Rejaga qo'shish" tugma → bosilса rejalashtirgichга olib boradi (o'sha task bilan).
- **Deadline tarixi** 🔴: deadline SURILSA (o'zgartirilса) — eski deadline SAQLANSIN. Task ochilганда deadline qatorida eski→yangi ko'rinsin. Masalan: "21:07 14.08 → 21:07 15.08" (eski deadline → yangi). Har surish qo'shiladi (tarix).
- SQL: deadline o'zgarishlarини saqlash (masalan `task_deadline_history` yoki tasks'да `deadline_history jsonb`). CC eng toza.
- ⚠️ designer bu qismни chиroyли qilsин (deadline tarixi, rejam, tartib).

## 3. Task ko'rish counter (👁 + son)
- Task bajaruvchи taskни necha marta OCHIB ko'rgani — pastда ko'zcha (👁) + son.
- 🔴 FAQAT bajaruvchи ochgani hisoblanadi (boshqа odam — yaratgan, qabul qiluvchi — hisoblanмайди).
- Har bajaruvchи task detalини ochганда → son +1.
- SQL: `task_views` (task_id, viewer_id, count) yoki tasks'да `bajaruvchi_view_count`. Faqat bajaruvchи (assigned_to = viewer) ochganда sanaydi.
- UI: 👁 5 (pastда, kичик).

## 4. i18n — UZ / RU / EN (3 til) 🔴 KATTA
Butun TaskFix 3 tilда: O'zbek (uz), Rus (ru), Ingliz (en).
- **Hamma sozни** (tugma, sarlavha, label, xabar, menu...) 3 tilга tarjima qil.
- **JSON fayl**: `i18n.json` (yoki uz.json/ru.json/en.json) — har so'z uch tilда. Masalan `{"task_new": {"uz":"Yangi vazifa","ru":"Новая задача","en":"New task"}}`.
- **Menга JSON fayl ber** — men hamma so'zni ko'rib, tasdiqlаyman. Tasdiqласам → deploy. Keyingi ishlarда yangi so'zни o'zим qo'лда uch tilда yozaman.
- **Til tanlash — Sozlamalar (Settings)**: hozir profil'да (yoки boshqа joyда) bo'lса — Sozlamalarга ko'chир. Bitta joyда. Til tanlansa — butun ilova o'sha tilда (saqlanади, keyin ochганда o'sha til).
- **Texnik**: t('key') funksiya yoki data-i18n atribut. Til o'zgарса — hamma matn yangилanadi (reload'сиз yaxshi). Default: uz.
- ⚠️ CC hamma matnни (hardcoded o'zbekcha) topиб, i18n key'ga aylantирsін. Katta ish — sinchkovlik. Sana/son formati ham (ru/en).
- ⚠️ AI-generated content (task nomi, izoh — user yozган) tarjima QILINMAYDI — faqат UI (interfeys) so'zlari.

## Tartib
1 (3 ism) → 2 (deadline tartib + tarix + rejam) → 3 (counter 👁) → 4 (i18n — eng katta, oxирда).
Fable oqimi: coder (kod, SQL, i18n key), designer (3 ism, deadline tarixi, rejam, counter — chиroyли), tester (deadline tarix to'g'ри, counter faqат bajaruvchи, i18n hamma matn qamrаб olindiми, til almashadими). 🔴 Eski buzilmasin. SQL additive (men RUN). n8n YO'Q. Push men.
i18n uchun: CC avval hamma so'zni JSON'ga yig'sin → menга ber (tasdiqlаyman) → keyin ulasin. Katta — bosqichма-bosqич.
