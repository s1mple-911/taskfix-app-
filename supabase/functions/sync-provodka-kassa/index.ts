// ============================================================
// sync-provodka-kassa — v1-2026-07-20
//
// TaskFix'da hodimga "Harajat kassa" tick qo'yilsa → Provodka (alohida
// Supabase loyiha) da xarajat kassa ochiladi/yopiladi.
//   nomi     = hodim ismi
//   subtitle = "Filial · Lavozim"
//
// NEGA EF: Provodka'ga yozish service_role kalit talab qiladi — u frontend'ga
// TUSHMASLIGI shart (repo public). Kalitlar EF env secrets'da.
//
// Kirish: { workspace_id, user_id, active }  (BITTALAB — bulk emas)
//
// DEPLOY: "Verify JWT" — ON. Quyidagi kod chaqiruvchi shu workspace
//         owner/admin ekanini ALOHIDA tekshiradi (admin-import-staff naqshi).
//
// ENV (foydalanuvchi dashboard'da qo'shadi):
//   PROVODKA_URL          — https://<provodka-ref>.supabase.co
//   PROVODKA_SERVICE_KEY  — Provodka loyihasining service_role kaliti
//
// Provodka tomoni TAYYOR: accounts.taskfix_user_id, accounts.subtitle +
//   upsert_hodim_kassa(p_taskfix_user_id, p_name, p_subtitle, p_active) RPC
//   (faqat service_role ga ochiq).
// ============================================================

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

const VERSION = 'v1-2026-07-20';

const CORS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

function fail(error: string, detail?: string, status = 400): Response {
  return json({ ok: false, error, detail: detail ?? null, v: VERSION }, status);
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return fail('method_not_allowed', 'Faqat POST', 405);

  try {
    // ---- 1) Chaqiruvchi JWT ----
    const authHeader = req.headers.get('Authorization') || '';
    if (!authHeader.startsWith('Bearer ')) return fail('unauthorized', 'Authorization sarlavhasi yo\'q', 401);

    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
    const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    if (!SUPABASE_URL || !SERVICE_KEY) return fail('config', 'SUPABASE_URL yoki SERVICE_ROLE_KEY sozlanmagan', 500);

    // Provodka env — bularsiz ish yo'q, aniq xato beramiz
    const PROVODKA_URL = Deno.env.get('PROVODKA_URL');
    const PROVODKA_SERVICE_KEY = Deno.env.get('PROVODKA_SERVICE_KEY');
    if (!PROVODKA_URL || !PROVODKA_SERVICE_KEY) {
      return fail('config', 'PROVODKA_URL/PROVODKA_SERVICE_KEY sozlanmagan (EF Secrets)', 500);
    }

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
    const userId: string = body.user_id;
    const active: boolean = body.active === true;
    if (!workspaceId || !userId) return fail('bad_body', 'workspace_id va user_id majburiy');

    // ---- 3) Ruxsat: chaqiruvchi shu workspace owner/admin'imi ----
    const admin: SupabaseClient = createClient(SUPABASE_URL, SERVICE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: mem, error: mErr } = await admin
      .from('workspace_members').select('role')
      .eq('workspace_id', workspaceId).eq('user_id', callerId).maybeSingle();
    if (mErr) return fail('db', mErr.message, 500);
    if (!mem || (mem.role !== 'owner' && mem.role !== 'admin')) {
      return fail('forbidden', 'Faqat workspace owner yoki admin', 403);
    }

    // Target hodim shu workspace a'zosimi
    const { data: tmem, error: tErr } = await admin
      .from('workspace_members').select('user_id')
      .eq('workspace_id', workspaceId).eq('user_id', userId).maybeSingle();
    if (tErr) return fail('db', tErr.message, 500);
    if (!tmem) return fail('forbidden', 'Bu hodim shu workspace a\'zosi emas', 403);

    // ---- 4) TaskFix DB'dan ism / filial / lavozim ----
    // Ism: profiles.full_name, bo'lmasa employee_details first+last
    const [profR, detR] = await Promise.all([
      admin.from('profiles').select('full_name').eq('id', userId).maybeSingle(),
      admin.from('employee_details').select('first_name, last_name, position_id')
        .eq('workspace_id', workspaceId).eq('user_id', userId).maybeSingle(),
    ]);
    const det = (detR.data as { first_name?: string; last_name?: string; position_id?: string } | null) || null;
    let name = (profR.data as { full_name?: string } | null)?.full_name || '';
    if (!name && det) name = [det.first_name, det.last_name].filter(Boolean).join(' ').trim();
    if (!name) name = 'Hodim';

    // Birinchi filial nomi
    let branchName = '';
    const { data: eb } = await admin
      .from('employee_branches').select('branch_id')
      .eq('workspace_id', workspaceId).eq('user_id', userId).limit(1).maybeSingle();
    const branchId = (eb as { branch_id?: string } | null)?.branch_id;
    if (branchId) {
      const { data: br } = await admin.from('branches').select('name').eq('id', branchId).maybeSingle();
      branchName = (br as { name?: string } | null)?.name || '';
    }

    // Lavozim nomi
    let positionName = '';
    if (det?.position_id) {
      const { data: pos } = await admin.from('positions').select('name').eq('id', det.position_id).maybeSingle();
      positionName = (pos as { name?: string } | null)?.name || '';
    }

    const subtitle = [branchName, positionName].filter(Boolean).join(' · ');

    // ---- 5) Provodka RPC: upsert_hodim_kassa ----
    let resp: Response;
    try {
      resp = await fetch(`${PROVODKA_URL.replace(/\/+$/, '')}/rest/v1/rpc/upsert_hodim_kassa`, {
        method: 'POST',
        headers: {
          'apikey': PROVODKA_SERVICE_KEY,
          'Authorization': `Bearer ${PROVODKA_SERVICE_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          p_taskfix_user_id: userId,
          p_name: name,
          p_subtitle: subtitle,
          p_active: active,
        }),
      });
    } catch (e) {
      return fail('provodka_unreachable', String(e), 502);
    }

    const rawText = await resp.text();
    let parsed: unknown = null;
    try { parsed = rawText ? JSON.parse(rawText) : null; } catch (_) { parsed = rawText; }

    if (!resp.ok) {
      return fail('provodka_error', `Provodka ${resp.status}: ${rawText}`.slice(0, 500), 502);
    }
    // RPC ataylab { ok:false, ... } qaytarishi mumkin
    if (parsed && typeof parsed === 'object' && (parsed as { ok?: boolean }).ok === false) {
      return fail('provodka_rejected', String((parsed as { error?: string }).error || rawText), 400);
    }

    return json({ ok: true, v: VERSION, user_id: userId, name, subtitle, active, provodka: parsed });

  } catch (e) {
    return fail('unexpected', String(e), 500);
  }
});
