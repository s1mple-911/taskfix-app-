# TASKFIX — Import tugmasini yashirish + to'liq audit (ishga tushishdan oldin)

Kontekst: TaskFix ertaga haqiqiy mijozlarga ishga tushadi. Birinchi tashqi mijoz allaqachon bor (temurbek — o'z kompaniyasini yaratdi, xodim qo'shdi). Fayl: `index.html`.

---

## 1. "Import (JSON)" tugmasi — faqat Aros uchun
Jamoa sahifasidagi **"⬆ Import (JSON)"** tugmasi aros_staff importi uchun edi — tashqi mijozlarga kerak emas va chalkashtiradi.

Qil: tugma faqat Aros workspace'da ko'rinsin.
```js
const AROS_WS = '12b22aa6-dc45-4197-ae84-2e32e3cd56c2';
// tugma: currentWorkspaceId === AROS_WS bo'lsagina render qilinsin
```
Boshqa workspace'larda umuman chizilmasin (yashirin emas — DOM'ga ham qo'shilmasin). Import bilan bog'liq modal/funksiyalar kodda qolaversin.

---

## 2. TO'LIQ AUDIT — ertangi ishga tushish uchun

Maqsad: yangi mijoz (bo'sh workspace, ma'lumotsiz) hech qayerda qotib qolmasin, xato ko'rmasin, boshqa mijoz ma'lumotini ko'rmasin.

### 2.1 Mavjud bo'lmagan chaqiruvlar
`loadTeamData` bugi (ReferenceError) allaqachon topilgan. Butun faylni yana bir bor tekshir:
- Har chaqirilayotgan funksiya/o'zgaruvchi uchun e'loni bormi
- `xxx?.()` naqshi — `?.` **e'lon qilinmagan** o'zgaruvchidan himoya QILMAYDI (ReferenceError beradi). Shunday joylar bo'lsa `typeof xxx === 'function'` bilan almashtir.
- Natijani son bilan yoz (nechta chaqiruv tekshirildi, nechta muammo topildi).

### 2.2 Bo'sh holatlar (yangi mijoz uchun eng muhim)
Yangi workspace'da hech narsa yo'q: vazifa yo'q, xodim yo'q (faqat owner), bo'lim yo'q, filial yo'q, lavozim yo'q.
Har sahifa/bo'limni shu holatda tekshir:
- Cheksiz "Yuklanmoqda..." bo'lmasin
- Bo'sh massiv/null'da `.map`, `.length`, `[0]` yiqilmasin
- Har bo'sh holatda **foydali empty-state**: nima qilish kerakligini aytadigan matn + tugma ("Birinchi vazifani yarating", "Xodim taklif qiling")
- Konsolda xato bo'lmasin

### 2.3 Muvaffaqiyatli amaldan keyingi UI yangilash
`loadTeamData` bugi shu naqshdan chiqqan: yozuv saqlandi → ro'yxat yangilash yiqildi → foydalanuvchi "Xato" ko'rdi → qayta bosdi → dublikat.
Butun faylda: **har saqlash/yaratish/o'chirishdan keyingi refresh chaqiruvi alohida try/catch'da bo'lsin**, xatosi asosiy amalni "muvaffaqiyatsiz" ko'rsatmasin. Xabar: "Saqlandi — ro'yxatni yangilang".

### 2.4 Aros'ga xos qattiq yozilgan narsalar
Boshqa mijozga ko'rinmasligi kerak bo'lgan hamma narsani top:
- Workspace ID, filial/ombor nomlari, lavozim ro'yxatlari, Aros logotipi/matnlari
- aros_staff importiga oid UI
- Telegram/n8n/Provodka bilan bog'liq tugmalar (agar bo'lsa) — bular faqat Aros uchun
Har birini `currentWorkspaceId === AROS_WS` sharti ostiga ol yoki umumiy qil. Ro'yxatini chiqar.

### 2.5 Xatolarni ko'rsatish
- Har `catch` blokida xato **foydalanuvchiga ko'rinsinmi** yoki jimgina yutilyaptimi — tekshir. Jimgina yutilgan joylar eng xavfli (nima bo'lganini bilib bo'lmaydi).
- Supabase xatolari o'zbekcha, tushunarli matn bilan (RLS/403 → "Ruxsat yo'q", tarmoq → "Ulanishda muammo, qayta urinib ko'ring").
- Konsolda `console.error` qolsin (debug uchun), lekin foydalanuvchi ham xabar ko'rsin.

### 2.6 Tashqi bog'liqliklar
CDN'dan yuklanadigan kutubxonalar (`supabase-js`, `xlsx` va h.k.) — O'zbekistonda CDN beqaror, bir marta allaqachon yiqilgan (`ERR_CONNECTION_CLOSED` → butun ilova ochilmadi).
- Kutubxona yuklanmaganini tekshir (`typeof window.supabase === 'undefined'`) → cheksiz loading emas, aniq xabar + "Qaytadan urinish".
- Self-host tavsiya (repo ichiga ko'chirish) — qilsang yaxshi, qilmasang ham kamida yuqoridagi tekshiruv bo'lsin.

### 2.7 Mobil
Asosiy oqimlar telefonda: login → onboarding → vazifa yaratish → xodim taklif → jamoa ro'yxati. Sig'maydigan/bosib bo'lmaydigan joylarni top va tuzat.

### 2.8 Xavfsizlik (tez tekshiruv)
- Frontend'da **service_role kalit yo'qligini** tasdiqla (faqat anon key bo'lishi kerak — repo public!)
- Boshqa workspace ma'lumotiga so'rov ketmayaptimi (har select'da `workspace_id` filtri yoki RLS)
- Konsolga maxfiy ma'lumot chiqmasin (token, kalit)

---

## Natija ko'rinishi
Audit oxirida ro'yxat ber:
1. **Kritik** (ertagacha tuzatilishi shart) — nima va qayerda
2. **Muhim** (bir hafta ichida)
3. **Keyinga** (yaxshilanish)
Har biriga fayl/qator raqami va qisqa tavsif. Kritiklarni **darrov tuzat**, qolganini ro'yxat qilib qoldir.

## Qoidalar
- Bitta fayl: `index.html`. Boshqa faylga tegma.
- `boot()`/init modul oxirida (TDZ qoidasi).
- Sintaksis validatsiya (node vm.Script) har o'zgarishdan keyin.
- Commit qil, push men qilaman.
