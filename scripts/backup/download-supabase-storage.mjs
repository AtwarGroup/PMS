import {mkdir, writeFile} from 'node:fs/promises';
import {createWriteStream} from 'node:fs';
import {pipeline} from 'node:stream/promises';
import {Readable} from 'node:stream';
import path from 'node:path';

const base=String(process.env.SUPABASE_URL||'').replace(/\/$/,'');
const key=String(process.env.SUPABASE_SERVICE_ROLE_KEY||'');
const destination=path.resolve(process.argv[2]||'backup/storage');
if(!base||!key)throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required');

const headers={apikey:key,Authorization:`Bearer ${key}`};
const safeSegment=value=>{
  const segment=String(value||'').replaceAll('\\','/');
  if(!segment||segment==='.'||segment==='..'||segment.includes('../')||path.isAbsolute(segment))throw new Error(`Unsafe storage path: ${segment}`);
  return segment;
};
const encodeObjectPath=value=>String(value).split('/').map(encodeURIComponent).join('/');

async function request(url,options={}){
  const response=await fetch(url,{...options,headers:{...headers,...(options.headers||{})}});
  if(!response.ok)throw new Error(`${options.method||'GET'} ${url} failed: ${response.status} ${await response.text()}`);
  return response;
}

async function listDirectory(bucket,prefix=''){
  const rows=[];
  for(let offset=0;;offset+=1000){
    const response=await request(`${base}/storage/v1/object/list/${encodeURIComponent(bucket)}`,{
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({prefix,limit:1000,offset,sortBy:{column:'name',order:'asc'}})
    });
    const page=await response.json();
    rows.push(...page);
    if(page.length<1000)break;
  }
  return rows;
}

async function downloadObject(bucket,objectName){
  const safeBucket=safeSegment(bucket),safeObject=safeSegment(objectName);
  const output=path.resolve(destination,safeBucket,safeObject);
  const expectedRoot=path.resolve(destination,safeBucket)+path.sep;
  if(!output.startsWith(expectedRoot))throw new Error(`Object escaped backup directory: ${objectName}`);
  await mkdir(path.dirname(output),{recursive:true});
  const response=await request(`${base}/storage/v1/object/authenticated/${encodeURIComponent(bucket)}/${encodeObjectPath(objectName)}`);
  if(!response.body)throw new Error(`Empty response body for ${bucket}/${objectName}`);
  await pipeline(Readable.fromWeb(response.body),createWriteStream(output,{mode:0o600}));
  return {bucket,object:objectName,size:Number(response.headers.get('content-length')||0)};
}

async function backupBucket(bucket){
  const queue=[''],objects=[];
  while(queue.length){
    const prefix=queue.shift();
    for(const item of await listDirectory(bucket,prefix)){
      const name=safeSegment(item.name);
      const objectName=prefix?`${prefix}/${name}`:name;
      const isFolder=!item.id&&!item.metadata;
      if(isFolder)queue.push(objectName);
      else objects.push(await downloadObject(bucket,objectName));
    }
  }
  return objects;
}

await mkdir(destination,{recursive:true});
const bucketResponse=await request(`${base}/storage/v1/bucket`);
const buckets=await bucketResponse.json();
const manifest={createdAt:new Date().toISOString(),bucketCount:buckets.length,buckets:[]};
for(const bucket of buckets){
  const objects=await backupBucket(bucket.id);
  manifest.buckets.push({id:bucket.id,name:bucket.name,public:Boolean(bucket.public),objectCount:objects.length,objects});
}
await writeFile(path.join(destination,'storage-manifest.json'),JSON.stringify(manifest,null,2),{mode:0o600});
console.log(`Storage backup completed: ${manifest.bucketCount} buckets, ${manifest.buckets.reduce((sum,b)=>sum+b.objectCount,0)} objects.`);
