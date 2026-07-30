# TaskFix — performance / stress test: ishga tushirish tartibi

`BRIEF_TASKFIX_STRESS.md` uchun 3 ta o'lchov vositasi. **Men RUN qilmadim — sizda.**
Har testdan keyin natijani menga bering, oxirida 4-bo'lim (xulosa) yoziladi.

| Test | Vosita | Prodga xavf | Vaqt |
|---|---|---|---|
| 1. Sahifa ochilish tezligi | `index.html` ichida `pf*` (o'chiq turadi) | **yo'q** — faqat o'lchov | 10 daq |
| 2. Yuklama (10/50/100/500) | `stress_test.js` | **bor** — prod Supabase'ga yuk | 5 daq |
| 3. Hajm (1k/10k/50k) | `TASKFIX_STRESS_SMOKE.sql` → `..._VOLUME.sql` → `..._CLEANUP.sql` | **bor** — prod bazaga yozadi (alohida ws) | 15 daq |

> ⚠️ 2 va 3 — prod loyihada. **Ish vaqtidan tashqarida** (kechqurun) ishga tushiring.
> 3-testdan keyin `TASKFIX_STRESS_CLEANUP.sql` ni **albatta** ishga tushiring.

---

## 1-test — sahifa ochilish tezligi (prodda xavfsiz)

Sukut bo'yicha **o'chiq**: yoqilmasa `fetch` ham o'ralmaydi, oddiy foydalanuvchiga ta'siri nol.

1. Ilovani oching, URL oxiriga `?perf=1` qo'shing (yoki konsolda `pfEnable()`).
2. Sahifalarni **birma-bir** aylanib chiqing, har birida ma'lumot ko'ringunicha kuting:
   Dashboard → Vazifalar → Planner → Bo'limlar → Bo'lim detali → Jamoa → Xodim detali →
   Loyihalar → Loyiha detali → Hisobot → Loglar
3. Chapdagi **⏱** tugmasini bosing → jadval chiqadi.
4. **"Nusxa (markdown)"** → menga tashlang. (Yoki konsolda `pfExport()`.)
5. Tugagach `pfDisable()`.

Konsolda qo'shimcha: `pfReport()` (jadval), `pfDetail(3)` (bitta sahifaning waterfall'i).

**Natija jadvali** (avtomatik chiqadi):

| Sahifa | So'rov | **To'lqin** | Jami ms | Σ so'rov ms | Eng sekin | Parallellik |
|---|---|---|---|---|---|---|

- **To'lqin** = ketma-ket bosqichlar soni. `1` = hammasi parallel (yaxshi).
  `3+` = qizil bilan belgilanadi — **asosiy sekinlik nomzodi**.
- **Parallellik** = Σ(so'rov vaqti) / (real vaqt). `1.0×` = to'liq ketma-ket.

---

## 2-test — yuklama

```bash
# 1) Avval rejani ko'ring (hech narsa yubormaydi)
node stress_test.js --dry

# 2) Haqiqiy test — TEST ws va TEST foydalanuvchi bilan
node stress_test.js --yes \
  --ws a57e5511-0000-4d00-9000-000057e55001 \
  --email <test-user-email> --password '<parol>'

# 3) Login'siz variant (RLS hammasini to'sadi — faqat tarmoq + rate limit o'lchanadi)
node stress_test.js --yes --anon
```

- Node 18+ kerak, npm paket kerak emas. **Faqat GET** — hech narsa yozilmaydi.
- `--yes` bo'lmasa ishlamaydi (tasodifan prodga yuk tushmasin).
- Xato ulushi 30% dan oshsa qolgan bosqichlar **avtomatik bekor**.
- Oxirida markdown jadval chiqadi — o'shani bering.

> `--ws` ni 3-testdagi test workspace'ga qarating. Aks holda so'rovlar prod
> ws'lardan o'qiydi (buzmaydi, lekin prod bazaga ortiqcha yuk).

---

## 3-test — hajm

0. **AVVAL `TASKFIX_STRESS_SMOKE.sql`** — 10 qatorlik sinov (2 soniya).
   Volume faylidagi INSERT'ning **aynan o'zini** 10 qator bilan sinaydi, 10 qatorni
   ko'rsatadi va **o'sha zahoti o'chiradi** (iz qolmaydi). Sintaksis/tip xatolari
   shu yerda chiqadi — 50k qator kutmasdan. Jadval chiqsa, 1-qadamga o'ting.
1. `TASKFIX_STRESS_VOLUME.sql` — Supabase SQL Editor'da RUN.
   - Alohida test ws yaratadi (`ZZZ STRESS TEST — o'chirish uchun`), 1k → 10k → 50k
     vazifa qo'shadi, har hajmda 7 ta haqiqiy so'rovni `EXPLAIN ANALYZE` bilan o'lchaydi.
   - Har so'rov **ikki marta**: RLS'siz (`raw_ms`) va `authenticated` roli bilan (`rls_ms`).
     Farq = RLS policy'sining narxi.
   - Natija — oxirgi SELECT jadvali. Nusxalab bering.
2. **Tugagach darhol** `TASKFIX_STRESS_CLEANUP.sql` — RUN.
   - `VACUUM ANALYZE` alohida ishga tushadi (tranzaksiya ichida ishlamaydi).
   - Nazorat SELECT `qolgan_vazifa = 0`, `qolgan_ws = 0` qaytarishi kerak.

**Himoyalar** (prod tegilmasligi uchun):
- Test ws uuid **qattiq yozilgan**; har INSERT/DELETE `workspace_id = <test>` bilan cheklangan.
- Aros prod ws (`12b22aa6-…`) **qora ro'yxatda**.
- Ws mavjud bo'lsa-yu nomi test belgisiga mos kelmasa → `RAISE EXCEPTION`, hech narsa qilinmaydi.
- Cleanup ham nomni tekshiradi — mos kelmasa o'chirmaydi.

> `v_add_member = true` bo'lgani uchun test ws sizning ilovangizda ko'rinadi
> (workspace almashtirgichda). Bu 2-test va RLS o'lchovi uchun kerak; tozalashdan keyin yo'qoladi.

---

## 1-TEST NATIJASI (2026-07-30) va TUZATISH

**O'lchandi:** boot **6079ms** · 9 to'lqin · 2.1× parallellik.
Qolgan sahifalar 300–2100ms — yaxshi. Har so'rov 300–400ms (DB **sekin emas**).
Ya'ni sekinlik **ketma-ketlikda** edi, ma'lumot hajmida yoki SQL'da emas.

**Tuzatildi (index.html):**

| # | Nima | Qanday |
|---|---|---|
| 1 | `auth.getUser()` — har boot'da tarmoq so'rovi | `getSession()` (localStorage'dan; token eskirgandagina tarmoq) → **−1 to'lqin** |
| 2 | `profiles` → `loadWorkspaces` ketma-ket | `Promise.all` — ikkalasi ham faqat `me.id` ga bog'liq → **−1 to'lqin** |
| 3 | `kanban_columns` va `tg_bot_users` oxirida alohida | 1-to'lqinga ko'chirildi (hech kimga bog'liq emas edi) → **−2 to'lqin** |
| 4 | `tg_bot_users(linked_user_id)` **ikki marta** so'ralardi | bir marta 1-to'lqinda, `loadTasksFull` keshdan oladi → **−1 so'rov, −1 to'lqin** |
| 5 | `loadTasksFull` alohida to'lqinda kutardi | 2-to'lqinga (u faqat `myWsRole` + `_myTgBotIds` ga bog'liq) → **−1 to'lqin** |
| 6 | `loadHrData` + Storage POST (**1466ms**) kritik yo'lda | **fonga** — tayyor bo'lgach ekran jimgina yangilanadi → **−2 to'lqin, ~2s** |

**`department_members` 2 marta** (844 + 1036ms) — bu dublikat emas edi, ikki xil so'rov:
biri *mening* bo'limlarim (boot uchun kerak), ikkinchisi *hamma xodim* bo'limlari
(HR/Jamoa uchun). Ikkinchisi `loadHrData` bilan birga **fonga** ketdi — boot yo'lida bittasi qoldi.

**`storage:object` POST 1466ms** — `prefetchPhotoUrls` → `createSignedUrls`, 80 ta rasm
uchun bitta imzolash so'rovi. `loadHrData` ichida, ya'ni endi **fonda**. Rasm tayyor
bo'lgunча avatarlar initsial bilan ko'rinadi.

**Kutilgan natija:** 9 to'lqin → **4** (2 boot + 2 kontekst), ~350ms/to'lqin ≈ **1.5–2s**.

> Tekshirildi: haqiqiy `loadCurrentContext` kodi sandbox'da (soxta klient, har so'rov 350ms)
> ishga tushirildi — **2 ta bloklovchi to'lqin**, kritik yo'l 720ms, HR fonda (721→1627ms,
> kritik yo'ldan tashqarida). Avval 5 to'lqin edi.

⚠️ **Qayta o'lchang**: `?perf=1` → boot qatorini avvalgi 6079ms bilan solishtiring.

---

## O'lchashdan OLDIN ma'lum bo'lgan narsalar (kodni o'qib)

Bular **statik tahlil** — raqam emas, tuzilma. Testlar shularni tasdiqlaydi yoki rad etadi.

**A. Boot ketma-ket zanjir.** `bootstrap()` (index.html) — har biri oldingisini kutadi:
`auth.getUser()` → `profiles` → `loadWorkspaces()` → `loadCurrentContext()`.
Bu ~4 ta ketma-ket round-trip, ilova ko'rinishidan **oldin**.

**B. `loadCurrentContext()` ichida ~5 to'lqin:**
1. `Promise.all` — 7 so'rov (members, departments, integrations, branches, subscriptions…) ✅ parallel
2. `Promise.all` — 2 so'rov (profiles, tg_bot_users) ✅ parallel
3. `loadHrData()` — 5 so'rov parallel, keyin Storage signed URL (yana 1 to'lqin)
4. `Promise.all([loadTasksFull, loadKanbanColumns])` ✅ parallel
5. `tg_bot_users` (linked_user_id) — yolg'iz so'rov

To'lqinlar ichi parallel, lekin **to'lqinlar orasi ketma-ket**. Ba'zilari birlashtirilishi mumkin.

> Halol eslatma: 3-to'lqindagi `loadHrData()` ni boot yo'liga **men qo'shdim**
> (tanlagichlarda lavozim ko'rinishi uchun, 2026-07-29). O'lchov uni qimmat deb
> ko'rsatsa — kritik yo'ldan chiqarib, fonda yuklash mumkin (lavozim keyinroq paydo bo'ladi).

**C. `loadTasksFull()` — LIMIT YO'Q.** Owner uchun:
`select('*').eq('workspace_id', …).order('created_at')` — **butun** workspace vazifalari
brauzerga tashiladi. 3-test aynan shuni tekshiradi (`1_royxat_limitsiz`).
Bu indeks bilan **hal bo'lmaydi** — yechim `limit`/pagination.

**D. Oddiy a'zoda `loadTasksFull()` 2 ta ketma-ket so'rov:**
`tg_bot_users` → keyin `tasks` (natija `.or()` shartiga kerak). Birlashtirish mumkin
(masalan RPC yoki tg id larni oldinroq olish).

---

## Natijalarni qaytarish shakli

Uchala natijani shu ko'rinishda bering — 4-bo'lim (xulosa) shuning ustiga yoziladi:

```
### 1-test
<pfExport() markdown'i>

### 2-test
<stress_test.js oxiridagi jadval>

### 3-test
<SQL natija jadvali>
```

Xulosada har muammo uchun: qayerda · nima qilish kerak · qancha vaqt ·
**frontend/SQL yetadimi yoki Python backend kerakmi**.
