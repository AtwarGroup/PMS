// Server-only scheduler endpoint. Authenticates its random DB-held worker token;
// neither user JWTs nor anonymous requests may drain the mail queue.
const url = Deno.env.get('SUPABASE_URL') || '';
const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const apiKey = Deno.env.get('RESEND_API_KEY') || '';
const sender = Deno.env.get('EMAIL_FROM') || 'ATWAR ONE <tasks@notify.tiradorstores.com>';
const replyTo = Deno.env.get('EMAIL_REPLY_TO') || 'atwar.one@tiradorstores.com';
const base = 'https://one.atwargroup.com';
const escape = (s: unknown) => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c] || c));
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {status,headers:{'Content-Type':'application/json'}});

async function rpc(name: string, args: Record<string,unknown>) {
 const r = await fetch(`${url}/rest/v1/rpc/${name}`, {method:'POST',signal:AbortSignal.timeout(15000),
  headers:{apikey:service,Authorization:`Bearer ${service}`,'Content-Type':'application/json'},body:JSON.stringify(args)});
 if (!r.ok) throw new Error(`database_${r.status}`);
 const text = await r.text(); return text ? JSON.parse(text) : null;
}
function content(items: Array<{payload:Record<string,string>}>) {
 const digest = items.every(i => ['due','critical','expired'].includes(i.payload.phase));
 const subject = digest ? `تنبيهات وثائق المركبات (${items.length})` : items[0].payload.subject;
 const blocks = items.map(({payload:p}) => {
  if (!/^\/(fleet|recruitment|it-support)\/[a-z-]+\.html\?/.test(p.path)) throw new Error('invalid_record_link');
  const link = base + p.path;
  return {html:`<tr><td style="padding:18px;border-bottom:1px solid #e2e8f0"><h2 style="font-size:18px;margin:0 0 12px">${escape(p.subject)}</h2><p style="line-height:1.9">${escape(p.summary)}</p>${p.due_at?`<p>الموعد المستهدف: ${escape(new Date(p.due_at).toLocaleDateString('ar-SA',{timeZone:'Asia/Riyadh',calendar:'gregory'}))}</p>`:''}<a href="${escape(link)}" style="display:inline-block;padding:12px 22px;background:#1769db;color:#fff;text-decoration:none;border-radius:8px">فتح الطلب في أطوار ون</a></td></tr>`,text:`${p.subject}\n${p.summary}\n${p.due_at?'الموعد المستهدف: '+p.due_at+'\n':''}${link}`};
 });
 return {subject:`أطوار ون — ${subject}`.replace(/[\r\n]/g,' '),
  html:`<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><title>${escape(subject)}</title></head><body style="margin:0;background:#f3f6fb;font-family:Tahoma,Arial,sans-serif;color:#10213d"><table role="presentation" width="100%"><tr><td align="center"><table role="presentation" width="100%" style="max-width:620px;background:#fff;margin:24px auto;border:1px solid #dfe7f2;border-radius:12px"><tr><td style="padding:24px;background:#0c2347;color:#fff;font-size:22px;font-weight:bold">ATWAR ONE — أطوار ون</td></tr>${blocks.map(b=>b.html).join('')}<tr><td style="padding:18px;font-size:12px;color:#52627a">رسالة آلية لإجراء مهم. افتح النظام للاطلاع على الحالة الحالية والتفاصيل وتنفيذ الإجراء.</td></tr></table></td></tr></table></body></html>`,
  text:blocks.map(b=>b.text).join('\n\n')+'\n\nرسالة آلية من أطوار ون.'};
}

Deno.serve(async request => {
 if (request.method !== 'POST') return json({error:'method_not_allowed'},405);
 const token = request.headers.get('x-atwar-worker');
 if (!token || !/^[a-f0-9]{64}$/.test(token)) return json({error:'unauthorized'},401);
 if (!url || !service) return json({error:'service_configuration_missing'},503);
 try {
  // Authenticate before revealing readiness or claiming any work.
  const config = await rpc('important_email_claim',{p_token:token,p_probe:true});
  if (!apiKey) return json({error:'email_configuration_missing'},503);
  const body = await request.json().catch(()=>({}));
  if (body.probe) return json({ready:true,enabled:config.enabled});
  if (!config.enabled) return json({disabled:true});
  let sent = 0;
  for (let i=0;i<5;i++) {
   const batch = await rpc('important_email_claim',{p_token:token,p_probe:false});
   if (!batch.items?.length) break;
   try {
    const valid = await rpc('important_email_validate',{p_batch:batch.batch_id,p_lease:batch.claim_token});
    if (!valid) continue;
    const mail = content(batch.items);
    const response = await fetch('https://api.resend.com/emails',{method:'POST',signal:AbortSignal.timeout(15000),
     headers:{Authorization:`Bearer ${apiKey}`,'Content-Type':'application/json','Idempotency-Key':`important-action/${batch.batch_id}`},
     body:JSON.stringify({from:sender,to:[batch.recipient],reply_to:replyTo,...mail})});
    const result = await response.json().catch(()=>({}));
    if (!response.ok || !result.id) {
     await rpc('important_email_finish',{p_batch:batch.batch_id,p_lease:batch.claim_token,p_error:`provider_${response.status}`,p_retry:response.status===429||response.status>=500});
     if(response.status===429)break;
     continue;
    }
    await rpc('important_email_finish',{p_batch:batch.batch_id,p_lease:batch.claim_token,p_provider:result.id});
    sent++;
   } catch {
    // If acceptance was ambiguous, the frozen payload/key makes retries safe within 20h.
    await rpc('important_email_finish',{p_batch:batch.batch_id,p_lease:batch.claim_token,p_error:'delivery_unknown_or_transient',p_retry:true}).catch(()=>{});
   }
  }
  return json({sent});
 } catch { return json({error:'authentication_or_database_unavailable'},503); }
});
