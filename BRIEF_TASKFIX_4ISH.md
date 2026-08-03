# TASKFIX — 4 ta ish (email sozlama + UI/UX + responsive + menu toggle)

Fayl: `index.html` (Supabase ref `nnpsbwsppgxbytlfloth`). Qoidalar: {error} doim; translateErr(); boot() oxirida; SQL additive alohida faylga; supabase-js {data,error}; RLS xavfsizlik. Push Asilbek.

---

## 1. EMAIL SOZLAMA (admin, har action toggle) — ENG MUHIM
Hozir HAR action'да email ketyapti → juda ko'p, bezovta. Admin workspace uchun qaysi action'да email ketishini toggle bilan boshqarsin.
- **Sozlamalar** sahifasида yangi "Email bildirishnomalari" bo'limi (faqat admin ko'radi/o'zgartiradi).
- Har action uchun ALOHIDA toggle (yoniq/o'chiq):
  - Task yaratildi
  - Task biriktirildi (assign)
  - Status o'zgardi
  - Izoh (comment) qo'shildi
  - Deadline yaqinlashdi/o'tdi
  - (CC boshqa mavjud email trigger'larni ham topsin — kod'да qaysi action'larда email ketyapti, hammasini toggle qil)
- Default: hozirgi holat (hammasi yoniq) yoki CC eng mantiqiy default taklif qilsin (masalan assign + deadline yoniq, qolgani o'chiq — kam bezovta).
- **Saqlash**: `workspace_settings` yoki shунга o'xshash jadval — `email_on_task_create bool, email_on_assign bool, email_on_status bool, email_on_comment bool, email_on_deadline bool` (yoki JSON `email_settings`). SQL additive.
- **Email yuboradigan joy** (Edge Function yoki n8n yoki client) — o'sha toggle'ni TEKSHIRSIN: action bo'lganда, workspace sozlamasи yoniqmi → yuborsin, o'chiqмi → yubormasin. CC email qayerдан ketyaptини topib (EF/n8n/client), o'sha joyга toggle tekshiruvини qo'shsin.
- ⚠️ Agar email n8n yoki EF'дан ketса — o'sha tomon ham sozlamani o'qishi kerak. CC arxitekturани aniqlаб, to'liq zanjirни (UI toggle → DB → email yuboruvchi) ulasин.
- Admin toggle o'chirса — o'sha action'да email BUTUNLAY ketмаsин.

## 2. UI/UX + IKONKALAR (senior Apple designer sifatida)
Ikonkалар juda sodda qolган. CC o'zини **senior UI/UX designer at Apple** deb hisoblаб, butun ilova ko'rinишини takomillashtirsin:
- **Ikonkalar**: sodda/eski ikonkаларни zamonaviy, aniq, izchil ikonка to'plami bilan almashtир (masalan lucide, heroicons — bittа to'plam, izchil). Har tugma/menu/action uchun mos ikonка.
- **Umumiy sayqal**: bo'shliq (spacing), tekislik (alignment), rang izchilligi, soyalar, burchak radiusi — Apple-darajа toza, minimalist, professional.
- Aros brend ranglarини saqla (agar bор bo'lса), lekin zamonaviy qil.
- ⚠️ Faqат VIZUAL — funksiya buzилмаsин. Har o'zgаришdан keyin ilova ishlаyaptими tekshir.
- Katta ish — bosqichma-bosqich (avval ikonка to'plami, keyin spacing/rang). Har bosqич alohida commit.

## 3. RESPONSIVE — kichik ekran (kompyuter)
Kichik ekranli kompyuterlarда TaskFix yarми ko'ринмайди — scroll bilan surib ko'ришга majbur. Tuzat:
- Layout kichik ekranга (masalan 1280px, 1366px, 1024px) moslashsин — kontent kesилmasин, gorizontal scroll bo'lмаsин.
- Kanban, ro'yxat, jadval, modal — hammаси kichik ekranда to'liq ko'ринsин yoки to'g'ри qisqаrsин (responsive).
- Zarur bo'lса: kolonkалар torайsин, shrift moslаshsин, panel yig'илsин.
- Sinash: 1024px, 1280px, 1366px, 1920px — hammаsида to'g'ри.

## 4. CHAP MENU — ochib/yopish (collapse)
Chap menu (sidebar) ochib/yopиладиган bo'lsин:
- Tugма (masalan ☰ yoки ‹ ›) bilan sidebar yig'иладi/ochилади.
- Yig'илганда: faqат ikonка (matnsиz) yoки butunlай yashиrиn — kontentга ko'proq joy.
- Ochилganда: to'liq (ikonка + matn).
- Holat eslаб qolinsин (localStorage — user preferences) — keyin ochганда o'sha holатда.
- Bu 3-ish (responsive) bilan bog'liq: kichik ekranда sidebar avtomат yig'илса yaxshi.

---

## Tartib
4 (menu toggle — eng oson) → 3 (responsive) → 1 (email — eng muhim, backend bilan) → 2 (UI/UX — eng katta, bosqichma-bosqich).
Yoki 1 (email — eng muhim/qiyin) birinchi bo'lса ham bo'ladi — Asilbek "1-o'rinда email" dedi. CC boshlashни o'zi tanlаб, lekin email'ni ustuvor qilsин.
Har ish alohида commit. Email uchun SQL → `TASKFIX_EMAIL_SETTINGS.sql`. Push men qиламan.
