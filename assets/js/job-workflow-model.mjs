export const stageLabels={DRAFT:'مسودة',IN_REVIEW:'قيد مراجعة المدير',CHANGES_REQUESTED:'معاد للتعديل',PUBLISHED:'معتمد ومنشور',ARCHIVED:'مؤرشف'};
export function jobStage(job){if(job.scheduled_effective_date)return job.schedule_status==='BLOCKED'?'تعذر بدء السريان — يحتاج مراجعة':'معتمد بانتظار السريان';return job.status==='MANAGER_APPROVED'?(job.final_reviewed_at?'بانتظار الاعتماد والنشر':'قيد المراجعة النهائية'):stageLabels[job.status]||job.status;}
export function pendingChanges(rows){return rows.filter(x=>x.status==='PENDING'&&x.action!=='COMMENT');}
// Object key ordering is not a business change; array ordering remains meaningful.
function canonical(value){return Array.isArray(value)?value.map(canonical):value&&typeof value==='object'?Object.fromEntries(Object.keys(value).sort().map(key=>[key,canonical(value[key])])):value;}
export function publicationChanges(job){
 const previous=job.published_snapshot;
 const fields=[['المسمى','title'],['الإدارة','family'],['المستوى الوظيفي','job_level'],['الرئيس المباشر','reports_to_title'],['الغرض الوظيفي','purpose']];
 const changed=fields.filter(([,key])=>JSON.stringify(canonical(previous?.[key]??''))!==JSON.stringify(canonical(job[key]??''))).map(([label])=>label);
 for(const [key,label] of [['responsibilities','المهام والمسؤوليات'],['authorities','الصلاحيات'],['kpis','مؤشرات الأداء'],['reports','المخرجات والتقارير'],['qualifications','المؤهلات'],['relationships','العلاقات']])
  if(JSON.stringify(canonical(previous?.content?.[key]??null))!==JSON.stringify(canonical(job.content?.[key]??null)))changed.push(label);
 return {firstPublication:!previous,changed};
}
export function jobValidation(job){
 const c=job.content||{},issues=[];
 if((job.title||'').trim().length<2)issues.push('المسمى الوظيفي');
 if((job.purpose||'').trim().length<40)issues.push('الغرض الوظيفي: ٤٠ حرفًا على الأقل');
 for(const [key,label] of [['responsibilities','المهام والمسؤوليات'],['authorities','الصلاحيات'],['kpis','مؤشرات الأداء'],['reports','المخرجات والتقارير']])if(!c[key]?.length)issues.push(label);
 if(!c.qualifications?.education?.trim())issues.push('المؤهل المطلوب');
 if(c.kpis?.length){
  if(c.kpis.some(x=>!x.name?.trim()||!x.measure?.trim()||!x.source?.trim()||!x.target?.trim()||!Number.isFinite(Number(x.weight))||Number(x.weight)<=0))issues.push('اسم وطريقة قياس ومصدر ومستهدف ووزن لكل مؤشر');
  if(Math.abs(c.kpis.reduce((sum,x)=>sum+Number(x.weight||0),0)-100)>0.001)issues.push('مجموع أوزان المؤشرات يجب أن يساوي ١٠٠٪');
 }
 return issues;
}
export function freshJob(source){return {title:'',family:source?.family||'',job_level:source?.job_level||'',purpose:source?.purpose||'',reports_to_title:'',reports_to_job_id:null,reference_profile_id:null,reviewer_id:null,reviewer_mode:'auto',reviewer_override_reason:'',content:structuredClone(source?.content||{responsibilities:[],authorities:[],kpis:[],reports:[],qualifications:{education:'',experience:'',skills:''},relationships:{internal:'',external:''}})};}

export function riyadhToday(now=new Date()){const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Riyadh',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(now);const part=type=>parts.find(x=>x.type===type).value;return `${part('year')}-${part('month')}-${part('day')}`;}
export function periodicDue(review,today=riyadhToday()){return Boolean(review?.enabled&&!review.needs_changes&&review.due_on<=today);}

export function addReviewMonths(date,months){const [year,month,day]=date.split('-').map(Number);const target=new Date(Date.UTC(year,month-1+months,1));const last=new Date(Date.UTC(target.getUTCFullYear(),target.getUTCMonth()+1,0)).getUTCDate();target.setUTCDate(Math.min(day,last));return target.toISOString().slice(0,10);}
