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
6. Supabase so'rovlarida `error`ni **tekshir** — supabase-js throw qilmaydi, jimgina yutilib qoladi (bir necha marta shu bilan vaqt yo'qolgan).
7. RLS policy ichida `workspace_members` inline subquery **yozma** (rekursiya → 42P17). `is_ws_manager()`/`is_ws_member()` ishlat.
8. Mavjud helper: `uiForm(title,fields[{id,label,type,placeholder,hint}],{okText})→Promise<vals|null>`, `uiConfirm(title,msg,{danger,okText})`, `toast(text,'ok'|'err')`, `logActivity(action,{entityType,entityId,entityTitle,details})`, `$`, `escapeHtml`, `.hr-*`, `.ui-*`, `.xtbl`.

## DB holati
- **Migratsiyalar**: 38–44, 46 ishga tushgan (40 bo'sh o'tgan — 42 to'ldirgan). **45** (staff_phone_lookup), **43** (schedule_monthly), **47** (harajat_kassa) — foydalanuvchi ishga tushirishi kutilmoqda.
- Yangi migratsiya raqami: **48**dan.
- **Aros workspace**: `12b22aa6-dc45-4197-ae84-2e32e3cd56c2` — 126 hodim import qilingan, 80 rasm Storage'da (`employee-photos/{ws}/{uid}.jpg`, private bucket, signed URL bilan ko'rsatiladi).
- `legacy_id_map` + `staff_import_map` — **ikkalasi ham kerak** (har xil vazifa: legacy ID xaritasi vs import kuzatuvi).
- `employee_schedule_days`: `day_type IN ('on','off')`, PK (workspace_id, user_id, date), ~40k qator.

## Muhim modullar (index.html)
- **HR/Jamoa**: `loadHrData`, `renderEmployee`, `empDtlSave`, `renderTeamTable` (~9500–10800).
- **Rasm**: `getPhotoUrl(uid)`/`empAvatarUrl`/`prefetchPhotoUrls` (signed URL kesh), `avatarHtml(name,size,url,uid)` — uid berilsa keshdan rasm. Yuklash: `phUploadPhoto` (canvas siqish).
- **Ish jadvali**: 3 rejim (weekly/monthly/flexible), `schOnModeChange`, `schSaveDays` (employee_schedule_days qayta hosil).
- **Routing**: `goPage`, `rtSetHash`/`rtRouteFromHash` (hash-routing, popstate).
- **Qidiruv**: `buildCmdItems` (cmd-palette, bo'limlarga ajratilgan).
- **Import**: `hrImport*` (preflight 5b — telefon+ism blokeri mijozda).
- **EF**: `admin-import-staff` (phase: identity | photos | connect), `sync-provodka-kassa` (Harajat kassa → Provodka RPC). Boshqa EF manbalari repoda YO'Q (admin-create-employee, send-email, tg-send... deployed).
- **Provodka integratsiyasi**: `hk*` funksiyalar (`hkSync`/`hkTableToggle`/`hkSetDb`). Jamoa jadval 💵 ustuni + hodim detali checkbox. EF `sync-provodka-kassa` env: `PROVODKA_URL`, `PROVODKA_SERVICE_KEY`.

## Ochiq masalalar
- **Dublikatlar**: Akobir tasdiqlangan (`cleanup_duplicate_staff.sql`da qo'lda juftlik). ~14 haqiqiy odam, qolgan 126 sintetik. Qo'shimcha juftliklar `dup_pairs` `manual` ro'yxatiga qo'lda qo'shiladi.
- **EF deploy kutilmoqda**: `admin-import-staff` v3.1 (connect action), `sync-provodka-kassa` v1 (+ 2 env secret: PROVODKA_URL, PROVODKA_SERVICE_KEY).
- **SQL kutilmoqda**: 43, 45, 47 (TaskFix); `PROVODKA_HODIM_KASSA.sql` (Provodka loyihasida).

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
