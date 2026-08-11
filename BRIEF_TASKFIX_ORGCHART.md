# BRIEF — Org Chart: zoom, drag, qo'lda joylashuv (2026-08-08)

Uch muammo, uch alohida commit. Hech biri eski funksiyaga (vazifa/kanban/HR papka
ko'rinishi) tegmaydi — o'zgarish faqat `osc*` chart qismida va **additive** SQL'da.

---

## 1. Zoom faqat org chart bo'lsin (butun sahifa emas)

**Sabab (aniqlangan)**: chart o'zi allaqachon `transform: scale()` ni faqat
`#oscStage` ga qo'llardi — ya'ni kod xato emas edi. Muammo boshqa joyda:
**chartda `wheel` hodisasi umuman ushlanmagan**. Trackpad'da pinch qilish
brauzerga `ctrl+wheel` bo'lib boradi va `preventDefault()` qilinmagani uchun
**brauzer butun sahifani** kattalashtirardi (sichqoncha g'ildiragi esa shunchaki
scroll qilardi). Ya'ni "zoom butun sahifani kattalashtiryapti" = brauzerning
sahifa zoom'i, chartniki emas.

**Yechim**:
- `oscViewport` ga `wheel` listener'i (`{passive:false}`) + `preventDefault()`
  → sahifa zoom'i **bo'lmaydi**, o'rniga chart zoom bo'ladi.
- Pinch (`e.ctrlKey`) va oddiy g'ildirak — ikkalasi ham chart zoom'i
  (pinch nozikroq qadam bilan). `shift+g'ildirak` — brauzerga qoldiriladi
  (gorizontal scroll).
- **Kursor ostida zoom**: masshtab o'zgarganda kursor tagidagi nuqta joyida
  qoladi (`scrollLeft/Top` qayta hisoblanadi) — Apple/Figma xatti-harakati.
- `deltaMode` normallashtiriladi (line/page rejimidagi sichqonchalar).
- **Scroll maydoni tuzatildi**: `transform` element o'lchamini o'zgartirmaydi,
  shuning uchun 100% dan kattalashtirilganda sahnaning o'ng/past qismiga
  scroll qilib bo'lmasdi. Endi sahna `#oscCanvas` ichida — uning o'lchami
  `natural × zoom` qilib qo'yiladi.
- Tugmalar: `−` / `+` / `Sig'dirish` / `100%` (reset) — o'zgarishsiz, lekin
  endi viewport markazini ushlab qoladi.
- Chegara `0.3…2.5` (avval `0.25…2`).

## 2. Drag — kartani qo'lda surish

- `oscViewport` dagi `mousedown` allaqachon pan uchun ishlatilardi; endi
  **karta ustida** boshlansa (va `oscCanEdit()`) — pan emas, **drag**.
- Suriladi: hodim, papka va birlashgan (papka·hodim) kartochka.
- **Ostidagilar birga siljiydi** — rahbarni surganda jamoasi ergashadi
  (aks holda chiziqlar cho'zilib, sxema o'qilmay qolardi). ⚠️ Lekin
  **qo'lda deb faqat surilgan tugun belgilanadi**: ostidagilar avto bo'lib
  qolaveradi (keyin yangi xodim qo'shilsa, o'zi to'g'ri joyga tushadi).
- Chiziqlar **surish paytida real vaqtda** qayta chiziladi (`requestAnimationFrame`).
- Zoom hisobga olinadi (`delta / oscZoom`), 0 dan chapga/tepaga chiqmaydi.
- **Bosish (klik) bilan chalkashmaydi**: 3px dan kam siljish — oddiy bosish
  (hodim sahifasi ochiladi); ko'proq siljisa keyingi `click` capture fazasida
  yutiladi.
- Amal tugmalari (`.osc-cact`) ustidan drag boshlanmaydi.

## 3. Qo'lda surilgan joy saqlanadi va avto layout unga tegmaydi

**DB (`TASKFIX_ORGCHART.sql`, additive)**: `node_x` / `node_y`
(`double precision`, NULL = avto) — **`org_people` VA `org_folders`** ga.
Brifda faqat `org_people` aytilgandi, lekin chartda papka kartochkasi ham bor
(papkada 0 yoki 2+ hodim bo'lganda) — bittasiga qo'shsak, kartalarning bir
qismi surilmay qolardi. `CHECK ((node_x IS NULL) = (node_y IS NULL))` —
yarim to'ldirilgan holat bo'lmasin. RLS o'zgarmaydi (mavjud
`org_*_update` policy'lari yetarli).

**Birlashgan kartochka** (papka·hodim bitta kartada) — joyi **papka**
qatorida saqlanadi (tugun kaliti ham papkaniki). Keyin papkaga ikkinchi
xodim qo'shilib birlashish buzilsa, papka o'z joyida qoladi, hodim avtoga
qaytadi — mantiqan to'g'ri.

**Layout**: `oscLayout()` avval hammasini avtomat joylaydi (o'zgarishsiz
algoritm), keyin ustidan qo'lda qiymatlar qo'yiladi:
- qo'lda tugun → aynan `node_x/node_y`;
- uning avlodi → **ota qancha siljigan bo'lsa, shuncha siljiydi** (avto
  bo'lib qolaveradi);
- qolgani → avvalgidek avto.

⚠️ Qo'lda surilgan tugunning avtomatik **o'rni bo'sh qoladi** (ataylab):
shunda bitta kartani surganda qolgan sxema "sakramaydi".

**Qaytarish**: har surilgan kartada ↺ tugmasi (faqat o'sha karta), va
panelda **"Avto joylashuv"** tugmasi (hammasi, tasdiq bilan). Ikkalasi ham
`node_x/node_y = NULL` yozadi.

**Saqlash**: `oscSaveNodePos()` — `.update(...).eq('id').select()` va
`if (error) throw error` + bo'sh natija = RLS to'sgan (6-qoida). Xato bo'lsa
**karta eski joyiga qaytariladi** va toast chiqadi (yolg'on "saqlandi" yo'q).
SQL ishga tushmagan bo'lsa (`node_x` ustuni yo'q, `42703`) — bir marta
ogohlantiruvchi toast, surish o'sha sessiyada ishlaydi (lekin saqlanmaydi),
ilova yiqilmaydi.

---

## ⚠️ Avvalgi qarorning bekor qilinishi

CLAUDE.md da (2026-08-06) shunday yozilgan edi: *"Joylashuv har safar qaytadan
hisoblanadi, `node_x/node_y` SAQLANMAYDI — ikki ko'rinish ajralib qola olmaydi
(eski `oc*` dagi 'qo'lda surilgan tugun eskiradi' muammosi yo'q)"*.

Bu qaror **foydalanuvchi talabi bilan bekor qilindi** (2026-08-08). Eski
muammoning qaytmasligi uchun:
- daraxt (papka ko'rinishi) va bo'ysunish mantig'i **avvalgidek** faqat
  `parent_id`/`parent_person_id`/`folder_id` dan hisoblanadi — `node_x/node_y`
  **ma'no tashimaydi**, faqat chizish uchun;
- qo'lda joy **hech qachon** tugunni daraxtdan ajratmaydi: yangi bola qo'shilsa
  ota tagida avto joylashadi va otasi bilan birga siljiydi;
- bitta tugma bilan hammasi avtoga qaytadi.

---

## Test qilingan holatlar (qo'lda)

- Pinch/g'ildirak chart ustida → **sahifa** zoom bo'lmaydi, chart bo'ladi.
- 200% da o'ng/past chekkaga scroll qilinadi (avval mumkin emas edi).
- Kartani surish → chiziqlar ergashadi; ostidagilar birga siljiydi.
- Surib qo'yib yuborilgach `oscRenderChart()` qayta chizadi — karta o'sha joyda.
- Sahifani qayta ochish → joy saqlangan (SQL ishga tushgan bo'lsa).
- Yangi xodim qo'shish → avto joylashadi, surilganlarga tegmaydi.
- "Avto joylashuv" → hammasi asl holatga.
- SQL ishga tushmagan holat → toast, ilova ishlayveradi.
