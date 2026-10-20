import {escapeHTML as esc,systemRoles} from './access-model.mjs?v=2.7.0';
const sb=await window.atwarGetSupabase(),host=document.getElementById('jobStageOwners'),state=document.getElementById('stageState');
const jobStages=[['DRAFT','إعداد المقترح الأولي'],['ASSIGN','ربط الأوصاف بالموظفين'],['FINAL_REVIEW','المراجعة النهائية'],['PUBLISH','الاعتماد والنشر']];
try{
 const {data:{session}}=await sb.auth.getSession();if(!session?.user){location.replace('../login.html');throw Error('يرجى تسجيل الدخول.');}
 const {data:context,error}=await sb.rpc('access_admin_context');if(error)throw error;
 const result=await sb.from('job_stage_owners').select('stage,profile_id');if(result.error)throw result.error;
 const owners=new Map(result.data.map(x=>[x.stage,x.profile_id])),users=context.users.filter(u=>u.active&&u.status==='active');
 host.innerHTML=jobStages.map(([stage,label])=>`<label>${label}<select data-job-stage="${stage}"><option value="" disabled ${owners.has(stage)?'':'selected'}>اختر المسؤول</option>${users.map(u=>`<option value="${esc(u.id)}" ${owners.get(stage)===u.id?'selected':''}>${esc(u.full_name)} — ${esc(systemRoles[u.role])}</option>`).join('')}</select><small data-stage-state="${stage}"></small></label>`).join('');
 for(const select of host.querySelectorAll('[data-job-stage]'))select.onchange=async()=>{
  const stage=select.dataset.jobStage,prior=owners.get(stage)||'',feedback=host.querySelector(`[data-stage-state="${stage}"]`);select.disabled=true;feedback.textContent='جارٍ الحفظ…';
  try{const {error}=await sb.rpc('set_job_stage_owner',{p_stage:stage,p_profile_id:select.value});if(error)throw error;owners.set(stage,select.value);feedback.textContent='تم تحديث المسؤول ونقل المهام المفتوحة.';}catch(e){select.value=prior;feedback.textContent=e.message;}finally{select.disabled=false;}
 };
 document.body.style.visibility='visible';
}catch(e){document.body.style.visibility='visible';state.dataset.error='true';state.textContent=e.message||'تعذر تحميل الإعدادات.';}
