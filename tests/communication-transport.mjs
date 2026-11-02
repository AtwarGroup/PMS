import assert from 'node:assert/strict';
import {invokeCommunication}from '../communication/transport.mjs';
const pause=()=>Promise.resolve();
function harness(responses){const calls=[];return {calls,sb:{functions:{invoke:async(name,opts)=>{calls.push({name,opts});const response=responses.shift();return typeof response==='function'?response(opts):response;}}}};}
const unavailable=()=>({error:{message:'Function error',context:new Response(JSON.stringify({error:'temporary'}),{status:503})}});
{
 const h=harness([{error:new Error('Failed to send a request to the Edge Function')},{data:{ok:true}}]);
 assert.deepEqual(await invokeCommunication(h.sb,'state',{}, {wait:pause}),{ok:true});assert.equal(h.calls.length,2);assert(h.calls[0].opts.signal instanceof AbortSignal);
}
{
 const data={action:'message',data:{clientId:'stable-client-123',body:'رسالة',file:{base64:'ZmlsZQ=='}}},h=harness([unavailable(),{data:{id:'original'}}]);
 assert.deepEqual(await invokeCommunication(h.sb,'action',data,{wait:pause}),{id:'original'});assert.deepEqual(h.calls[0].opts.body,h.calls[1].opts.body,'retry changed message identity or attachment');
}
{
 const h=harness([unavailable()]);await assert.rejects(invokeCommunication(h.sb,'action',{action:'react'},{wait:pause}));assert.equal(h.calls.length,1,'toggle retried');
}
{
 const h=harness([{error:{context:new Response(JSON.stringify({error:'غير مخول'}),{status:403})}}]);await assert.rejects(invokeCommunication(h.sb,'file',{}, {wait:pause}),e=>e.status===403&&e.message==='غير مخول');assert.equal(h.calls.length,1);
}
{
 const h=harness([{error:new Error('network')},{error:new Error('network')}]);await assert.rejects(invokeCommunication(h.sb,'state',{}, {wait:pause}),/تعذر الاتصال بخدمة المحادثات/);assert.equal(h.calls.length,2);
}
{
 const h=harness([opts=>new Promise(resolve=>opts.signal.addEventListener('abort',()=>resolve({error:new Error('aborted')}),{once:true}))]);
 await assert.rejects(invokeCommunication(h.sb,'state',{}, {timeoutMs:8,wait:pause}),/تأخر الاتصال/);assert.equal(h.calls.length,1,'timed-out request exceeded its total budget');assert(h.calls[0].opts.signal.aborted);
}
console.log('PASS communication transport: transient recovery, same message/file identity, no toggle retry, permission denial, Arabic errors and actual cancellation within one total deadline');
