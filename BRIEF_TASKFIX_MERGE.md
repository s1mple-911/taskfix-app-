# TASKFIX — duplicate xodim birlashtirish + lavozim ko'rsatish + task tarixi

Fayl: `index.html` + SQL. TaskFix Supabase. Prod ishlab turibdi (real mijozlar). Aros workspace `12b22aa6-dc45-4197-ae84-2e32e3cd56c2`.
Qoidalar: `{error}` doim tekshirilsin; `translateErr()`; `boot()` modul oxirida; sintaksis validatsiya; SQL additive/ehtiyotkor, alohida faylga.

---

## 1. DUPLICATE XODIM BIRLASHTIRISH (eng ehtiyotkor — AVVAL diagnostika)
Aros importi tufayli ba'zi xodimlar 2 marta: bittasi qo'lda qo'shilgan, bittasi importdан (masalan 2 ta "Asilbek Ermatov"). Qo'lda qo'shilganlar ~10 ta. Bularni birlashtirish: ikkala nusxadagi ma'lumot + biriktirilgan vazifalar/loyihalar BITTA profilга yig'ilsin, ikkinchisi o'chirilsin.

⚠️ ENG MUHIM: vazifalar YO'QOLMASLIGI kerak. Shuning uchun bosqichma-bosqich:

### 1a. DIAGNOSTIKA (avval — o'chirmasdan)
SQL yoz (Asilbek RUN qiladi), NATIJANI KO'RSATADI, hech narsa o'zgartirmaydi:
- Bir xil `full_name` (yoki o'xshash — trim/lower) bilan 2+ profil bor workspace ichida → ro'yxat:
  `full_name, profil_id, email, telefon, created_at, workspace role, biriktirilgan vazifalar soni, loyiha a'zoligi soni`
- Qaysi biri "qo'lda" (email haqiqiy?) qaysi biri "import" (email `@staff.taskfix.org` yoki sintetik?) — farqlab ko'rsat.
- Aynan qaysi jadvallarda `user_id` ishlatilishini aniqla va ro'yxatла: `tasks.assigned_to`, `tasks.acceptor_id`(bo'lsa), `tasks.bajardi_user_id`, `tasks.created_by`, `workspace_members.user_id`, `project_members.user_id`, `employee_details.user_id`, `employee_branches.user_id`, `positions`(bog'lanish), izoh/notification/activity jadvallari, va boshqa har qanday `user_id` FK. HAMMA joyni top — biror joy qolib ketsa ma'lumot yo'qoladi yoki FK buziladi.

Bu diagnostika natijasini Asilbek menga ko'rsatadi — keyin birlashtirish SQL'i aniqlanadi.

### 1b. BIRLASHTIRISH (diagnostikadan keyin)
Har duplicate juftlik uchun: bittasini "asosiy" (keep), ikkinchisini "eski" (remove) deb belgila (qaysi biri farqi yo'q — Asilbek aytdi).
- **Ma'lumot to'ldirish**: asosiyда bo'sh maydonlar (telefon, email, lavozim, filial) eskidan to'ldirilsin (asosiyдa bor bo'lsa tegilmaydi).
- **Barcha `user_id` havolalarini ko'chirish**: yuqorida topilgan HAR jadvalda `remove_id` → `keep_id`. Masalan `update tasks set assigned_to=keep where assigned_to=remove`. Har jadval uchun.
  - `workspace_members`/`project_members` da ikkalasi ham a'zo bo'lsa — dublikat bo'lmasin (avval remove'ni o'chir yoki `on conflict do nothing`).
- **Eski profilni o'chirish**: barcha havolalar ko'chgach `remove` profilни (va auth.users'ни? — EHTIYOT: auth.users o'chirilsa login yo'qoladi; import nusxаси login qilmaydi, lekin tasdiqlа) o'chir yoki nofaol qil.
- **Atomik**: har juftlik bitta tranzaksiyada — yarim ko'chib qolmasin.
- **Idempotent/xavfsiz**: qayta RUN qilinsa buzmasin.

⚠️ Bu SQL diagnostikadan keyin yoziladi — CC avval 1a ni bersin, Asilbek RUN qilib natijani ko'rsatadi, KEYIN CC 1b ni aniq yozadi. Ikki bosqich, aralashtirma.

Ixtiyoriy (yaxshi bo'lardi): kelajakda dublikat oldini olish — xodim qo'shishда shu workspace'да bir xil email/telefon bor bo'lsa ogohlantirish. Bu alohида, hozir majburiy emas.

---

## 2. Xodim tanlashда lavozim ko'rinsin
Vazifa berishда (bajaruvchi tanlash) va boshqa xodim tanlagichларда — ism yonида **lavozim** ham ko'rinsin.
- Format: "Asilbek Ermatov · Backend Dasturchi" (ism · lavozim). Lavozim yo'q bo'lsa faqat ism.
- Manba: `employee_details.position_id` → `positions.name` (yoki mavjud lavozim bog'lanishи).
- Hamma xodim tanlagichларда izchil: vazifa yaratish/tahrirlash, loyiha bosqichi, filtr, a'zo taklif.
- Avatar bo'lsa — avatar + ism + lavozim.

---

## 3. Task tarixi — muhim o'zgarishlar saqlansin
Vazifa tahrirlanганда eski holat saqlansin va vazifa ичида ko'rinsin. FAQAT muhimlari: **deadline, bajaruvchi (assigned_to), status**.
- DB: agar mavjud tarix jadvali bo'lsa (masalan `entry_history` analogи yoki activity log) — undan foydalan. Yo'q bo'lsa yangi:
  ```sql
  create table if not exists task_history (
    id uuid primary key default gen_random_uuid(),
    task_id uuid not null references tasks(id) on delete cascade,
    field text not null,        -- 'deadline' | 'assigned_to' | 'status'
    old_value text, new_value text,
    changed_by uuid, changed_by_name text,
    changed_at timestamptz not null default now()
  );
  ```
- Vazifa saqlanganда (deadline/bajaruvchi/status o'zgargan bo'lsa) — eski→yangi qatori yoziladi. Faqat shu 3 maydon; boshqa o'zgarishlar (nom, tavsif) hozir kuzatilmaydi.
- **Ko'rsatish**: vazifa detalida "Tarix" bo'limi (yoki ochiluvchi panel):
  - "Deadline: 24.07 → 26.07 · {kim} · {sana}"
  - "Bajaruvchi: Kamola → Asilbek · {kim} · {sana}"
  - "Status: Yangi → Jarayonda · {kim} · {sana}"
  - Eng yangisi tepada. Bo'sh bo'lsa "O'zgarishlar yo'q".
- Bajaruvchi/status uchun ID emas, ISM/yorliq ko'rsatilsin (o'qib bo'ladigan).
- `changed_by_name` — o'zgartirgan odam ismi (TEXT — profiles join shart emas, saqlashда yoz).

---

## Tartib
1a (diagnostika — AVVAL, Asilbek RUN qilib natija ko'rsatadi) → [pauza] → 1b (birlashtirish, diagnostikaga qarab) → 2 (lavozim) → 3 (task tarixi).
2 va 3 ni 1b ni kutmasdan qilса bo'ladi (mustaqil). SQL'lar alohida: `TASKFIX_MERGE_DIAG.sql` (1a), `TASKFIX_MERGE.sql` (1b), `TASKFIX_HISTORY.sql` (3). Har biri alohida commit. Push Asilbekda.
