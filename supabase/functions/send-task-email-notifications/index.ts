const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? '';
const EMAIL_FROM = Deno.env.get('EMAIL_FROM') ?? 'ATWAR ONE <tasks@notify.tiradorstores.com>';
const EMAIL_REPLY_TO = Deno.env.get('EMAIL_REPLY_TO') ?? 'atwar.one@tiradorstores.com';
const APP_BASE_URL = (Deno.env.get('APP_BASE_URL') ?? '').replace(/\/$/, '');

const jsonHeaders = { 'Content-Type': 'application/json' };
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function escapeHtml(value: unknown) {
  return String(value ?? '').replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;',
  })[char] ?? char);
}

function eventTitle(type: string) {
  return type === 'returned' ? 'تمت إعادة المهمة للعمل'
    : type === 'reassigned' ? 'تم إسناد مهمة إليك'
    : 'مهمة جديدة مسندة إليك';
}

function priorityLabel(priority: string) {
  return ({ urgent: 'عاجلة', important: 'مهمة', normal: 'عادية', high: 'عالية', low: 'منخفضة' } as Record<string, string>)[priority] ?? 'عادية';
}

function emailHtml(row: Record<string, unknown>) {
  const payload = (row.payload ?? {}) as Record<string, unknown>;
  const taskUrl = `${APP_BASE_URL}/tasks/?task=${encodeURIComponent(String(row.task_id))}`;
  const description = String(payload.description ?? '').trim();
  return `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"></head>
  <body style="margin:0;background:#f3f6fb;font-family:Tahoma,Arial,sans-serif;color:#10213d">
    <div style="max-width:620px;margin:24px auto;background:#fff;border:1px solid #dfe7f2;border-radius:14px;overflow:hidden">
      <div style="background:#0c2347;color:#fff;padding:22px 28px"><div style="font-size:20px;font-weight:700">ATWAR ONE</div><div style="font-size:13px;color:#bcd0ee;margin-top:5px">نظام إدارة المهام</div></div>
      <div style="padding:26px 28px">
        <h2 style="margin:0 0 12px;font-size:20px">${escapeHtml(eventTitle(String(row.event_type)))}</h2>
        <p style="margin:0 0 18px;color:#52627a">مرحبًا ${escapeHtml(payload.assignee_name)}، قام ${escapeHtml(payload.actor_name)} بإسناد المهمة التالية إليك:</p>
        <div style="border:1px solid #e1e8f2;border-radius:10px;padding:18px">
          <div style="font-size:18px;font-weight:700;margin-bottom:12px">${escapeHtml(payload.title)}</div>
          ${description ? `<div style="color:#52627a;margin-bottom:12px;line-height:1.8">${escapeHtml(description)}</div>` : ''}
          <div style="font-size:13px;line-height:2;color:#52627a">
            <div><b>الأولوية:</b> ${escapeHtml(priorityLabel(String(payload.priority)))}</div>
            <div><b>تاريخ البداية:</b> ${escapeHtml(payload.start_date || '—')}</div>
            <div><b>تاريخ الانتهاء:</b> ${escapeHtml(payload.due_date || '—')}</div>
          </div>
        </div>
        <a href="${escapeHtml(taskUrl)}" style="display:inline-block;margin-top:20px;background:#2474e5;color:#fff;text-decoration:none;padding:12px 24px;border-radius:9px;font-weight:700">عرض المهمة</a>
        <p style="font-size:12px;color:#8a96a8;margin:22px 0 0">هذه رسالة آلية من نظام ATWAR ONE.</p>
      </div>
    </div>
  </body></html>`;
}

async function dbRequest(path: string, init: RequestInit = {}) {
  return fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      ...jsonHeaders,
      Prefer: 'return=representation',
      ...(init.headers ?? {}),
    },
  });
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: corsHeaders });
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !RESEND_API_KEY || !APP_BASE_URL) {
    return new Response(JSON.stringify({ error: 'Email service is not configured.' }), { status: 503, headers: { ...jsonHeaders, ...corsHeaders } });
  }

  const now = new Date().toISOString();
  const query = `email_notification_outbox?select=*&status=in.(pending,failed)&next_attempt_at=lte.${encodeURIComponent(now)}&order=created_at.asc&limit=10`;
  const pendingResponse = await dbRequest(query);
  if (!pendingResponse.ok) return new Response(await pendingResponse.text(), { status: 500, headers: corsHeaders });
  const pending = await pendingResponse.json() as Array<Record<string, unknown>>;
  let sent = 0;

  for (const row of pending) {
    const claim = await dbRequest(`email_notification_outbox?id=eq.${row.id}&status=in.(pending,failed)`, {
      method: 'PATCH', body: JSON.stringify({ status: 'processing', attempts: Number(row.attempts ?? 0) + 1, updated_at: now }),
    });
    const claimed = await claim.json() as unknown[];
    if (!claim.ok || !claimed.length) continue;

    try {
      const sendResponse = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { ...jsonHeaders, Authorization: `Bearer ${RESEND_API_KEY}` },
        body: JSON.stringify({
          from: EMAIL_FROM,
          to: [row.recipient_email],
          reply_to: EMAIL_REPLY_TO,
          subject: `${eventTitle(String(row.event_type))}: ${String((row.payload as Record<string, unknown>)?.title ?? '')}`,
          html: emailHtml(row),
        }),
      });
      const result = await sendResponse.json();
      if (!sendResponse.ok) throw new Error(result?.message ?? 'Resend rejected the email.');
      await dbRequest(`email_notification_outbox?id=eq.${row.id}`, {
        method: 'PATCH', body: JSON.stringify({ status: 'sent', provider_message_id: result.id ?? null, processed_at: new Date().toISOString(), last_error: null, updated_at: new Date().toISOString() }),
      });
      sent++;
    } catch (error) {
      const attempts = Number(row.attempts ?? 0) + 1;
      const terminal = attempts >= 5;
      await dbRequest(`email_notification_outbox?id=eq.${row.id}`, {
        method: 'PATCH', body: JSON.stringify({
          status: 'failed',
          last_error: String(error instanceof Error ? error.message : error).slice(0, 1000),
          next_attempt_at: terminal ? '9999-12-31T00:00:00Z' : new Date(Date.now() + Math.min(60, 2 ** attempts) * 60000).toISOString(),
          updated_at: new Date().toISOString(),
        }),
      });
    }
  }

  return new Response(JSON.stringify({ processed: pending.length, sent }), { headers: { ...jsonHeaders, ...corsHeaders } });
});
