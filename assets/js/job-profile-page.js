import {mountEmployeeChanges} from './employee-job-changes.js?v=2.5.24';
import {createJobAcknowledgementPdf} from './job-ack-pdf.js';
const css=document.createElement('link');css.rel='stylesheet';css.href='../assets/css/job-profile.css?v=2.4.17';document.head.append(css);
const sb=await window.atwarGetSupabase(),host=document.getElementById('jobProfile');
const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
const arr=v=>Array.isArray(v)?v:[],txt=x=>typeof x==='string'?x:(x?.text||x?.name||'');
const ACK_TEXT='أقر بأنني اطلعت على الوصف الوظيفي المعتمد، وأوافق على تنفيذ المهام والمسؤوليات والصلاحيات ومؤشرات الأداء الواردة فيه، وأتحمل مسؤولية الالتزام بها ضمن الأنظمة والسياسات والتوجيهات المعتمدة.';

const revisionOf=job=>{const n=Number(job?.published_snapshot?.revision??job?.revision??1);return Number.isFinite(n)&&n>0?n:1};

async function makePdf({profile,manager,job,acknowledgement}){
  const snapshot=job.published_snapshot||{};
  return createJobAcknowledgementPdf({
    employeeName:profile.full_name||profile.email,email:profile.email,
    department:profile.department||snapshot.family,managerName:manager?.full_name,
    title:snapshot.title||job.title,revision:revisionOf(job),acceptedAt:acknowledgement.accepted_at,
    purpose:snapshot.purpose,content:snapshot.content,acknowledgementText:ACK_TEXT,id:acknowledgement.id
  });
}

function ackHtml(ack){
  if(!ack)return `<section class="job-acknowledgement pending"><h2>إقرار الاطلاع والمسؤولية</h2><p>بعد قراءة الوصف الوظيفي كاملًا، يلزم تأكيد الاطلاع والموافقة قبل تسجيل الإقرار وإرسال نسخته المعتمدة.</p><label class="ack-check"><input id="ackCheckbox" type="checkbox"><span>${esc(ACK_TEXT)}</span></label><div class="ack-actions"><button class="ack-button" id="ackButton" disabled>اعتماد الإقرار وإرسال النسخة</button><span class="ack-status" id="ackStatus"></span></div></section>`;
  const accepted=new Intl.DateTimeFormat('ar-SA',{dateStyle:'long',timeStyle:'short',timeZone:'Asia/Riyadh'}).format(new Date(ack.accepted_at)),retry=ack.email_status!=='sent';
  return `<section class="job-acknowledgement accepted"><div class="ack-success"><span class="ack-success-mark">✓</span><div><h2>تم اعتماد إقرارك</h2><p>سُجلت الموافقة بتاريخ ${esc(accepted)} على الإصدار ${esc(ack.job_revision)}.</p></div></div>${retry?`<p class="ack-email-warning">تم حفظ الإقرار، لكن إرسال البريد لم يكتمل. يمكنك إعادة المحاولة دون تكرار الإقرار.</p><div class="ack-actions"><button class="ack-retry" id="ackRetry">إعادة إرسال ملف PDF</button><span class="ack-status" id="ackStatus"></span></div>`:'<p>تم إرسال ملف PDF إلى بريدك ومديرك المباشر والموارد البشرية.</p>'}</section>`;
}
async function send(context){
  const pdfBase64=await makePdf(context);
  const {data,error}=await sb.functions.invoke('send-job-acknowledgement',{body:{acknowledgementId:context.acknowledgement.id,pdfBase64}});
  if(error||!data?.sent){
    let detail=data?.error;
    try{if(!detail&&error?.context)detail=(await error.context.clone().json())?.error}catch{}
    throw new Error(detail||error?.message||'تعذر إرسال رسالة الإقرار.');
  }
}
function wire(context){
  document.querySelectorAll('[data-profile-tab]').forEach(b=>b.onclick=()=>{document.querySelectorAll('[data-profile-tab]').forEach(x=>x.classList.toggle('active',x===b));document.querySelectorAll('.profile-panel').forEach(x=>x.classList.toggle('active',x.id===`tab-${b.dataset.profileTab}`))});
  const requestedTab=new URLSearchParams(location.search).get('tab');if(requestedTab)document.querySelector(`[data-profile-tab="${requestedTab}"]`)?.click();
  const checkbox=document.getElementById('ackCheckbox'),button=document.getElementById('ackButton');if(checkbox&&button){checkbox.onchange=()=>button.disabled=!checkbox.checked;button.onclick=async()=>{const status=document.getElementById('ackStatus');button.disabled=true;checkbox.disabled=true;status.textContent='جارٍ تسجيل الإقرار وتجهيز ملف PDF...';try{const {data,error}=await sb.rpc('acknowledge_job_description',{p_job_description_id:context.job.id,p_user_agent:navigator.userAgent});if(error)throw error;const acknowledgement=Array.isArray(data)?data[0]:data;if(!acknowledgement?.id)throw new Error('لم يتم إنشاء سجل الإقرار.');try{await send({...context,acknowledgement})}catch(error){console.error(error)}location.reload()}catch(error){status.textContent=error?.message||'تعذر تسجيل الإقرار.';checkbox.disabled=false;button.disabled=!checkbox.checked}}}
  const retry=document.getElementById('ackRetry');if(retry)retry.onclick=async()=>{const status=document.getElementById('ackStatus');retry.disabled=true;status.textContent='جارٍ تجهيز وإرسال الملف...';try{await send(context);location.reload()}catch(error){status.textContent=error?.message||'تعذر إرسال البريد.';retry.disabled=false}};
}

const {data:{session}}=await sb.auth.getSession();
if(!session?.user)location.href='../login.html';else{
  const {data:profile}=await sb.from('profiles').select('*').eq('id',session.user.id).single();if(!profile)location.href='../login.html';else{
    window.atwarSyncShellIdentity?.(profile,session.user);let manager=null;if(profile.manager_id){const r=await sb.rpc('get_my_manager_profile');manager=Array.isArray(r.data)?r.data[0]||null:r.data||null}
    const ar=await sb.from('employee_job_assignments').select('job_description_id').eq('profile_id',profile.id).maybeSingle();let id=ar.data?.job_description_id||profile.job_description_id,job=null;if(id){const r=await sb.from('job_descriptions').select('*').eq('id',id).maybeSingle();job=r.data}if(!job&&profile.job_title){const r=await sb.from('job_descriptions').select('*').eq('title',profile.job_title).not('published_at','is',null).maybeSingle();job=r.data}
    if(!job?.published_snapshot)host.innerHTML='<section class="box empty-job"><h2>لا يوجد وصف منشور بعد</h2><p>ستظهر هنا النسخة المعتمدة فقط بعد اكتمال مراجعتها.</p></section>';else{
      const d=job.published_snapshot,c=d.content||{},q=c.qualifications||{},fr=await sb.from('job_description_forms').select('usage_note,display_order,form_library(*)').eq('job_description_id',job.id).order('display_order'),forms=(fr.data||[]).map(x=>({...x.form_library,usage_note:x.usage_note})).filter(x=>x.status==='PUBLISHED');
      const ackResult=await sb.from('job_description_acknowledgements').select('*').eq('profile_id',profile.id).eq('job_description_id',job.id).eq('job_revision',revisionOf(job)).maybeSingle();const acknowledgement=ackResult.data||null;
      const documentContext={profile,manager,job,snapshot:d,content:c,revision:revisionOf(job)};
      const requested=new URLSearchParams(location.search).get('tab'),mode=['tasks','authority','performance'].includes(requested)?requested:'description';
      window.AtwarJobDocument.mount(host,documentContext,{mode,heading:'ملفي الوظيفي المعتمد',footer:ackHtml(acknowledgement)+'<div id="employeeJobChanges"></div>'+(forms.length?`<section class="qualification-box"><h2>النماذج والأدلة المرتبطة</h2><div class="linked-form-grid">${forms.map(f=>`<a href="${esc(f.file_url||'#')}" target="_blank" rel="noopener"><b>${esc(f.title)}</b><span>${esc(f.usage_note||f.description||'')}</span></a>`).join('')}</div></section>`:'')});wire({profile,manager,job,acknowledgement});await mountEmployeeChanges(document.getElementById('employeeJobChanges'),{sb,profile,job});
    }
  }
}
