// ============================================================
// admin-import-staff — v2-photos-2026-07-17
//
// aros_staff JSON'idan hodim import qiladi. Bo'laklab chaqiriladi.
//
// IKKI FAZA:
//   phase='identity' (default) — auth user + workspace_members + staff_import_map
//   phase='photos'             — manba rasmini Storage'ga ko'chirish
//
// Boshqa hech narsa bu yerda EMAS. employee_details, employee_branches,
// employee_schedule_days, legacy_id_map — hammasi MIJOZDA, owner huquqi
// bilan RLS orqali yoziladi. Sabab: EF ga faqat service_role MAJBURAN
// talab qiladigan ish beriladi (auth user yaratish, rasm fetch — brauzerda
// CORS to'sadi). Shunda service_role sirti kichik qoladi va 150s limitga
// urilmaymiz.
//
// Maydon xaritasi / normalizatsiya — MIJOZ tomonida (index.html:
// hrImportMapRow / hrImportNormPhone / hrImportNormDate). Bu funksiya
// normalizatsiya QILINGAN qatorni kutadi va o'zi QAYTA tekshiradi
// (looksE164 + expectedEmail) — mijozga ishonmaymiz.
//
// TALAB QILADI:
//   40 → staff_import_map, auth_user_id_by_email()
//   41 → employee_details.photo_path, employee-photos bucket (phase='photos')
//
// NEGA yangi funksiya, admin-create-employee'ga qo'shimcha emas:
//   • u inviteUserByEmail ishlatadi → 130 ta email yuborardi, ustiga
//     @staff.taskfix.org soxta domen — xatlar qaytadi
//   • u "Verify JWT" OFF bilan deploy qilingan; bu yerda ON
//   • ishlayotgan taklif oqimini buzmaymiz
//
// DEPLOY: "Verify JWT" — ON (default). Quyidagi kod chaqiruvchi
//         workspace owner/admin ekanini ALOHIDA tekshiradi.
// ============================================================

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

const VERSION = 'v2-photos-2026-07-17';

const CORS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const EMAIL_DOMAIN = 'staff.taskfix.org';

// Bir invoke'da nechta qator — mijoz ham shu bilan bo'lakka bo'ladi.
// 130 × ~0.4s createUser Edge Function vaqt limitiga yaqinlashadi.
const MAX_ROWS_PER_CALL = 25;

// Rasm sekinroq: har biri tashqi fetch + Storage upload. 126 × ~1s
// bitta chaqiruvda 150s limitga urilardi — shuning uchun kichikroq bo'lak.
const MAX_PHOTOS_PER_CALL = 10;

const PHOTO_BUCKET = 'employee-photos';
const PHOTO_FETCH_TIMEOUT_MS = 15_000;   // osilib qolgan URL butun chaqiruvni yemasin
const PHOTO_MAX_BYTES = 5 * 1024 * 1024;

type RowStatus = 'created' | 'adopted' | 'updated' | 'skipped' | 'error';
type PhotoStatus = 'uploaded' | 'skipped' | 'error';

interface InRow {
  source_id: string;
  phone_e164: string;
  email: string;
  full_name?: string | null;
  // Qolgan HR maydonlari (ism, familiya, lavozim, shartnoma…) bu funksiyaga
  // KELMAYDI — ularni mijoz RLS orqali o'zi yozadi (owner sifatida).
  // Bu yerda faqat service_role talab qiladigan ish bajariladi:
  //   auth user + workspace_members + staff_import_map
}

interface OutRow {
  source_id: string;
  status: RowStatus;
  user_id: string | null;
  reason: string | null;
}

// phase='photos' — identitet allaqachon yaratilgan, endi rasm.
interface PhotoRow {
  user_id: string;      // TaskFix auth UUID (identity fazasi qaytargan)
  image_url: string;    // manba URL (api.staff.aros.uz/...)
}

interface PhotoOut {
  user_id: string;
  status: PhotoStatus;
  path: string | null;
  reason: string | null;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

function fail(error: string, detail?: string, status = 400, hint?: string): Response {
  // admin-create-employee'ning javob shakli — mijozdagi xato ishlovi
  // (index.html: fnErr.context.json() → error/detail/hint/v) shuni kutadi.
  return json({ ok: false, error, detail: detail ?? null, hint: hint ?? null, v: VERSION }, status);
}

// "already registered" — GoTrue xabari versiyaga qarab o'zgaradi,
// shuning uchun matn bo'yicha keng qidiramiz (index.html:3046 shu naqsh).
function isAlreadyRegistered(err: { message?: string; status?: number } | null): boolean {
  if (!err) return false;
  if (err.status === 422) return true;
  return /already|registered|exists|duplicate/i.test(err.message || '');
}

// E.164 ni QAYTA tekshiramiz — mijozga ishonmaymiz.
// Bu normalizatsiya EMAS (u mijozda), faqat shakl tekshiruvi.
function looksE164(p: string): boolean {
  return /^\+[1-9]\d{7,14}$/.test(p);
}

// Email telefondan deterministik hosil bo'ladi — mijoz yuborganini
// tasdiqlaymiz, ixtiyoriy email qabul qilmaymiz.
function expectedEmail(phoneE164: string): string {
  return phoneE164.replace(/^\+/, '') + '@' + EMAIL_DOMAIN;
}

function isUuid(s: unknown): boolean {
  return typeof s === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

// Faqat http(s). Manba URL'i mijozdan keladi — unga ishonmaymiz.
// Bu SSRF'ga to'liq qarshi emas (bu yerda kerak ham emas: chaqiruvchi
// allaqachon workspace admini), lekin file:// va data: ni to'sadi.
function looksHttpUrl(u: unknown): boolean {
  if (typeof u !== 'string') return false;
  try {
    const p = new URL(u);
    return p.protocol === 'http:' || p.protocol === 'https:';
  } catch (_) {
    return false;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return fail('method_not_allowed', 'Faqat POST', 405);

  try {
    // ---- 1) Chaqiruvchini aniqlaymiz (Verify JWT ON bo'lsa ham o'zimiz tekshiramiz) ----
    const authHeader = req.headers.get('Authorization') || '';
    if (!authHeader.startsWith('Bearer ')) {
      return fail('unauthorized', 'Authorization sarlavhasi yo\'q', 401);
    }

    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
    const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    if (!SUPABASE_URL || !SERVICE_KEY) {
      return fail('config', 'SUPABASE_URL yoki SERVICE_ROLE_KEY sozlanmagan', 500);
    }

    // Chaqiruvchi kim — uning o'z JWT'si bilan
    const asCaller: SupabaseClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userRes, error: uErr } = await asCaller.auth.getUser();
    if (uErr || !userRes?.user) return fail('unauthorized', 'JWT yaroqsiz', 401);
    const callerId = userRes.user.id;

    // ---- 2) Body ----
    const body = await req.json().catch(() => null);
    if (!body) return fail('bad_body', 'JSON o\'qib bo\'lmadi');

    const workspaceId: string = body.workspace_id;
    const rows: InRow[] = Array.isArray(body.rows) ? body.rows : [];
    const dryRun: boolean = body.dry_run === true;
    const sourceSystem: string = body.source_system || 'aros_staff';
    const importRunId: string | null = body.import_run_id || null;
    const phase: string = body.phase || 'identity';

    if (!workspaceId) return fail('bad_body', 'workspace_id majburiy');
    if (phase !== 'identity' && phase !== 'photos') {
      return fail('bad_body', `phase noma'lum: ${phase}`, 400, "identity yoki photos");
    }
    if (!rows.length) return fail('bad_body', 'rows bo\'sh');

    const maxRows = phase === 'photos' ? MAX_PHOTOS_PER_CALL : MAX_ROWS_PER_CALL;
    if (rows.length > maxRows) {
      return fail('too_many_rows', `Bir chaqiruvda ${maxRows} tadan ko'p bo'lmasin (keldi: ${rows.length}, phase: ${phase})`,
        400, 'Mijoz tomonda bo\'laklarga bo\'ling');
    }

    // import_run_id — rollback kaliti, u FAQAT auth user yaratishga tegishli.
    // Rasm fazasida user allaqachon bor, qaytariladigan narsa yo'q.
    if (phase === 'identity' && !dryRun && !importRunId) {
      return fail('bad_body', 'import_run_id majburiy (dry_run bo\'lmasa)', 400,
        'Rollback shu id bo\'yicha ishlaydi');
    }

    // ---- 3) Ruxsat: chaqiruvchi shu workspace'ning owner/admin'imi ----
    // service_role RLS'ni chetlab o'tadi — shuning uchun bu tekshiruv
    // MAJBURIY, aks holda istalgan foydalanuvchi istalgan workspace'ga
    // hodim qo'sha oladi.
    const admin: SupabaseClient = createClient(SUPABASE_URL, SERVICE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: mem, error: mErr } = await admin
      .from('workspace_members')
      .select('role')
      .eq('workspace_id', workspaceId)
      .eq('user_id', callerId)
      .maybeSingle();
    if (mErr) return fail('db', mErr.message, 500);
    if (!mem || (mem.role !== 'owner' && mem.role !== 'admin')) {
      return fail('forbidden', 'Faqat workspace owner yoki admin import qila oladi', 403);
    }

    // ---- 3b) FAZA: rasm ----
    // Nega bu yerda, mijozda emas: manba rasmini brauzer OLOLMAYDI (CORS),
    // va Storage'ga yozish service_role talab qiladi (41-migratsiyada
    // employee-photos uchun yozish policy'si ATAYLAB yo'q).
    if (phase === 'photos') {
      const photoRows = rows as unknown as PhotoRow[];
      const photoResults: PhotoOut[] = [];

      // Mijoz ixtiyoriy user_id yubormasin — kim shu workspace a'zosi ekanini
      // bitta so'rovda aniqlaymiz (har qator uchun alohida so'rov qilmaymiz).
      const wantIds = photoRows.map((r) => r?.user_id).filter((id) => isUuid(id));
      const memberIds = new Set<string>();
      if (wantIds.length) {
        const { data: mems, error: msErr } = await admin
          .from('workspace_members')
          .select('user_id')
          .eq('workspace_id', workspaceId)
          .in('user_id', wantIds);
        if (msErr) return fail('db', 'a\'zolarni o\'qishda: ' + msErr.message, 500);
        (mems || []).forEach((m: { user_id: string }) => memberIds.add(m.user_id));
      }

      for (const row of photoRows) {
        const out: PhotoOut = { user_id: String(row?.user_id ?? ''), status: 'skipped', path: null, reason: null };
        try {
          if (!isUuid(row?.user_id)) { out.reason = 'user_id UUID emas'; photoResults.push(out); continue; }
          if (!looksHttpUrl(row?.image_url)) { out.reason = 'image_url http(s) emas'; photoResults.push(out); continue; }
          if (!memberIds.has(row.user_id)) {
            out.reason = 'bu user shu workspace a\'zosi emas';
            photoResults.push(out); continue;
          }

          // Kengaytma HAR DOIM .jpg — 41-migratsiyadagi storage RLS policy'si
          // ("o'z rasmi" tekshiruvi) aynan shu naqshga tayanadi. Haqiqiy
          // content-type esa Storage metadatasida saqlanadi.
          const path = `${workspaceId}/${row.user_id}.jpg`;

          if (dryRun) {
            out.status = 'uploaded';   // quruq yurgizishda "yuklanardi"
            out.path = path;
            photoResults.push(out);
            continue;
          }

          const resp = await fetch(row.image_url, { signal: AbortSignal.timeout(PHOTO_FETCH_TIMEOUT_MS) });
          if (!resp.ok) throw new Error(`manba ${resp.status} qaytardi`);

          const ctype = (resp.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
          // Manba content-type'ni har doim to'g'ri qo'ymaydi — o'lchangan:
          // 80 ta ishlaydigan rasmda 'image/jpeg' VA 'application/octet-stream'
          // ikkalasi ham uchraydi. Shuning uchun oq ro'yxat emas, QORA ro'yxat:
          // faqat aniq rasm bo'lmagan javoblarni rad etamiz (login sahifasi,
          // JSON xato). Bo'sh content-type — ruxsat.
          if (ctype && (ctype.startsWith('text/') || ctype === 'application/json')) {
            throw new Error(`rasm emas (content-type: ${ctype})`);
          }

          const buf = new Uint8Array(await resp.arrayBuffer());
          if (!buf.byteLength) throw new Error('bo\'sh javob');
          if (buf.byteLength > PHOTO_MAX_BYTES) {
            throw new Error(`juda katta: ${Math.round(buf.byteLength / 1024)} KB`);
          }

          const { error: upErr } = await admin.storage.from(PHOTO_BUCKET)
            .upload(path, buf, { upsert: true, contentType: ctype || 'image/jpeg' });
          if (upErr) throw new Error('upload: ' + upErr.message);

          // employee_details qatorini mijoz allaqachon yozgan. Bu yerda FAQAT
          // photo_path yangilanadi — update, upsert EMAS: qator yo'q bo'lsa
          // tartib buzilgan, jimgina yarim-yorti qator yaratmaymiz.
          const { data: updated, error: pErr } = await admin
            .from('employee_details')
            .update({ photo_path: path })
            .eq('workspace_id', workspaceId)
            .eq('user_id', row.user_id)
            .select('user_id');
          if (pErr) throw new Error('photo_path: ' + pErr.message);
          if (!updated || !updated.length) {
            throw new Error('employee_details qatori topilmadi — avval HR maydonlarini yozing');
          }

          out.status = 'uploaded';
          out.path = path;
        } catch (e) {
          // Rasm xatosi importni TO'XTATMAYDI — hisobotga tushadi, davom etamiz.
          out.status = 'error';
          out.reason = (e as Error).message || String(e);
        }
        photoResults.push(out);
      }

      const photoSummary = photoResults.reduce((acc: Record<string, number>, r) => {
        acc[r.status] = (acc[r.status] || 0) + 1;
        return acc;
      }, {});

      return json({
        ok: true, v: VERSION, phase: 'photos', dry_run: dryRun,
        summary: photoSummary, results: photoResults,
      });
    }

    // ---- 4) Qator-qator ----
    // MUHIM: bitta qator yiqilsa BUTUN chaqiruv yiqilmaydi. Xato yig'iladi,
    // qolganlari davom etadi. Import idempotent — tuzatib qayta yurgiziladi.
    const results: OutRow[] = [];

    for (const row of rows) {
      const out: OutRow = { source_id: String(row?.source_id ?? ''), status: 'skipped', user_id: null, reason: null };
      try {
        // --- Blokerlar (mijoz ham tekshiradi; bu ikkinchi qatlam) ---
        if (!out.source_id) { out.reason = 'source_id yo\'q'; results.push(out); continue; }
        if (!row.phone_e164 || !looksE164(row.phone_e164)) {
          out.reason = 'phone_e164 yo\'q yoki E.164 emas: ' + (row.phone_e164 ?? '—');
          results.push(out); continue;
        }
        const wantEmail = expectedEmail(row.phone_e164);
        if (row.email && row.email.toLowerCase() !== wantEmail) {
          out.reason = `email telefondan hosil bo'lmagan (kutildi: ${wantEmail})`;
          results.push(out); continue;
        }

        // --- 4a) Map'da bormi? (idempotentlik, 1-qatlam) ---
        const { data: mapped, error: mapErr } = await admin
          .from('staff_import_map')
          .select('user_id')
          .eq('workspace_id', workspaceId)
          .eq('source_system', sourceSystem)
          .eq('source_id', out.source_id)
          .maybeSingle();
        if (mapErr) throw new Error('map o\'qishda: ' + mapErr.message);

        let userId: string | null = mapped?.user_id ?? null;
        let createdNow = false;

        if (userId) {
          out.status = 'updated';   // kutilgan holat, xato emas
        } else {
          // --- 4b) Yaratamiz ---
          if (dryRun) {
            out.status = 'created';           // quruq yurgizishda "yaratilardi"
            out.user_id = null;
            results.push(out);
            continue;
          }

          const { data: created, error: cErr } = await admin.auth.admin.createUser({
            email: wantEmail,
            phone: row.phone_e164,
            // Soxta email — tasdiqlash xati yubormaymiz, darrov tasdiqlangan.
            email_confirm: true,
            phone_confirm: true,
            user_metadata: {
              full_name: row.full_name ?? null,
              source_system: sourceSystem,
              source_id: out.source_id,
            },
          });

          if (cErr && isAlreadyRegistered(cErr)) {
            // --- Adopt (idempotentlik, 2-qatlam) ---
            // User bor, lekin map'da yo'q → oldingi yurgizish map yozishdan
            // oldin uzilgan. Topamiz va bog'laymiz. Bu xavfsiz: email
            // telefondan hosil bo'lgan, ya'ni email mos → telefon ham mos.
            const { data: foundId, error: fErr } = await admin
              .rpc('auth_user_id_by_email', { p_email: wantEmail });
            if (fErr) throw new Error('adopt (rpc): ' + fErr.message);
            if (!foundId) {
              // "already registered" dedi, lekin email bo'yicha topilmadi →
              // ehtimol TELEFON band (boshqa email bilan). Bu haqiqiy to'qnashuv.
              throw new Error('telefon yoki email band, lekin bu email bo\'yicha user topilmadi — qo\'lda tekshiring');
            }
            userId = foundId as string;
            out.status = 'adopted';
          } else if (cErr) {
            throw new Error('createUser: ' + cErr.message);
          } else {
            userId = created.user!.id;
            createdNow = true;
            out.status = 'created';
          }
        }

        if (!userId) throw new Error('user_id aniqlanmadi');
        out.user_id = userId;

        // --- 4c) workspace_members ---
        // RLS uchun SHART: is_ws_member()/is_ws_manager() shu jadvalga tayanadi.
        // Bo'lmasa hodim tizimga kirsa ham hech narsa ko'rmaydi.
        const { error: wmErr } = await admin
          .from('workspace_members')
          .upsert({ workspace_id: workspaceId, user_id: userId, role: 'member' },
                  { onConflict: 'workspace_id,user_id', ignoreDuplicates: true });
        if (wmErr) throw new Error('workspace_members: ' + wmErr.message);

        // --- 4d) staff_import_map ---
        // Darrov yozamiz — keyingi qatorda uzilib qolsa yetim auth user qolmasin.
        const { error: siErr } = await admin
          .from('staff_import_map')
          .upsert({
            workspace_id: workspaceId,
            source_system: sourceSystem,
            source_id: out.source_id,
            user_id: userId,
            phone_e164: row.phone_e164,
            import_run_id: importRunId,
            created_in_run: createdNow,   // rollback FAQAT shularni o'chiradi
            last_imported_at: new Date().toISOString(),
          }, { onConflict: 'workspace_id,source_system,source_id' });
        if (siErr) throw new Error('staff_import_map: ' + siErr.message);

      } catch (e) {
        out.status = 'error';
        out.reason = (e as Error).message || String(e);
      }
      results.push(out);
    }

    const summary = results.reduce((acc: Record<string, number>, r) => {
      acc[r.status] = (acc[r.status] || 0) + 1;
      return acc;
    }, {});

    return json({ ok: true, v: VERSION, phase: 'identity', dry_run: dryRun, import_run_id: importRunId, summary, results });

  } catch (e) {
    return fail('unexpected', (e as Error).message || String(e), 500);
  }
});
