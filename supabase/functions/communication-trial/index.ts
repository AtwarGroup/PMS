import { createClient } from 'npm:@supabase/supabase-js@2.117.0';
import { Buffer } from 'node:buffer';
import { command, snapshot, seed, conversation } from './model.mjs';
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
  const {data:allowed,error:gateError}=await caller.rpc('communication_trial_status');if(gateError||!allowed)return json({error:'تجربة التواصل غير متاحة لهذا الحساب.'},403);
  const raw=await req.text();if(raw.length>4500000)return json({error:'الطلب يتجاوز حد التجربة.'},413);
  const input=JSON.parse(raw),db=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
  for(let attempt=0;attempt<5;attempt++){
   const {data:record,error}=await db.rpc('communication_trial_load',{p_actor:user.id});if(error)throw error;
   let state=record.state;
   if(!state.users){state=seed();state.users=record.users;const admin=state.users.find((p:any)=>p.role==='admin')?.id,manager=state.users.find((p:any)=>p.role==='manager')?.id,employee=state.users.find((p:any)=>p.role==='employee')?.id;state.conversations=[{id:'trial-group',type:'group',title:'فريق اختبار التواصل',owner:manager,members:state.users.map((p:any)=>p.id)},{id:'trial-direct',type:'direct',title:'',owner:manager,members:[manager,employee]}];state.messages=[];state.tasks=[];state.seq=0;}
   // Active accounts and relationships come from profiles, never from the browser.
   state.users=record.users;
   if(input.path==='accounts')return json(state.users.filter((p:any)=>p.id===user.id));
   if(input.path==='state')return json(snapshot(state,user.id));
   if(input.path==='file'){
    const m=state.messages.find((m:any)=>m.file?.id===input.data?.id);if(!m)return json({error:'الملف غير متاح.'},404);conversation(state,m.conversation,user.id);return json(m.file);
   }
   if(input.path!=='action')return json({error:'الإجراء غير متاح.'},400);
   const result=command(state,user.id,input.data?.action,input.data?.data||{});
   const {data:saved,error:saveError}=await db.rpc('communication_trial_save',{p_actor:user.id,p_version:record.version,p_state:state});if(saveError)throw saveError;if(saved)return json(result);
  }
  return json({error:'حدث تحديث متزامن. أعد المحاولة.'},409);
 }catch(e){return json({error:e instanceof Error?e.message:'تعذر تنفيذ الطلب.'},Number((e as any)?.status)||400);}
});
