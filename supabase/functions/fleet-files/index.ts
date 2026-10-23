import {createClient} from 'https://esm.sh/@supabase/supabase-js@2.117.0';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info'};
const response=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
const digest=async(bytes:Uint8Array)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(b=>b.toString(16).padStart(2,'0')).join('');
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return response({error:'Method not allowed'},405);
 const url=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_ANON_KEY')!,service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
 const user=createClient(url,key,{global:{headers:{Authorization:req.headers.get('Authorization')||''}},auth:{persistSession:false}});
 const {data:{user:identity},error:authError}=await user.auth.getUser();if(authError||!identity)return response({error:'Unauthorized'},401);
 let body;try{body=await req.json();}catch{return response({error:'Invalid request'},400);}
 if(!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(body.id)||!['request','handover'].includes(body.kind)||!['archive','download'].includes(body.action))return response({error:'Invalid file request'},400);
 // Every action rechecks the caller's live module and record access. Client paths/bytes are ignored.
 const {data:file,error}=await user.rpc(body.kind==='request'?'fleet_download':'fleet_handover_photo',{p_id:body.id});
 if(error||!file)return response({error:'File unavailable'},403);
 const admin=createClient(url,service,{auth:{persistSession:false}}),bucket=admin.storage.from('fleet-files'),path=body.kind+'/'+body.id;
 try{
  if(body.action==='archive'&&!file.stored){
   const bytes=Uint8Array.from(atob(file.base64.replace(/\s/g,'')),c=>c.charCodeAt(0));
   if(bytes.length!==file.size||await digest(bytes)!==file.hash)throw Error('Source checksum mismatch');
   const {error:uploadError}=await bucket.upload(path,bytes,{contentType:file.mime,upsert:false});
   if(uploadError&&![409,400].includes(Number(uploadError.statusCode)))throw uploadError;
   const {data:check,error:downloadError}=await bucket.download(path);if(downloadError||!check)throw Error('Storage verification unavailable');
   if(await digest(new Uint8Array(await check.arrayBuffer()))!==file.hash)throw Error('Stored checksum mismatch');
   const {error:finishError}=await admin.rpc('fleet_file_archive_complete',{p_id:body.id,p_kind:body.kind,p_hash:file.hash});if(finishError)throw finishError;
  }
  if(body.action==='archive')return response({stored:true});
  if(!file.stored)return response({base64:file.base64,name:file.name,mime:file.mime});
  // Stream through authenticated access checks; no reusable bearer download URL survives revocation.
  const {data:download,error:downloadError}=await bucket.download(path);if(downloadError||!download)throw Error('Download unavailable');
  return new Response(download,{headers:{...cors,'Content-Type':'application/octet-stream','Cache-Control':'no-store'}});
 }catch{return response({error:'تعذر إتمام نقل أو تنزيل الملف. النسخة الأصلية تبقى محفوظة حتى نجاح التحقق.'},503);}
});
