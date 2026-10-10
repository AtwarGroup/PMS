import {escape,riyadhDay} from './workspace-core.mjs?v=2.5.59';
export function renderJobFollowup(rows,day=riyadhDay()){
 const published=rows.filter(r=>r.published),accepted=published.filter(r=>r.accepted),pending=published.filter(r=>!r.accepted),missing=rows.filter(r=>!r.published);
 const reviews=[...new Map(rows.filter(r=>r.review_enabled&&r.review_due).map(r=>[r.job_id,r])).values()].sort((a,b)=>a.review_due.localeCompare(b.review_due));
 const person=(r,note)=>`<div class="space-row"><span class="space-row-copy"><strong>${escape(r.name)}</strong><small>${escape(r.title||'لا يوجد وصف منشور')} · ${escape(note)}</small></span></div>`;
 return `<h3>تغطية إقرارات الأوصاف الوظيفية</h3><p>${accepted.length} من ${published.length} أقروا بالنسخة الحالية · ${published.length?Math.round(100*accepted.length/published.length)+'%':'لا توجد أوصاف منشورة للفريق'}</p><details><summary>لم يقروا بعد (${pending.length})</summary>${pending.map(r=>person(r,'الإصدار '+r.revision)).join('')||'<p>لا توجد إقرارات معلقة.</p>'}</details><details><summary>دون وصف منشور (${missing.length})</summary>${missing.map(r=>person(r,'يحتاج ربطًا أو نشرًا')).join('')||'<p>جميع أفراد الفريق مرتبطون بأوصاف منشورة.</p>'}</details><h3>مواعيد المراجعة الدورية للأوصاف</h3>${reviews.map(r=>`<div class="space-row"><span class="space-row-copy"><strong>${escape(r.title)}</strong><small>${escape(r.review_due)}${r.review_due<=day?' · مستحقة للمراجعة':''}</small></span></div>`).join('')||'<p>لا توجد مراجعات دورية مفعلة لهذا النطاق.</p>'}`;
}
export async function mountJobFollowup(host,sb){
 if(!host||typeof sb.rpc!=='function')return;
 try{const {data,error}=await sb.rpc('job_acknowledgement_followup');if(error)throw error;host.innerHTML=renderJobFollowup(data||[]);}catch{host.innerHTML='<p role="status">تعذر تحميل متابعة الإقرارات؛ نعيد المحاولة تلقائيًا.</p>';}
}
export async function mountApprovalSettings(host,sb,profile){
 if(!host||profile.role!=='admin'||typeof sb.from!=='function')return;
 if(host.contains?.(document.activeElement))return;
 try{
  const {data,error}=await sb.from('approval_followup_settings').select('*').eq('id',true).single();if(error)throw error;
  host.innerHTML=`<details><summary>إعدادات تذكير وتصعيد الاعتماد · ${data.enabled?'مفعّل':'متوقف'}</summary><form id="approvalSettingsForm"><label><input name="enabled" type="checkbox" ${data.enabled?'checked':''}> تفعيل إشعارات المتابعة</label><label>التذكير بعد (أيام تقويمية)<input name="reminder_days" type="number" min="1" max="90" required value="${data.reminder_days}"></label><label>التصعيد بعد (أيام تقويمية)<input name="escalation_days" type="number" min="2" max="180" required value="${data.escalation_days}"></label><p>تُحسب المدة من الإرسال للاعتماد بتوقيت الرياض. إشعار واحد لكل مرحلة ودورة اعتماد؛ التصعيد للمدير المباشر لصاحب الاعتماد فقط إذا كان يملك حق الاطلاع. لا تتغير صلاحية القرار.</p><button type="submit" class="atwar-btn primary">حفظ الإعدادات</button><p id="approvalSettingsStatus" role="status"></p></form></details>`;
  const form=host.querySelector('form');form.onsubmit=async e=>{e.preventDefault();const button=form.querySelector('button'),status=host.querySelector('#approvalSettingsStatus');const reminder=Number(form.elements.reminder_days.value),escalation=Number(form.elements.escalation_days.value);if(!Number.isInteger(reminder)||!Number.isInteger(escalation)||reminder<1||reminder>90||escalation<=reminder||escalation>180){status.textContent='حدد مددًا صحيحة؛ التصعيد بعد التذكير.';return;}button.disabled=true;
   try{const result=await sb.from('approval_followup_settings').update({enabled:form.elements.enabled.checked,reminder_days:reminder,escalation_days:escalation,revision:data.revision+1}).eq('id',true).eq('revision',data.revision).select('revision').single();if(result.error)throw result.error;data.revision=result.data.revision;status.textContent='تم حفظ الإعدادات. تطبق المتابعة كل ساعة.';}catch{status.textContent='تعذر الحفظ أو تغيرت الإعدادات. أعد فتح الصفحة والمحاولة.';}finally{button.disabled=false;}
  };
 }catch{host.innerHTML='<p role="status">تعذر تحميل إعدادات متابعة الاعتماد.</p>';}
}
