import {escape,taskLink,taskNextStep,riyadhDay} from './workspace-core.mjs?v=2.5.59';
const active=t=>!t.deleted_at&&['قيد الانتظار','قيد التنفيذ'].includes(t.status);
export function workspaceBriefing({profile,tasks=[],followups=[],requests={tracking:[]},projects=[],directIds=[],day=riyadhDay()}){
 const horizon=new Date(day+'T00:00:00Z');horizon.setUTCDate(horizon.getUTCDate()+7);const end=horizon.toISOString().slice(0,10);
 const ordinary=tasks.filter(t=>!t.deleted_at&&t.task_type!=='job_workflow');
 const upcoming=ordinary.filter(t=>active(t)&&t.assignee_id===profile.id&&((t.due_date>day&&t.due_date<=end)||(t.start_date>day&&t.start_date<=end))).map(t=>({...t,upcomingDate:t.due_date>day&&t.due_date<=end?t.due_date:t.start_date})).sort((a,b)=>a.upcomingDate.localeCompare(b.upcomingDate)||a.id.localeCompare(b.id));
 const waiting=ordinary.filter(t=>t.assignee_id===profile.id&&t.status==='بانتظار الاعتماد').map(t=>({id:'waiting:'+t.id,title:t.title,href:taskLink(t),state:'بانتظار الاعتماد',next:taskNextStep(t,null,{profile,projects}),date:t.submitted_at,ageLabel:'مدة انتظار القرار'}));
 waiting.push(...requests.tracking.filter(r=>r.pending&&!r.action));
 waiting.sort((a,b)=>{const stamp=x=>Number.isFinite(Date.parse(x.date))?Date.parse(x.date):Infinity;return stamp(a)-stamp(b)||a.id.localeCompare(b.id);});
 const byTask=new Map(ordinary.filter(active).map(t=>[t.id,t]));
 const relevant=t=>t.assignee_id===profile.id||t.creator_id===profile.id||directIds.includes(t.assignee_id)||projects.some(p=>p.id===t.project_id&&(p.manager_id===profile.id||p.sponsor_id===profile.id));
 const blockers=followups.filter(f=>f.blocked&&byTask.has(f.task_id)&&relevant(byTask.get(f.task_id))).map(f=>({task:byTask.get(f.task_id),followup:f})).sort((a,b)=>(a.followup.follow_date||'9999').localeCompare(b.followup.follow_date||'9999')||a.task.id.localeCompare(b.task.id));
 return {upcoming,waiting,blockers,day,end};
}
export function renderBriefing(model,{today=0,decisions=0,projects=0}={}){
 const empty=text=>'<p class="space-empty">'+escape(text)+'</p>';
 const upcoming=model.upcoming.map(t=>`<a class="space-row" href="${escape(taskLink(t))}"><span class="space-row-copy"><strong>${escape(t.title)}</strong><small>موعد قريب: ${escape(t.upcomingDate)}</small><small>الخطوة التالية: ${escape(taskNextStep(t))}</small></span><span class="space-pill">فتح</span></a>`).join('')||empty('لا توجد مهام شخصية تبدأ أو تستحق خلال الأيام السبعة القادمة.');
 const blockers=model.blockers.map(({task:t,followup:f})=>`<a class="space-row" href="${escape(taskLink(t))}"><span class="space-row-copy"><strong>${escape(t.title)}</strong><small>سبب التعثر: ${escape(f.reason||'لم يُحدد')}</small><small>الخطوة التالية: ${escape(taskNextStep(t,f))}</small><small>موعد المتابعة: ${escape(f.follow_date||'غير محدد')}</small></span><span class="space-pill ${f.follow_date&&f.follow_date<model.day?'late':''}">متابعة</span></a>`).join('')||empty('لا توجد عوائق مسجلة في المهام التي تتابعها.');
 const items=[['مهامي اليوم',today,'spaceTodayPanel'],['المطلوب مني',decisions,'spaceDecisionPanel'],['القادم خلال أسبوع',model.upcoming.length,'spaceUpcomingPanel'],['بانتظار الآخرين',model.waiting.length,'spaceWaitingPanel'],['عوائق التنفيذ',model.blockers.length,'spaceBlockerPanel'],['مشاريعي',projects,'spaceProjectsPanel']];
 const summary=items.map(([label,count,target])=>`<a href="#${target}" class="space-summary-item"><strong>${count}</strong><span>${label}</span></a>`).join('');
 return {summary,upcoming,blockers};
}
