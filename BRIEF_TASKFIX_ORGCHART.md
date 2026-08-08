# TASKFIX — Org Chart 3 fix (zoom + drag + saqlash)

Fayl: `index.html` (Supabase `nnpsbwsppgxbytlfloth`). 🔴 Eski funksiyalar buzilmasin. UI/UX Apple-darajа. SQL additive → `TASKFIX_ORGCHART.sql`. Org chart = org_people + org_folders daraxti (oscDerivedManagers).

## 1. Zoom — faqat org chart, butun sahifa emas
Hozir: zoom butun sahifani kattalashtiryapti (xato). Kerak: FAQAT org chart konteyneri zoom bo'lsin.
- **G'ildirak (scroll)** bilan zoom — sichqoncha org chart ustida bo'lsa, wheel event chart'ni zoom qiladi (sahifa scroll EMAS). `preventDefault` + transform scale.
- **Zoom tugmalari (+/−)** ham — chart burchagida.
- **Pinch (trackpad)** ham — ikки barmoq.
- Zoom faqat org chart SVG/konteyneriга (transform: scale), sahifa/body zoom bo'lmasin.
- Zoom markazи — sichqoncha nuqtаsи (yoki chart markazi). Zoom bilan pan (surish) — chart ичida harakatlansин.
- Reset tugma (100%) foydali.

## 2. Drag — hodimni qo'lda surish
Hozir: hodim joyи avtomат (daraxt hisoblaydi). Kerak: hodimni **drag** bilan qo'lда surib, joyини o'zgartirish.
- Hodim kartаsини sichqoncha bilan ushlаb, chart ичida istagan joyга surish (x, y).
- Surish paytида chiziqlar (bog'lanишlар) hodim bilan harakatlansин.

## 3. Qo'lda surilgan — avto tegmaydi + saqlanadi (DB)
🔴 Eng muhим: hodim qo'lда surилса — u **avtomат joylashuvга qайtмаsин** (avto hisob uni bosмаsин). Va **saqlansин** (qayta ochganда o'sha joyда).
- DB: `org_people` ga `node_x float, node_y float` (yoki `manual_x/manual_y`) — qo'lда surilган koordinата. Null = avtomат (hisoblanади), qiymat bор = qo'lда (o'sha joyда).
- Drag tugagач → node_x/node_y saqlanади (DB).
- Render: node_x/node_y bор bo'lса — o'sha joyда (avto hisob EMAS). Null bo'lса — avto (daraxt).
- Ya'ni: avto layout faqat qo'lда surилмаganларга. Qo'lда surilган — barqaror.
- "Avto joylashuvga qайtar" tugma foydali (node_x/y null qiladi → yana avto).

## Amalga oshirish
- Zoom + pan + drag — SVG/HTML transform bilan. Kutubxonа shart emas (vanilla), lekin toza qil.
- Drag paytида zoom hisobga olinsин (scale bilan koordinата to'g'ри).
- node_x/node_y — chart koordinата (zoom/pan'дан mustaqил, ички koordinата).
- RLS: node_x/y yozиш — a'zо/manager (mavjud org_people yozиш qoidаsи).

## Tartib
1 (zoom — faqat chart) → 2 (drag) → 3 (saqlash node_x/y + avto tegmaslik). Har fix alohида commit. SQL (node_x/y) additive. 🔴 Har qadamда eski funksiя (task/kanban/HR papka) ishlаyaptими tekshir. Push Asilbek.
