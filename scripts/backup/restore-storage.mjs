import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
export function backupMime(object,bytes,bucket) {
  if(object.mime)return object.mime;
  // Older manifests lack MIME metadata; retain compatibility with restricted private buckets.
  if(bytes.subarray(0,5).toString()==='%PDF-')return 'application/pdf';
  if(bytes.subarray(0,8).equals(Buffer.from('89504e470d0a1a0a','hex')))return 'image/png';
  if(bytes.subarray(0,3).equals(Buffer.from('ffd8ff','hex')))return 'image/jpeg';
  const ext=path.extname(object.object).toLowerCase();
  return ({'.pdf':'application/pdf','.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.webp':'image/webp','.docx':'application/vnd.openxmlformats-officedocument.wordprocessingml.document','.xlsx':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','.xls':'application/vnd.ms-excel','.doc':'application/msword','.txt':'text/plain'})[ext]||(bucket.allowed_mime_types?.length===1?bucket.allowed_mime_types[0]:'application/octet-stream');
}
export async function restoreStorage({origin,sourceOrigin,key,directory,fetchImpl=fetch}) {
  const target=new URL(origin),source=new URL(sourceOrigin);
  if(target.origin===source.origin)throw Error('Refusing to restore storage into production');
  if(target.protocol!=='https:'&&!['127.0.0.1','localhost'].includes(target.hostname))throw Error('HTTPS required');
  if(!key)throw Error('Disposable target service key required');
  const root=path.resolve(directory),manifest=JSON.parse(await readFile(path.join(root,'storage-manifest.json'),'utf8'));
  const request=async(route,options={})=>{
    const response=await fetchImpl(target.origin+'/storage/v1/'+route,{...options,headers:{Authorization:'Bearer '+key,apikey:key,...options.headers}});
    if(!response.ok)throw Error('Storage restore request failed: '+response.status);
    return response;
  };
  const existing=await (await request('bucket')).json();let restored=0;
  for(const bucket of manifest.buckets){
    if(!/^[a-zA-Z0-9_-]+$/.test(bucket.id))throw Error('Invalid bucket name');
    const current=existing.find(b=>b.id===bucket.id);
    if(current&&Boolean(current.public)!==Boolean(bucket.public))throw Error('Target bucket visibility differs from backup');
    if(!current)await request('bucket',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:bucket.id,name:bucket.name,public:Boolean(bucket.public),file_size_limit:bucket.file_size_limit??null,allowed_mime_types:bucket.allowed_mime_types??null})});
    for(const object of bucket.objects){
      const parts=String(object.object).split('/');
      if(parts.some(p=>!p||p==='.'||p==='..'||p.includes('\\')))throw Error('Unsafe backup object path');
      const file=path.resolve(root,bucket.id,...parts);
      if(!file.startsWith(root+path.sep))throw Error('Unsafe backup path');
      const bytes=await readFile(file),route='object/'+encodeURIComponent(bucket.id)+'/'+parts.map(encodeURIComponent).join('/');
      await request(route,{method:'POST',headers:{'Content-Type':backupMime(object,bytes,bucket),'x-upsert':'true'},body:bytes});
      const downloaded=new Uint8Array(await (await request('object/authenticated/'+encodeURIComponent(bucket.id)+'/'+parts.map(encodeURIComponent).join('/'))).arrayBuffer());
      if(hash(downloaded)!==hash(bytes))throw Error('Restored attachment checksum mismatch');
      restored++;
    }
  }
  return {buckets:manifest.buckets.length,objects:restored,verified:true};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const result=await restoreStorage({origin:process.env.RESTORE_DRILL_SUPABASE_URL,sourceOrigin:process.env.SUPABASE_URL,key:process.env.RESTORE_DRILL_SERVICE_ROLE_KEY,directory:process.argv[2]});
 console.log('Disposable storage restore and download verification: '+JSON.stringify(result));
}
