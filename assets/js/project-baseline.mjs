import {escapeHTML as escape} from './tasks-core.mjs?v=1.9.8';
export const baselineTasks=tasks=>tasks.filter(t=>!t.deleted_at&&t.status!=='ملغاة'&&t.task_type!=='job_workflow');
export const baselineRevisions=tasks=>baselineTasks(tasks).map(t=>({id:t.id,revision:t.revision})).sort((a,b)=>a.id.localeCompare(b.id));
export function dateVariance(planned,current){
 if(!planned||!current)return null;
 const a=Date.parse(planned+'T00:00:00Z'),b=Date.parse(current+'T00:00:00Z');
 return Number.isFinite(a)&&Number.isFinite(b)?Math.round((b-a)/86400000):null;
}
export function baselineComparison(baseline,project,tasks){
 if(!baseline)return null;
 const old=new Map(baseline.task_snapshot.map(t=>[t.id,t])),now=new Map(baselineTasks(tasks).map(t=>[t.id,t]));
 const fields=['title','start_date','due_date','assignee_id','project_phase_id','project_weight','project_milestone'];
 const rows=[...new Set([...old.keys(),...now.keys()])].map(id=>{
  const planned=old.get(id),current=now.get(id);
  const changed=planned&&current&&fields.some(key=>String(planned[key]??'')!==String(current[key]??''));
  return {id,planned,current,kind:!planned?'added':!current?'removed':changed?'changed':'same',variance:planned&&current?dateVariance(planned.due_date,current.due_date):null};
 }).sort((a,b)=>({changed:0,added:1,removed:2,same:3})[a.kind]-({changed:0,added:1,removed:2,same:3})[b.kind]||a.id.localeCompare(b.id));
 return {rows,added:rows.filter(r=>r.kind==='added').length,removed:rows.filter(r=>r.kind==='removed').length,changed:rows.filter(r=>r.kind==='changed').length,startVariance:dateVariance(baseline.project_snapshot.start_date,project.start_date),dueVariance:dateVariance(baseline.project_snapshot.due_date,project.due_date)};
}
const delta=n=>n===null?'غير متاح':n===0?'دون تغيير':n>0?`+${n} يوم`:`${n} يوم`;
export function renderBaseline(baseline,project,tasks,{canCapture=false,failed=false}={}){
 if(failed)return '<h2>الخطة المرجعية</h2><p class="project-empty" role="status">تعذر تحميل الخطة المرجعية. سنعيد المحاولة مع التحديث التلقائي.</p>';
 if(!baseline)return `<h2>الخطة المرجعية</h2><p class="project-muted">ثبّت نسخة من مواعيد المشروع ومهامه الحالية، ثم قارن بها التغييرات اللاحقة. تثبيت الخطة إجراء توثيق، ولا ينشئ اعتمادًا جديدًا.</p><p class="project-muted">لم تُثبّت خطة مرجعية لهذا المشروع بعد.</p>${canCapture?'<button id="captureBaseline" class="atwar-btn primary" type="button">تثبيت الخطة الحالية كمرجع</button>':''}`;
 const model=baselineComparison(baseline,project,tasks),snapshot=baseline.project_snapshot;
 const captured=new Intl.DateTimeFormat('ar-SA',{dateStyle:'medium',timeStyle:'short',timeZone:'Asia/Riyadh',calendar:'gregory'}).format(new Date(baseline.captured_at));
 const dates=t=>t?`${escape(t.start_date||'—')} — ${escape(t.due_date||'—')}`:'—';
 const names={added:'مضافة بعد تثبيت المرجع',removed:'محذوفة أو ملغاة من الخطة',changed:'تغيّر في الخطة',same:'دون تغيير في الخطة'};
 const rows=model.rows.map(r=>`<tr><td>${r.current?`<button class="atwar-btn" data-task="${escape(r.id)}">${escape(r.current.title)}</button>`:escape(r.planned.title)}${r.planned&&r.current&&r.planned.title!==r.current.title?`<small class="project-muted">الاسم المرجعي: ${escape(r.planned.title)}</small>`:''}</td><td>${dates(r.planned)}<small class="project-muted">${escape(r.planned?.assignee_name_snapshot||'')}</small></td><td>${dates(r.current)}<small class="project-muted">${escape(r.current?.assignee_name_snapshot||'')}</small></td><td>${escape(delta(r.variance))}</td><td>${names[r.kind]}</td><td>${escape(r.current?.status||'خارج الخطة الحالية')}${r.current?.actual_end_date?`<small class="project-muted">الإنجاز الفعلي: ${escape(r.current.actual_end_date)}</small>`:''}</td></tr>`).join('');
 const scope=`<details class="project-modal"><summary>مقارنة الهدف والمخرجات</summary><h3>الهدف المرجعي</h3><p class="project-body">${escape(snapshot.objective)||'لم يحدد'}</p><h3>الهدف الحالي</h3><p class="project-body">${escape(project.objective)||'لم يحدد'}</p><h3>المخرجات المرجعية</h3><p class="project-body">${escape(snapshot.deliverables)||'لم تحدد'}</p><h3>المخرجات الحالية</h3><p class="project-body">${escape(project.deliverables)||'لم تحدد'}</p></details>`;
 return `<h2>الخطة المرجعية مقابل الحالية</h2><p class="project-muted">ثُبّت المرجع بواسطة ${escape(baseline.captured_by_name)} في ${escape(captured)}. يحتفظ النظام بهذا المرجع الأصلي.</p><div class="project-facts"><div>فترة المرجع<b>${dates(snapshot)}</b></div><div>الفترة الحالية<b>${dates(project)}</b></div><div>تغيّر نهاية المشروع<b>${escape(delta(model.dueVariance))}</b></div></div>${scope}<p class="project-muted">${model.changed} مهام تغيّرت خطتها · ${model.added} مهام مضافة · ${model.removed} مهام خارج الخطة الحالية. الإشارة الموجبة تعني تمديد الموعد؛ ولا تعني بمفردها تأخر التنفيذ.</p><div class="project-table-wrap"><table class="project-table"><thead><tr><th>المهمة</th><th>الخطة المرجعية</th><th>الخطة الحالية</th><th>تغيّر النهاية</th><th>تغيّر النطاق</th><th>حالة التنفيذ الحالية</th></tr></thead><tbody>${rows}</tbody></table></div>${!rows?'<p class="project-empty">لا توجد مهام في الخطة المرجعية أو الحالية.</p>':''}`;
}
