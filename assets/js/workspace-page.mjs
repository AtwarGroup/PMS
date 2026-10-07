import {workspaceModel,renderWorkspace} from './workspace-core.mjs?v=2.5.42';
async function allRows(makeQuery){let rows=[];for(let from=0;;from+=500){const {data,error}=await makeQuery().range(from,from+499);if(error)throw error;rows.push(...(data||[]));if((data||[]).length<500)return rows;}}
export async function mountWorkspace(sb,profile){
 const status=document.getElementById('spaceSync');let pending=false;
 async function refresh(){
  if(pending||document.hidden)return;pending=true;status.textContent='جاري تحديث مساحتك…';
  const sections=['tasks','decisions','projects','updates'];
  try{
   const [tasks,projects,members,people,notifications]=await Promise.allSettled([
    allRows(()=>sb.from('tasks').select('id,title,status,assignee_id,creator_id,approval_commissioner_id,task_type,start_date,due_date,project_id,progress,project_weight,deleted_at').is('deleted_at',null).order('id')),
    allRows(()=>sb.from('projects').select('id,title,status,manager_id,sponsor_id,created_by,due_date,deleted_at').is('deleted_at',null).order('id')),
    allRows(()=>sb.from('project_members').select('project_id,user_id').eq('user_id',profile.id).order('project_id')),
    profile.role==='manager'?allRows(()=>sb.from('profiles').select('id').eq('manager_id',profile.id).order('id')):Promise.resolve([]),
    (async()=>{const {data,error}=await sb.from('notifications').select('id,title,message,task_id,project_id,type,read_at').eq('recipient_id',profile.id).is('read_at',null).order('created_at',{ascending:false}).limit(5);if(error)throw error;return data||[];})()
   ]);
   const value=r=>r.status==='fulfilled'?r.value:[];
   const model=workspaceModel({profile,tasks:value(tasks),projects:value(projects),members:value(members),directIds:value(people).map(p=>p.id)}),html=renderWorkspace(model,value(notifications));
   const failed={tasks:tasks.status==='rejected',decisions:[tasks,projects,people].some(r=>r.status==='rejected'),projects:[tasks,projects,members].some(r=>r.status==='rejected'),updates:notifications.status==='rejected'};
   for(const key of sections){document.getElementById('space'+key).innerHTML=failed[key]?'<p class="space-empty" role="status">تعذر تحميل هذا القسم. سنعيد المحاولة عند عودة الاتصال.</p>':html[key];document.getElementById('spaceCount'+key).textContent=failed[key]?'—':String(key==='updates'?value(notifications).length:key==='tasks'?model.due.length:model[key].length);}
   document.getElementById('spaceFocus').textContent=failed.tasks?'متابعة أعمالك في مكان واحد':model.overdue?`لديك ${model.overdue} مهام متأخرة؛ ابدأ بالأقدم.`:model.due.length?`لديك ${model.due.length} مهام مستحقة اليوم.`:'يومك واضح؛ لا توجد مهام مستحقة اليوم.';
   document.querySelectorAll('[data-space-notification]').forEach(b=>b.onclick=async()=>{const row=value(notifications).find(n=>n.id===b.dataset.spaceNotification);await window.atwarOpenNotificationRecord?.(sb,row,'../',message=>{status.textContent=message;});});
   status.textContent=Object.values(failed).some(Boolean)?'بعض الأقسام غير متاحة؛ نعيد المحاولة تلقائيًا.':'محدّث الآن · تحديث تلقائي';window.lucide?.createIcons();
  }catch{status.textContent='تعذر التحديث؛ نعيد المحاولة عند استقرار الاتصال.';}
  finally{pending=false;}
 }
 await refresh();let timer=setInterval(refresh,60000);
 addEventListener('online',refresh);document.addEventListener('visibilitychange',()=>{if(!document.hidden)void refresh();});
 addEventListener('pagehide',()=>{clearInterval(timer);});addEventListener('pageshow',e=>{if(e.persisted){clearInterval(timer);timer=setInterval(refresh,60000);void refresh();}});
}
