import assert from 'node:assert/strict';
import {createTaskAttachmentsController} from '../assets/js/task-attachments.mjs';
let calls=[],timers=[],changed=0,events={},fail=false;
const original={setTimeout,clearTimeout,addEventListener:globalThis.addEventListener};globalThis.setTimeout=fn=>(timers.push(fn),timers.length);globalThis.clearTimeout=()=>{};globalThis.addEventListener=(n,fn)=>events[n]=fn;
try{
 const controller=createTaskAttachmentsController({getSupabase:async()=>({functions:{invoke:async(n,{body})=>{calls.push({n,body});return fail?{error:new Error('offline')}:{data:{pending:body.id?1:0}};}}}),getCurrentUser:()=>({uid:'user'}),getSelectedTask:()=>({attachments:[{id:'file',fileName:'name',storagePath:'do-not-trust-client'}]}),getCurrentProfile:()=>({role:'employee'}),confirmAction:async()=>true,toast:()=>{},onChanged:async()=>changed++});
 await new Promise(r=>setImmediate(r));await controller.remove('file');assert.equal(changed,1);assert.deepEqual(calls.at(-1).body,{id:'file'});assert.equal(timers.length,1);await timers[0]();assert.deepEqual(calls.at(-1).body,{retry:true});
 fail=true;await controller.remove('file');assert.equal(changed,1,'Failed request cannot report removal');
}finally{Object.assign(globalThis,original);}
console.log('Attachment deletion uses authenticated server queue, retries pending cleanup and does not trust client paths or report failed deletion as success');
