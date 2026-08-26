# TASKFIX — 8 ish (tavsif editor + ranglar + filter + izoh tarix + qabul qiluvchi)

Fayl: `index.html` (Supabase `nnpsbwsppgxbytlfloth`). 🔴 Eski buzilmasin. 🔴 i18n uz/ru/en (har yangi string 3 til). 🔴 Emoji yo'q — Lucide (EMOJI_IC). Push Asilbek. Prod: tasdiqlagach. SQL additive.

## 1. Tavsif — Word'dek rich text editor
- Tavsif (task description) joyini KATTAroq + SCROLL (jurnaldek/Word'dek ochilsin).
- 🔴 Rich text (Word'dek format): rang, shrift (font), o'lcham, qalin (bold), kursiv (italic).
- Harflarni formatlash — matnni belgilab rang/shrift/o'lcham o'zgartirish.
- Scroll bo'lsin (uzun matn), kattaroq joy.
- CC to'liq rich text editor (contenteditable yoki yengil kutubxona — mavjud stack'ga mos, og'ir emas).
- 🔴 Saqlash: format bilan (HTML yoki rich format) DB'da saqlanadi, qayta ochilganda ko'rinadi.

## 2. Deadline ranglari — jadval view
Jadval view'da deadline rangi:
- 🔴 Deadline o'tib ketgan + task YOPILMAGAN → QIZIL.
- 🔴 Deadline vaqtida yopilgan → YASHIL.
- 🔴 Deadline o'tib ketgan LEKIN task yopilgan → QIZIL+YASHIL (yarmi qizil, yarmi yashil, ranglar bir-biriga yeb ketsin — gradient/split).
- Ya'ni 3 holat: qizil (kechikkan+ochiq), yashil (vaqtida), qizil-yashil (kechikkan lekin yopilgan).

## 3. Statuslar uchun rang
- Har status uchun rang (ochilmagan/jarayonda/bajarilgan/bekor va h.k. — mavjud statuslar).
- Status rangi jadval + kanban'da ko'rinsin (ajralib tursin).
- CC mos ranglar (status mantiqiga: kutmoqda=kulrang, jarayon=ko'k, bajarildi=yashil, muddat o'tdi=qizil...).

## 4. Deadline + status filterlarini yaxshilash
- Deadline filter (o'tgan/bugun/ertaga/kelajak/muddatsiz) — yaxshilansin.
- Status filter — yaxshilansin.
- CC filterlarni qulay, aniq qilsin (multiselect, tez).

## 5. Izoh tarixi (audit) 🔴
- Hozir izoh o'chsa tarix yozilmayapti.
- 🔴 Izoh o'chirilsa/o'zgartirilsa — TARIXDA qolsin. To'liq audit:
  - Nima yozilgan edi (matn).
  - Kim yozgan (muallif).
  - Kim o'chirdi/tahrirladi.
  - Qachon (yozilgan vaqt + o'chirilgan/tahrirlangan vaqt).
- Ya'ni izoh o'chsa yo'qolmaydi — tarixda "X yozgan edi: ..., Y o'chirdi (sana)".
- DB: izoh audit jadval (comment_id, matn, muallif, amal[yozildi/o'chirildi/tahrirlandi], kim, qachon).

## 6. Bajarildi column — qachon bajarilgani
- Bajarildi column'da: bajarilgan vazifa QACHON bajarilgani ko'rinsin.
- 🔴 Ichida ham (task detali), tashqarida ham (jadval/kanban column).
- Ya'ni bajarilgan sana/vaqt — column'da + task ichida.

## 7. Takrorlanuvchi vazifa filtri
- 🔴 Takrorlanuvchi (recur) vazifalarni ko'rish uchun ALOHIDA filter.
- Kanban'da HAM, jadval view'da HAM.
- Filter: "faqat takrorlanuvchi" (recur=true) — ajratib ko'rsatadi.

## 8. Qabul qiluvchi (acceptor) mantiqi 🔴 MUHIM
Hozir: qabul qiluvchi task'da bajaruvchi 'bajarildi' qilsa → task reassign bo'ladi qabul qiluvchiga.
🔴 Yangi mantiq (o'zgartirish):
- Task ASSIGNED turadi bajaruvchida (reassign QILINMAYDI).
- + Qabul qiluvchida HAM ko'rinadi (assigned for — ikkisida ham).
- Ya'ni: bajaruvchida assigned, qabul qiluvchida ham assigned (ikki joyda).
- 🔴 "Bajarildi" bosish FAQAT qabul qiluvchida bo'lsin.
  - Bajaruvchi 'bajarildi' bossa → ERROR message (siz bajarolmaysiz, qabul qiluvchi tasdiqlaydi).
  - Faqat qabul qiluvchi 'bajarildi' qila oladi.
  - 🔴 ADMIN mustasno — admin ham 'bajarildi' qila oladi.
- Ya'ni: bajaruvchi ishlaydi, qabul qiluvchi (yoki admin) tasdiqlaydi (bajarildi).

## Fable oqimi
coder (rich text editor, deadline/status ranglar, filter, izoh audit, bajarildi sana, recur filter, qabul qiluvchi mantiq), designer (Word'dek editor, ranglar — Apple, filter, audit ko'rinish), tester (🔴 rich text saqlanadi, ranglar 3 holat, izoh audit to'liq, bajarildi sana, recur filter, qabul qiluvchi — bajaruvchi bajarildi bosolmaydi (error), qabul qiluvchi+admin bosadi, eski buzilmagan). 🔴 i18n uz/ru/en. 🔴 Emoji yo'q. Dev-first. SQL additive (men RUN). Push men.

## Tartib
1. Tavsif rich text editor (Word'dek).
2. Deadline ranglari (jadval — 3 holat).
3. Status ranglari.
4. Filter yaxshilash (deadline + status).
5. Izoh audit (tarix — kim/qachon/o'chirdi).
6. Bajarildi sana (column + ichida).
7. Recur filter (kanban + jadval).
8. 🔴 Qabul qiluvchi mantiq (assigned ikkisida, bajarildi faqat qabul qiluvchi/admin).
