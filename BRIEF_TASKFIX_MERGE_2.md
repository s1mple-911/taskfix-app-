# TASKFIX — duplicate birlashtirish (1b) + xodim o'chirishda vazifalarni qayta biriktirish

Fayl: `index.html` + SQL. TaskFix Supabase. Aros ws `12b22aa6-dc45-4197-ae84-2e32e3cd56c2`. Prod ishlayapti.
Qoidalar: `{error}` tekshirilsin; `translateErr()`; `boot()` oxirida; sintaksis validatsiya; SQL additive/ehtiyot, alohida faylga.

Diagnostika natijasi (tayyor):
- profiles PK'ga FK'lar: CASCADE = department_members, notifications, tg_chat_links, tg_link_tokens, workspace_members. NO ACTION = tasks.assigned_to, tasks.created_by, task_comments, task_attachments (bular o'chmaydi — havola ko'chiriladi). SET NULL = branches.manager_user_id, tg_bot_users.linked_user_id.
- 2 duplicate juftlik:
  - **Nodir**: KEEP `d7d8f5f3-821c-4c45-896b-e0e6a2de8c42` (email arosnadir2026@gmail.com, login qiladi, 1 vazifa) · REMOVE `eb0d0a9e-71dc-4bad-acdf-672c6c0f4a23` (email yo'q, 5 vazifa) → 5 vazifa keep'ga ko'chadi.
  - **Saidakbar Muhiddinov**: KEEP `840a22ea-4315-4eeb-8efa-15b45561a27b` (12 vazifa) · REMOVE `50ef8131-75be-4a0e-a760-2341edf21df2` (0 vazifa).

---

## 1. MERGE SQL (TASKFIX_MERGE_1B.sql) — bu 2 juftlik uchun
Idempotent, atomik (butun blok bitta tranzaksiya yoki har juftlik alohida DO bloki). Har juftlik uchun KEEP/REMOVE aniq yozilgan (yuqoridagi uuid'lar).

Tartib (HAR REMOVE uchun, o'chirishdan OLDIN):
1. **Havola ko'chirish** — REMOVE uid ishlatilgan HAR jadvalda KEEP ga o'tkaz:
   - `update tasks set assigned_to = KEEP where assigned_to = REMOVE;`
   - `update tasks set created_by = KEEP where created_by = REMOVE;`
   - `update task_comments set author_id = KEEP where author_id = REMOVE;`
   - `update task_attachments set uploaded_by = KEEP where uploaded_by = REMOVE;`
   - `update branches set manager_user_id = KEEP where manager_user_id = REMOVE;`
   - `update tg_bot_users set linked_user_id = KEEP where linked_user_id = REMOVE;`
   - Diagnostika B2 dinamik skanerда topilgan BOSHQA har qanday uuid ustuni ham (masalan tasks.acceptor_id, tasks.bajardi_user_id, project_members.user_id, department_members.user_id, activity/notification jadvallari) — HAMMASI. Ro'yxatga tayanma, diagnostikada chiqqan to'liq ro'yxatni ishlat. Biror joy qolsa ma'lumot yo'qoladi.
2. **CASCADE jadvallar (a'zolik) — dublikat bo'lmasin:**
   - `workspace_members`: KEEP allaqachon a'zo → REMOVE qatorini o'chir (`delete from workspace_members where user_id=REMOVE and workspace_id=...`). Agar KEEP a'zo bo'lmasa — REMOVE ni KEEP ga update (lekin ikkalasi ham a'zo, shuning uchun delete).
   - `department_members`: REMOVE bo'lim a'zosi bo'lsa va KEEP ham a'zo bo'lsa → REMOVE o'chir; faqat REMOVE a'zo bo'lsa → KEEP ga update (on conflict do nothing). (Diagnostikada ikkalasида ham dept=0, shuning uchun ehtimol shart emas — lekin himoya sifatida yoz.)
   - `notifications`, `tg_chat_links`, `tg_link_tokens`: REMOVE nikini KEEP ga ko'chir yoki o'chir (bular muhim emas — REMOVE import nusxasi, o'chsa zarar yo'q; lekin CASCADE bo'lgani uchun profil o'chishidan oldin hal qil).
3. **Bo'sh maydonlarni to'ldirish**: KEEP da bo'sh (email/phone/lavozim/avatar) va REMOVE da bor bo'lsa → KEEP ga ko'chir. KEEP da bor bo'lsa tegma. (Nodir'da KEEP email bor; REMOVE'да telefon/lavozim bo'lsa KEEP ga.)
4. **REMOVE profilni o'chirish**: hamma havola ko'chgach → `delete from profiles where id = REMOVE;`.
   - auth.users: REMOVE import nusxasi login qilmaydi. profiles o'chgach auth.users REMOVE ni ham o'chirish kerakmi — TEKSHIR: agar profiles.id → auth.users.id FK bo'lsa va CASCADE bo'lmasa, auth.users REMOVE qoladi (yetim). Uni ham o'chir (`delete from auth.users where id=REMOVE`) — lekin faqat login qilmaganiga ishonch hosil qilib (email yo'q yoki sintetik). EHTIYOT: KEEP ni hech qachon o'chirma.
5. **Tekshiruv (oxirida, RAISE bilan)**: KEEP profil bor, REMOVE yo'q; Nodir KEEP endi 6 vazifa (1+5); Saidakbar KEEP 12 vazifa. Kutilgandan farq bo'lsa RAISE (rollback).

⚠️ Bu SQL faqat shu 2 juftlik uchun (uuid hardcoded) — universal merge emas. Kelajakda yana chiqsa yangi diagnostika + yangi SQL.

## 2. Xodim o'chirishda vazifalarni qayta biriktirish (index.html)
Maqsad: **vazifa egasiz qolmasin**. Xodimni o'chirishda uning vazifalari boshqa(lar)ga o'tkazilsin.

Oqim:
- Jamoa → xodim → "O'chirish" bosilganda → **ogohlantirish modali**:
  - "{Ism}ni o'chirmoqchisiz. Unga biriktirilgan **N ta vazifa** bor:"
  - Vazifalar ro'yxati (nomi + status + deadline), har biri yonida **kichik xodim tanlagich** (kimga o'tkazish — ism·lavozim).
  - Tepada: **"Hammasini bittaga o'tkazish: [xodim tanla]"** — bosilsa hamma qatorga o'sha xodim qo'yiladi (tez yo'l).
  - Har vazifani alohida ham boshqa xodimga qo'yish mumkin (ro'yxatда o'zgartirish).
  - Tugmalar: **"O'tkazib, o'chirish"** (hamma vazifa tanlangan xodim(lar)ga → keyin xodim o'chiriladi) · **"Skip (biriktirmasdan o'chirish)"** (vazifalar egasiz/assigned_to=null qoladi) · **"Bekor"**.
- "O'tkazib, o'chirish": har vazifa `assigned_to` yangilanadi (tanlangan xodimga) → keyin xodim o'chiriladi (yoki ws'dan chiqariladi — mavjud o'chirish oqimi qanday bo'lsa).
- Vazifasi yo'q xodim → modal sodda: "N=0, o'chirishni tasdiqlang".
- Har amal `{error}` tekshiriladi; muvaffaqiyat toast faqat rostdan o'tsa; xato ko'rinadi.
- **Muhim**: bu faqat UI-tomon o'chirishda ishlaydi. Agar o'chirish deb `workspace_members` dан chiqarish nazarда tutilsa — vazifa `assigned_to` baribir o'sha uid qoladi (profil o'chmaydi). Aniqla: "o'chirish" = ws'dan chiqarishmi yoki profil o'chirishmi. Ws'dan chiqarish bo'lsa ham vazifalarni qayta biriktirish taklif qilinsin (egasiz ko'rinmasin).

## Tartib
1 (merge SQL — men RUN qilaman, natija tekshiriladi) · 2 (o'chirishda qayta biriktirish — mustaqil, darrov). Alohida commit. Push Asilbekda.
