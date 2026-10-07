import {canApproveRelationalTask} from './tasks-core.mjs?v=1.9.8';
import {weightedProgress} from './projects-core.mjs';
export const escape=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
export const riyadhDay=(date=new Date())=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Riyadh',year:'numeric',month:'2-digit',day:'2-digit'}).format(date);
export const taskLink=t=>`../tasks/index.html?task=${encodeURIComponent(t.id)}&owner=${encodeURIComponent(t.assignee_id||'')}${t.status==='مكتملة'?'&scope=COMPLETED':''}`;
export function workspaceModel({profile,tasks=[],projects=[],members=[],directIds=[],day=riyadhDay()}){
 const active=tasks.filter(t=>!t.deleted_at&&!['مكتملة','ملغاة'].includes(t.status));
 const mine=active.filter(t=>t.assignee_id===profile.id);
 const due=mine.filter(t=>t.task_type!=='job_workflow'&&t.status!=='بانتظار الاعتماد'&&((t.due_date&&t.due_date<=day)||t.start_date===day)).sort((a,b)=>(a.due_date||'9999').localeCompare(b.due_date||'9999'));
 const decisions=active.filter(t=>t.task_type==='job_workflow'?t.assignee_id===profile.id:canApproveRelationalTask(t,profile,{directIds,projects}));
 const memberProjects=new Set(members.filter(m=>m.user_id===profile.id).map(m=>m.project_id));
 const personalProjects=projects.filter(p=>!p.deleted_at&&!['CLOSED','CANCELLED'].includes(p.status)&&(p.manager_id===profile.id||p.sponsor_id===profile.id||p.created_by===profile.id||memberProjects.has(p.id))).sort((a,b)=>(a.due_date||'9999').localeCompare(b.due_date||'9999')).map(p=>({...p,progress:weightedProgress(tasks.filter(t=>t.project_id===p.id))}));
 return {due,decisions,projects:personalProjects,overdue:due.filter(t=>t.due_date&&t.due_date<day).length,day};
}
export function renderWorkspace(model,notifications=[]){
 const empty=text=>`<p class="space-empty">${text}</p>`;
 const task=(t,decision=false)=>`<a class="space-row" href="${taskLink(t)}"><span class="space-row-icon"><i data-lucide="${decision?'stamp':'check-square-2'}"></i></span><span class="space-row-copy"><strong>${escape(t.title)}</strong><small>${escape(t.status)}${t.due_date?' · '+escape(t.due_date):''}</small></span><span class="space-pill ${!decision&&t.due_date&&t.due_date<model.day?'late':''}">${decision?'مراجعة':t.due_date&&t.due_date<model.day?'متأخرة':'فتح'}</span></a>`;
 return {tasks:model.due.length?model.due.slice(0,6).map(t=>task(t)).join(''):empty('لا توجد مهام مستحقة اليوم. يمكنك الاطلاع على بقية مهامك.'),decisions:model.decisions.length?model.decisions.slice(0,6).map(t=>task(t,true)).join(''):empty('لا توجد قرارات أو مراجعات مطلوبة منك حاليًا.'),projects:model.projects.length?model.projects.slice(0,4).map(p=>`<a class="space-project" href="../projects/index.html?id=${encodeURIComponent(p.id)}"><div><strong>${escape(p.title)}</strong><span>${p.progress}%</span></div><progress max="100" value="${p.progress}" aria-label="تقدم ${escape(p.title)}"></progress><small>موعد التسليم: ${escape(p.due_date||'غير محدد')}</small></a>`).join(''):empty('لا توجد مشاريع نشطة تشارك فيها حاليًا.'),updates:notifications.length?notifications.slice(0,5).map(n=>`<button type="button" class="space-row space-update" data-space-notification="${escape(n.id)}"><span class="space-row-icon"><i data-lucide="bell"></i></span><span class="space-row-copy"><strong>${escape(n.title||'مستجد جديد')}</strong><small>${escape(n.message||'افتح للاطلاع على التفاصيل')}</small></span></button>`).join(''):empty('أنت مطّلع على جميع المستجدات الحالية.')};
}
