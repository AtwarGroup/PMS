import {proposalStates,proposalNext,proposalNeedsAction,proposalLink} from './improvements-core.mjs?v=1.0.0';
import {canApproveRelationalTask} from './tasks-core.mjs?v=1.9.8';
import {weightedProgress} from './projects-core.mjs?v=2.5.55';
export const escape=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
export const riyadhDay=(date=new Date())=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Riyadh',year:'numeric',month:'2-digit',day:'2-digit'}).format(date);
const ordinaryTaskLink=t=>`../tasks/index.html?task=${encodeURIComponent(t.id)}&owner=${encodeURIComponent(t.assignee_id||'')}${t.status==='مكتملة'?'&scope=COMPLETED':''}`;
export function taskLink(t){
 const w=t.legacy_metadata?.job_workflow;
 if(w?.policy_id)return `../policies/index.html?id=${encodeURIComponent(w.policy_id)}&version=${encodeURIComponent(w.policy_version_id||'')}`;
 if(w?.request_id)return `../job-library/employee-changes.html?id=${encodeURIComponent(w.request_id)}`;
 if(w?.phase==='EMPLOYEE_ACK')return '../profile/index.html?view=job';
 if(w?.job_id)return `../job-library/review.html?id=${encodeURIComponent(w.job_id)}`;
 return ordinaryTaskLink(t);
}
export function requestModel({profile,tasks=[],reschedules=[],changes=[],policies=[],versions=[],proposals=[]}){
 const byTask=new Map(tasks.filter(t=>!t.deleted_at).map(t=>[t.id,t]));const actions=[],tracking=[],replaced=new Set();
 const add=(id,title,href,state,next,note,action=false,date='',taskIds=[],priority='normal')=>{const row={id,title,href,state,next,note,action,date,priority};if(action){actions.push(row);taskIds.filter(Boolean).forEach(x=>replaced.add(x));}else tracking.push(row);return row;};
 for(const r of reschedules){const t=byTask.get(r.task_id);if(!t)continue;const pending=r.status==='PENDING'&&['قيد الانتظار','قيد التنفيذ'].includes(t.status);const action=pending&&(r.task_creator_id===profile.id||profile.role==='admin');if(!action&&r.requester_id!==profile.id)continue;
 add('schedule:'+r.id,'إعادة جدولة: '+t.title,ordinaryTaskLink(t),({PENDING:'بانتظار القرار',APPROVED:'تمت الموافقة',REJECTED:'مرفوض',CANCELLED:'ملغى'})[r.status]||r.status,pending?'منشئ المهمة أو مسؤول النظام':'انتهى الطلب',r.decision_note||`الموعد المقترح: ${r.proposed_due_date||'—'}`,action,r.created_at);}
 for(const r of changes){const action=(r.status==='MANAGER_REVIEW'&&r.manager_id===profile.id)||(['ADMIN_REVIEW','APPLIED'].includes(r.status)&&profile.role==='admin');if(!action&&r.requester_id!==profile.id)continue;
 const state=({MANAGER_REVIEW:'مراجعة المدير',ADMIN_REVIEW:'اعتماد مسؤول النظام',APPLIED:'معتمد في المسودة — بانتظار النشر',PUBLISHED:'تم النشر',REJECTED:'مرفوض',STALE:'يحتاج مراجعة جديدة'})[r.status]||r.status;
 add('change:'+r.id,'تعديل الوصف: '+r.job_title,`../job-library/employee-changes.html?id=${encodeURIComponent(r.id)}`,state,({MANAGER_REVIEW:'المدير المباشر',ADMIN_REVIEW:'مسؤول النظام',APPLIED:'مسؤول النظام لاستكمال النشر',STALE:'مقدم الطلب لمراجعة التعديل'})[r.status]||'انتهى الطلب',r.admin_note||r.manager_note||r.reason,action,r.created_at,[r.manager_task_id,r.admin_task_id]);}
 const stageOwners={PREPARATION:'preparer_id',REVIEW:'reviewer_id',APPROVAL:'approver_id',RATIFICATION:'ratifier_id'},stageNames={PREPARATION:'إعداد',REVIEW:'مراجعة',APPROVAL:'موافقة',RATIFICATION:'اعتماد',APPROVED:'معتمدة'};
 for(const v of versions){const p=policies.find(p=>p.id===v.policy_id);if(!p)continue;const owner=p[stageOwners[v.status]],action=!!owner&&owner===profile.id;const involved=[p.preparer_id,p.reviewer_id,p.approver_id,p.ratifier_id,v.created_by].includes(profile.id);if(!action&&!involved&&profile.role!=='admin')continue;
 const policyRow=add('policy:'+v.id,p.title+' · إصدار '+v.version_number,`../policies/index.html?id=${encodeURIComponent(p.id)}&version=${encodeURIComponent(v.id)}`,stageNames[v.status]||v.status,v.status==='APPROVED'?'اكتمل الاعتماد':owner?'صاحب صلاحية '+stageNames[v.status]:'مسؤول النظام لتحديد صاحب الصلاحية',v.effective_date?'تاريخ السريان: '+v.effective_date:'',action,v.updated_at,[v.current_task_id]);policyRow.ageLabel='منذ آخر تحديث';policyRow.kind='review';}
 for(const p of proposals){const action=proposalNeedsAction(p,profile);if(!action&&p.requester_id!==profile.id&&profile.role!=='admin')continue;add('improvement:'+p.id,'مقترح: '+p.title,proposalLink(p.id),proposalStates[p.status]+(p.task_id||p.project_id?' · مرتبط بالتنفيذ':''),proposalNext(p),p.decision_note,action,p.created_at||p.updated_at,[],({HIGH:'urgent',MEDIUM:'important',LOW:'normal'})[p.priority]);}
 tracking.sort((a,b)=>(b.date||'').localeCompare(a.date||''));return {actions,tracking,replaced};
}
export function renderRequests(rows,emptyText){return rows.length?rows.map(r=>`<a class="space-row" href="${escape(r.href)}"><span class="space-row-icon"><i data-lucide="${r.action?'stamp':'git-pull-request'}"></i></span><span class="space-row-copy"><strong>${escape(r.title)}</strong><small>${escape(r.state)} · ${escape(r.next)}</small>${r.note?`<small>${escape(r.note)}</small>`:''}</span><span class="space-pill ${r.late?'late':''}">${r.late?'مراجعة متأخرة':r.action?'اتخاذ إجراء':'التفاصيل'}</span></a>`).join(''):`<p class="space-empty">${escape(emptyText)}</p>`;}
export function actionInbox(requests,decisions,day=riyadhDay()){
 const rows=[...requests.actions.map(row=>({...row,kind:row.kind||'request'})),...decisions.filter(t=>!requests.replaced.has(t.id)).map(t=>({id:'task:'+t.id,kind:t.task_type==='job_workflow'?'review':'approval',title:t.title,href:taskLink(t),state:t.status,next:t.task_type==='job_workflow'?'مراجعة المستند المرتبط':'مراجعة إنجاز المهمة',action:true,date:t.task_type==='job_workflow'?t.created_at:t.submitted_at,ageLabel:t.task_type==='job_workflow'?'عمر المراجعة':'مدة انتظار الاعتماد',deadline:t.task_type==='job_workflow'?t.due_date:null,priority:t.priority}))];
 const priority={urgent:0,important:1,normal:2};
 const overdue=r=>r.deadline&&r.deadline<day?0:1;
 const stamp=r=>Number.isFinite(Date.parse(r.date))?Date.parse(r.date):Infinity;
 return rows.sort((a,b)=>overdue(a)-overdue(b)||(priority[a.priority]??2)-(priority[b.priority]??2)||stamp(a)-stamp(b)||a.id.localeCompare(b.id));
}
export function filterActionInbox(rows,{kind='all',priority='all'}={},day=riyadhDay()){
 const kinds=['all','request','review','approval','late'],priorities=['all','urgent','important','normal'];
 if(!kinds.includes(kind))kind='all';if(!priorities.includes(priority))priority='all';
 return rows.filter(row=>(kind==='all'||(kind==='late'?!!row.deadline&&row.deadline<day:row.kind===kind))&&(priority==='all'||(row.priority||'normal')===priority));
}
export function renderActionInbox(rows,day=riyadhDay(),emptyText='لا توجد إجراءات مطلوبة منك حاليًا.'){
 const dateDay=value=>{if(!value)return null;const date=new Date(value);return Number.isFinite(date.getTime())?riyadhDay(date):null;};
 const enriched=rows.map(row=>{const date=dateDay(row.date),age=date?Math.max(0,Math.floor((Date.parse(day+'T00:00:00Z')-Date.parse(date+'T00:00:00Z'))/86400000)):null;const ageText=age===null?'':`${row.ageLabel||'عمر الطلب'}: ${age===0?'اليوم':age+' يوم'}`;return {...row,note:[row.note,ageText,row.deadline?'موعد المراجعة: '+row.deadline:''].filter(Boolean).join(' · '),late:!!row.deadline&&row.deadline<day};});
 return renderRequests(enriched,emptyText);
}
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
 return {tasks:model.due.length?model.due.slice(0,6).map(t=>task(t)).join(''):empty('لا توجد مهام مستحقة اليوم. يمكنك الاطلاع على بقية مهامك.'),decisions:model.decisions.length?model.decisions.map(t=>task(t,true)).join(''):empty('لا توجد قرارات أو مراجعات مطلوبة منك حاليًا.'),projects:model.projects.length?model.projects.slice(0,4).map(p=>`<a class="space-project" href="../projects/index.html?id=${encodeURIComponent(p.id)}"><div><strong>${escape(p.title)}</strong><span>${p.progress}%</span></div><progress max="100" value="${p.progress}" aria-label="تقدم ${escape(p.title)}"></progress><small>موعد التسليم: ${escape(p.due_date||'غير محدد')}</small></a>`).join(''):empty('لا توجد مشاريع نشطة تشارك فيها حاليًا.'),updates:notifications.length?notifications.slice(0,5).map(n=>`<button type="button" class="space-row space-update" data-space-notification="${escape(n.id)}"><span class="space-row-icon"><i data-lucide="bell"></i></span><span class="space-row-copy"><strong>${escape(n.title||'مستجد جديد')}</strong><small>${escape(n.message||'افتح للاطلاع على التفاصيل')}</small></span></button>`).join(''):empty('أنت مطّلع على جميع المستجدات الحالية.')};
}
