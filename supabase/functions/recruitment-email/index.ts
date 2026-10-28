const url=(Deno.env.get('SUPABASE_URL')||'').replace(/\/$/,'');
const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
const anon=Deno.env.get('SUPABASE_ANON_KEY')||'';
const resend=Deno.env.get('RECRUITMENT_RESEND_API_KEY')||Deno.env.get('RESEND_API_KEY')||'';
const enabled=Deno.env.get('RECRUITMENT_EMAIL_ENABLED')==='true';
const staging=url==='https://eeaedzisysjarwvolbwq.supabase.co';
const base=staging?'https://test.atwargroup.com':(Deno.env.get('APP_BASE_URL')||'').replace(/\/$/,'');
const origins=new Set(staging?['https://test.atwargroup.com','https://atwar-one-staging.blackstar1024.chatgpt.site']:[base]);
const esc=(v:unknown)=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get('origin')||'';
 const headers={'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':origins.has(origin)?origin:base,'Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Access-Control-Allow-Methods':'POST,GET,OPTIONS','Vary':'Origin'};
 const reply=(x:unknown,status=200)=>Response.json(x,{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method==='GET')return reply({enabled,configured:!!(resend&&service&&anon&&base),staging,test_recipient:staging?'Jobs@tiradorstores.com':undefined});
 if(req.method!=='POST'||(origin&&!origins.has(origin)))return reply({error:'طلب غير متاح'},403);
 if(!enabled)return reply({error:'إرسال بريد التوظيف غير مفعل حاليًا. يمكنك استخدام رابط العرض والطباعة من داخل النظام.'},503);
 if(!resend||!service||!anon||!base)return reply({error:'خدمة البريد غير مهيأة؛ تم حفظ الإجراء داخل النظام ولم يرسل بريد.'},503);
 try{
 const raw=await req.text();if(raw.length>2000)return reply({error:'بيانات تتجاوز الحد'},400);
 const body=JSON.parse(raw),uuid=/^[a-f0-9-]{36}$/i;
 if(!uuid.test(body.offer_id)||!['offer','reply'].includes(body.event)||(body.token&&!uuid.test(body.token)))return reply({error:'بيانات رسالة غير صحيحة'},400);
 const rpc=async(name:string,data:unknown,privileged=false)=>{
 const key=privileged?service:anon;
 const result=await fetch(url+'/rest/v1/rpc/'+name,{method:'POST',headers:{'Content-Type':'application/json',apikey:key,Authorization:privileged?'Bearer '+service:(/^Bearer eyJ/.test(req.headers.get('authorization')||'')?req.headers.get('authorization')!:'Bearer '+anon)},body:JSON.stringify(data)});
 if(!result.ok)throw Error('db_denied');const responseText=await result.text();return responseText?JSON.parse(responseText):null;};
 const id=await rpc('recruitment_email_prepare',{p_offer:body.offer_id,p_event:body.event,p_token:body.token||null});
 const job=await rpc('recruitment_email_claim',{p_id:id},true);
 if(job.already_sent)return reply({sent:true,already_sent:true});
 if(job.busy)return reply({pending:true},202);
 try{
 const p=job.payload,link=base+'/recruitment/candidate.html?token='+encodeURIComponent(job.portal_token),company=p.issuer==='tirador'?'مؤسسة لوازم الأبواب للتجارة — تيرادور':'أطوار للتجارة';
 const subject=(staging?'[اختبار — ليس عرضًا فعليًا] ':'')+(body.event==='offer'?'عرض العمل الإلكتروني':'نسخة إقرار المرشح')+' — '+company;
 const intro=body.event==='offer'?'يرجى مراجعة عرض العمل وتسجيل الموافقة أو الاعتذار وتاريخ المباشرة المتوقع.':'تم تسجيل رد المرشح: '+(p.state==='accepted'?'موافق':'معتذر')+(p.expected_start_date?'؛ تاريخ المباشرة المتوقع: '+p.expected_start_date:'');
 const text=`${company}\n${staging?'هذه رسالة اختبار للبيئة التجريبية ولا تمثل عرض توظيف فعليًا.\n':''}المرشح: ${p.candidate}\nالوظيفة: ${p.title}\nنسخة العرض: ${p.version}\n${intro}\nالعرض والإقرار والطباعة: ${link}`;
 const html=`<!doctype html><html lang="ar" dir="rtl"><body style="font-family:Tahoma,Arial,sans-serif;color:#18263c;line-height:1.8"><h1 style="font-size:22px">${esc(company)}</h1>${staging?'<p><strong>رسالة اختبار — لا تمثل عرض توظيف فعليًا.</strong></p>':''}<p>المرشح: ${esc(p.candidate)}<br>الوظيفة: ${esc(p.title)}<br>نسخة العرض: ${esc(p.version)}</p><p>${esc(intro)}</p><p><a href="${esc(link)}">عرض الخطاب والإقرار / الطباعة</a></p></body></html>`;
 const sent=await fetch('https://api.resend.com/emails',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+resend,'Idempotency-Key':'recruitment-'+id},body:JSON.stringify({from:Deno.env.get('RECRUITMENT_EMAIL_FROM')||Deno.env.get('EMAIL_FROM')||'ATWAR ONE <tasks@notify.tiradorstores.com>',to:[staging?'Jobs@tiradorstores.com':job.recipient],subject,html,text})});
 const result=await sent.json();
 if(!sent.ok||!result.id){await rpc('recruitment_email_finish',{p_id:id,p_error:'provider_status_'+sent.status},true);return reply({error:'تعذر إرسال البريد. الإجراء محفوظ ويمكن إعادة المحاولة.'},502);}
 await rpc('recruitment_email_finish',{p_id:id,p_provider_id:result.id},true);
 return reply({sent:true,provider_id:result.id,staging});
 }catch{await rpc('recruitment_email_finish',{p_id:id,p_error:'delivery_failed_or_unknown'},true).catch(()=>{});return reply({error:'تعذر تأكيد إرسال البريد؛ أعد المحاولة من نفس العرض.'},502);}
 }catch{return reply({error:'تعذر إرسال الرسالة. تحقق من الصلاحية والعرض.'},403);}
});
