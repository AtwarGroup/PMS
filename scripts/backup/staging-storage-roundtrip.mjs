import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {verifyStorageBackup} from './verify-storage-backup.mjs';

const digest=b=>createHash('sha256').update(b).digest('hex');
export async function stagingStorageRoundtrip({directory,origin,key,bucket,fetchImpl=fetch,verifyPrivateAccess}) {
  if(new URL(origin).origin!=='https://eeaedzisysjarwvolbwq.supabase.co')throw Error('Fixed staging target required');
  if(!key||!/^restore-drill-(production|staging)-[0-9]+$/.test(bucket))throw Error('Scoped temporary bucket required');
  await verifyStorageBackup(directory);
  const manifest=JSON.parse(await readFile(path.join(directory,'storage-manifest.json'),'utf8'));
  if(manifest.version!==2)throw Error('Checksummed manifest v2 required');
  const request=async(route,options={})=>{
    const r=await fetchImpl(origin+'/storage/v1/'+route,{...options,signal:AbortSignal.timeout(60000),headers:{Authorization:'Bearer '+key,apikey:key,...options.headers}});
    if(!r.ok)throw Error('Staging storage operation failed: '+r.status);
    return r;
  };
  const existing=await (await request('bucket')).json();
  if(existing.some(b=>b.id===bucket))throw Error('Temporary bucket already exists; refusing to modify it');
  let created=false,verified=0,bytes=0;
  try {
    await request('bucket',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:bucket,name:bucket,public:false})});
    created=true;
    const info=await (await request('bucket/'+bucket)).json();
    if(info.public!==false)throw Error('Temporary bucket must remain private');
    for(const b of manifest.buckets)for(const object of b.objects){
      const body=await readFile(path.join(directory,b.id,...object.object.split('/')));
      const route='object/'+bucket+'/'+[b.id,...object.object.split('/')].map(encodeURIComponent).join('/');
      const mime=object.mime||'application/octet-stream';
      await request(route,{method:'POST',headers:{'Content-Type':mime,'x-upsert':'false'},body});
      const response=await request('object/authenticated/'+bucket+'/'+[b.id,...object.object.split('/')].map(encodeURIComponent).join('/'));
      const restored=new Uint8Array(await response.arrayBuffer());
      if(digest(restored)!==object.sha256||restored.length!==body.length)throw Error('Restored attachment digest or size mismatch');
      if(response.headers.get('content-type')?.split(';')[0]!==mime)throw Error('Restored attachment MIME type mismatch');
      verified++;bytes+=body.length;
    }
    if(verifyPrivateAccess)await verifyPrivateAccess(bucket);
  } finally {
    if(created){
      await request('bucket/'+bucket+'/empty',{method:'POST'});
      await request('bucket/'+bucket,{method:'DELETE'});
      const remaining=await (await request('bucket')).json();
      if(remaining.some(b=>b.id===bucket))throw Error('Temporary bucket cleanup incomplete');
    }
  }
  return {verified,bytes,privateBucket:true,cleanupVerified:true};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  const db=process.env.RESTORE_DRILL_DB_URL;
  const parsed=new URL(db),ref='eeaedzisysjarwvolbwq';
  if(parsed.hostname!=='db.'+ref+'.supabase.co'&&!(parsed.hostname.endsWith('.pooler.supabase.com')&&decodeURIComponent(parsed.username)==='postgres.'+ref))throw Error('Fixed staging SQL target required');
  const verifyPrivateAccess=async bucket=>{
    const sql=`BEGIN; SET LOCAL ROLE anon; SELECT count(*) FROM storage.objects WHERE bucket_id='${bucket}'; RESET ROLE; SET LOCAL ROLE authenticated; SELECT count(*) FROM storage.objects WHERE bucket_id='${bucket}'; ROLLBACK;`;
    try {
      const {stdout}=await promisify(execFile)('docker',['run','--rm','-e','PGCONNECT_TIMEOUT=30','postgres:17.6','psql',db,'-X','-qAt','-v','ON_ERROR_STOP=1','-c',sql],{timeout:60000,maxBuffer:1048576});
      if(stdout.trim()!=='0\n0')throw Error('Unexpected read visibility');
    } catch {throw Error('Temporary restore bucket access check failed');}
    console.log('Temporary restored files invisible to anon and authenticated roles.');
  };
  const result=await stagingStorageRoundtrip({directory:process.argv[2],origin:process.env.RESTORE_DRILL_SUPABASE_URL,key:process.env.RESTORE_DRILL_SERVICE_ROLE_KEY,bucket:process.env.RESTORE_TEST_BUCKET,verifyPrivateAccess});
  console.log('Hosted staging Storage roundtrip: '+JSON.stringify(result));
}
