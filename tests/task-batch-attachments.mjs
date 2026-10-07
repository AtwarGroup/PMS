import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {createTaskAttachmentsController} from '../assets/js/task-attachments.mjs';
const calls=[];
const task={attachments:[{id:'shared',sharedBatch:true,storageBucket:'task-batch-attachments',storagePath:'owner/batch/file',fileName:'تعليمات'},{id:'personal',storagePath:'task/file',fileName:'إنجاز'}]};
const originalOpen=globalThis.open;
globalThis.open=(...args)=>calls.push(['open',...args]);
try {
 const controller=createTaskAttachmentsController({getSupabase:async()=>({storage:{from(bucket){return {async createSignedUrl(path){calls.push(['sign',bucket,path]);return {data:{signedUrl:'https://example.invalid/signed'}};}};}}}),getSelectedTask:()=>task,getCurrentUser:()=>({uid:'owner'}),getCurrentProfile:()=>({role:'admin'}),confirmAction:async()=>{throw Error('Shared file deletion must stop before confirmation');},toast:()=>{}});
 await controller.remove('shared');
 await controller.open('shared');
 await controller.open('personal');
 assert.deepEqual(calls.filter(c=>c[0]==='sign'),[['sign','task-batch-attachments','owner/batch/file'],['sign','task-attachments','task/file']]);
} finally {globalThis.open=originalOpen;}
const source=readFileSync('assets/js/supabase-firebase-compat.js','utf8');
let failShared=false;
const context=vm.createContext({ms:()=>1,sb:{from(table){const result={error:table==='task_batch_attachments'&&failShared?new Error('Access failed'):null,data:table==='task_batch_attachments'?[{id:'shared',batch_id:'batch-a',file_name:'تعليمات',storage_path:'owner/batch/file',size_bytes:10}]:[]};return {select(){return this;},in(){return this;},order(){return this;},then(resolve){return Promise.resolve(result).then(resolve);}};}}});
vm.runInContext(source.slice(source.indexOf('async function loadChildren('),source.indexOf('function taskLegacy(')),context);
const children=await context.loadChildren(['task-a','task-b','task-c'],[{id:'task-a',batch_id:'batch-a'},{id:'task-b',batch_id:'batch-a'},{id:'task-c'}]);
assert.equal(children.attachments.get('task-a')[0].sharedBatch,true);
assert.equal(children.attachments.get('task-b')[0].storageBucket,'task-batch-attachments');
assert.equal(children.attachments.has('task-c'),false,'An unrelated task must not inherit shared files');
failShared=true;
await assert.rejects(()=>context.loadChildren(['task-a'],[{id:'task-a',batch_id:'batch-a'}]),/Access failed/);
console.log('Shared files use the private batch bucket, cannot be deleted through personal task controls, remain batch scoped, and failed reads are surfaced.');
