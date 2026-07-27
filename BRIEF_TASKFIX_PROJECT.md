# TASKFIX — Loyiha turi (ketma-ket / parallel) + loyiha moduli to'liq audit

Fayl: `index.html`. Loyiha moduli asosan 2519-2886 + flow 6575-6638. Prod ishlab turibdi (real mijozlar).

Qoidalar:
- Supabase `{ error }` doim tekshirilsin; muvaffaqiyat xabari faqat rostdan o'tsa (CLAUDE.md 6).
- Xatolar `translateErr()` orqali, o'zbekcha.
- `boot()`/init modul oxirida (TDZ). Har o'zgarishdan keyin sintaksis validatsiya.
- Aros'ga xos narsalar boshqa mijozga ko'rinmasin (`isArosWs()`).
- SQL additive, alohida faylga (`TASKFIX_PROJECT.sql`), Asilbek RUN qiladi.

---

## 1. Loyiha turi: Ketma-ket / Parallel
Hozirgi mexanizm allaqachon ikkalasini qo'llaydi (`depends_on_prev`): true=ketma-ket (qulf), false=parallel (darrov ochiq). Yangi murakkab logika QURMA — faqat default'ni loyiha darajasida boshqar.

**DB:**
```sql
alter table projects add column if not exists flow_type text not null default 'sequential'
  check (flow_type in ('sequential','parallel'));
```

**Loyiha yaratish (openCreateProject / saveProject):**
- Yangi maydon: "Loyiha turi" — 2 tanlov (radio yoki 2 katta karta):
  - **🔗 Ketma-ket** — "Vazifalar navbatma-navbat ochiladi. Oldingisi tugamaguncha keyingisi qulflangan."
  - **⚡ Parallel** — "Hamma vazifa birdan ochiq. Istalgan tartibda bajariladi."
- Tanlov ikonlar + qisqa tushuntirish bilan — foydalanuvchi farqni darrov tushunsin (senior UX).

**Bosqich qo'shish (prjAddTask / prjSaveTask):**
- `flow_type='sequential'` → "oldingi tugagach ochilsin" toggle default **YOQIQ** (hozirgidek).
- `flow_type='parallel'` → toggle default **O'CHIQ** (task darrov ochiq, `depends_on_prev=false`).
- Toggle baribir ko'rinsin — foydalanuvchi bitta taskni istisno qilishi mumkin (parallel loyihada bitta task ketma-ket, yoki aksincha). Ya'ni tur = default, qat'iy qoida emas.

**Ko'rsatish:**
- Loyiha ro'yxati kartochkasida va detal sarlavhasida tur chipi: 🔗 Ketma-ket / ⚡ Parallel.
- Flow ko'rinishida parallel loyiha uchun timeline o'rniga (yoki bilan birga) — hamma ochiq ekanini bildiruvchi vizual (masalan qulf ikonlari yo'q, hammasi "faol" rangda).

**Turni keyin o'zgartirish:** loyiha "⚙️ Sozlash"da flow_type ni ham o'zgartirish mumkin bo'lsin (mavjud yangi tasklarga ta'sir qiladi; eski tasklar o'z depends_on_prev'ini saqlaydi — yoki hammasini yangilashni so'rasin, o'zing sodda variantni tanla va izohla).

---

## 2. Loyiha moduli — TO'LIQ AUDIT
Loyiha ichida hozir bor narsalar ishlashda qolsin va yaxshilansin. Audit + tuzatish:

### 2.1 "Kim / nima holatda" ko'rinishi (Asilbek talabi)
Har loyiha ichida aniq ko'rinsin:
- **Har vazifa kimda** — bajaruvchi ismi (avatar + full_name), har bosqichda.
- **Kim to'xtatib turibdi** — "hozir shu bosqichda: {vazifa} · {kim}" (mavjud prjCurrentTask), lekin ko'zga tashlanadigan qilib. Ketma-ket loyihada "keyingi hamma shu odamni kutmoqda" degan ma'no aniq bo'lsin.
- **"Bajardi: {ism}"** (V8'da qo'shilgan tasks.bajardi_user_id) — loyiha vazifalarida ham ko'rinsin (bajarilgan bosqichda kim bajarganini).
- Qabul qiluvchi (acceptor) loyiha vazifasida ham bo'lsa — u ham ko'rinsin.

### 2.2 Ikonlar va vizual (senior UI/UX)
Butun loyiha modulini vizual jihatdan qayta ko'r:
- Flow timeline ikonlar: bajarilgan ✓ / hozir ▶ / qulflangan 🔒 / parallel ⚡ / bog'liq 🔗 — izchil, chiroyli, aniq.
- Status ranglari izchil (yashil/ko'k/kulrang) — butun ilova bilan bir xil palitra.
- Progress bar, badge'lar, kartochkalar — zamonaviy, ortiqcha shovqinsiz.
- Mobil: flow timeline telefonda yaxshi ko'rinsin (vertikal, qisilmasin).
- Bo'sh holatlar: loyiha yo'q / bosqich yo'q / a'zo yo'q — foydali matn + CTA tugma.

### 2.3 Xatolarni ko'rsatish (audit topgan muammolar — tuzat)
Loyiha modulida jimgina yutilgan xatolar bor (CC oldin aniqlagan):
- `loadProjectDetail` — 3 so'rovda `{error}` tekshirilmaydi (RLS rad etsa sahifa jim qoladi). Har birini tekshir, xato ko'rinsin.
- `loadProjects` — xato `escapeHtml(e.message)` xom ko'rsatiladi → `translateErr()` ga o'tkaz.
- Loyiha yaratish/o'chirish/a'zo/bosqich — har amaldan keyingi refresh alohida try/catch, muvaffaqiyatni "xato"ga aylantirmasin.

### 2.4 Nozik mantiq (audit — kerak bo'lsa tuzat)
- **Takrorlanish lazy**: reset faqat owner/admin loyihani ochganda ishlaydi. Agar bu muammo bo'lsa — flag qil, lekin fon jarayoni (cron/trigger) qurish katta ish, hozir shart bo'lmasa izoh qoldir.
- **Flow qayta tartiblash yo'q**: bosqichlarni surish/o'rtaga qo'shish UI'da yo'q. Agar oson bo'lsa — bosqichni yuqori/past surish tugmasi qo'sh (flow_order almashtirish). Katta bo'lsa — keyingi ish, izoh qoldir.
- **Loyiha status (done/paused)**: UI'da o'zgartirish tugmasi yo'q, faqat DB'dan. "Sozlash"ga qo'sh: loyihani "To'xtatish/Faollashtirish/Tugallandi" tugmalari.
- **Kanban drag qulflangan taskni tashlasa** jimgina hech narsa qilmaydi — foydalanuvchiga "Bu vazifa hali qulflangan" deb bildir.

### 2.5 Ruxsatlar izchilligi
- owner/admin: to'liq boshqaruv; a'zo: faqat ko'rish; bajaruvchi: o'z bosqichi. Bu to'g'ri ishlashda qolsin.
- Har o'zgartiruvchi amal `isOwnerLike()` bilan himoyalangan bo'lsin (UI + iloji bo'lsa server).

---

## Tartib
1 (loyiha turi) → 2 (audit + tuzatishlar). Har biri alohida commit. Audit oxirida: kritik/muhim/keyinga ro'yxati — kritiklarni darrov tuzat.
SQL → `TASKFIX_PROJECT.sql`. Push Asilbekda.
