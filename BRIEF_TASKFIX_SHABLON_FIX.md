# TASKFIX — Shablon konsept TUZATISH + taxminiy deadline + kanban tarix

Fayl: `index.html`. 🔴 Eski buzilmasin. 🔴 i18n uz/ru/en. 🔴 Emoji yo'q — Lucide. Push Asilbek. Prod: tasdiqlagach.

## ⚠️ KONSEPT TUZATISH (oldin noto'g'ri tushunilgan)
Oldingi SHABLON ishida "shablon" alohida section/so'z sifatida chiqqan — bu NOTO'G'RI. To'g'ri konsept:

### To'g'ri konsept:
- 🔴 Loyiha Flow'da turgan bosqichlar = SHABLON (alohida "shablon" section YO'Q, alohida so'z YO'Q).
- "Yangi bosqich qo'shish" bosilganda → "SHABLON qo'shish" modal ochilsin (bosqich = shablon yaratish).
- Ya'ni loyiha ichida "task" tushunchasi YO'Q — Flow'dagilar shablon.
- Shablon vaqti kelganda → HAQIQIY TASK create bo'ladi (avvalgidek).
- 🔴 LEKIN: yaratilgan task loyiha ICHIGA ALOQASI YO'Q — u loyiha ichida ko'rinmaydi.
- Task faqat KANBAN VIEW'да ko'rinadi (loyiha ichida, kanban view).

### Nima o'zgaradi:
- "Shablon" so'zini UI'da to'g'ri joylashtir: Flow bosqichi = shablon (bosqich qo'shish = shablon qo'shish modal).
- Alohida "shablon" ro'yxati/section BO'LMASIN (agar qo'shilган bo'lsa — olib tashla).
- Loyiha ichida (Flow) — shablonlar. Kanban view — haqiqiy tasklar (shablondan tug'ilgan).
- ⚠️ CC oldingi implementatsiyani ko'rib, "shablon" ni to'g'ri joyga qo'ysin (Flow = shablon, alohida section yo'q).

## 1. Kanban view — tarix (eski sikllar)
- 🔴 Loyiha ichida KANBAN view'да tarix ko'rinsin: eski/tugallangan loyihalarning tasklari QANDAY HOLDA tugagani.
- Masalan: reja tasklari hammasi bajarilganmi, qaysi holatda tugagan (reja/fakt).
- Hozir tarix KO'RINMAYAPTI — tekshir: tarix bormi (yangi loyiha bo'lsa yo'q), yoki filter/ko'rsatish ishlamayaptimi.
- Sikl filter (oldingi) bilan: har sikl (1-5 09.2026...) tanlanganda o'sha sikl tasklari reja/fakt holati.
- ⚠️ Agar tarix yo'q bo'lsa (hali sikl tugamagan) — bo'sh holatni aniq ko'rsat ("hali tarix yo'q"), xato emas.
- Kanban view'да haqiqiy tasklar (shablondan) — o'tган sikllar bo'yicha.

## 2. Taxminiy deadline — yaratishdan OLDIN
- Hozir ketma-ket taxminiy deadline task YARATILGANDAN KEYIN ko'rsatilyapti.
- 🔴 To'g'ri: taxminiy deadline yaratishdan OLDIN — deadline (kun soni) qo'ygan ZAHOTI ko'rinsin.
- Ya'ni: user shablon/bosqich yaratayotganda, kun soni qo'ysa → darrov taxminiy tugash sanasi ko'rinsin (jonli, formada).
- Zanjir bo'yicha (ketma-ket) — oldingi bosqichdan hisoblab taxminiy sana, formada real vaqt.
- ⚠️ Yaratish formasida (modal), deadline maydonida — kun soni o'zgarса taxminiy sana yangilanadi.

## Fable oqimi
coder (shablon konsept to'g'rilash — Flow=shablon alohida section yo'q, kanban tarix ko'rsatish/tekshir, taxminiy deadline yaratishdan oldin formada), designer (bosqich=shablon modal, kanban tarix, taxminiy deadline jonli), tester (🔴 shablon alohida section yo'q, Flow=shablon, kanban tarix ko'rinadi/bo'sh holat, taxminiy deadline yaratishdan oldin jonli, eski buzilmagan). 🔴 i18n. 🔴 Emoji yo'q. Push men.

## Tartib
1. Shablon konsept to'g'rilash (Flow=shablon, alohida section yo'q, bosqich qo'shish=shablon modal).
2. Kanban tarix (eski sikllar reja/fakt — tekshir/ko'rsat).
3. Taxminiy deadline — yaratishdan oldin (formada jonli).
Keyin katta ish (Asilbek aytadi).
