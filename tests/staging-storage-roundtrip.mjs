import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {stagingStorageRoundtrip} from '../scripts/backup/staging-storage-roundtrip.mjs';
const directory=await mkdtemp(path.join(os.tmpdir(),'atwar-storage-roundtrip-'));
const data=Buffer.from('Synthetic restore fixture only');
const bucket='restore-drill-staging-123';
const common={directory,origin:'https://eeaedzisysjarwvolbwq.supabase.co',key:'test-fixture-not-a-key',bucket};
try {
 await mkdir(path.join(directory,'fixture'));
 await writeFile(path.join(directory,'fixture','sample.txt'),data);
 await writeFile(path.join(directory,'storage-manifest.json'),JSON.stringify({version:2,bucketCount:1,buckets:[{id:'fixture',objectCount:1,objects:[{bucket:'fixture',object:'sample.txt',size:data.length,sha256:createHash('sha256').update(data).digest('hex'),mime:'text/plain'}]}]}));
 function backend({preexisting=false,corrupt=false,deleteDelay=false}={}){
  const calls=[];let exists=preexisting;let uploaded;let deletions=0;
  const fetchImpl=async(url,o={})=>{
   const route=new URL(url).pathname.replace('/storage/v1/',''),method=o.method||'GET';calls.push([method,route]);
   if(route==='bucket'&&method==='GET')return Response.json(exists?[{id:bucket,public:false}]:[]);
   if(route==='bucket'&&method==='POST'){assert.equal(JSON.parse(o.body).public,false);exists=true;return Response.json({});}
   if(route==='bucket/'+bucket&&method==='GET')return Response.json({id:bucket,public:false});
   if(route.startsWith('object/'+bucket+'/')&&method==='POST'){assert.equal(o.headers['x-upsert'],'false');uploaded=o.body;return Response.json({});}
   if(route.startsWith('object/authenticated/'+bucket+'/'))return new Response(corrupt?Buffer.from('corrupt'):uploaded,{headers:{'content-type':'text/plain'}});
   if(route==='bucket/'+bucket+'/empty'&&method==='POST')return Response.json({});
   if(route==='bucket/'+bucket&&method==='DELETE'){if(deleteDelay&&deletions++===0)return Response.json({error:'not empty yet'},{status:400});exists=false;return Response.json({});}
   throw Error('Unexpected fixture request');
  };
  return {fetchImpl,calls};
 }
 const success=backend();assert.equal((await stagingStorageRoundtrip({...common,...success})).verified,1);assert(success.calls.some(([m,r])=>m==='DELETE'&&r==='bucket/'+bucket));
 const delayed=backend({deleteDelay:true});await stagingStorageRoundtrip({...common,...delayed,wait:async()=>{}});assert.equal(delayed.calls.filter(([m])=>m==='DELETE').length,2);
 const damaged=backend({corrupt:true});await assert.rejects(stagingStorageRoundtrip({...common,...damaged}),/digest or size mismatch/);assert(damaged.calls.some(([m])=>m==='DELETE'));
 const existing=backend({preexisting:true});await assert.rejects(stagingStorageRoundtrip({...common,...existing}),/already exists/);assert.equal(existing.calls.length,1);
 const denied=backend();await assert.rejects(stagingStorageRoundtrip({...common,...denied,verifyPrivateAccess:async()=>{throw Error('visibility check failed');}}),/visibility check failed/);assert(denied.calls.some(([m])=>m==='DELETE'));
 const foreign=backend();await assert.rejects(stagingStorageRoundtrip({...common,...foreign,origin:'https://mjmxebkyswuphbgsukdt.supabase.co'}),/Fixed staging/);assert.equal(foreign.calls.length,0);
 await writeFile(path.join(directory,'fixture','sample.txt'),'tampered');
 const invalid=backend();await assert.rejects(stagingStorageRoundtrip({...common,...invalid}));assert.equal(invalid.calls.length,0);
 console.log('Staging Storage roundtrip, corruption cleanup, existing-bucket protection and fixed-target guards passed.');
} finally {await rm(directory,{recursive:true,force:true});}
