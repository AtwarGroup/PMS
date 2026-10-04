import { createClient } from 'npm:@supabase/supabase-js@2.117.0';
import { Buffer } from 'node:buffer';
import { command, snapshot, conversation, notificationSettings } from './model.mjs';
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Content-Type':'application/json'};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
Deno.serve(async(req)=>{
 if(req.method==='OPTIONS')return new Response(null,{headers});
 if(req.method!=='POST')return json({error:'Method not allowed'},405);
 try {
  const token=req.headers.get('Authorization')?.replace(/^Bearer /,'');if(!token)return json({error:'يلزم تسجيل الدخول.'},401);
  const url=Deno.env.get('SUPABASE_URL')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!;
  const caller=createClient(url,anon,{global:{headers:{Authorization:'Bearer '+token}},auth:{persistSession:false}});
  const {data:{user},error:authError}=await caller.auth.getUser(token);if(authError||!user)return json({error:'الجلسة غير صالحة.'},401);
  const {data:allowed,error:gateError}=await caller.rpc('communication_status');if(gateError||!allowed)return json({error:'التواصل غير متاح لهذا الحساب.'},403);
  const raw=await req.text();if(raw.length>14500000)return json({error:'الطلب يتجاوز الحد المسموح.'},413);
  const input=JSON.parse(raw),db=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
  if(input.path==='action'&&input.data?.action==='presence'){const {data:result,error:pe}=await db.rpc('communication_presence',{p_actor:user.id,p_data:input.data.data||{}});if(pe)throw pe;return json(result);}
  for(let attempt=0;attempt<5;attempt++){
   const {data:record,error}=await db.rpc('communication_load',{p_actor:user.id});if(error)throw error;
   let state=record.state;
   // Active accounts and relationships come from profiles, never from the browser.
   state.users=record.users;
   if(input.path==='message'){
    const {data:row,error:re}=await db.rpc('communication_message',{p_actor:user.id,p_message:input.data?.id});if(re)throw re;return json({...row,task:row.task?{id:row.task,restricted:true}:null});
   }
   if(input.path==='history'){
    const {data:rows,error:he}=await db.rpc('communication_history',{p_actor:user.id,p_conversation:input.data?.conversation,p_before:input.data?.before});if(he)throw he;
    return json(rows.map((m:any)=>({...m,task:m.task?{id:m.task,restricted:true}:null})));
   }
   if(input.path==='accounts')return json(state.users.filter((p:any)=>p.id===user.id));
   if(input.path==='state'){
    if(input.data?.target&&!state.messages.some((m:any)=>m.id===input.data.target)){const {data:row,error:re}=await db.rpc('communication_message',{p_actor:user.id,p_message:input.data.target});if(re)throw re;state.messages.push(row);if(row.thread&&!state.messages.some((m:any)=>m.id===row.thread)){const {data:root,error:rr}=await db.rpc('communication_message',{p_actor:user.id,p_message:row.thread});if(rr)throw rr;state.messages.push(root);}}
    const safe={...state,messages:state.messages.map((m:any)=>({...m,task:null}))};const view=snapshot(safe,user.id);
    const {data:tasks,error:te}=await caller.from('tasks').select('id,title,status,assignee_id,creator_id,due_date').is('deleted_at',null).order('created_at',{ascending:false}).limit(500);if(te)throw te;
    const {data:projects,error:pe}=await caller.from('projects').select('id,title,status').is('deleted_at',null).order('updated_at',{ascending:false}).limit(200);if(pe)throw pe;
    view.tasks=(tasks||[]).map((t:any)=>({id:t.id,title:t.title,status:t.status,assignee:t.assignee_id,creator:t.creator_id,due:t.due_date,real:true}));
    // Lookup linked tasks separately: an old linked task must not vanish at the catalogue limit.
    for(const m of view.messages){const id=state.messages.find((x:any)=>x.id===m.id)?.task;if(!id)continue;let t=view.tasks.find((x:any)=>x.id===id);if(!t){const {data:row,error:re}=await caller.from('tasks').select('id,title,status,assignee_id,creator_id,due_date').eq('id',id).is('deleted_at',null).maybeSingle();if(re)throw re;if(row)t={id:row.id,title:row.title,status:row.status,assignee:row.assignee_id,creator:row.creator_id,due:row.due_date,real:true};}m.task=t||{id,restricted:true};}
    const {data:assignees,error:ae}=await caller.rpc('communication_assignees');if(ae)throw ae;view.assignees=assignees||[];view.projects=projects||[];return json(view);
   }
   if(input.path==='file'){
    const {data:f,error:fe}=await db.rpc('communication_file',{p_actor:user.id,p_file:input.data?.id});if(fe)throw fe;return json(f);
   }
   if(input.path!=='action')return json({error:'الإجراء غير متاح.'},400);
   if(['createTask','linkTask'].includes(input.data?.action)){
    const d=input.data.data||{};conversation(state,d.conversation,user.id);
    if(!state.messages.some((m:any)=>m.id===d.message&&m.conversation===d.conversation))return json({error:'الرسالة غير متاحة'},403);
    const {data:id,error:ce}=await caller.rpc('communication_task_command',{p_message:d.message,p_task:input.data.action==='linkTask'?d.task:null,p_title:d.title||null,p_assignee:d.assignee||null,p_due:d.due||null});if(ce)throw ce;return json({id,real:true});
   }
   const d=input.data?.data||{};
   for(const key of ['message','reply','thread']){if(d[key]&&!state.messages.some((m:any)=>m.id===d[key])){const {data:row,error:re}=await db.rpc('communication_message',{p_actor:user.id,p_message:d[key]});if(re)throw re;state.messages.push(row);}}
   const result=command(state,user.id,input.data?.action,input.data?.data||{});
   if(input.data?.action==='notificationClaim')Object.assign(result,{sound:notificationSettings(state,user.id).sound,desktop:notificationSettings(state,user.id).desktop});
   const files=state.messages.filter((m:any)=>m.file?.base64).map((m:any)=>({id:m.file.id,conversation:m.conversation,file:{...m.file}}));for(const m of state.messages)if(m.file)delete m.file.base64;
   const {data:saved,error:saveError}=await db.rpc('communication_save',{p_actor:user.id,p_version:record.version,p_state:state,p_files:files,p_publish:!['presence','notificationClaim'].includes(input.data?.action)});if(saveError)throw saveError;if(saved)return json(result);
  }
  return json({error:'حدث تحديث متزامن. أعد المحاولة.'},409);
 }catch(e){return json({error:e instanceof Error?e.message:'تعذر تنفيذ الطلب.'},Number((e as any)?.status)||400);}
});
