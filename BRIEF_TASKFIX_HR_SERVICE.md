# TASKFIX — HR Service + Org Schema (yangi katta feature)

Fayl: `index.html` (Supabase ref `nnpsbwsppgxbytlfloth`). 
🔴 ENG MUHIM: mavjud funksiyalar BUZILMASIN (task, project, kanban, email, jamoa — hammasi ishlashda davom etsin). UI/UX Apple-darajа chiroyli. Qoidalar: {error} doim; translateErr(); boot() oxirida; SQL additive alohida faylga; supabase-js {data,error}; RLS xavfsizlik; Aros ranglar.

---

## 1. Integratsiyalar → "Qo'shimcha service" (nomini o'zgartir)
- Chap menu / bo'limда "Integratsiyalar" nomi → **"Qo'shimcha service"** ga o'zgartir.
- Faqat NOM o'zgaradi, ичидаги (Telegram va h.k.) qoladi.

## 2. Yangi service: HR Service
- "Qo'shimcha service" ичида (Telegram yonида) yangi **HR Service** karta/element.
- Icon + rasm to'g'ri qo'yilsin (HR ga mos — masalan odamlar/tashkilot ikonкаsи, Lucide). Chiroyli, izchil.
- HR Service yoqilса (Telegram yoqilгани kabi) → chap menuda YANGI SECTION paydo bo'ladi (xuddi Telegram section kabi).

## 3. Chap menuda HR section (Telegram naqshida)
- HR Service yoqilгач, chap menuда yangi **"HR"** section (Telegram section qanday qo'shilса, xuddi shундай naqsh — o'sha kodni namuna qil).
- HR section ичида **subsection**: **"Org Schema"** (tashkiliy tuzilma).
- Kelajakда boshqа HR subsection qo'shилиши mumkín — kengaytiriladigan qil.

## 4. Eski "Jamoa ичидаги tashkilot" — vaqtincha yashir
- Hozir Jamoa (Team) ичида tashkilot/org joyи bор — u endi HR'ga ko'chdi.
- Uni **vaqtincha yashir** (o'chirма — comment yoки flag bilan yashir, keyin kerak bo'lса qайtarаmiz).
- Jamoa qolган qismи (a'zolар ro'yxати, rollar) ishlashda davom etsin.

## 5. Org Schema — asosий feature (papka + hodimlar daraxti)
Org Schema — tashkiliy tuzilma. Papkалар (bo'limlар) daraxti, ичida hodimlar, kim kimga bo'ysunади.

### Papka
- **Ikки manba**: (a) mavjud bo'limlар (departments) — avtomат ko'ринади; (b) yangi papka — HR o'zi yaratadi (departmentга bog'liq emas).
- Papka ичида **papka** bo'la oladi (daraxt — cheksиz yoки chuqur).
- Papka daraxti: papka boysunади papkага (parent-child).

### Hodimlar
- Har papka ичiga hodim qo'shиладi.
- Papka ичидаги hodimlar **o'zидан tepадagiga bo'ysunади** (daraxt bo'yicha — ierarxия).
- Bir hodim qaйsi papkаda + kimga bo'ysunишi ko'ринади.

### Ikки VIEW (bir xil ma'lumot, bir xil ishlaydi)
- **View 1 — Papka ko'rinishи** (fayl menejer kabi): papkалар ro'yxати/daraxti, ичiga kириб hodim qo'shиш.
- **View 2 — Org Chart (vizual)**: tashkiliy sxema (kim kimga bo'ysunади — vizual daraxt, chiroyli org chart).
- 🔴 **IKKALASI BIR XIL ISHLAYDI**: papka ko'ринишидан hodim qo'shsам — org chart'да ham ko'ринади; org chart'дан qo'shsам — papkада ham. Bir manba (DB), ikки ko'риниш.

### DB (additive, SQL)
```sql
-- HR papka (daraxt)
create table if not exists hr_folders (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  name text not null,
  parent_id uuid references hr_folders(id),  -- daraxt
  department_id uuid references departments(id),  -- mavjud bo'limдан bo'lса
  ordering int default 0,
  created_at timestamptz default now()
);
-- Hodim ↔ papka + bo'ysunish
create table if not exists hr_members (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  folder_id uuid references hr_folders(id),
  user_id uuid references profiles(id),
  manager_user_id uuid references profiles(id),  -- kimga bo'ysunadi
  ordering int default 0
);
```
CC eng to'g'ri sxemani tanlasин (mavjud departments/profiles bilan bog'lаб). RLS: workspace a'zо o'qийди, manager/admin yozади. security_invoker view'lar.

### UI/UX 🔴
- Apple-darajа: toza, minimalist, chiroyli. Org chart vizual jozibador (kartochkалар, chiziqlар, avatar).
- Papka daraxti — qulay (ochиш/yopиш, drag yoки tugма bilan).
- Hodim kartаsи: avatar, ism, lavozim.
- Ikки view orasида almashиш (tab yoки tugма).

---

## Tartib
1 (nom) → 2 (HR service karta + icon) → 3 (chap menu section — Telegram naqshi) → 4 (eski org yashir) → 5 (Org Schema: DB → papka view → org chart view). 
5 eng katta — bosqichma-bosqich: avval DB + papka CRUD, keyin hodim qo'shиш, keyin org chart vizual.
🔴 Har qadamда eski funksiя (task/project/kanban/email) ishlаyaptими tekshir. SQL → `TASKFIX_HR.sql`. Har qadам alohида commit. Push Asilbek.
