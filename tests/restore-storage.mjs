import assert from 'node:assert/strict';
import {mkdtemp,writeFile,mkdir,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {restoreStorage,backupMime} from '../scripts/backup/restore-storage.mjs';
const root=await mkdtemp(join(tmpdir(),'atwar-storage-test-'));
try{
 assert.equal(backupMime({object:'opaque-id'},Buffer.from('%PDF-1.7'),{}),'application/pdf');
 assert.equal(backupMime({object:'report.xlsx'},Buffer.from('zip'),{}),'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
 await mkdir(join(root,'private-files'));await writeFile(join(root,'private-files','x.pdf'),'PDF fixture');
 const manifest={buckets:[{id:'private-files',name:'private-files',public:false,objects:[{object:'x.pdf'}]}]};await writeFile(join(root,'storage-manifest.json'),JSON.stringify(manifest));
 let stored,corrupt=false;
 const fetchImpl=async(url,options)=>{if(url.endsWith('/bucket'))return new Response(JSON.stringify(options.method?{}:[]));if(options.method==='POST'){stored=options.body;return new Response('{}');}return new Response(corrupt?'corrupted':stored)};
 const args={origin:'https://restore.example.test',sourceOrigin:'https://production.example.test',key:'isolated',directory:root,fetchImpl};
 assert.equal((await restoreStorage(args)).objects,1);
 corrupt=true;await assert.rejects(restoreStorage(args),/checksum/);
 await assert.rejects(restoreStorage({...args,origin:args.sourceOrigin}),/production/);
 manifest.buckets[0].objects=[{object:'../escape'}];await writeFile(join(root,'storage-manifest.json'),JSON.stringify(manifest));await assert.rejects(restoreStorage(args),/Unsafe/);
}finally{await rm(root,{recursive:true,force:true});}
console.log('PASS: restore attachment upload/download checksum, same-production denial and path traversal denial');
