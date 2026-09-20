const SUPABASE_URL=(Deno.env.get('SUPABASE_URL')??'').replace(/\/$/,'');
const SERVICE_ROLE_KEY=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'';
const RESEND_API_KEY=Deno.env.get('RESEND_API_KEY')??'';
const EMAIL_FROM=Deno.env.get('EMAIL_FROM')??'ATWAR ONE <tasks@notify.tiradorstores.com>';
const EMAIL_REPLY_TO=Deno.env.get('EMAIL_REPLY_TO')??'hr@tiradorstores.com';
const HR_EMAIL=(Deno.env.get('HR_EMAIL')??'hr@tiradorstores.com').trim().toLowerCase();
const APP_BASE_URL=(Deno.env.get('APP_BASE_URL')??'https://one.atwargroup.com').replace(/\/$/,'');
const jsonHeaders={'Content-Type':'application/json'};
const corsHeaders={
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type',
};

const escapeHtml=(value:unknown)=>String(value??'').replace(/[&<>"']/g,char=>({
  '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;',
})[char]??char);

function serviceHeaders(extra:Record<string,string>={}){
  return {apikey:SERVICE_ROLE_KEY,Authorization:`Bearer ${SERVICE_ROLE_KEY}`,...jsonHeaders,...extra};
}

async function dbRequest(path:string,init:RequestInit={}){
  return fetch(`${SUPABASE_URL}/rest/v1/${path}`,{
    ...init,
    headers:{...serviceHeaders({'Prefer':'return=representation'}),...(init.headers??{})},
  });
}

function decodeBase64(value:string){
  const clean=value.replace(/^data:application\/pdf;base64,/, '').replace(/\s/g,'');
  const binary=atob(clean);
  const bytes=new Uint8Array(binary.length);
  for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);
  return {clean,bytes};
}

async function sha256(bytes:Uint8Array){
  const hash=await crypto.subtle.digest('SHA-256',bytes);
  return [...new Uint8Array(hash)].map(x=>x.toString(16).padStart(2,'0')).join('');
}

function emailHtml(row:Record<string,unknown>){
  const snapshot=(row.job_snapshot??{}) as Record<string,unknown>;
  const title=String(snapshot.title??'الوصف الوظيفي');
  const accepted=new Intl.DateTimeFormat('ar-SA',{dateStyle:'long',timeStyle:'short',timeZone:'Asia/Riyadh'}).format(new Date(String(row.accepted_at)));
  return `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"></head>
  <body style="margin:0;background:#f3f6fb;font-family:Tahoma,Arial,sans-serif;color:#10213d">
    <div style="max-width:650px;margin:24px auto;background:#fff;border:1px solid #dfe7f2;border-radius:14px;overflow:hidden">
      <div style="background:#0c2347;color:#fff;padding:22px 28px"><div style="font-size:20px;font-weight:700">ATWAR ONE</div><div style="font-size:13px;color:#bcd0ee;margin-top:5px">إقرار الاطلاع على الوصف الوظيفي</div></div>
      <div style="padding:26px 28px">
        <h2 style="margin:0 0 14px">تم اعتماد إقرار الموظف</h2>
        <div style="border:1px solid #e1e8f2;border-radius:10px;padding:18px;line-height:2">
          <div><b>الموظف:</b> ${escapeHtml(row.employee_name_snapshot)}</div>
          <div><b>المسمى الوظيفي:</b> ${escapeHtml(title)}</div>
          <div><b>إصدار الوصف:</b> ${escapeHtml(row.job_revision)}</div>
          <div><b>وقت الموافقة:</b> ${escapeHtml(accepted)}</div>
        </div>
        <p style="line-height:2;color:#52627a">${escapeHtml(row.acknowledgement_text)}</p>
        <p style="line-height:2;color:#52627a">مرفق نسخة PDF من الوصف الوظيفي والإقرار المعتمد.</p>
        <a href="${escapeHtml(`${APP_BASE_URL}/profile/job-description.html`)}" style="display:inline-block;margin-top:8px;background:#2474e5;color:#fff;text-decoration:none;padding:12px 24px;border-radius:9px;font-weight:700">عرض الوصف في ATWAR ONE</a>
        <p style="font-size:12px;color:#8a96a8;margin:22px 0 0">هذه رسالة آلية مرسلة إلى الموظف ومديره المباشر والموارد البشرية.</p>
      </div>
    </div>
  </body></html>`;
}

Deno.serve(async request=>{
  if(request.method==='OPTIONS')return new Response('ok',{headers:corsHeaders});
  if(request.method!=='POST')return new Response('Method not allowed',{status:405,headers:corsHeaders});
  if(!SUPABASE_URL||!SERVICE_ROLE_KEY||!RESEND_API_KEY){
    return new Response(JSON.stringify({error:'Acknowledgement email service is not configured.'}),{status:503,headers:{...jsonHeaders,...corsHeaders}});
  }

  const authorization=request.headers.get('Authorization')??'';
  if(!authorization.startsWith('Bearer '))return new Response('Authentication required',{status:401,headers:corsHeaders});
  const userResponse=await fetch(`${SUPABASE_URL}/auth/v1/user`,{headers:{apikey:SERVICE_ROLE_KEY,Authorization:authorization}});
  if(!userResponse.ok)return new Response('Invalid session',{status:401,headers:corsHeaders});
  const user=await userResponse.json() as {id?:string};

  let body:{acknowledgementId?:string,pdfBase64?:string};
  try{body=await request.json();}catch{return new Response('Invalid JSON body',{status:400,headers:corsHeaders});}
  const acknowledgementId=String(body.acknowledgementId??'');
  if(!/^[0-9a-f-]{36}$/i.test(acknowledgementId))return new Response('Invalid acknowledgement id',{status:400,headers:corsHeaders});

  let pdf:{clean:string,bytes:Uint8Array};
  try{pdf=decodeBase64(String(body.pdfBase64??''));}catch{return new Response('Invalid PDF encoding',{status:400,headers:corsHeaders});}
  if(pdf.bytes.length<100||pdf.bytes.length>8*1024*1024||new TextDecoder().decode(pdf.bytes.slice(0,4))!=='%PDF'){
    return new Response('Invalid or oversized PDF',{status:400,headers:corsHeaders});
  }

  const rowResponse=await dbRequest(`job_description_acknowledgements?select=*&id=eq.${encodeURIComponent(acknowledgementId)}&profile_id=eq.${encodeURIComponent(String(user.id??''))}&limit=1`);
  const rows=await rowResponse.json() as Array<Record<string,unknown>>;
  if(!rowResponse.ok||!rows.length)return new Response('Acknowledgement not found',{status:404,headers:corsHeaders});
  const row=rows[0];
  if(row.email_status==='sent')return new Response(JSON.stringify({sent:true,alreadySent:true}),{headers:{...jsonHeaders,...corsHeaders}});

  const claim=await dbRequest(`job_description_acknowledgements?id=eq.${acknowledgementId}&email_status=in.(pending,failed)`,{
    method:'PATCH',body:JSON.stringify({email_status:'processing',email_last_error:null,updated_at:new Date().toISOString()}),
  });
  const claimed=await claim.json() as unknown[];
  if(!claim.ok||!claimed.length)return new Response('Acknowledgement email is already being processed',{status:409,headers:corsHeaders});

  const digest=await sha256(pdf.bytes);
  const pdfPath=`${row.profile_id}/${acknowledgementId}.pdf`;
  try{
    const upload=await fetch(`${SUPABASE_URL}/storage/v1/object/job-acknowledgements/${pdfPath}`,{
      method:'POST',headers:serviceHeaders({'Content-Type':'application/pdf','x-upsert':'true'}),body:pdf.bytes,
    });
    if(!upload.ok)throw new Error(`PDF storage failed: ${await upload.text()}`);

    const employeeEmail=String(row.employee_email_snapshot??'').trim().toLowerCase();
    const cc=[String(row.manager_email_snapshot??'').trim().toLowerCase(),HR_EMAIL]
      .filter((value,index,list)=>value&&value!==employeeEmail&&list.indexOf(value)===index);
    if(!employeeEmail)throw new Error('Employee email is missing.');

    const send=await fetch('https://api.resend.com/emails',{
      method:'POST',headers:{...jsonHeaders,Authorization:`Bearer ${RESEND_API_KEY}`},
      body:JSON.stringify({
        from:EMAIL_FROM,to:[employeeEmail],cc,reply_to:EMAIL_REPLY_TO,
        subject:`إقرار الوصف الوظيفي: ${String(row.employee_name_snapshot??'الموظف')}`,
        html:emailHtml(row),
        attachments:[{filename:`ATWAR_JOB_ACK_${acknowledgementId}.pdf`,content:pdf.clean}],
      }),
    });
    const result=await send.json();
    if(!send.ok)throw new Error(result?.message??'Email provider rejected the message.');

    await dbRequest(`job_description_acknowledgements?id=eq.${acknowledgementId}`,{
      method:'PATCH',body:JSON.stringify({
        pdf_path:pdfPath,pdf_sha256:digest,email_status:'sent',email_provider_id:result.id??null,
        email_last_error:null,emailed_at:new Date().toISOString(),updated_at:new Date().toISOString(),
      }),
    });
    return new Response(JSON.stringify({sent:true}),{headers:{...jsonHeaders,...corsHeaders}});
  }catch(error){
    const message=String(error instanceof Error?error.message:error).slice(0,1000);
    await dbRequest(`job_description_acknowledgements?id=eq.${acknowledgementId}`,{
      method:'PATCH',body:JSON.stringify({email_status:'failed',email_last_error:message,updated_at:new Date().toISOString()}),
    });
    return new Response(JSON.stringify({error:message}),{status:500,headers:{...jsonHeaders,...corsHeaders}});
  }
});
