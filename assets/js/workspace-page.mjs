import {workspaceModel,renderWorkspace,requestModel,renderRequests} from './workspace-core.mjs?v=2.5.49';
async function allRows(makeQuery){let rows=[];for(let from=0;;from+=500){const {data,error}=await makeQuery().range(from,from+499);if(error)throw error;rows.push(...(data||[]));if((data||[]).length<500)return rows;}}
export async function mountWorkspace(sb,profile){
 const status=document.getElementById('spaceSync');let pending=false;
 async function refresh(){
  if(pending||document.hidden)return;pending=true;status.textContent='جاري تحديث مساحتك…';
  const sections=['tasks','decisions','projects','updates','requests'];
  try{
   const [tasks,projects,members,people,notifications,reschedules,changes,policies,versions,proposals]=await Promise.allSettled([
    allRows(()=>sb.from('tasks').select('id,title,status,assignee_id,creator_id,approval_commissioner_id,task_type,start_date,due_date,project_id,progress,project_weight,deleted_at,legacy_metadata').is('deleted_at',null).order('id')),
    allRows(()=>sb.from('projects').select('id,title,status,manager_id,sponsor_id,created_by,due_date,deleted_at').is('deleted_at',null).order('id')),
    allRows(()=>sb.from('project_members').select('project_id,user_id').eq('user_id',profile.id).order('project_id')),
    profile.role==='manager'?allRows(()=>sb.from('profiles').select('id').eq('manager_id',profile.id).order('id')):Promise.resolve([]),
    (async()=>{const {data,error}=await sb.from('notifications').select('id,title,message,task_id,project_id,improvement_id,type,read_at').eq('recipient_id',profile.id).is('read_at',null).order('created_at',{ascending:false}).limit(5);if(error)throw error;return data||[];})(),
    allRows(()=>sb.from('task_reschedule_requests').select('*').order('id')),
    allRows(()=>sb.from('employee_job_change_requests').select('*').order('id')),
    allRows(()=>sb.from('policies').select('id,title,preparer_id,reviewer_id,approver_id,ratifier_id').order('id')),
    allRows(()=>sb.from('policy_versions').select('id,policy_id,status,version_number,effective_date,current_task_id,created_by,updated_at').order('id')),
    allRows(()=>sb.from('improvement_proposals').select('id,title,requester_id,status,decision_note,task_id,project_id,updated_at').order('id'))
   ]);
   const value=r=>r.status==='fulfilled'?r.value:[];
   const model=workspaceModel({profile,tasks:value(tasks),projects:value(projects),members:value(members),directIds:value(people).map(p=>p.id)}),html=renderWorkspace(model,value(notifications));
   const requests=requestModel({profile,tasks:value(tasks),reschedules:value(reschedules),changes:value(changes),policies:value(policies),versions:value(versions),proposals:value(proposals)});
   model.decisions=model.decisions.filter(t=>!requests.replaced.has(t.id));
   html.decisions=renderRequests(requests.actions,'')+(model.decisions.length?renderWorkspace(model).decisions:'');
   if(!requests.actions.length&&!model.decisions.length)html.decisions=renderRequests([],'لا توجد إجراءات مطلوبة منك حاليًا.');
   html.requests=renderRequests(requests.tracking,'لا توجد طلبات تتابعها حاليًا.');
   const requestFailure=[reschedules,changes,policies,versions,proposals].some(r=>r.status==='rejected');
   const failed={requests:requestFailure||tasks.status==='rejected',tasks:tasks.status==='rejected',decisions:[tasks,projects,people,reschedules,changes,policies,versions,proposals].some(r=>r.status==='rejected'),projects:[tasks,projects,members].some(r=>r.status==='rejected'),updates:notifications.status==='rejected'};
   for(const key of sections){document.getElementById('space'+key).innerHTML=failed[key]?'<p class="space-empty" role="status">تعذر تحميل هذا القسم. سنعيد المحاولة عند عودة الاتصال.</p>':html[key];document.getElementById('spaceCount'+key).textContent=failed[key]?'—':String(key==='updates'?value(notifications).length:key==='tasks'?model.due.length:key==='requests'?requests.tracking.length:key==='decisions'?model.decisions.length+requests.actions.length:model[key].length);}
   document.getElementById('spaceFocus').textContent=failed.tasks?'متابعة أعمالك في مكان واحد':model.overdue?`لديك ${model.overdue} مهام متأخرة؛ ابدأ بالأقدم.`:model.due.length?`لديك ${model.due.length} مهام مستحقة اليوم.`:(model.decisions.length+requests.actions.length?`لديك ${model.decisions.length+requests.actions.length} إجراءات تنتظر منك مراجعة أو قرارًا.`:'يومك واضح؛ لا توجد مهام مستحقة أو إجراءات مطلوبة الآن.');
   document.querySelectorAll('[data-space-notification]').forEach(b=>b.onclick=async()=>{const row=value(notifications).find(n=>n.id===b.dataset.spaceNotification);await window.atwarOpenNotificationRecord?.(sb,row,'../',message=>{status.textContent=message;});});
   status.textContent=Object.values(failed).some(Boolean)?'بعض الأقسام غير متاحة؛ نعيد المحاولة تلقائيًا.':'محدّث الآن · تحديث تلقائي';window.lucide?.createIcons();
  }catch{status.textContent='تعذر التحديث؛ نعيد المحاولة عند استقرار الاتصال.';}
  finally{pending=false;}
 }
 await refresh();let timer=setInterval(refresh,60000);
 addEventListener('online',refresh);document.addEventListener('visibilitychange',()=>{if(!document.hidden)void refresh();});
 addEventListener('pagehide',()=>{clearInterval(timer);});addEventListener('pageshow',e=>{if(e.persisted){clearInterval(timer);timer=setInterval(refresh,60000);void refresh();}});
}
