import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,readFile,rm,symlink} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {verifyStorageBackup,digestFile} from '../scripts/backup/verify-storage-backup.mjs';
import {restoreStorage} from '../scripts/backup/restore-storage.mjs';
const root=await mkdtemp(path.join(tmpdir(),'atwar-backup-integrity-'));
try{
 const storage=path.join(root,'storage'),file=path.join(storage,'files','one.bin');
 await mkdir(path.dirname(file),{recursive:true});await writeFile(file,'original');
 const object={bucket:'files',object:'one.bin',...await digestFile(file)};
 const valid={version:2,bucketCount:1,buckets:[{id:'files',objectCount:1,objects:[object]}]};
 const save=async value=>writeFile(path.join(storage,'storage-manifest.json'),JSON.stringify(value));
 await save(valid);assert.deepEqual(await verifyStorageBackup(storage),{buckets:1,objects:1,checksummedObjects:1,legacyObjects:0});
 // Same-length damage defeats size-only checks; it must also prevent any target API writes.
 await writeFile(file,'corrupt!');let requests=0;
 await assert.rejects(verifyStorageBackup(storage),/checksum/);
 await assert.rejects(restoreStorage({origin:'https://target.example.test',sourceOrigin:'https://source.example.test',key:'fixture',directory:storage,fetchImpl:async()=>{requests++;throw Error('Unexpected API access')}}),/checksum/);
 assert.equal(requests,0);
 await writeFile(file,'short');await assert.rejects(verifyStorageBackup(storage),/size/);
 await rm(file);await assert.rejects(verifyStorageBackup(storage),/ENOENT/);
 await writeFile(file,'original');
 for(const mutate of [
  m=>m.bucketCount=2,
  m=>m.buckets[0].objectCount=2,
  m=>{m.buckets[0].objects.push({...object});m.buckets[0].objectCount=2},
  m=>m.buckets[0].objects[0].object='../outside',
  m=>m.buckets[0].objects[0].bucket='other',
  m=>delete m.buckets[0].objects[0].sha256,
 ]){
  const changed=structuredClone(valid);mutate(changed);await save(changed);await assert.rejects(verifyStorageBackup(storage));
 }
 await save(valid);await rm(file);await writeFile(path.join(root,'outside.bin'),'original');await symlink(path.join(root,'outside.bin'),file);await assert.rejects(verifyStorageBackup(storage),/Unsafe/);await rm(file);await writeFile(file,'original');
 await save({buckets:[{id:'files',objects:[{object:'one.bin',size:0}]}]});
 assert.deepEqual(await verifyStorageBackup(storage),{buckets:1,objects:1,checksummedObjects:0,legacyObjects:1},'Old backups remain usable but cannot claim checksum verification');
 await writeFile(file,'');const empty={...object,...await digestFile(file)};
 await save({...valid,buckets:[{id:'files',objectCount:1,objects:[empty]}]});assert.equal((await verifyStorageBackup(storage)).checksummedObjects,1);
 // Exercise the actual downloader with misleading HTTP length metadata, fully offline.
 const stub=path.join(root,'offline-fetch.mjs'),download=path.join(root,'download');
 await writeFile(stub,`globalThis.fetch=async url=>{
 if(url.endsWith('/storage/v1/bucket'))return Response.json([{id:'files',name:'files',public:false}]);
 if(url.endsWith('/storage/v1/object/list/files'))return Response.json([{id:'fixture',name:'one.bin',metadata:{}}]);
 if(url.endsWith('/storage/v1/object/authenticated/files/one.bin'))return new Response('original',{headers:{'content-length':'999','content-type':'application/octet-stream'}});
 throw Error('Unexpected offline request');};`);
 const child=spawnSync(process.execPath,[fileURLToPath(new URL('../scripts/backup/download-supabase-storage.mjs',import.meta.url)),download],{encoding:'utf8',env:{...process.env,SUPABASE_URL:'https://fixture.invalid',SUPABASE_SERVICE_ROLE_KEY:'fixture',NODE_OPTIONS:'--import '+pathToFileURL(stub).href}});
 assert.equal(child.status,0,child.stderr);
 const downloadedManifest=JSON.parse(await readFile(path.join(download,'storage-manifest.json'),'utf8'));
 assert.equal(downloadedManifest.version,2);assert.equal(downloadedManifest.buckets[0].objects[0].size,8);assert.equal(downloadedManifest.buckets[0].objects[0].sha256,object.sha256);
 assert.equal((await verifyStorageBackup(download)).checksummedObjects,1);
 console.log('PASS: backup attachment corruption, truncation, missing files, duplicate/path/count guards, legacy limits, empty files and rejection before any restore API request');
}finally{await rm(root,{recursive:true,force:true});}
