# TASKFIX — scale tayyorgarligi: pagination + indeks + RLS

Fayl: `index.html` + SQL. Prod ishlayapti (387 vazifa hozir). Maqsad: 10000+ vazifa / 1000+ foydalanuvchiда tez qolish. Stress-test aniq ko'rsatdi — quyida har muammo o'lchov bilan.

Qoidalar: `{error}` doim; `translateErr()`; `boot()` oxirida; sintaksis validatsiya; SQL additive, alohida faylga (`TASKFIX_SCALE.sql`). Prod'da ehtiyot.

Stress-test natijasi (50000 vazifa, raw_ms = Postgres, rls_ms = RLS bilan):
- Ro'yxat LIMITsiz: 176ms raw → 855ms RLS, SEQ SCAN
- Ro'yxat LIMIT100: 218ms raw → 836ms RLS, SEQ SCAN (LIMIT bor-u, lekin baribir sekin — RLS+sort)
- Holat: SEQ SCAN · Kalendar: SEQ SCAN · Hisobot: 809ms RLS
- Bajaruvchi/qidiruv: indeks bor, tez (11ms/1.8ms)

---

## 1. PAGINATION (eng muhim — LIMITsiz so'rovlar)
`loadTasksFull()` va boshqa hamma vazifa yuklaydigan joyда LIMIT yo'q → owner uchun BUTUN workspace brauzerга tashiladi. 10000 vazифада bu og'ir (tarmoq + brauzer xotira).

- **loadTasksFull**: `.range(0, N-1)` yoки `.limit(N)` qo'sh. Sahifаlаб yuklа (masalan 100-200 tadan).
- Kanban/ro'yxat/kalendarда: ko'rinадиган qism yuklаnsин, scroll/sahifалаш bilan qolgani. Yoки: workspace katta bo'lса (masalan >500 vazифа) — pagination, kichик bo'lса hozirgidek.
- Filtr/qidiruv **serverда** bo'lсин (allaqачон ba'zиси shundай) — brauzerда 10000 tani filtrlаш emas.
- **Muhим**: pagination qo'shганда mavjud UX buzилмаsин — foydalanuvчи hozир hammани ko'ради, endi "ko'proq yuklа" yoки infinite scroll bo'ladi. Sodda, tushunарли.
- Owner uchun "hamma vazифа" kerак joylar (masalan hisobot, statistика) — ular **agregат** so'rov bo'lсин (count/sum serverда), hamma qatorни tortмаsин.

## 2. INDEKSLAR (SEQ SCAN → Index Scan)
Test SEQ SCAN ko'рсатган ustunlarга indeks. CC allaqачон ba'zиси bor (idx_tasks_ws, assigned, dept, trgm) — YETISHMAYOTGANLARINI qo'sh:
```sql
-- holat bo'yicha filtr (SEQ SCAN edi)
create index if not exists idx_tasks_status on tasks(status);
-- kalendar/deadline oralig'i (SEQ SCAN edi)
create index if not exists idx_tasks_deadline on tasks(deadline);
-- ro'yxat: ws + created_at (sort SEQ SCAN)
create index if not exists idx_tasks_ws_created on tasks(workspace_id, created_at desc);
-- kompozit: ws + status (kanban ustun bo'yicha)
create index if not exists idx_tasks_ws_status on tasks(workspace_id, status);
```
- CC `explain analyze` bilan har birини tekshirсин — indeks haqиqатан ishlатиладими (planner tanlаydiми). Ishlatмаса — sabab (masalan RLS ifodasi indeksни to'sяpti).
- Ortiqcha indeks qo'shма — faqат test SEQ SCAN ko'рсатганларига. Har indeks yozишни sekinlаштиради (INSERT/UPDATE), shuning uchun kerakлиси.

## 3. RLS OPTIMALLASHTIRISH (4-36× sekinlashuv)
RLS policy so'rovни 4-36 barobar sekinlаштиряpti (raw 22ms → rls 809ms hisobot). Sabab odатда: policy ичидаги `EXISTS`/subquery har qатор uchun qaйta bajarилaди, yoки `auth.uid()` funksия takror chaqiriladi.

- `tasks` (va boshqа asosий jadval) RLS policy'ларини ko'р. Umumий muammоlar:
  - `auth.uid()` policy ичида ko'п marta → `(select auth.uid())` bilan o'rab qo'y (Postgres bir marta hisоблаydi — Supabase rasmий tavsияsи, katta tezlаniш).
  - Policy ичидаги `workspace_id in (select ... from workspace_members where user_id = auth.uid())` — bu har so'rovда bajarилaди; `workspace_members(user_id, workspace_id)` indeksи borлигини tasdiqлa.
  - Murakkаb EXISTS zanjири bo'lса — soddalаштир yoки `security definer` yordamчи funksияга o'tказ (stable, bir marta hisoblanadigan).
- Har o'zгаришдан keyин `explain analyze` bilan rls_ms qайta o'lchа — kamayдими.
- ⚠️ RLS o'zгартирганда XAVFSIZLIK buzilмаsин — foydalanuvчи faqат o'z workspace'ини ko'ришда davom etсин. Har policy o'zгаришидан keyин: boshqa ws ma'lumoti ko'ринмаsligini tekshir. Bu eng nozик qism — sekinlик uchun xavfsizликни qurbon qилма.

## 4. O'LCHOV (isbot)
Har bosqichдан keyин: stress-test VOLUME'ни qайta ishga tushир (test ws'да, keyин cleanup) yoки `explain analyze` bilan solиштир:
- Pagination: 10000 vazифа yuklаnиши necha ms (avval/keyin)
- Indeks: SEQ SCAN → Index Scan bo'lдими
- RLS: rls_ms/raw_ms nisbati kamaydiми
Natижани jadval qilib ko'рсат.

## Tartib
2 (indeks — eng tez, darrov foyda) → 3 (RLS — eng katta sekinlik sababi) → 1 (pagination — eng ko'п frontend ish). Har biri alohida commit. SQL → `TASKFIX_SCALE.sql`. Prod'да ehtiyot, RLS'ни alohida sinash. Push Asilbekда.
