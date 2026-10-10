import {createClient} from 'https://esm.sh/@supabase/supabase-js@2.57.4';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info'};
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 const respond=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
 if(req.method!=='POST')return respond({error:'Method not allowed'},405);
 const auth=req.headers.get('Authorization')||'';
 const url=Deno.env.get('SUPABASE_URL')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!,secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
 const userClient=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
 const {data:{user},error}=await userClient.auth.getUser();if(error||!user)return respond({error:'Unauthorized'},401);
 const {data:profile}=await userClient.from('profiles').select('active,status').eq('id',user.id).single();if(!profile?.active||profile.status!=='active')return respond({error:'Inactive account'},403);
 let body;try{body=await req.json();}catch{return respond({error:'Invalid request'},400);}
 const admin=createClient(url,secret,{auth:{persistSession:false}});
 if(body.id){
  if(!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(body.id))return respond({error:'Invalid attachment'},400);
  const {data:deleted,error:de}=await userClient.from('task_attachments').delete().eq('id',body.id).select('id');
  if(de)return respond({error:'لا تملك صلاحية حذف المرفق أو أن المهمة مقفلة.'},403);
  if(!deleted?.length){const {data:q}=await admin.from('task_attachment_cleanup').select('id').eq('attachment_id',body.id).eq('requested_by',user.id).limit(1);if(!q?.length)return respond({error:'المرفق غير متاح للحذف.'},403);}
 }
 const {data:queue,error:qe}=await admin.from('task_attachment_cleanup').select('*').eq('requested_by',user.id).is('completed_at',null).order('requested_at').limit(20);
 if(qe)return respond({error:'تعذر تحميل قائمة التنظيف.'},500);
 let pending=0;
 for(const row of queue||[]){
  if(!row.storage_path.startsWith(row.task_id+'/')||row.storage_path.split('/').some((segment:string)=>segment==='..')){pending++;continue;}
  // Privileged cleanup may touch only the already-authorized task folder, never an arbitrary client path.
  const {error:re}=await admin.storage.from('task-attachments').remove([row.storage_path]);
  const {error:ue}=await admin.from('task_attachment_cleanup').update({attempts:row.attempts+1,last_error:re?'تعذر حذف الملف من التخزين.':null,completed_at:re?null:new Date().toISOString()}).eq('id',row.id).eq('requested_by',user.id);
  if(re||ue)pending++;
 }
 const {count}=await admin.from('task_attachment_cleanup').select('id',{count:'exact',head:true}).eq('requested_by',user.id).is('completed_at',null);
 return respond({deleted:!!body.id,pending:count??pending});
});
