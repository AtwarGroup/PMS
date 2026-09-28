const URL_BASE=(Deno.env.get('SUPABASE_URL')??'').replace(/\/$/,'');
const SERVICE_KEY=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'';
const RESEND_KEY=Deno.env.get('RESEND_API_KEY')??'';
const FROM=Deno.env.get('EMAIL_FROM')??'ATWAR ONE <tasks@notify.tiradorstores.com>';
const HR_EMAIL=(Deno.env.get('HR_EMAIL')??'hr@tiradorstores.com').trim().toLowerCase();
const APP_URL=(Deno.env.get('APP_BASE_URL')??'https://one.atwargroup.com').replace(/\/$/,'');
const headers={'Content-Type':'application/json'};
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, x-client-info, content-type'};
const esc=(value:unknown)=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]??char));
const list=(value:unknown)=>Array.isArray(value)?value:[];
const label=(value:unknown)=>typeof value==='string'?value:String((value as Record<string,unknown>)?.text??(value as Record<string,unknown>)?.name??'');
const ackText='أقر بأنني اطلعت على الوصف الوظيفي المعتمد، وأوافق على تنفيذ المهام والمسؤوليات والصلاحيات ومؤشرات الأداء الواردة فيه، وأتحمل مسؤولية الالتزام بها ضمن الأنظمة والسياسات والتوجيهات المعتمدة.';

function emailHtml(payload:Record<string,unknown>){
  const snapshot=(payload.job_snapshot??{}) as Record<string,unknown>;
  const content=(snapshot.content??{}) as Record<string,unknown>;
  const section=(title:string,items:unknown)=>{const values=list(items).map(label).filter(Boolean);return values.length?`<h3 style="color:#1769e0;margin:20px 0 8px">${esc(title)}</h3><ol style="line-height:1.9;padding-right:22px">${values.map(x=>`<li>${esc(x)}</li>`).join('')}</ol>`:''};
  const qualifications=(content.qualifications??{}) as Record<string,unknown>;
  const q=Object.entries(qualifications).filter(([,value])=>typeof value==='string'&&value.trim()).map(([key,value])=>`<li>${esc(({education:'المؤهل',experience:'الخبرة',skills:'المهارات'} as Record<string,string>)[key]??key)}: ${esc(value)}</li>`).join('');
  return `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"></head><body style="font-family:Tahoma,Arial,sans-serif;color:#10213d;background:#f3f6fb;margin:0"><main style="max-width:650px;margin:22px auto;padding:24px;background:white;border-radius:14px"><h1 style="color:#0c2347">وصفك الوظيفي المعتمد</h1><p>مرحبًا ${esc(payload.employee_name)}، نُشر وصفك الوظيفي وأصبح متاحًا للاطلاع والإقرار.</p><h2>${esc(snapshot.title)}</h2><p><b>الإدارة:</b> ${esc(snapshot.family)} &nbsp; <b>الإصدار:</b> ${esc(snapshot.revision)}</p><h3>الغرض من الوظيفة</h3><p style="line-height:1.9">${esc(snapshot.purpose)}</p>${section('المهام والمسؤوليات',content.responsibilities)}${section('الصلاحيات',content.authorities)}${section('مؤشرات الأداء',content.kpis)}${section('التقارير والمخرجات',content.reports)}${q?`<h3>المؤهلات والخبرات</h3><ul>${q}</ul>`:''}<h3>نص الإقرار المطلوب</h3><p style="line-height:1.9">${esc(ackText)}</p><p><b>يرجى فتح ملفك الوظيفي وقراءة النسخة المعتمدة ثم تسجيل إقرارك داخل النظام.</b></p><a href="${esc(APP_URL+'/profile/job-description.html')}" style="display:inline-block;background:#1769e0;color:white;padding:12px 20px;border-radius:9px;text-decoration:none">فتح الوصف وتسجيل الإقرار</a><p style="font-size:12px;color:#64748b">نسخة إلى الموارد البشرية للمتابعة. لا يُسجل الإقرار بمجرد قراءة هذا البريد.</p></main></body></html>`;
}

async function db(path:string,init:RequestInit={}){
  return fetch(`${URL_BASE}/rest/v1/${path}`,{...init,headers:{apikey:SERVICE_KEY,Authorization:`Bearer ${SERVICE_KEY}`,...headers,Prefer:'return=representation',...(init.headers??{})}});
}
const response=(body:Record<string,unknown>,status=200)=>new Response(JSON.stringify(body),{status,headers:{...headers,...cors}});

Deno.serve(async request=>{
  if(request.method==='OPTIONS')return new Response('ok',{headers:cors});
  if(request.method!=='POST')return response({error:'Method not allowed'},405);
  if(!URL_BASE||!SERVICE_KEY||!RESEND_KEY||!HR_EMAIL)return response({error:'Email service is not configured.'},503);
  const token=request.headers.get('Authorization')??'';
  if(!token.startsWith('Bearer '))return response({error:'Authentication required'},401);
  const auth=await fetch(`${URL_BASE}/auth/v1/user`,{headers:{apikey:SERVICE_KEY,Authorization:token}});
  if(!auth.ok)return response({error:'Invalid session'},401);

  const now=new Date().toISOString();
  const pending=await db(`job_publication_email_outbox?select=*&status=in.(pending,failed)&next_attempt_at=lte.${encodeURIComponent(now)}&attempts=lt.5&order=created_at.asc&limit=10`);
  if(!pending.ok)return response({error:'Unable to read publication email queue.'},502);
  const rows=await pending.json() as Array<Record<string,unknown>>;
  let sent=0,failed=0;
  for(const row of rows){
    const claim=await db(`job_publication_email_outbox?id=eq.${row.id}&status=in.(pending,failed)`,{method:'PATCH',body:JSON.stringify({status:'processing',attempts:Number(row.attempts??0)+1,updated_at:now})});
    if(!claim.ok||(await claim.json() as unknown[]).length===0)continue;
    try{
      const recipient=String(row.recipient_email??'').trim().toLowerCase();
      const snapshot=((row.payload as Record<string,unknown>)?.job_snapshot??{}) as Record<string,unknown>;
      if(!recipient||!snapshot.title)throw new Error('Recipient email or published job snapshot is missing.');
      const send=await fetch('https://api.resend.com/emails',{method:'POST',headers:{...headers,Authorization:`Bearer ${RESEND_KEY}`},body:JSON.stringify({from:FROM,to:[recipient],cc:recipient===HR_EMAIL?[]:[HR_EMAIL],subject:`وصفك الوظيفي المعتمد: ${snapshot.title}`,html:emailHtml(row.payload as Record<string,unknown>)})});
      const result=await send.json();
      if(!send.ok)throw new Error(String(result?.message??'Email provider rejected message.'));
      const mark=await db(`job_publication_email_outbox?id=eq.${row.id}`,{method:'PATCH',body:JSON.stringify({status:'sent',provider_message_id:result.id??null,last_error:null,processed_at:new Date().toISOString(),updated_at:new Date().toISOString()})});
      if(!mark.ok)throw new Error('Email sent but queue status could not be saved.');
      sent++;
    }catch(error){
      failed++;
      const attempts=Number(row.attempts??0)+1;
      await db(`job_publication_email_outbox?id=eq.${row.id}`,{method:'PATCH',body:JSON.stringify({status:'failed',last_error:String(error instanceof Error?error.message:error).slice(0,700),next_attempt_at:new Date(Date.now()+Math.min(3600,60*2**attempts)*1000).toISOString(),updated_at:new Date().toISOString()})});
    }
  }
  return response({processed:rows.length,sent,failed});
});
