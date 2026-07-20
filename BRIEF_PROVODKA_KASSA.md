# TaskFix ↔ Provodka — Harajat kassa sinxronizatsiyasi

## Maqsad
TaskFix'da hodimga **"Harajat kassa"** tick qo'yilsa → **Provodka** (alohida Supabase loyiha) da avtomatik xarajat kassa ochiladi: **nomi = hodim ismi**, ostida **"Filial · Lavozim"**. Tick olib tashlansa → kassa o'chadi (soft). Shu orqali aniq bir odamga xarajat uchun pul topshiriladi.

Provodka tomoni TAYYOR (PROVODKA_HODIM_KASSA.sql — foydalanuvchi Provodka loyihasida ishga tushiradi): `accounts` jadvalida `taskfix_user_id`, `subtitle` ustunlari va `upsert_hodim_kassa(p_taskfix_user_id, p_name, p_subtitle, p_active)` RPC bor. RPC **faqat service_role** ga ochiq.

## P1 — Checkbox Jamoa jadvalida (main)
Detalga kirmasdan o'zgartirish uchun:
- Jamoa jadvaliga **"Harajat kassa"** ustuni — checkbox, faqat owner/admin o'zgartira oladi (memberга disabled/ko'rinmas)
- Bosilganda: (1) `employee_details.harajat_kassa` yangilanadi, (2) EF chaqiriladi (pastda), (3) optimistik UI + xato bo'lsa qaytarish + toast
- Detaldagi mavjud checkbox ham xuddi shu yagona handler orqali ishlasin (ikki joyda ikki xil mantiq bo'lmasin)
- Ustun tor bo'lsin (icon/check), jadval eniga zarar bermasin

## P2 — TaskFix EF: `sync-provodka-kassa`
Nega EF: Provodka'ga yozish uchun **service key** kerak — u frontend'ga tushmasligi shart (repo public!). Kalitlar EF **env secrets**'da.

- **Verify JWT: ON**; ichkarida chaqiruvchi shu workspace **owner/admin** ekani tekshiriladi (admin-import-staff'dagi naqsh)
- Env (foydalanuvchi dashboard'da qo'shadi): `PROVODKA_URL`, `PROVODKA_SERVICE_KEY`
- Kirish: `{ workspace_id, user_id, active }` (BITTALAB — bulk emas)
- Ish tartibi:
  1. Ruxsat tekshiruvi
  2. TaskFix DB'dan yig'ish: `profiles.full_name` (yoki employee_details first+last), birinchi filial nomi (`employee_branches` → `branches.name`), lavozim (`positions.name`)
  3. `subtitle = [filial, lavozim].filter(Boolean).join(' · ')`
  4. Provodka RPC: `POST {PROVODKA_URL}/rest/v1/rpc/upsert_hodim_kassa` headers `apikey: SERVICE_KEY, Authorization: Bearer SERVICE_KEY` body `{p_taskfix_user_id, p_name, p_subtitle, p_active}`
  5. Javobdagi `ok:false` → xato qaytar (frontend checkbox'ni qaytaradi)
- Env yo'q bo'lsa → aniq xato: "PROVODKA_URL/KEY sozlanmagan"
- VERSION maydoni javobda (deploy tekshiruvi uchun, mavjud naqsh)

## P3 — Ism/filial/lavozim o'zgarganda yangilash (yengil)
Hodim detali "Saqlash"da agar `harajat_kassa = true` va ism/filial/lavozim o'zgargan bo'lsa — EF'ni `active:true` bilan qayta chaqir (RPC o'zi update qiladi). Murakkab kuzatuv shart emas — shu yetarli.

## Qoidalar
- Validatsiya har o'zgarishdan keyin; prefiks `hk*`; toza Uzbek Latin
- EF xatolari `String(e)` (JSON.stringify emas)
- HISOBOT: foydalanuvchi qadamlarini yoz (Provodka SQL → EF deploy + 2 env secret → push → sinash)

## Foydalanuvchi qadamlari (HISOBOTga kiritish uchun)
1. **Provodka** loyihasida `PROVODKA_HODIM_KASSA.sql` (1-blok ko'rish → 2-blok)
2. TaskFix EF `sync-provodka-kassa` deploy (**Verify JWT ON**) + Secrets: `PROVODKA_URL` (https://<provodka-ref>.supabase.co), `PROVODKA_SERVICE_KEY`
3. Push + hard refresh
4. Sinov: Jamoa'da bitta hodimga tick → Provodka Kassa sahifasida "Ism (Filial · Lavozim)" paydo bo'lishi; tick olib tashlash → yo'qolishi
