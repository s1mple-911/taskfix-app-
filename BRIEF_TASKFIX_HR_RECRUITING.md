# TASKFIX — HR Recruiting (hodim ishga olish)

Fayl: `index.html` (Supabase `nnpsbwsppgxbytlfloth`). HR Service ichida. 🔴 Eski buzilmasin. UI/UX Apple (ideal — registratsiya page zo'r). SQL additive. n8n YO'Q. Push Asilbek. Katta feature — bosqichma-bosqich.

## Umumiy oqim
HR Service ichida "Hodim ishga olish" bo'limi:
- **Ro'yxat** (list): ishga olingan/olinаётган hodimlar. Tepada "+ Yangi xodim olish".
- **Yangi xodim** bosilса → so'raladi: **HR yuklaydi** yoki **Hodim yuklaydi** (2 yo'l).
  - **HR yuklaydi** → registratsiya formasi ochiladi, HR hamma ma'lumotни kiritadi.
  - **Hodim yuklaydi** → bir martalik LINK generatsiya → hodimга beriladi → hodim link orqали kirиб ma'lumotни kiritadi (HR kiritган ma'lumot hodimга ko'ринмайди).
- Hodim to'ldirgач → ro'yxatда **pending**. HR ichига kirиб, box'larni (TaskFix/kassa) tanlаб, saqlaydi.

## Registratsiya ma'lumotlari (form)
🔴 REQUIRED (majburiy):
- **Passport seria** (masalan AA1234567)
- **Passport rasm**: oldi + orqa (2 rasm)
- **Ota/ona passport rasm**: oldi + orqa (2 rasm) — required
- **2 telefon**: o'ziniki + ota/ona — ikkovi required
- **Email** — required
- **Hodim rasmi** (foto)
- **Shartnoma** (yuklash)

OPTIONAL:
- **Kim ishga oldi?** — bosilса bizdаgi audit + HR lar ro'yxати chиqадi (mavjud xodimlar), tanlanadi. + **lavozim** tanlanadi.
- **Kim tavsiya qildi / qayerdan topildi?** — optional matn.

HR uchun QO'SHIMCHA (hodim formasида yo'q, HR tanlaydi):
- **Lavozim** — qo'lda ro'yxat (CC boshlang'ich ro'yxat, keyin kengaytiriladi).
- **Filial** — org schemadan (mavjud org_folders — filiallar).

🔴 BOX'lar (HR tanlaydi, saqlanganда amal):
- **TaskFix** box → TaskFix invitation (hodim TaskFix'ga taklif).
- **Xarajat/kassa** box → xarajat kassa ochiladi.
- ⚠️ CC eng XAVFSIZ yo'l: box belgilanadi → saqlanganда amal (avtomat invitation/kassa), yoki tasdiq bilan. CC injection/xato bo'lmasligini ta'minlasin. Kassa/TaskFix ochish — Provodka/TaskFix bilan bog'liq, ehtiyot.

⚠️ CC TEKSHIRSIN — yana qanday ma'lumot kerak (masalan: tug'ilgan sana, manzil, ish boshlash sanasi, JSHSHIR/PINFL). Mantiqiy qo'shsin.

## Ikki yo'l — texnik
1. **HR yuklaydi**: forma ichida HR hammasini kiritadi → saqlaydi → pending yoki to'g'ridan active.
2. **Hodim yuklaydi**: 
   - Bir martalik LINK generatsiya (token, masalan `taskfix.org/hr-apply?token=xxx`).
   - 🔴 Havola BIR MARTA — hodim to'ldirgач o'chadi (token ishlatilgan → invalid).
   - Hodim link orqали kiradi (login SHART EMAS — public form, token bilan) → ma'lumot kiritadi → yuboradi.
   - HR kiritган ma'lumot (lavozim, filial, box) hodimга KO'RINMAYDI — faqat hodim o'z ma'lumotini kiritadi.
   - Hodim yuborgач → ro'yxatда pending → HR ichига kirиб box tanlаб saqlaydi.

## Registratsiya page — UI/UX IDEAL
- Hodim to'ldiradigan page (link orqали) — 🔴 ZO'R chиqsин (sotувга tayyor, professional).
- Bosqichли (step) yoki bitta toza forma. Rasm yuklash (drag-drop yoki tugma), preview. Validatsiya (required, format). Mobil + desktop. Apple darajа.
- designer bunga ALOHIDA e'tibor.

## DB (additive)
- `hr_candidates` (id, status[pending/hired/rejected], created_by, created_at, ...ma'lumotlar).
- Rasm/fayl → Supabase Storage (passport, foto, shartnoma). RLS.
- `hr_apply_tokens` (token, candidate_id, used bool, expires) — bir martalik link.
- Lavozim ro'yxati (qo'lda) — `hr_positions` yoki config.
- Filial — mavjud org_folders.
- CC eng toza sxema. RLS: HR/audit ko'radi.

## XAVFSIZLIK 🔴
- Passport/shaxsiy ma'lumot — MAXFIY. RLS: faqat HR/audit ko'radi. Storage RLS.
- Bir martalik token — ishlatilgач invalid (qayta ishlatilmaydi).
- Public apply form (hodim) — faqat token bilan, boshqa ma'lumot sizmaydi.
- Rozilik: shaxsiy ma'lumot (passport, kredit) — rozilik matni (hodim tasdiqlaydi).

## Bosqichlar
1. DB + ro'yxat (list) + "Yangi xodim" (2 yo'l tanlash).
2. HR yuklaydi — registratsiya forma (hamma maydon, rasm, Storage).
3. Hodim yuklaydi — bir martalik link + public apply page (UI ideal).
4. Pending → HR box tanlaydi (TaskFix invitation + kassa) — xavfsiz.
5. Lavozim (ro'yxat) + filial (org schema) + audit/HR tanlash.

## Fable oqimi
coder (DB, forma, token/link, Storage, box mantiq + xavfsizlik), designer (registratsiya page IDEAL + list + forma — Apple), tester (🔴 XAVFSIZLIK: shaxsiy ma'lumot RLS sizmaydi, token bir marta, box injection, Storage RLS). 🔴 Eski buzilmasin. SQL additive (men RUN). Push men. To'liq hisobot. Katta — bosqichma-bosqich.

---

# CC (Fable) QARORLARI — 2026-08-18
🔴 Ikkala agent uchun YAGONA MANBA. Mavjud kod o'rganilgandan keyin qabul qilindi; sabablari bilan.

## D1. Public apply page = ALOHIDA FAYL `hr-apply.html`
`landing.html` naqshi (repo ildizida, o'zi-yetarli, CSS+JS ichida). URL: `taskfix.org/hr-apply.html?t=<token>`.
- **Nega index.html EMAS**: (a) `index.html` 1.3 MB — begona odam butun ilovani yuklamasin; (b) ilova bundle'ida butun admin UI matni bor; (c) `index.html` boshidagi landing darvozasi (16–39-qator) mehmonni `landing.html` ga yuboradi — apply uchun unga TEGISH kerak bo'lardi (auth oqimini sindirish xavfi).
- 🔴 **Darvozaga TEGILMAYDI** — `hr-apply.html` boshqa fayl, darvoza unga umuman ta'sir qilmaydi.
- Ichida faqat: supabase-js (anon key) + 3 ta RPC + Storage upload. Boshqa hech narsa.

## D2. Anon yozish — IKKI QATLAM (eng muhim xavfsizlik qarori)
**Ma'lumot**: anon `hr_candidates` ga TO'G'RIDAN yozmaydi. Faqat `hr_apply_submit(p_token uuid, p_payload jsonb)` SECURITY DEFINER RPC.
- RPC ichida tokenni ATOMIK yopadi: `UPDATE hr_apply_tokens SET used_at = now() WHERE token = p_token AND used_at IS NULL AND expires_at > now() RETURNING candidate_id` — 0 qator qaytsa hech narsa yozilmaydi (`prjResetRecurrence` dagi optimistik da'vo naqshi). Ikki marta yuborish, poyga — imkonsiz.
- `p_payload` dan FAQAT oq ro'yxatdagi maydonlar o'qiladi (`->>` bilan nomma-nom). Butun jsonb qatorga yozilmaydi → mijoz `status`/`want_taskfix`/`workspace_id` ni bosib o'tolmaydi.
- `hr_candidates` da anon uchun **hech qanday policy YO'Q** (RLS yoqilgan, `TO authenticated` policy'lar).

**Fayllar**: private bucket **`hr-docs`**.
- anon uchun FAQAT `INSERT` policy va yo'l prefiksi TOKEN bo'lishi shart:
  `bucket_id = 'hr-docs' AND (storage.foldername(name))[1] = 'apply' AND (storage.foldername(name))[2]::uuid` → `public.hr_token_open(...)` true.
- anon uchun `SELECT`/`UPDATE`/`DELETE` policy **YO'Q** → write-only. Ya'ni token bilan ham boshqa nomzod faylini o'qib bo'lmaydi.
- 🔴 Shu sababli apply sahifasida preview **mahalliy** `URL.createObjectURL(file)` bilan (yuklangan faylni qayta o'qish imkoni yo'q).
- HR o'qishi: `createSignedUrls` (mavjud `employee-photos` naqshi, `PHOTO_TTL_SEC`).
- Token uuid — taxmin qilib bo'lmaydi; ishlatilgach `hr_token_open` false → yuklash ham to'xtaydi.

## D3. Token
`hr_apply_tokens (token uuid PK DEFAULT gen_random_uuid(), workspace_id, candidate_id, created_by, created_at, expires_at DEFAULT now()+interval '7 days', used_at, used_ua text)`.
- Ochiq = `used_at IS NULL AND expires_at > now()`. Yordamchi `public.hr_token_open(uuid)` SECURITY DEFINER (Storage policy va sahifa ikkalasi ham shundan foydalanadi — bitta haqiqat manbai).
- 🔴 `hr_apply_peek(p_token)` RPC — sahifa ochilganda faqat `{ok, state:'open'|'used'|'expired'|'invalid', company_name}` qaytaradi. **Lavozim, filial, box, HR izohi, boshqa nomzodlar — HECH BIRI qaytmaydi** (brief 44-qator).
- Har uch RPC: `REVOKE ALL FROM PUBLIC` + aniq `GRANT EXECUTE TO anon` (faqat kerakligiga).

## D4. Lavozim — MAVJUD `positions` jadvali qayta ishlatiladi
Yangi `hr_positions` YARATILMAYDI. Sabab: `positions` allaqachon bor (`positionsCache`, `loadHrData`, `hr_editor` bayrog'i unda), u aynan qo'lda boshqariladi. Ikkinchi ro'yxat ikkilanish va "qaysi biri to'g'ri?" muammosini tug'dirardi.

## D5. Filial — `org_folders` (brief talabi)
`hr_candidates.branch_folder_id uuid REFERENCES org_folders(id) ON DELETE SET NULL`. ⚠️ `branches` jadvali ham bor, lekin brief org schemani so'ragan — o'shani ishlatamiz.

## D6. BOX'lar — saqlanadi, amal ALOHIDA va IDEMPOTENT
🔴 Box tanlovi `hr_candidates` ga **yoziladi** (`want_taskfix_invite`, `want_kassa`), lekin amal saqlash tranzaksiyasi ichida BAJARILMAYDI.
- **Nega**: invitation (auth + `admin-create-employee` EF) va kassa (`sync-provodka-kassa` EF, Provodka bazasi) — TASHQI tizimlar. DB tranzaksiyasi ularni qaytara olmaydi; yarim bajarilgan holat qolsa qayta urinish kerak bo'ladi. "Saqlandi" deb yozib, aslida taklif ketmagan holat — 6-qoidaning eng yomon buzilishi bo'lardi.
- Natija qatorga yoziladi: `taskfix_invited_at`, `kassa_created_at`, `kassa_error text`.
- Har amal **optimistik da'vo** bilan idempotent: `UPDATE ... SET taskfix_invited_at = now() WHERE id = ? AND taskfix_invited_at IS NULL RETURNING id` — 0 qator = boshqa admin ulgurdi → jim chiqish (`prjStartKickoff` naqshi). Ikki marta taklif KETMAYDI.
- ⚠️ `sync-provodka-kassa` EF **deploy kutilmoqda** (CLAUDE.md) — yo'q bo'lsa aniq xato ko'rsatiladi, jimgina "ochildi" DEYILMAYDI.

## D7. Qo'shimcha maydonlar (brief 36-qator: "CC tekshirsin")
**Required qo'shiladi**: `birth_date` (tug'ilgan sana), `pinfl` (JSHSHIR, CHECK `^[0-9]{14}$`), `address` (yashash manzili), `parent_name` (ota/ona F.I.O — telefoni bor, ismi yo'q edi).
**Optional qo'shiladi**: `gender` (TEXT+CHECK `m|f`), `passport_issued_by`, `passport_issued_at`, `passport_expires_at`, `start_date` (ish boshlash — HR tomonida), `notes`.
🔴 **Rozilik**: `consent_at timestamptz`, `consent_version text` — rozilik matni sahifada ko'rsatiladi va belgilanmasa yuborish tugmasi ishlamaydi (brief 64-qator).
Passport seria CHECK: `~ '^[A-Za-z]{2}[0-9]{7}$'` (AA1234567).

## D8. Status oqimi
`draft` (HR yaratdi, link berildi — hodim hali to'ldirmagan) → `pending` (hodim yubordi YOKI HR to'ldirdi; tasdiq kutmoqda) → `hired` | `rejected`. TEXT + CHECK.

## D9. RLS
`hr_candidates` / `hr_apply_tokens`: SELECT/INSERT/UPDATE/DELETE — `TO authenticated`, shart: `is_ws_manager(workspace_id)` **OR** `hr_is_editor(workspace_id, (SELECT auth.uid()))`.
- ⚠️ `hr_is_editor` `TASKFIX_HR_EDITORS.sql` da va u **RUN kutilmoqda** bo'lishi mumkin. SQL boshida funksiya borligini tekshir: yo'q bo'lsa policy faqat `is_ws_manager` bilan yoziladi + `RAISE NOTICE` (jimgina emas). Skript baribir ishlashi kerak.
- anon uchun jadvalga policy **YO'Q**.

## D10–D12 — Asilbek qarorlari (2026-08-18)

### D10. Majburiylik HR va nomzod uchun HAR XIL
- **HR formasida MAJBURIY**: shartnoma · **kim taklif qildi** (`referred_by`) · **lavozim** (`position_id`) — bularni faqat HR biladi.
- **Apply sahifasida (nomzod)**: bu uchtasi **UMUMAN YO'Q**. `hraReferral` maydoni apply sahifasidan **olib tashlanadi** (hozir 3-qadamda turibdi), `contract` fayli esa nomzod yo'lida **ixtiyoriy** bo'ladi (shartnomani HR yuklaydi).
- ⚠️ `hr_apply_submit` dagi "6 fayl majburiy" tekshiruvi **5 ga** tushadi (shartnoma chiqadi); `referred_by` oq ro'yxatdan **chiqariladi** (nomzod uni yubormaydi).

### D11. Yetim fayllar — LAZY tozalash, 7 kun
🔴 Cron/n8n YO'Q → loyihada allaqachon ishlatilgan **LAZY** naqsh (`prjRecurDue`/`prjStartKickoff`): HR "Hodim ishga olish" sahifasini ochganda ishga tushadi.
- Nishon: `used_at IS NULL AND expires_at < now()` bo'lgan token va nomzod hamon `draft` — ya'ni **yuborilmagan va muddati o'tgan** apply papkasi.
- Tartib: `apply/<token>/` fayllarini `list()` + `remove()` → **keyin** token qatorini o'chirish. 🔴 Teskarisi mumkin emas: token qatori o'chsa `hrdocs_auth_*` ning `apply/` shoxi false bo'ladi va fayllar abadiy qulflanadi (`hrcDelete` dagi aynan o'sha saboq).
- 🔴 `ws/` yo'liga HECH QACHON tegilmaydi (HR yuklagan fayllar).
- Optimistik da'vo bilan (ikki admin bir vaqtda ochsa ikki marta ishlamasin), fon amali: `toast` YO'Q, faqat `console`; xato bo'lsa sahifa ishlashda davom etadi.
- Nomzod qatori **o'chirilmaydi** (HR qoralamani ko'rib turadi va yangi havola bera oladi) — faqat fayllar va eskirgan token ketadi.

### D12. `hr-apply.html` — UZ / RU / EN
Nomzod rus/ingliz tilli bo'lishi mumkin. Sahifa ichida mini-lug'at + til tanlagich (`index.html` dagi `langSw` vizual naqshi). Til: URL `?lang=` → `localStorage` → `navigator.language` → `uz`. 10-qoida (CLAUDE.md) shu faylga ham taalluqli.

## Bosqichlar (Fable rejasi)
- **1-bosqich** (parallel, konflikt yo'q): coder → `TASKFIX_HR_RECRUITING.sql`; designer → `hr-apply.html` (statik qobiq + CSS, Supabase JS'siz).
- **2-bosqich**: coder → `hr-apply.html` ga JS (RPC + Storage) + `index.html` da ro'yxat/forma/token.
- **3-bosqich**: box amallari (TaskFix invitation + kassa) — idempotent.
- **4-bosqich**: tester (xavfsizlik: RLS sizishi, token bir marta, Storage, box).
