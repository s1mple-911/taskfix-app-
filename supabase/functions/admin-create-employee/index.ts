// ============================================================
// admin-create-employee — v4-2026-07-23 (repo)
//
// Xodimni DARROV yaratadi (yoki email bo'yicha mavjudni topadi), workspace'ga
// a'zo qiladi, (ixtiyoriy) lavozim/filial yozadi va parol o'rnatish emailini
// yuboradi (Supabase SMTP).
//
// NEGA EF: auth foydalanuvchi yaratish service_role kalit talab qiladi — u
// frontend'ga TUSHMASLIGI shart (repo public). Kalitlar EF env'da.
//
// Kirish (frontend uch joyda chaqiradi):
//   { email, full_name?, phone?, position?, branch_id?, workspace_id, redirect_to? }
//   - empSave (index.html):        full_name, phone, position, branch_id
//   - sendInvite (index.html):     full_name, phone   (bo'limlarni frontend o'zi yozadi)
//   - teamResendEmail (index.html): faqat email + workspace_id  → mavjud userga qayta email
//
// Javob: { ok, v, user_id, created, email_sent, email_error }
//
// DEPLOY: "Verify JWT" — ON. Quyidagi kod chaqiruvchi shu workspace owner/admin
//         ekanini ALOHIDA tekshiradi (admin-import-staff / sync-provodka-kassa naqshi).
//
// ENV (Supabase avtomatik beradi — qo'lda qo'shilmaydi):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY
// ============================================================

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

const VERSION = 'v4-2026-07-23';

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
    // ---- 0) ENV ----
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
    const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') || '';
    if (!SUPABASE_URL || !SERVICE_KEY) {
      return fail('config', 'SUPABASE_URL yoki SUPABASE_SERVICE_ROLE_KEY yo\'q (Edge Secrets)', 500);
    }

    // ---- 1) Chaqiruvchi JWT ----
    const authHeader = req.headers.get('Authorization') || '';
    if (!authHeader.startsWith('Bearer ')) return fail('unauthorized', 'Authorization sarlavhasi yo\'q', 401);

    const asCaller: SupabaseClient = createClient(SUPABASE_URL, ANON_KEY || SERVICE_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userRes, error: uErr } = await asCaller.auth.getUser();
    if (uErr || !userRes?.user) return fail('unauthorized', 'JWT yaroqsiz', 401);
    const callerId = userRes.user.id;

    // ---- 2) Body ----
    const body = await req.json().catch(() => null);
    if (!body) return fail('bad_body', 'JSON o\'qib bo\'lmadi');
    const email: string = (body.email || '').trim().toLowerCase();
    const workspaceId: string = body.workspace_id;
    const fullName: string = (body.full_name || '').trim();
    const phone: string | null = body.phone ? String(body.phone).trim() : null;
    const position: string = (body.position || '').trim();
    const branchId: string | null = body.branch_id || null;
    const redirectTo: string | undefined = body.redirect_to || undefined;
    if (!email || !/^\S+@\S+\.\S+$/.test(email)) return fail('bad_body', 'Email noto\'g\'ri');
    if (!workspaceId) return fail('bad_body', 'workspace_id majburiy');

    const admin: SupabaseClient = createClient(SUPABASE_URL, SERVICE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // ---- 3) Ruxsat: chaqiruvchi shu workspace owner/admin'imi ----
    const { data: mem, error: mErr } = await admin
      .from('workspace_members').select('role')
      .eq('workspace_id', workspaceId).eq('user_id', callerId).maybeSingle();
    if (mErr) return fail('db', mErr.message, 500);
    if (!mem || (mem.role !== 'owner' && mem.role !== 'admin')) {
      return fail('forbidden', 'Faqat workspace owner yoki admin', 403);
    }

    // ---- 4) Foydalanuvchi: mavjudmi yoki yangi ----
    // Mavjudlikni recovery-link generatsiyasi bilan tekshiramiz (email YUBORMAYDI,
    // yo'q bo'lsa xato qaytaradi — user AVTOMATIK YARATILMAYDI).
    let userId: string | null = null;
    let created = false;

    const probe = await admin.auth.admin.generateLink({
      type: 'recovery', email, options: redirectTo ? { redirectTo } : undefined,
    });
    if (!probe.error && probe.data?.user) {
      userId = probe.data.user.id;
    } else {
      const meta: Record<string, unknown> = {};
      if (fullName) meta.full_name = fullName;
      if (phone) meta.phone = phone;
      const cu = await admin.auth.admin.createUser({
        email, email_confirm: true, user_metadata: meta,
      });
      if (cu.error || !cu.data?.user) {
        return fail('create_user', cu.error?.message || 'Foydalanuvchi yaratilmadi', 500);
      }
      userId = cu.data.user.id;
      created = true;
    }

    // ---- 5) Profil (best-effort — trigger allaqachon yaratishi mumkin) ----
    try {
      const patch: Record<string, unknown> = { id: userId };
      if (fullName) patch.full_name = fullName;
      if (phone) patch.phone = phone;
      if (Object.keys(patch).length > 1) {
        await admin.from('profiles').upsert(patch, { onConflict: 'id' });
      }
    } catch (_) { /* sokin */ }

    // ---- 6) Workspace a'zolik (trigger dublikati 23505 → e'tiborsiz) ----
    const { error: wmErr } = await admin.from('workspace_members')
      .insert({ workspace_id: workspaceId, user_id: userId, role: 'member' });
    if (wmErr && (wmErr as { code?: string }).code !== '23505') {
      return fail('membership', wmErr.message, 500);
    }

    // ---- 7) Lavozim (ixtiyoriy, best-effort) ----
    if (position) {
      try {
        let posId: string | null = null;
        const { data: pSel } = await admin.from('positions').select('id')
          .eq('workspace_id', workspaceId).eq('name', position).maybeSingle();
        posId = (pSel as { id?: string } | null)?.id || null;
        if (!posId) {
          const { data: pIns } = await admin.from('positions')
            .insert({ workspace_id: workspaceId, name: position }).select('id').single();
          posId = (pIns as { id?: string } | null)?.id || null;
        }
        if (posId) {
          await admin.from('employee_details')
            .upsert({ workspace_id: workspaceId, user_id: userId, position_id: posId },
              { onConflict: 'workspace_id,user_id' });
        }
      } catch (_) { /* sokin — lavozim keyin qo'lda qo'shilishi mumkin */ }
    }

    // ---- 8) Filial (ixtiyoriy, best-effort) ----
    if (branchId) {
      try {
        await admin.from('employee_branches')
          .upsert({ workspace_id: workspaceId, user_id: userId, branch_id: branchId },
            { onConflict: 'workspace_id,user_id,branch_id', ignoreDuplicates: true });
      } catch (_) { /* sokin */ }
    }

    // ---- 9) Parol o'rnatish emaili (Supabase SMTP) ----
    // resetPasswordForEmail — yangi ham, mavjud user ham ishlaydi. SMTP yo'q bo'lsa
    // email_error qaytadi (frontend "SMTP sozlamasini tekshiring" deb ko'rsatadi).
    let emailSent = false;
    let emailError: string | null = null;
    try {
      const anon: SupabaseClient = createClient(SUPABASE_URL, ANON_KEY || SERVICE_KEY);
      const { error: rErr } = await anon.auth.resetPasswordForEmail(
        email, redirectTo ? { redirectTo } : undefined,
      );
      if (rErr) emailError = rErr.message; else emailSent = true;
    } catch (e) {
      emailError = String(e);
    }

    return json({
      ok: true, v: VERSION, user_id: userId, created,
      email_sent: emailSent, email_error: emailError,
    });

  } catch (e) {
    return fail('unexpected', String(e), 500);
  }
});
