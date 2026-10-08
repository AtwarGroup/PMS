import {freshJob,jobValidation} from './job-workflow-model.mjs?v=2.5.55';
const sb=await window.atwarGetSupabase(),$=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
let profile,users=[],jobs=[],draft=freshJob(),step=0,saving=false,dirty=false,requestId=crypto.randomUUID();
const steps=['بيانات الوظيفة','المهام والصلاحيات','المؤشرات والمخرجات','المؤهلات والعلاقات','المراجعة والإرسال'];
const options=(rows,value,label)=>rows.map(x=>`<option value="${esc(x.id)}" ${x.id===value?'selected':''}>${esc(label(x))}</option>`).join('');
function notice(message,error=false){$('authoringNotice').textContent=message;$('authoringNotice').classList.toggle('danger',error);}
function field(label,key,value,type='text'){return `<div class="edit-field"><label for="author-${key.replaceAll('.','-')}">${label}</label><${type==='textarea'?'textarea':'input'} id="author-${key.replaceAll('.','-')}" data-field="${key}" ${type==='textarea'?'':`type="${type}" value="${esc(value)}"`}>${type==='textarea'?esc(value):''}${type==='textarea'?'</textarea>':''}</div>`;}
function list(key,title,fields){const rows=draft.content[key]||[];return `<section><h2>${title}</h2>${rows.map((item,index)=>`<article class="authoring-item"><header><b>البند ${index+1}</b><div class="item-controls"><button type="button" data-move="${key}:${index}:-1" ${index===0?'disabled':''} aria-label="نقل البند للأعلى">↑</button><button type="button" data-move="${key}:${index}:1" ${index===rows.length-1?'disabled':''} aria-label="نقل البند للأسفل">↓</button><button type="button" data-remove="${key}:${index}">حذف</button></div></header><div class="edit-grid">${fields.map(([name,label,type])=>field(label,`content.${key}.${index}.${name}`,typeof item==='string'?(name==='text'||name==='name'?item:''):item[name],type)).join('')}</div></article>`).join('')||'<p>لم تضف بنودًا بعد.</p>'}<button type="button" class="review-btn" data-add="${key}">إضافة ${title==='مؤشرات الأداء'?'مؤشر':'بند'}</button></section>`;}
function render(){
 $('authoringTitle').textContent=draft.id?'إعداد الوصف: '+draft.title:'إضافة وصف وظيفي';
 $('authoringSteps').innerHTML=steps.map((label,i)=>`<button type="button" data-step="${i}" class="${step===i?'active':''}" ${step===i?'aria-current="step"':''}>${i+1}. ${label}</button>`).join('');
 for(const key of ['responsibilities','authorities','kpis','reports'])draft.content[key]=(draft.content[key]||[]).map(x=>typeof x==='string'?{[key==='kpis'||key==='reports'?'name':'text']:x}:x);
 (draft.content.kpis||[]).forEach(k=>(k.scale||[]).forEach((level,i)=>{if(k['scale_'+(i+1)]===undefined)k['scale_'+(i+1)]=level.label||level.range||'';}));
 const override=draft.reviewer_mode==='override';
 const currentManager=users.find(x=>x.id===users.find(u=>u.id===draft.reference_profile_id)?.manager_id);
 let body='';
 if(step===0)body=`<h2>بيانات الوظيفة</h2><div class="edit-grid">${field('المسمى الوظيفي','title',draft.title)}${field('الإدارة / العائلة الوظيفية','family',draft.family)}${field('المستوى الوظيفي','job_level',draft.job_level)}<div class="edit-field"><label for="reportsToJob">يتبع الوظيفة</label><select id="reportsToJob" data-field="reports_to_job_id"><option value="">اختر الوظيفة الأعلى في الهيكل</option>${options(jobs.filter(j=>j.id!==draft.id&&j.status!=='ARCHIVED'),draft.reports_to_job_id,j=>j.title)}</select></div><div class="edit-field"><label for="referenceEmployee">موظف مرجعي لتحديد المدير المباشر</label><select id="referenceEmployee" data-field="reference_profile_id"><option value="">اختياري؛ لا يربط الموظف بالوصف</option>${options(users,draft.reference_profile_id,u=>u.full_name+' — '+(u.job_title||''))}</select></div>${field('الغرض الوظيفي','purpose',draft.purpose,'textarea')}</div><p>يُحدد المراجع من المدير المباشر للموظفين المرتبطين، أو الموظف المرجعي، أو شاغل الوظيفة الأعلى. ${currentManager?'المدير المباشر للموظف المرجعي: '+esc(currentManager.full_name):''}</p>${draft.reviewer_mode==='legacy'?'<p>هذا وصف قائم؛ تُحفظ مرجعية المراجعة السابقة إلى أن تختار تحديدها تلقائيًا.</p><button type="button" id="useAutoManager" class="review-btn">استخدام المدير المباشر تلقائيًا</button>':''}${profile.role==='admin'?`<label><input type="checkbox" id="useOverride" ${override?'checked':''}> تعيين بديل للمراجع في حالة استثنائية</label><div id="overrideFields" class="edit-grid" ${override?'':'hidden'}><div class="edit-field"><label for="overrideReviewer">المراجع البديل</label><select id="overrideReviewer" data-field="reviewer_id"><option value="">اختر البديل</option>${options(users,draft.reviewer_id,u=>u.full_name)}</select></div>${field('سبب تعيين البديل','reviewer_override_reason',draft.reviewer_override_reason,'textarea')}</div>`:''}`;
 if(step===1)body=list('responsibilities','المهام والمسؤوليات',[['text','المهمة أو المسؤولية','textarea'],['frequency','الدورية']])+ '<hr>'+list('authorities','الصلاحيات',[['text','الإجراء','textarea'],['type','نوع الصلاحية'],['scope','النطاق'],['limit','الحد'],['escalation','التصعيد']]);
 if(step===2)body=list('kpis','مؤشرات الأداء',[['name','اسم المؤشر'],['perspective','محور بطاقة الأداء'],['measure','طريقة / معادلة القياس','textarea'],['unit','وحدة القياس'],['target','المستهدف'],['source','مصدر القياس'],['weight','الوزن %','number'],['frequency','دورية القياس'],...Array.from({length:5},(_,i)=>['scale_'+(i+1),'حد المستوى '+(i+1)])])+ '<p>يجب أن يساوي مجموع الأوزان ١٠٠٪ قبل إرسال الوصف.</p><hr>'+list('reports','المخرجات والتقارير',[['name','المخرج أو التقرير'],['frequency','دورية التسليم'],['recipient','الجهة المستلمة']]);
 if(step===3)body=`<h2>المؤهلات والمهارات والعلاقات</h2><div class="edit-grid">${[['education','المؤهل'],['experience','الخبرة'],['skills','المهارات']].map(([k,l])=>field(l,'content.qualifications.'+k,draft.content.qualifications?.[k]||'','textarea')).join('')}${[['internal','العلاقات الداخلية'],['external','العلاقات الخارجية']].map(([k,l])=>field(l,'content.relationships.'+k,draft.content.relationships?.[k]||'','textarea')).join('')}</div>`;
 if(step===4){const issues=jobValidation(draft);body=`<h2>مراجعة المسودة</h2><div class="workflow-summary"><span>${esc(draft.title||'المسمى غير محدد')}</span><span>${esc(draft.family||'الإدارة غير محددة')}</span><span>${draft.id?'رمز الوظيفة: '+esc(draft.job_code):'يُنشأ رمز الوظيفة عند الحفظ'}</span></div><p>${esc(draft.purpose)}</p><div class="workflow-summary">${[['responsibilities','مسؤوليات'],['authorities','صلاحيات'],['kpis','مؤشرات'],['reports','مخرجات']].map(([k,l])=>`<span>${draft.content[k]?.length||0} ${l}</span>`).join('')}</div>${issues.length?`<div class="workflow-return-note"><b>متطلبات الإرسال المتبقية</b><ul>${issues.map(x=>`<li>${esc(x)}</li>`).join('')}</ul><p>يمكنك حفظ المسودة الآن واستكمالها لاحقًا.</p></div>`:'<p>المحتوى جاهز للتحقق والإرسال إلى المدير المباشر.</p>'}<p>إعداد ← مراجعة المدير المباشر ← مراجعة نهائية ← اعتماد ونشر ← إقرار الموظف</p>`;}
 $('authoringBody').innerHTML=body;
 $('previousStep').hidden=step===0;$('nextStep').hidden=step===steps.length-1;
 document.querySelectorAll('[data-step]').forEach(b=>b.onclick=()=>{step=Number(b.dataset.step);render();});
 document.querySelectorAll('[data-add]').forEach(b=>b.onclick=()=>{const key=b.dataset.add;draft.content[key]||=[];draft.content[key].push(key==='kpis'?{name:'',weight:'',measure:'',source:'',target:''}:key==='reports'?{name:''}:{text:''});dirty=true;render();});
 document.querySelectorAll('[data-remove]').forEach(b=>b.onclick=async()=>{if(!await window.AtwarUI.confirm({title:'حذف البند من المسودة',message:'سيُحذف البند من هذه المسودة.'}))return;const [key,i]=b.dataset.remove.split(':');draft.content[key].splice(Number(i),1);dirty=true;render();});
 document.querySelectorAll('[data-move]').forEach(b=>b.onclick=()=>{const [key,i,d]=b.dataset.move.split(':'),a=Number(i),z=a+Number(d);[draft.content[key][a],draft.content[key][z]]=[draft.content[key][z],draft.content[key][a]];dirty=true;render();});
 $('useOverride')?.addEventListener('change',e=>{draft.reviewer_mode=e.target.checked?'override':'auto';dirty=true;render();});
 $('useAutoManager')?.addEventListener('click',()=>{draft.reviewer_mode='auto';dirty=true;render();});
}
function setValue(path,value){let object=draft;const keys=path.split('.');for(const key of keys.slice(0,-1)){object[key]||={};object=object[key];}object[keys.at(-1)]=value;}
$('authoringForm').addEventListener('input',e=>{if(e.target.dataset.field){setValue(e.target.dataset.field,e.target.value);dirty=true;}});
$('authoringForm').addEventListener('change',e=>{if(e.target.dataset.field){setValue(e.target.dataset.field,e.target.value);if(e.target.dataset.field==='reports_to_job_id')draft.reports_to_title=jobs.find(j=>j.id===e.target.value)?.title||'';dirty=true;}});
$('authoringForm').onsubmit=e=>e.preventDefault();
$('previousStep').onclick=()=>{step--;render();};$('nextStep').onclick=()=>{step++;render();};
$('copyJob').onchange=async()=>{const source=jobs.find(j=>j.id===$('copyJob').value);if(dirty&&!await window.AtwarUI.confirm({title:'استبدال محتوى المسودة',message:'سيُستبدل المحتوى غير المحفوظ بمحتوى الوصف المختار.'}))return;const identity=draft.id?{id:draft.id,job_code:draft.job_code,revision:draft.revision,status:draft.status}:{};draft={...freshJob(source?.published_snapshot||source),...identity};dirty=true;step=0;render();};
async function save(send=false){
 if(saving)return;
 if(!draft.title.trim()){step=0;render();return notice('أدخل المسمى الوظيفي أولًا.',true);}
 const issues=send?jobValidation(draft):[];if(issues.length){step=4;render();return notice('أكمل متطلبات الإرسال الموضحة أدناه.',true);}
 saving=true;for(const id of ['saveDraft','sendReview'])$(id).disabled=true;
 try{
  const content=structuredClone(draft.content);content.kpis=(content.kpis||[]).map(k=>{const result={...k,weight:k.weight===''?'':Number(k.weight)};if(Array.from({length:5},(_,i)=>k['scale_'+(i+1)]).some(Boolean))result.scale=Array.from({length:5},(_,i)=>({score:i+1,label:k['scale_'+(i+1)]||''}));for(let i=1;i<=5;i++)delete result['scale_'+i];return result;});
  const payload={...draft,content};delete payload.published_snapshot;
  const r=await sb.rpc(draft.id?'save_job_description_draft':'create_job_description_draft',draft.id?{p_job_id:draft.id,p_expected_revision:draft.revision,p_payload:payload}:{p_request_id:requestId,p_payload:payload});
  if(r.error)throw r.error;draft=r.data;dirty=false;history.replaceState({},'',`create.html?id=${encodeURIComponent(draft.id)}`);$('copyJob').disabled=true;
  if(send){const result=await sb.rpc('submit_job_description_draft',{p_job_id:draft.id,p_expected_revision:draft.revision});if(result.error)throw result.error;location.href=`review.html?id=${encodeURIComponent(draft.id)}`;return;}
  render();notice('حُفظت المسودة. يمكنك استكمالها لاحقًا من مكتبة الوظائف.');
 }catch(error){notice(error.message||'تعذر حفظ المسودة.',true);}
 finally{saving=false;for(const id of ['saveDraft','sendReview'])$(id).disabled=false;}
}
$('saveDraft').onclick=()=>save();$('sendReview').onclick=()=>save(true);
window.addEventListener('beforeunload',e=>{if(dirty){e.preventDefault();e.returnValue='';}});
async function boot(){
 const {data:{session}}=await sb.auth.getSession();if(!session)return location.href='../login.html';
 const p=await sb.from('profiles').select('id,full_name,role,active,status').eq('id',session.user.id).single();profile=p.data;
 const stages=await sb.from('job_stage_owners').select('stage,profile_id');if(profile?.role!=='admin'&&!stages.data?.some(s=>s.stage==='DRAFT'&&s.profile_id===profile.id))throw new Error('لا تملك صلاحية إعداد الأوصاف الوظيفية.');
 const [directory,library]=await Promise.all([sb.rpc('job_stage_directory'),sb.from('job_descriptions').select('*').order('title')]);if(directory.error||library.error)throw directory.error||library.error;users=directory.data||[];jobs=library.data||[];
 const id=new URLSearchParams(location.search).get('id');if(id){const j=jobs.find(x=>x.id===id);if(!j)throw new Error('الوصف غير موجود أو غير متاح.');if(!['DRAFT','CHANGES_REQUESTED','PUBLISHED'].includes(j.status))throw new Error('أعد الوصف للتعديل قبل تغيير محتواه.');draft=structuredClone(j);draft.content.kpis=(draft.content.kpis||[]).map(k=>typeof k==='string'?{name:k}:{...k,...Object.fromEntries((k.scale||[]).map((s,i)=>['scale_'+(i+1),s.label||s.range||'']))});$('copyJob').disabled=true;}
 $('copyJob').innerHTML='<option value="">ابدأ بوصف فارغ</option>'+options(jobs.filter(x=>x.status!=='ARCHIVED'),' ',j=>j.title);
 window.atwarSyncShellIdentity?.(profile,session.user);$('authoringState').hidden=true;$('authoringApp').hidden=false;document.body.style.visibility='visible';render();
}
boot().catch(e=>{document.body.style.visibility='visible';$('authoringState').textContent=e.message;});
