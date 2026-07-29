# CLAUDE.md — TaskFix loyihasi (doimiy xotira)

Har sessiyada BIRINCHI shu fayl o'qiladi. Har katta o'zgarishdan keyin **o'zing yangila**.

## Loyiha
- **TaskFix** — vazifa/jamoa boshqaruvi ilovasi. Supabase backend + bitta katta `index.html` (~560KB) frontend.
- **Supabase ref**: `nnpsbwsppgxbytlfloth`
- **Deploy**: GitHub Pages, **build yo'q** — `index.html` to'g'ridan xizmat qilinadi (vanilla JS, framework yo'q).
- **Til**: barcha UI matnlari toza **Uzbek Latin**.

## Qat'iy qoidalar (BUZMA)
1. Har `index.html` o'zgarishidan keyin **node-vm sintaksis validatsiya** (pastda). XATO chiqsa — to'xta, tuzat.
2. Yangi element ID'lariga **prefiks**: jadval `sch*`, routing `rt*`, rasm `ph*`. Mavjud ID'larni buzma (`edtWd_*`, `edtWorkStart/End` empDtlSave'ga bog'liq).
3. SQL: **TEXT + CHECK, ENUM emas** (30/32-migratsiyalardagi saboq). Idempotent (`IF NOT EXISTS`), tekshiruvda `RAISE EXCEPTION` (jimgina o'tmasin).
4. `aros_staff_export.json` — **hech qachon commit qilinmaydi** (`.gitignore`da, 6MB).
5. Inline handler ichida arrow function **yo'q**; `escapeHtml()` har doim (XSS).
6. **Xato jimgina yutilmasin — muvaffaqiyat xabari faqat haqiqiy muvaffaqiyatda.** Bu eng ko'p buzilgan qoida (audit 2026-07-24: ~20 joy tuzatildi).
   - Har Supabase yozuv/o'qishda `const { error } = await ...` — supabase-js **throw QILMAYDI**, `{error}` qaytaradi. `await sb.from(...).update(...)` ni `{error}` siz yozsang, `catch` **hech qachon ishlamaydi** va DB rad etsa ham "Saqlandi" chiqadi. `if (error) throw error;` yoz.
   - `.functions.invoke(...)` ham `{error}` qaytaradi (funksiya-darajali xato throw emas) — uni ham tekshir.
   - `toast('Saqlandi'/'✅ ...')` faqat `throw`dan keyin, muvaffaqiyat yo'lida bo'lsin — yozuvdan **oldin** yoki tekshiruvsiz emas.
   - Bo'sh `catch(e){}` **taqiqlanadi**. Kamida `console.error(...)`. Foydalanuvchi kutayotgan amal bo'lsa — `toast`/`showMsg` ham. Fon bildirishnomasi (tg-send/email) bo'lsa — `console.error` yetarli.
   - Foydalanuvchiga ko'rsatiladigan xato **doim `translateErr(e.message || String(e))`** orqali (o'zbekcha; xom Postgres/RLS/tarmoq matni chiqmasin). Xom `e.message` ko'rsatma.
7. RLS policy ichida `workspace_members` inline subquery **yozma** (rekursiya → 42P17). `is_ws_manager()`/`is_ws_member()` ishlat.
8. Mavjud helper: `uiForm(title,fields[{id,label,type,placeholder,hint}],{okText})→Promise<vals|null>`, `uiConfirm(title,msg,{danger,okText})`, `toast(text,'ok'|'err')`, `logActivity(action,{entityType,entityId,entityTitle,details})`, `$`, `escapeHtml`, `.hr-*`, `.ui-*`, `.xtbl`.
   - `uiForm` maydon turlari: `text|textarea|number|select|toggle|datetime|choice`. **`choice`** — ikonli 2+ kartali radio: `options:[{value,label,icon,desc}]` (CSS `.ui-choice*`).

## DB holati
- **Migratsiyalar**: 38–44, 46 ishga tushgan (40 bo'sh o'tgan — 42 to'ldirgan). **45** (staff_phone_lookup), **43** (schedule_monthly), **47** (harajat_kassa) — foydalanuvchi ishga tushirishi kutilmoqda.
- Yangi migratsiya raqami: **48**dan.
- **Aros workspace**: `12b22aa6-dc45-4197-ae84-2e32e3cd56c2` — 126 hodim import qilingan, 80 rasm Storage'da (`employee-photos/{ws}/{uid}.jpg`, private bucket, signed URL bilan ko'rsatiladi).
- `legacy_id_map` + `staff_import_map` — **ikkalasi ham kerak** (har xil vazifa: legacy ID xaritasi vs import kuzatuvi).
- `employee_schedule_days`: `day_type IN ('on','off')`, PK (workspace_id, user_id, date), ~40k qator.

## Muhim modullar (index.html)
- **HR/Jamoa**: `loadHrData`, `renderEmployee`, `empDtlSave`, `renderTeamTable` (~9500–10800). `loadHrData()` endi **workspace ochilishida** ham chaqiriladi (`loadWorkspaceData`, org uchun) — lavozim butun ilovada bor bo'lishi uchun; u ichida `prefetchPhotoUrls` ham bor (avvalgi alohida photo_path so'rovi olib tashlandi).
- **Xodim tanlagichlarda lavozim**: `memberPos(uid)` (→ `teamMemberPos`, xatosiz bo'sh matn) va `memberNamePos(uid,name)` → `"Ism · Lavozim"`. **escapeHtml qilmaydi** — chaqiruvchida qilinadi. Ishlatilgan joylar: `msFilter` (avatar+ism+lavozim, qidiruv lavozim bo'yicha ham), `openCreate`→`cAcceptor`, `prjAddTask`, `prjInviteMember`, `empFilterRenderList` (+`.efo-pos`), `tblAsgRenderList`, `tblNewAsg`, `deptAddSel`, `cmtMentionInput/Render` (matnga qo'shiladigan `@Ism` o'zgarmadi), org chart nomzodlari.
- **Vazifa tarixi (`th*`)**: `task_history` (TASKFIX_HISTORY.sql). Kuzatiladi FAQAT `deadline|assigned_to|status` (`TH_FIELDS`). Yagona choke-point `thRecord(prev, next)` — eski/yangi obyektni solishtiradi, `old_value/new_value` (xom) + `old_label/new_label` (o'qiladigan, `thLabel`) + `changed_by_name` yozadi. Chaqiriladi: `updateField`, `changeStatus`, `acceptTask`, `returnTask`, `tblUpdate` (nusxa optimistik yozuvdan OLDIN: `_thPrev`), `prjShiftNextDeadline`. Ko'rsatish: detal oynasida "Tarix" bo'limi (`thListHtml`, CSS `.th-*`), `openDetail` `Promise.all`da yuklaydi. Jadval yo'q bo'lsa `thTableMissing` aniqlaydi → `_thMissing=true`, xato faqat console'ga, saqlash oqimi buzilmaydi. ⚠️ Yozuv MIJOZDA — TG bot/EF to'g'ridan `tasks`ni yangilasa tarixga tushmaydi (trigger qo'shilmagan, ataylab).
- **Rasm**: `getPhotoUrl(uid)`/`empAvatarUrl`/`prefetchPhotoUrls` (signed URL kesh), `avatarHtml(name,size,url,uid)` — uid berilsa keshdan rasm. Yuklash: `phUploadPhoto` (canvas siqish).
- **Ish jadvali**: 3 rejim (weekly/monthly/flexible), `schOnModeChange`, `schSaveDays` (employee_schedule_days qayta hosil).
- **Routing**: `goPage`, `rtSetHash`/`rtRouteFromHash` (hash-routing, popstate).
- **Universal qidiruv (`gs*`)**: `// ============ 🔍 UNIVERSAL QIDIRUV (gs*) ============` bloki, `init()`dan **oldin, global scope'da** (~14222). **Modal YO'Q** — topbardagi `#topSearchInp` haqiqiy input (`oninput=gsOnInput`, `onkeydown=gsKey`, `onfocus=gsOpen`), natijalar `#gsDrop`/`#gsList` panelida uning ostida ochiladi (`.gs-drop`, `@keyframes gsDrop` .22s). Panel **`<body>`ning bevosita farzandi** + `gsPosition()` (fixed, `getBoundingClientRect`) — topbar `sticky`/`z-index:20` bilan urishmasin; `z-index:90` (modal 100 ostida). ⌘K → `gsFocus()` (fokus + select + ochish). `gsClose()` matnni saqlaydi (Esc/tashqariga bosish, `gsWatch` mousedown), `gsDone()` natija tanlangandan keyin tozalaydi. Xodim qatorida **`＋ Vazifa`** tugmasi (`.gs-act` → `gsNewTaskFor(uid)`): `openCreate()` + `msSelected=[{type:'user'|'me',id,label}]` + `msUpdateSummary()`/`msFilter()`. Shu sababli natija elementi `<div role="option">` (button ichida button bo'lmasligi uchun). Yagona dvigatel: `gsLocal(q,qd)` (kesh: wsMembers/tasksCache/departments/branchesCache/positionsCache/projectsCache) + `gsServer(q)` (parallel `ilike`: tasks/projects/positions, har biri `{error}`) → `gsApplyServer` (id bo'yicha dublikatsiz) → `gsPaint()`. Guruhlar `GS_GROUPS`, guruhda 5 ta + `gsShowMore`. Telefon `gsPhoneMatch`/`gsHiPhone` (raqamlargacha normallashtirish, oxirgi 9 raqam). Highlight `gsHi`/`gsHiPhone` (escapeHtml ichida). Debounce `GS_DEBOUNCE`, eskirgan javob `_gsSeq` bilan bekor. CSS `.gs-*`; mobilda (`@media max-width:640px`) panel deyarli butun kenglik (`gsPosition` `innerWidth<=640`). `openCmdPalette`/`closeCmdPalette` — eski nom aliaslari (⌘K listener va init'dagi Escape ishlatadi; Escape `_gsShown`ga qaraydi). Tezlik uchun ixtiyoriy `TASKFIX_SEARCH.sql` (pg_trgm GIN).
  - ⚠️ **Saboq (2026-07-28)**: eski qidiruv butunlay `init()` ICHIDA edi → funksiyalar lokal, HTML inline handler esa global scope'da baholanadi → `openCmdPalette is not defined`. **Inline handler chaqiradigan funksiya global bo'lishi SHART** (top-level `function`). Top-level `const`/`let` (masalan `$`) inline handler'ga ko'rinadi, funksiya ichidagilar YO'Q.
- **Import**: `hrImport*` (preflight 5b — telefon+ism blokeri mijozda).
- **EF**: `admin-import-staff` (phase: identity | photos | connect), `sync-provodka-kassa` (Harajat kassa → Provodka RPC), `admin-create-employee` (v4 — xodim yaratish/topish + a'zolik + lavozim/filial + parol emaili; **repoda tiklandi 2026-07-23**, deploy kutilmoqda). Boshqa EF manbalari repoda YO'Q (send-email, tg-send, tg-webhook... deployed).
- **Loyiha (Project)**: `// ============ LOYIHALAR ============` bloki (~2620–3000) + flow yordamchilari (`prjShiftNextDeadline`/`prjReloadTasks`). Turi `projects.flow_type` (`sequential`|`parallel`, default sequential) — **faqat yangi bosqich uchun default** (`prjAddTask` toggle'i), har vazifa o'z `depends_on_prev`ini saqlaydi. Qulf: `tasks.is_locked` (server trigger **avtoritet**) — `prjTaskOpen` avval `is_locked`ka qaraydi, `prjShouldBeOpen` faqat mantiqni hisoblaydi (ikkisi ziddiyatda = "qulf qotib qolgan" → owner'ga `prjUnlockTask` tugmasi). Boshqa: `prjRenderHero` (kim ushlab turibdi), `prjMoveTask` (↑↓ tartib), `prjSyncLocks`, `prjApplyTypeToTasks`, `prjRenderHeader`, `prjShowError`. CSS `.prj-*`.
  - **Refresh qoidasi**: vazifani o'zgartiruvchi HAR amal `tasksCache` VA `prjTasks` ni yangilashi shart (`refreshActiveView` faqat tasksCache'dan sinxronlaydi — o'chgan qator u yerda yo'q, shuning uchun o'zi tozalanmaydi). O'chirish/ko'chirishdan keyin `loadProjectDetail()` yoki `prjReloadTasks()` (u endi serverda yo'q bosqichlarni ham tozalaydi). Mavjud bo'lmagan vazifa uchun `taskGoneLocal(id)` — ro'yxatni tozalaydi, xom "topilmadi" xatosi o'rniga yumshoq xabar; `isRowGone(err)` PGRST116'ni aniqlaydi.
- **Provodka integratsiyasi**: `hk*` funksiyalar (`hkSync`/`hkTableToggle`/`hkSetDb`). Jamoa jadval 💵 ustuni + hodim detali checkbox. EF `sync-provodka-kassa` env: `PROVODKA_URL`, `PROVODKA_SERVICE_KEY`.

## Ochiq masalalar
- **Dublikatlar**: Akobir tasdiqlangan (`cleanup_duplicate_staff.sql`da qo'lda juftlik). ~14 haqiqiy odam, qolgan 126 sintetik. Qo'shimcha juftliklar `dup_pairs` `manual` ro'yxatiga qo'lda qo'shiladi.
- **EF deploy kutilmoqda**: `admin-import-staff` v3.1 (connect action), `sync-provodka-kassa` v1 (+ 2 env secret: PROVODKA_URL, PROVODKA_SERVICE_KEY).
- **SQL kutilmoqda**: 43, 45, 47, `TASKFIX_V8.sql`, `TASKFIX_PROJECT.sql`, `TASKFIX_HISTORY.sql` (vazifa tarixi — busiz "Tarix" bo'limi "yoqilmagan" deb yozadi), `TASKFIX_SEARCH.sql` (ixtiyoriy — qidiruv indeksi, ilova busiz ham ishlaydi) (TaskFix); `PROVODKA_HODIM_KASSA.sql` (Provodka loyihasida).
- **Dublikat birlashtirish (2026-07-29, BRIEF_TASKFIX_MERGE.md)**: `TASKFIX_MERGE_DIAG.sql` (1a — **faqat SELECT**, dublikat profillar + HAR uuid/matn ustunidagi user_id havolalari + UNIQUE to'qnashuv nuqtalari). Foydalanuvchi RUN qilib natijani berishi kutilmoqda → keyin `TASKFIX_MERGE.sql` (1b — birlashtirish) yoziladi. Diagnostika mavjud `cleanup_duplicate_staff.sql` dan mustaqil (`norm_phone_digits`/`dup_pairs` ga tayanmaydi) va qo'lda qo'shilgan dublikatlarni ham topadi.
- **Loyiha moduli (2026-07-27)**: (1) `TASKFIX_PROJECT.sql` — `projects.flow_type` + diagnostika (status CHECK, RLS, flow ustunlari). Ustun bo'lmasa ilova ishlaydi: `prjNoFlowTypeCol(err)` aniqlaydi, flow_type'siz qayta yozadi va ogohlantiradi. (2) `projects.status` — UI `active|paused|done` yozadi ("Sozlash"), DB'da CHECK bo'lsa xato chiqishi mumkin (SQL diagnostikasi shuni tekshiradi). (3) **Takrorlanish hamon LAZY** — reset faqat owner/admin loyihani ochganda (`prjRecurDue`+`prjResetRecurrence`); cron yo'q. (4) Loyiha RLS'i (34-migratsiya) repoda yo'q — server tomon tekshirilmagan, UI'da hamma o'zgartiruvchi amal `isOwnerLike()` bilan yopilgan.
- **V8 (2026-07-24)**: (1) "Bajardi: {ism} · sana" vazifa detalida — `tasks.bajardi_user_id`/`bajardi_at` (TASKFIX_V8.sql). `changeStatus` best-effort yozadi (ustunlar bo'lmasa jimgina console.error, zaxira `submitter_id`/`completed_at`). (2) Xodim filtri — `empFilter` (Set), `applyEmpFilter` (`tasks` + `department` sahifalari), yagona global filtr 2 bar bilan: 'tasks' (`#empFilterPanel`) va 'dept' (`#deptEmpFilterPanel`). localStorage `empFilter_<ws>`. Tasks: list/kanban/kalendar/jadval; Bo'lim detali: kanban/list/kalendar (Jamoa tabida bar yashirin). Planner'ga qo'shilmagan (yashirin filtrlanish oldini olish uchun `applyEmpFilter` faqat shu 2 sahifada). Funksiyalar scope-aware: `empFilterTogglePanel/RenderList(scope)`.

## Validatsiya buyrug'i
```bash
node -e "
const fs=require('fs'), vm=require('vm');
const h=fs.readFileSync('index.html','utf8');
const re=/<script(?![^>]*src=)[^>]*>([\s\S]*?)<\/script>/g;
let m, code=null;
while((m=re.exec(h))){ if(m[1].indexOf('async function init')!==-1) code=m[1]; }
try { new vm.Script(code); console.log('OK', code.length); }
catch(e){ console.log('XATO:', e.message); process.exit(1); }
"
```
