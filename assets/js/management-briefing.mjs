import {escape,taskLink,riyadhDay} from './workspace-core.mjs?v=2.5.60';
const active=t=>['قيد الانتظار','قيد التنفيذ'].includes(t.status);
export function managementBriefing({profile,tasks=[],projects=[],directIds=[],followups=[],inbox=[],day=riyadhDay()}){
 const enabled=['admin','manager'].includes(profile.role);
 const shift=n=>{const d=new Date(day+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);};
 const since=shift(-6),until=shift(7),team=new Set([profile.id,...directIds]);
 const managed=projects.filter(p=>!p.deleted_at&&(p.manager_id===profile.id||p.sponsor_id===profile.id||profile.role==='admin'));
 const projectIds=new Set(managed.map(p=>p.id));
 const scope=enabled?tasks.filter(t=>!t.deleted_at&&(profile.role==='admin'||team.has(t.assignee_id)||projectIds.has(t.project_id))):[];
 const ordinary=scope.filter(t=>t.task_type!=='job_workflow');
 const current=ordinary.filter(active);
 const completionDay=t=>t.completed_at&&Number.isFinite(Date.parse(t.completed_at))?riyadhDay(new Date(t.completed_at)):t.actual_end_date;
 const completed=ordinary.filter(t=>t.status==='مكتملة'&&completionDay(t)>=since&&completionDay(t)<=day);
 const pending=ordinary.filter(t=>t.status==='بانتظار الاعتماد');
 const overdue=current.filter(t=>t.due_date&&t.due_date<day).sort((a,b)=>a.due_date.localeCompare(b.due_date)||a.id.localeCompare(b.id));
 const byTask=new Map(current.map(t=>[t.id,t]));
 const blockers=followups.filter(f=>f.blocked&&byTask.has(f.task_id)).map(f=>({task:byTask.get(f.task_id),followup:f}));
 const groups=new Map();
 for(const task of current.filter(t=>t.assignee_id&&t.due_date>=day&&t.due_date<=until)){
  const key=task.assignee_id+':'+task.due_date;
  if(!groups.has(key))groups.set(key,{owner:task.assignee_name_snapshot||'المسند إليه',date:task.due_date,tasks:[]});
  groups.get(key).tasks.push(task);
 }
 const concentrations=[...groups.values()].filter(g=>g.tasks.length>=3).sort((a,b)=>b.tasks.length-a.tasks.length||a.date.localeCompare(b.date));
 const governance=scope.filter(t=>t.task_type==='job_workflow'&&active(t)).sort((a,b)=>(a.due_date||'9999').localeCompare(b.due_date||'9999')||a.id.localeCompare(b.id));
 return {enabled,profileRole:profile.role,day,since,until,completed,pending,overdue,blockers,concentrations,governance,inbox,projects:managed.filter(p=>!['CLOSED','CANCELLED'].includes(p.status))};
}
export function renderManagementBriefing(m){
 if(!m.enabled)return '';
 const empty=text=>`<p class="space-empty">${escape(text)}</p>`;
 const link=(t,note)=>`<a class="space-row" href="${escape(taskLink(t))}"><span class="space-row-copy"><strong>${escape(t.title)}</strong><small>${escape(t.assignee_name_snapshot||'المسند إليه')} · ${escape(note)}</small></span></a>`;
 const count=(label,n,target)=>`<a class="space-summary-item" href="#${target}"><strong>${n}</strong><span>${label}</span></a>`;
 const section=(id,title,body)=>`<section class="management-section" id="${id}"><h3>${title}</h3>${body}</section>`;
 const metrics=count('مكتملة خلال آخر ٧ أيام',m.completed.length,'managementCompleted')+count('متأخرة حاليًا',m.overdue.length,'managementOverdue')+count('بانتظار الاعتماد',m.pending.length,'managementPending')+count('عوائق مسجلة',m.blockers.length,'managementBlockers');
 const concentration=m.concentrations.map(g=>`<details class="management-concentration"><summary>${escape(g.owner)} · ${escape(g.date)} · ${g.tasks.length} مهام مستحقة</summary>${g.tasks.map(t=>link(t,'موعد الاستحقاق: '+t.due_date)).join('')}</details>`).join('');
 const projectRows=m.projects.map(p=>`<a class="space-row" href="../projects/index.html?id=${encodeURIComponent(p.id)}"><span class="space-row-copy"><strong>${escape(p.title)}</strong><small>موعد نهاية المشروع: ${escape(p.due_date||'غير محدد')}</small></span></a>`).join('');
 return `<p class="management-scope">${escape(m.since)} — ${escape(m.day)} · ${m.projects.length} مشاريع مفتوحة · ${m.inbox.length} إجراءات مطلوبة منك الآن. ${m.inbox.length?'<a href="#spaceDecisionPanel">فتح الإجراءات</a>':''}</p><p class="management-scope">${m.profileRole==='admin'?'الأعمال المتاحة بحسب صلاحياتك.':'فريقك المباشر والمشاريع التي تديرها أو تعتمدها.'} لا يتضمن الملخص تقييمًا تلقائيًا للموظفين.</p><nav class="management-metrics" aria-label="ملخص المتابعة الإدارية">${metrics}</nav><div class="management-grid">${section('managementCompleted','ما أُنجز خلال الأسبوع',m.completed.map(t=>link(t,'مكتملة')).join('')||empty('لا توجد مهام مكتملة مسجلة في هذه الفترة.'))}${section('managementOverdue','ما يحتاج متابعة الآن',m.overdue.map(t=>link(t,'استحقاق: '+t.due_date)).join('')||empty('لا توجد مهام تنفيذ متأخرة حاليًا.'))}${section('managementPending','إنجازات تنتظر قرار الاعتماد',m.pending.map(t=>link(t,'بانتظار الاعتماد')).join('')||empty('لا توجد إنجازات بانتظار الاعتماد.'))}${section('managementBlockers','عوائق التنفيذ المسجلة',m.blockers.map(({task:t,followup:f})=>link(t,f.reason||'عائق دون تفاصيل')).join('')||empty('لا توجد عوائق مسجلة.'))}${section('managementConcentrations','تجمع الاستحقاقات خلال الأسبوع القادم',`<p class="management-scope">٣ مهام أو أكثر للشخص نفسه في اليوم نفسه؛ راجع المواعيد بحسب جهد العمل الفعلي.</p>${concentration||empty('لا توجد تجمعات استحقاق بهذا المعيار.')}`)}${section('managementGovernance','مراجعات وإقرارات الأوصاف والسياسات',m.governance.map(t=>link(t,'موعد المتابعة: '+(t.due_date||'غير محدد'))).join('')||empty('لا توجد مراجعات أو إقرارات مفتوحة في هذا النطاق.'))}${section('managementProjects','المشاريع المفتوحة',projectRows||empty('لا توجد مشاريع مفتوحة في هذا النطاق.'))}</div>`;
}
