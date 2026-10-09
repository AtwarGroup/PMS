import {managementBriefing,renderManagementBriefing} from './management-briefing.mjs?v=1.0.0';
import {workspaceBriefing,renderBriefing} from './workspace-briefing.mjs?v=1.0.0';
import {workspaceModel,renderWorkspace,requestModel,renderRequests,actionInbox,renderActionInbox,filterActionInbox} from './workspace-core.mjs?v=2.5.59';
async function allRows(makeQuery){let rows=[];for(let from=0;;from+=500){const {data,error}=await makeQuery().range(from,from+499);if(error)throw error;rows.push(...(data||[]));if((data||[]).length<500)return rows;}}
export async function mountWorkspace(sb,profile){
 const status=document.getElementById('spaceSync');let pending=false,queued=false,suspended=false,lastInbox=[],inboxDay,inboxFailed=true;
 function renderInbox(){
  if(inboxFailed)return;
  const rows=filterActionInbox(lastInbox,{kind:document.getElementById('spaceActionKind')?.value||'all',priority:document.getElementById('spaceActionPriority')?.value||'all'},inboxDay);
  document.getElementById('spacedecisions').innerHTML=renderActionInbox(rows,inboxDay,lastInbox.length?'لا توجد إجراءات مطابقة للفلاتر المحددة.':'لا توجد إجراءات مطلوبة منك حاليًا.');
  const result=document.getElementById('spaceActionResult');if(result)result.textContent=`عرض ${rows.length} من ${lastInbox.length}`;
  window.lucide?.createIcons();
 }
 for(const id of ['spaceActionKind','spaceActionPriority'])document.getElementById(id)?.addEventListener?.('change',renderInbox);
 async function refresh(){
  if(suspended||document.hidden)return;if(pending){queued=true;return;}pending=true;queued=false;status.textContent='جاري تحديث مساحتك…';
  const sections=['tasks','decisions','projects','updates','requests'];
  try{
   const [tasks,projects,members,people,notifications,reschedules,changes,policies,versions,proposals,followups]=await Promise.allSettled([
    allRows(()=>sb.from('tasks').select('id,title,status,assignee_id,creator_id,approval_commissioner_id,task_type,start_date,due_date,project_id,progress,project_weight,deleted_at,legacy_metadata,submitted_at,created_at,completed_at,actual_end_date,priority,creator_name_snapshot,assignee_name_snapshot').is('deleted_at',null).order('id')),
    allRows(()=>sb.from('projects').select('id,title,status,manager_id,sponsor_id,created_by,due_date,deleted_at').is('deleted_at',null).order('id')),
    allRows(()=>sb.from('project_members').select('project_id,user_id').eq('user_id',profile.id).order('project_id')),
    profile.role==='manager'?allRows(()=>sb.from('profiles').select('id,full_name').eq('manager_id',profile.id).order('id')):Promise.resolve([]),
    (async()=>{const {data,error}=await sb.from('notifications').select('id,title,message,task_id,project_id,improvement_id,type,read_at').eq('recipient_id',profile.id).is('read_at',null).order('created_at',{ascending:false}).limit(5);if(error)throw error;return data||[];})(),
    allRows(()=>sb.from('task_reschedule_requests').select('*').order('id')),
    allRows(()=>sb.from('employee_job_change_requests').select('*').order('id')),
    allRows(()=>sb.from('policies').select('id,title,preparer_id,reviewer_id,approver_id,ratifier_id').order('id')),
    allRows(()=>sb.from('policy_versions').select('id,policy_id,status,version_number,effective_date,current_task_id,created_by,updated_at').order('id')),
    allRows(()=>sb.from('improvement_proposals').select('id,title,requester_id,status,decision_note,task_id,project_id,updated_at,created_at,priority').order('id')),
    allRows(()=>sb.from('task_followup_details').select('task_id,blocked,reason,next_step,owner_role,follow_date').order('task_id'))
   ]);
   const value=r=>r.status==='fulfilled'?r.value:[];
   const model=workspaceModel({profile,tasks:value(tasks),projects:value(projects),members:value(members),directIds:value(people).map(p=>p.id)}),html=renderWorkspace(model,value(notifications));
   const requests=requestModel({profile,tasks:value(tasks),reschedules:value(reschedules),changes:value(changes),policies:value(policies),versions:value(versions),proposals:value(proposals)});
   const inbox=actionInbox(requests,model.decisions,model.day);
   model.decisions=model.decisions.filter(t=>!requests.replaced.has(t.id));
   html.decisions=renderActionInbox(inbox,model.day);
   html.requests=renderRequests(requests.tracking,'لا توجد طلبات تتابعها حاليًا.');
   const requestFailure=[reschedules,changes,policies,versions,proposals].some(r=>r.status==='rejected');
   const failed={requests:requestFailure||tasks.status==='rejected',tasks:tasks.status==='rejected',decisions:[tasks,projects,people,reschedules,changes,policies,versions,proposals].some(r=>r.status==='rejected'),projects:[tasks,projects,members].some(r=>r.status==='rejected'),updates:notifications.status==='rejected'};
   for(const key of sections){document.getElementById('space'+key).innerHTML=failed[key]?'<p class="space-empty" role="status">تعذر تحميل هذا القسم. سنعيد المحاولة عند عودة الاتصال.</p>':html[key];document.getElementById('spaceCount'+key).textContent=failed[key]?'—':String(key==='updates'?value(notifications).length:key==='tasks'?model.due.length:key==='requests'?requests.tracking.length:key==='decisions'?model.decisions.length+requests.actions.length:model[key].length);}
   lastInbox=inbox;inboxDay=model.day;inboxFailed=failed.decisions;if(inboxFailed){const result=document.getElementById('spaceActionResult');if(result)result.textContent='البيانات غير متاحة حاليًا';}else renderInbox();
   const brief=workspaceBriefing({profile,tasks:value(tasks),followups:value(followups),requests,projects:value(projects),directIds:value(people).map(p=>p.id),day:model.day}),briefHtml=renderBriefing(brief,{today:model.due.length,decisions:inbox.length,projects:model.projects.length});
   const briefFailures={summary:failed.tasks||failed.decisions||failed.projects||failed.requests||followups.status==='rejected',upcoming:failed.tasks,waiting:failed.requests||projects.status==='rejected',blockers:[tasks,projects,people,followups].some(r=>r.status==='rejected')};
   const setBrief=(id,html)=>{const host=document.getElementById(id);if(host)host.innerHTML=html;};
   const missing='<p class="space-empty" role="status">تعذر تحميل هذا القسم. سنعيد المحاولة تلقائيًا.</p>';
   setBrief('spaceSummary',briefFailures.summary?missing:briefHtml.summary);
   setBrief('spaceupcoming',briefFailures.upcoming?missing:briefHtml.upcoming);
   setBrief('spacewaiting',briefFailures.waiting?missing:renderActionInbox(brief.waiting,model.day,'لا توجد طلبات أو مهام تنتظر إجراءً من الآخرين.'));
   setBrief('spaceblockers',briefFailures.blockers?missing:briefHtml.blockers);
   for(const key of ['upcoming','waiting','blockers']){const count=document.getElementById('spaceCount'+key);if(count)count.textContent=briefFailures[key]?'—':String(brief[key].length);}
   const managementHost=document.getElementById('spaceManagement');
   if(managementHost){managementHost.hidden=!['admin','manager'].includes(profile.role);if(!managementHost.hidden){const unavailable=failed.decisions||failed.projects||followups.status==='rejected';const body=document.getElementById('spaceManagementBody');if(body)body.innerHTML=unavailable?missing:renderManagementBriefing(managementBriefing({profile,tasks:value(tasks),projects:value(projects),directIds:value(people).map(p=>p.id),followups:value(followups),inbox,day:model.day}));}}
   document.getElementById('spaceFocus').textContent=failed.tasks?'متابعة أعمالك في مكان واحد':model.overdue?`لديك ${model.overdue} مهام متأخرة؛ ابدأ بالأقدم.`:model.due.length?`لديك ${model.due.length} مهام مستحقة اليوم.`:(model.decisions.length+requests.actions.length?`لديك ${model.decisions.length+requests.actions.length} إجراءات تنتظر منك مراجعة أو قرارًا.`:'يومك واضح؛ لا توجد مهام مستحقة أو إجراءات مطلوبة الآن.');
   document.querySelectorAll('[data-space-notification]').forEach(b=>b.onclick=async()=>{const row=value(notifications).find(n=>n.id===b.dataset.spaceNotification);await window.atwarOpenNotificationRecord?.(sb,row,'../',message=>{status.textContent=message;});});
   status.textContent=(Object.values(failed).some(Boolean)||Object.values(briefFailures).some(Boolean))?'بعض الأقسام غير متاحة؛ نعيد المحاولة تلقائيًا.':'محدّث الآن · تحديث تلقائي';window.lucide?.createIcons();
  }catch{status.textContent='تعذر التحديث؛ نعيد المحاولة عند استقرار الاتصال.';}
  finally{pending=false;if(queued&&!suspended&&!document.hidden){queued=false;void refresh();}}
 }
 await refresh();let timer=setInterval(refresh,60000);
 addEventListener('online',refresh);document.addEventListener('visibilitychange',()=>{if(!document.hidden)void refresh();});
 addEventListener('pagehide',()=>{suspended=true;queued=false;clearInterval(timer);});addEventListener('pageshow',e=>{if(e.persisted){suspended=false;clearInterval(timer);timer=setInterval(refresh,60000);void refresh();}});
}
