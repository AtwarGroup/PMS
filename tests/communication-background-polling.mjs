import assert from 'node:assert/strict';
const windowEvents=new EventTarget(),documentEvents=new EventTarget();let tick,reads=0,claims=0,presence=0;
globalThis.window=windowEvents;globalThis.document=documentEvents;Object.assign(document,{readyState:'complete',hidden:false,querySelectorAll:()=>[],querySelector:()=>null});
const nativeInterval=globalThis.setInterval,nativeClear=globalThis.clearInterval;
globalThis.setInterval=f=>(tick=f,1);globalThis.clearInterval=()=>{};
const sb={auth:{getUser:async()=>({data:{user:{id:'employee'}}}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})},rpc:async()=>({data:true}),
functions:{invoke:async(n,{body})=>{if(body.data.action==='presence')presence++;else claims++;return{data:{show:false}}}},
from:()=>({select(){return this},eq(){return this},is(){return this},order(){return this},limit(){reads++;return Promise.resolve({data:[{id:'already-delivered'}]})}}),
channel:()=>({on(){return this},subscribe(){return this}}),removeChannel:async()=>{}};
window.atwarGetSupabase=async()=>sb;
try{const {startCommunicationAlerts}=await import('../assets/js/communication-global.mjs');await startCommunicationAlerts();assert.equal(claims,1);
 const settle=async()=>{for(let n=0;n<8;n++)await new Promise(r=>setImmediate(r))};
 tick();await settle();assert.equal(claims,1,'already-claimed unread alert called server again');
 const oldReads=reads,oldPresence=presence;document.hidden=true;tick();await settle();assert.equal(reads,oldReads);assert.equal(presence,oldPresence,'hidden tab sent heartbeat');
 document.hidden=false;document.dispatchEvent(new Event('visibilitychange'));await settle();assert.equal(reads,oldReads+1);assert.equal(claims,1);
 window.dispatchEvent(new Event('pagehide'));console.log('PASS background polling: handled notifications claimed once, hidden tabs suspend requests, visibility restores refresh');
}finally{globalThis.setInterval=nativeInterval;globalThis.clearInterval=nativeClear;}
