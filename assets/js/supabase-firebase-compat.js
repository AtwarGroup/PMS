// ATWAR ONE compatibility bridge: preserves the full legacy UI contract while routing data/auth to Supabase.
// Browser-safe only: uses the publishable key through atwarGetSupabase(). No service-role secret is present here.
const sb = await window.atwarGetSupabase();

async function dispatchQueuedTaskEmails(){
  try{
    const {error}=await sb.functions.invoke('send-task-email-notifications',{body:{}});
    if(error)console.warn('Task email delivery is queued for retry.',error);
  }catch(error){console.warn('Task email delivery is queued for retry.',error)}
}

const _apps=[{name:'ATWAR_SUPABASE_COMPAT'}];
const _aliases=new Map();
function publicKey(real){for(const [alias,id] of _aliases)if(String(id)===String(real))return alias;return String(real)}
const _listeners=new Set();
let _authUser=null;

export function initializeApp(){return _apps[0]}
export function getApps(){return _apps}
export function getDatabase(){return {kind:'supabase-db'}}
export function getAuth(){return {kind:'supabase-auth',get currentUser(){return _authUser},signOut:()=>signOut()}}
export function serverTimestamp(){return Date.now()}

function pathOf(r){return String(r?.path??r??'').replace(/^\/+|\/+$/g,'')}
export function ref(_db,path=''){return {path:pathOf(path),key:pathOf(path).split('/').filter(Boolean).at(-1)||null}}
export function query(r,...mods){return {...r,mods}}
export function orderByChild(field){return {type:'orderByChild',field}}
export function equalTo(value){return {type:'equalTo',value}}
export function limitToLast(value){return {type:'limitToLast',value:Number(value)||0}}
export function push(r){const key=globalThis.crypto?.randomUUID?.()||`tmp_${Date.now()}_${Math.random().toString(36).slice(2)}`;return {path:[pathOf(r),key].filter(Boolean).join('/'),key}}

function ms(v){if(!v)return 0;const n=typeof v==='number'?v:new Date(v).getTime();return Number.isFinite(n)?n:0}
function iso(v){if(v===null||v===''||v===undefined)return null;if(typeof v==='number')return new Date(v).toISOString();const d=new Date(v);return Number.isNaN(d.getTime())?null:d.toISOString()}
function dateOnly(v){if(v===null||v===undefined||v==='')return null;return String(v).slice(0,10)}

function profileLegacy(p){
  if(!p)return null;
  return {
    uid:p.id,email:p.email||'',name:p.full_name||p.email||'',fullName:p.full_name||'',
    title:p.job_title||'',jobTitle:p.job_title||'',department:p.department||'',
    role:p.role||'employee',managerUid:p.manager_id||'',managerId:p.manager_id||'',
    managerChain:p.manager_chain||{},permissions:Array.isArray(p.permissions)?p.permissions:[],
    active:p.active!==false,status:p.status||'active',firebase_uid:p.firebase_uid||'',
    employeeCode:p.employee_code||'',joinDate:p.join_date||'',workLocation:p.work_location||'',employmentType:p.employment_type||'',
    jobDescription:p.job_description||null,kpis:p.kpis||null
  };
}

async function loadChildren(taskIds){
  const ids=[...new Set((taskIds||[]).filter(Boolean))];
  if(!ids.length)return {activities:new Map(),subtasks:new Map(),attachments:new Map()};
  const [ar,sr,fr]=await Promise.all([
    sb.from('task_activity').select('*').in('task_id',ids).order('sequence_no',{ascending:true}),
    sb.from('subtasks').select('*').in('task_id',ids).order('position',{ascending:true}),
    sb.from('task_attachments').select('id,task_id,uploader_id,file_name,storage_path,size_bytes,created_at').in('task_id',ids).order('created_at',{ascending:false})
  ]);
  const activities=new Map(),subtasks=new Map(),attachments=new Map();
  for(const a of ar.data||[]){const x={type:a.event_type||'activity',detail:a.detail||'',userUid:a.actor_id||'',userName:a.actor_name_snapshot||'',createdAt:ms(a.created_at)};(activities.get(a.task_id)||activities.set(a.task_id,[]).get(a.task_id)).push(x)}
  for(const s of sr.data||[]){const x={id:s.id,title:s.title||'',done:!!s.done,createdAt:ms(s.created_at),completedAt:ms(s.completed_at)||null};(subtasks.get(s.task_id)||subtasks.set(s.task_id,[]).get(s.task_id)).push(x)}
  for(const f of fr.data||[]){const x={id:f.id,uploaderId:f.uploader_id||'',fileName:f.file_name||'',storagePath:f.storage_path||'',sizeBytes:Number(f.size_bytes||0),createdAt:ms(f.created_at)};(attachments.get(f.task_id)||attachments.set(f.task_id,[]).get(f.task_id)).push(x)}
  return {activities,subtasks,attachments};
}

function taskLegacy(t,children){
  if(!t)return null;
  return {
    id:t.legacy_id||t.firebase_task_key||t.id,title:t.title||'',desc:t.description||'',type:t.task_type||'',
    status:t.status||'قيد الانتظار',priority:t.priority||'normal',progress:Number(t.progress||0),
    createdByUid:t.creator_id||'',assignUid:t.assignee_id||'',createdBy:t.creator_name_snapshot||'',assign:t.assignee_name_snapshot||'',
    start:t.start_date||'',end:t.due_date||'',actualEnd:t.actual_end_date||'',notes:t.notes||'',managerNotes:t.manager_notes||'',revision:Number(t.revision||1),reopenReason:t.reopen_reason||'',
    createdAt:ms(t.created_at),updatedAt:ms(t.updated_at),startedAt:ms(t.started_at)||null,submittedAt:ms(t.submitted_at)||null,
    approvedAt:ms(t.approved_at)||null,approvedBy:t.approved_by_name_snapshot||'',returnedAt:ms(t.returned_at)||null,returnedBy:t.returned_by_name_snapshot||'',
    reopenedAt:ms(t.reopened_at)||null,reopenedBy:t.reopened_by_name_snapshot||'',completedAt:ms(t.completed_at)||null,
    cancelledAt:ms(t.cancelled_at)||null,cancelReason:t.cancel_reason||'',slaHours:t.sla_hours??null,slaDueAt:ms(t.sla_due_at)||null,
    activity:children?.activities?.get(t.id)||[],subtasks:children?.subtasks?.get(t.id)||[],attachments:children?.attachments?.get(t.id)||[],
    _relationalId:t.id
  };
}

class Snap{
  constructor(value,key=null){this._value=value;this.key=key}
  exists(){return this._value!==null&&this._value!==undefined&&(typeof this._value!=='object'||Array.isArray(this._value)||Object.keys(this._value).length>0)}
  val(){return this._value}
}

async function visibleTasks(extra=null){
  let q=sb.from('tasks').select('*').is('deleted_at',null);
  // The main Tasks workspace is intentionally active-only.
  // Completed/approved tasks are served from completed/index.html.
  const isMainTasksWorkspace=/\/tasks\/(?:index\.html)?$/.test(location.pathname);
  if(isMainTasksWorkspace && !extra?.id)q=q.neq('status','مكتملة');
  if(extra?.assignee)q=q.eq('assignee_id',extra.assignee);
  if(extra?.creator)q=q.eq('creator_id',extra.creator);
  if(extra?.id)q=q.eq('id',_aliases.get(extra.id)||extra.id);
  const {data,error}=await q.order('updated_at',{ascending:false});if(error)throw error;
  const children=await loadChildren((data||[]).map(x=>x.id));
  return (data||[]).map(t=>taskLegacy(t,children));
}

export async function get(r){
  const path=pathOf(r),parts=path.split('/').filter(Boolean),mods=r?.mods||[];
  if(path==='users'){
    let q=sb.from('profiles').select('*');
    const ord=mods.find(x=>x.type==='orderByChild'),eq=mods.find(x=>x.type==='equalTo');
    if(ord?.field==='managerUid'&&eq)q=q.eq('manager_id',eq.value);
    const {data,error}=await q;if(error)throw error;const out={};for(const p of data||[])out[p.id]=profileLegacy(p);return new Snap(out);
  }
  if(parts[0]==='users'&&parts[1]){const {data,error}=await sb.from('profiles').select('*').eq('id',parts[1]).maybeSingle();if(error)throw error;return new Snap(data?profileLegacy(data):null,parts[1])}
  if(parts[0]==='tasksByUser'){
    const owner=parts[1],key=parts[2];
    if(key){const rows=await visibleTasks({id:key});const t=rows.find(x=>!owner||x.assignUid===owner)||null;return new Snap(t,key)}
    const rows=await visibleTasks(owner?{assignee:owner}:null),out={};for(const t of rows){const k=publicKey(t._relationalId);out[k]=t}return new Snap(out,owner||null);
  }
  if(parts[0]==='createdTaskIndex'&&parts[1]){const rows=await visibleTasks({creator:parts[1]}),out={};for(const t of rows)out[publicKey(t._relationalId)]=t.assignUid;return new Snap(out,parts[1])}
  if(parts[0]==='notificationsByUser'){
    let q=sb.from('notifications').select('*').order('created_at',{ascending:false});const lim=mods.find(x=>x.type==='limitToLast')?.value||100;q=q.limit(lim);
    const {data,error}=await q;if(error)throw error;const rows=data||[],taskIds=[...new Set(rows.map(n=>n.task_id).filter(Boolean))];let owners=new Map();
    if(taskIds.length){const tr=await sb.from('tasks').select('id,assignee_id').in('id',taskIds);if(!tr.error)owners=new Map((tr.data||[]).map(t=>[String(t.id),t.assignee_id]))}
    const out={};for(const n of rows)out[n.id]={type:n.type||'',title:n.title||'',message:n.message||n.detail||'',createdAt:ms(n.created_at),read:false,taskKey:n.task_id?publicKey(n.task_id):'',ownerUid:n.owner_id||n.assignee_id||owners.get(String(n.task_id))||''};return new Snap(out);
  }
  return new Snap(null);
}

async function currentAuthUser(){const {data:{session}}=await sb.auth.getSession();if(!session?.user){_authUser=null;return null}_authUser={uid:session.user.id,id:session.user.id,email:session.user.email||'',get emailVerified(){return !!session.user.email_confirmed_at}};return _authUser}
export async function signInWithEmailAndPassword(_auth,email,password){const {data,error}=await sb.auth.signInWithPassword({email,password});if(error){error.code=error.code||'auth/invalid-credential';throw error}_authUser={uid:data.user.id,id:data.user.id,email:data.user.email||''};return {user:_authUser}}
export async function signOut(){await sb.auth.signOut();_authUser=null}
export function onAuthStateChanged(_auth,cb){let dead=false;currentAuthUser().then(u=>{if(!dead)cb(u)});const {data:{subscription}}=sb.auth.onAuthStateChange((_e,s)=>{if(dead)return;_authUser=s?.user?{uid:s.user.id,id:s.user.id,email:s.user.email||''}:null;cb(_authUser)});return ()=>{dead=true;subscription?.unsubscribe?.()}}

function taskPatch(next){
  const p={};
  const add=(k,v)=>{if(v!==undefined)p[k]=v};
  add('title',next.title);add('description',next.desc);add('task_type',next.type||'task');add('status',next.status);add('priority',next.priority);add('progress',Number(next.progress||0));
  add('start_date',dateOnly(next.start));add('due_date',dateOnly(next.end));add('actual_end_date',dateOnly(next.actualEnd));add('notes',next.notes??'');add('manager_notes',next.managerNotes??'');add('reopen_reason',next.reopenReason??null);
  add('started_at',iso(next.startedAt));add('submitted_at',iso(next.submittedAt));add('approved_at',iso(next.approvedAt));add('approved_by_name_snapshot',next.approvedBy||null);add('returned_at',iso(next.returnedAt));add('returned_by_name_snapshot',next.returnedBy||null);add('reopened_at',iso(next.reopenedAt));add('reopened_by_name_snapshot',next.reopenedBy||null);add('completed_at',iso(next.completedAt));
  return p;
}

async function reconcileSubtasks(taskId,nextItems){
  const {data:existing,error}=await sb.from('subtasks').select('*').eq('task_id',taskId);if(error)throw error;const old=new Map((existing||[]).map(x=>[String(x.id),x]));
  const keep=[];
  for(let i=0;i<(nextItems||[]).length;i++){
    const x=nextItems[i]||{},id=String(x.id||globalThis.crypto?.randomUUID?.()||'');if(!id)continue;keep.push(id);
    const payload={task_id:taskId,position:i+1,title:String(x.title||''),done:!!x.done};
    if(old.has(id)){const {error:e}=await sb.from('subtasks').update(payload).eq('id',id);if(e)throw e}else{const {error:e}=await sb.from('subtasks').insert({id,...payload,created_at:iso(x.createdAt)||new Date().toISOString()});if(e)throw e}
  }
  const remove=[...old.keys()].filter(id=>!keep.includes(id));if(remove.length){const {error:e}=await sb.from('subtasks').delete().in('id',remove);if(e)throw e}
}

export async function runTransaction(r,mutator){
  const path=pathOf(r),parts=path.split('/').filter(Boolean);
  if(parts[0]!=='tasksByUser'||!parts[2])return {committed:false,snapshot:new Snap(null)};
  const key=_aliases.get(parts[2])||parts[2];const rows=await visibleTasks({id:key});const cur=rows[0];if(!cur)return {committed:false,snapshot:new Snap(null,key)};
  const current=structuredClone(cur),next=mutator(structuredClone(current));if(next===undefined)return {committed:false,snapshot:new Snap(current,key)};
  const beforeSubs=JSON.stringify(current.subtasks||[]),afterSubs=JSON.stringify(next.subtasks||[]);
  const patch=taskPatch(next);
  const {data,error}=await sb.rpc('update_task_safe',{p_task_id:key,p_expected_revision:Number(current.revision||1),p_patch:patch});
  if(error){
    if(String(error.message||'').includes('ATWAR_CONFLICT'))error.code='ATWAR_CONFLICT';
    throw error;
  }
  const row=Array.isArray(data)?data[0]:data;
  if(beforeSubs!==afterSubs)await reconcileSubtasks(key,next.subtasks||[]);
  const children=await loadChildren([key]);const snapTask=taskLegacy(row,children);await emitLocal();
  if(current.assignee_id!==row.assignee_id||(current.status==='بانتظار الاعتماد'&&row.status==='قيد التنفيذ'))await dispatchQueuedTaskEmails();
  return {committed:true,snapshot:new Snap(snapTask,key)};
}

async function createOne(task,assigneeId,aliasKey){
  const {data,error}=await sb.rpc('create_task_safe',{p_title:String(task.title||'').trim(),p_assignee_id:assigneeId,p_description:task.desc||'',p_priority:task.priority||'normal',p_start_date:task.start||null,p_due_date:task.end||null,p_notes:task.notes||''});if(error)throw error;const id=Array.isArray(data)?data[0]:data;if(aliasKey&&id)_aliases.set(aliasKey,id);return id;
}

async function rootUpdate(changes){
  const entries=Object.entries(changes||{});const taskEntries=entries.filter(([k])=>k.startsWith('tasksByUser/'));
  const creates=taskEntries.filter(([,v])=>v&&typeof v==='object');const deletes=taskEntries.filter(([,v])=>v===null);
  let shouldDispatchEmail=false;
  // Reassignment = same task key appears as a create under new owner and delete under old owner.
  for(const [newPath,obj] of creates){const np=newPath.split('/'),alias=np[2],real=_aliases.get(alias)||alias;const matchingDelete=deletes.find(([oldPath])=>oldPath.split('/')[2]===alias);
    if(matchingDelete){
      const rows=await visibleTasks({id:real});const cur=rows[0];if(!cur)throw new Error('Task not found');
      const {error}=await sb.rpc('update_task_safe',{p_task_id:real,p_expected_revision:Number(cur.revision||1),p_patch:{assignee_id:np[1],assignee_name_snapshot:obj.assign||null}});
      if(error)throw error;shouldDispatchEmail=true;continue;
    }
  }
  const pureCreates=creates.filter(([newPath])=>!deletes.some(([oldPath])=>oldPath.split('/')[2]===newPath.split('/')[2]));
  if(pureCreates.length===1){const [p,obj]=pureCreates[0],parts=p.split('/');await createOne(obj,parts[1],parts[2]);shouldDispatchEmail=true;}
  else if(pureCreates.length>1){const payload=pureCreates.map(([p,t])=>({title:t.title||'',description:t.desc||'',priority:t.priority||'normal',status:t.status||'قيد الانتظار',progress:Number(t.progress||0),assignee_id:p.split('/')[1],start_date:t.start||null,due_date:t.end||null,notes:t.notes||'',manager_notes:t.managerNotes||''}));const {error}=await sb.rpc('import_tasks_safe',{p_rows:payload});if(error)throw error;shouldDispatchEmail=true;}
  for(const [oldPath] of deletes){const parts=oldPath.split('/'),alias=parts[2];if(creates.some(([p])=>p.split('/')[2]===alias))continue;const id=_aliases.get(alias)||alias;const {error}=await sb.rpc('delete_task_safe',{p_task_id:id,p_reason:null});if(error)throw error;}
  await emitLocal();
  if(shouldDispatchEmail)await dispatchQueuedTaskEmails();
}

export async function update(r,changes){
  const path=pathOf(r);
  if(!path){
    const notifIds=Object.keys(changes||{}).filter(k=>k.startsWith('notificationsByUser/')).map(k=>k.split('/')[2]).filter(Boolean);
    if(notifIds.length){const {error}=await sb.from('notifications').delete().in('id',[...new Set(notifIds)]);if(error)throw error;await emitLocal();}
    const taskChanges=Object.fromEntries(Object.entries(changes||{}).filter(([k])=>k.startsWith('tasksByUser/')||k.startsWith('createdTaskIndex/')));
    if(Object.keys(taskChanges).some(k=>k.startsWith('tasksByUser/')))await rootUpdate(taskChanges);
    return;
  }
  const parts=path.split('/').filter(Boolean);
  if(parts[0]==='notificationsByUser'){
    // ATWAR ONE policy: notifications have no read flag. Marking read means deleting the row.
    if(parts[2]){const {error}=await sb.from('notifications').delete().eq('id',parts[2]);if(error)throw error;await emitLocal();return}
    const ids=Object.keys(changes||{}).map(k=>k.split('/')[0]).filter(Boolean);if(ids.length){const {error}=await sb.from('notifications').delete().in('id',ids);if(error)throw error;await emitLocal()}return;
  }
  if(parts[0]==='tasksByUser'&&parts[2]){
    const id=_aliases.get(parts[2])||parts[2];const rows=await visibleTasks({id});if(!rows[0])return;
    const next={...rows[0],...changes};
    const {error}=await sb.rpc('update_task_safe',{p_task_id:id,p_expected_revision:Number(rows[0].revision||1),p_patch:taskPatch(next)});
    if(error)throw error;await emitLocal();return;
  }
}

export async function set(r,data){
  const path=pathOf(r),parts=path.split('/').filter(Boolean);
  if(parts[0]==='notificationsByUser')return; // DB triggers create operational notifications.
  if(parts[0]==='tasksByUser'&&parts[2])return rootUpdate({[path]:data});
}
export async function remove(r){const path=pathOf(r),parts=path.split('/').filter(Boolean);if(parts[0]==='notificationsByUser'&&parts[2]){const {error}=await sb.from('notifications').delete().eq('id',parts[2]);if(error)throw error;await emitLocal()}}

async function emitLocal(){for(const fn of [..._listeners]){try{await fn()}catch(e){console.warn('compat listener',e)}}}
let _realtimeChannel=null;
function ensureRealtime(){
  if(_realtimeChannel)return;
  try{
    _realtimeChannel=sb.channel('atwar-one-compat-v18')
      .on('postgres_changes',{event:'*',schema:'public',table:'tasks'},()=>emitLocal())
      .on('postgres_changes',{event:'*',schema:'public',table:'subtasks'},()=>emitLocal())
      .on('postgres_changes',{event:'*',schema:'public',table:'notifications'},()=>emitLocal())
      .on('postgres_changes',{event:'*',schema:'public',table:'task_comments'},()=>emitLocal())
      .on('postgres_changes',{event:'*',schema:'public',table:'task_attachments'},()=>emitLocal())
      .subscribe();
  }catch(e){console.warn('Realtime unavailable; polling fallback remains active.',e)}
}
export function onValue(r,callback,errorCallback){
  ensureRealtime();
  let alive=true,busy=false,refreshQueued=false;
  const refresh=async()=>{
    if(!alive)return;
    if(busy){refreshQueued=true;return;}
    busy=true;
    try{callback(await get(r))}catch(e){errorCallback?.(e)}finally{
      busy=false;
      if(refreshQueued&&alive){refreshQueued=false;queueMicrotask(refresh)}
    }
  };
  _listeners.add(refresh);refresh();
  const timer=setInterval(refresh,60000);
  return ()=>{alive=false;clearInterval(timer);_listeners.delete(refresh)};
}
