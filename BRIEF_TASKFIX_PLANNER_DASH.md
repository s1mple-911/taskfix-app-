# TASKFIX — User search + Task time range + Reja ko'rish + Dashboard remake

Fayl: `index.html` (Supabase `nnpsbwsppgxbytlfloth`). 🔴 Eski buzilmasin. UI/UX Apple (ideal). SQL additive. n8n YO'Q. 🔴 i18n MAJBURIY (uz/ru/en — har yangi matn). 🔴 Emoji YO'Q — Lucide inline SVG. Push Asilbek. Katta — bosqichma-bosqich. Prod: Asilbek tasdiqlagach.

## 1. User search box — optimization (ixcham)
Hozir task create'да user search box JUDA KATTA maydon oladi. Ixcham qil.
- CC eng qulay/ixcham UI tanlasin (masalan compact dropdown — bosilsa ochiladi, qidiruv + tanlash; yoki kichik input).
- Kam joy, qulay, tez. Qidiruv (ism bo'yicha).
- 🔴 Task create formasi umuman tozaroq/ixcham bo'lsin.

## 2. Task time range → rejalashtirgichga avtomat
Task create'да muddat 3 xil (biri tanlanadi YOKI ikkalasi ham tanlanmasligi mumkin):
- **Deadline** (mavjud — sana/vaqt) — YOKI
- **Time range** (YANGI): aniq kun + soat oralig'i (masalan Dushanba 14:00–16:00).
- Ikkalasidan biri, yoki hech biri (ixtiyoriy).
- 🔴 **Time range tanlansa** → o'sha task BAJARUVCHINING rejalashtirgichiga AVTOMAT joylashadi. Ya'ni: men user X'ga task create qildim + time range (Dushanba 14:00–16:00) → user X o'z rejalashtirgichiga kirsa, o'sha task o'sha vaqtda turadi.
- Bajaruvchi o'z planner'ida ko'radi (men qo'ygan vaqt).
- ⚠️ Mavjud planner (plnGetSchedule/rejam) bilan integratsiya — task planner blokiga aylanadi.

## 3. Boshqa user rejasini ko'rish (permission)
- Admin har userga "boshqalarning rejalashtirgichini ko'rish" huquqini beradi (dynamic).
- Masalan CEO boshqa xodim ish grafigini ko'rmoqchi → admin unga ruxsat beradi.
- 🔴 Kimga ochish — WORKSPACE ADMIN hal qiladi (admin huquqi bor user).
- Ruxsat bor user → boshqa userlar planner'ini ko'ra oladi (tanlab: kimning rejasi).
- Ruxsat yo'q → faqat o'zini.
- DB: permission (masalan `can_view_others_planner` yoki workspace_members'да flag). RLS: faqat ruxsatli ko'radi.
- UI: planner'да "Kimning rejasi" tanlash (ruxsat bor bo'lsa) — o'zi + ruxsat berilganlar.

## 4. DASHBOARD — TO'LIQ REMAKE (rol-based, UI/UX boshidan) 🔴
Hozir dashboard hammada BIR XIL. Kerak: ADMIN va ODDIY USER uchun BOSHQACHA.
- **To'liq remake** — UI/UX boshidan, Apple darajа, ideal, sotувga tayyor.
- **Rol-based**:
  - **Admin**: to'liq ko'rinish — barcha vazifalar, muddati o'tgan/bugun TOTAL raqamlar, statistika, jamoa holati, hamma.
  - **Oddiy user**: SODDAROQ — 🔴 "barcha vazifalar / muddati o'tgan / bugun" TOTAL raqamlarni KO'RMAYDI (bular admin uchun). Oddiy user faqat O'ZINING vazifalari, o'z reja, o'ziga tegishli.
- CC nima qo'sha olsa — QO'SHSIN (foydali dashboard elementlari):
  - Admin: jamoa progress, top xodimlar, muddati o'tgan umumiy, loyihalar holati, statistika chart, activity.
  - User: mening bugungi tasklarim, mening rejam, mening loyihalarim, yaqin deadline (faqat o'ziniki).
- 🔴 Rol aniqlash: workspace admin huquqi (mavjud) bo'yicha. Admin → to'liq; user → soddaroq.
- Widget/karta chiroyli (Lucide, chart — Chart.js/SVG, progress). Responsive (mobil + desktop).

## DB (additive)
- Task time range: tasks'ga `plan_date, plan_start, plan_end` (nullable) — time range.
- Reja ko'rish: permission (`can_view_others_planner` yoki flag) — admin beradi.
- Dashboard: mavjud ma'lumotdan (task, project) hisoblanadi. Yangi jadval shart emas (ehtimol).
- CC eng toza sxema. RLS: reja/total faqat ruxsatli.

## Fable oqimi
coder (search ixcham, time range→planner, reja permission, dashboard rol-based mantiq), designer (search compact, dashboard REMAKE admin/user — Apple ideal, widget/chart/Lucide), tester (🔴 time range planner'ga to'g'ri, reja permission sizmaydi, dashboard rol-based — user total ko'rmaydi, RLS). 🔴 i18n uz/ru/en. 🔴 Emoji yo'q (Lucide). 🔴 Eski buzilmasin. SQL additive (men RUN). Push men. To'liq hisobot. Prod: men tasdiqlagach.

## Tartib
1 (search ixcham) → 2 (time range → planner) → 3 (reja ko'rish permission) → 4 (dashboard remake — eng katta).
Katta — bosqichma-bosqich. Dashboard (4) alohida katta ish (rol-based, UI remake). Men tasdiqlagach prodga.
