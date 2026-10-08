import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {createRefreshCoordinator,createSharedInFlightReads} from '../assets/js/supabase-sync.mjs';
const source=readFileSync(new URL('../assets/js/supabase-firebase-compat.js',import.meta.url),'utf8').replace(/^import .*;\n/m,'').replace(/export /g,'');
let offlineRead=false,offlineChild=false,offlineWrite=false,conflict=false,writeCalls=0;
let row={id:'test-task',title:'Test',description:'original',notes:'retained',revision:1,status:'قيد الانتظار',creator_id:'user',assignee_id:'user'};
const child=[{id:'child',task_id:'test-task',title:'Existing child',done:false}];
const networkError=()=>new TypeError('Failed to fetch');
const sb={
 from(table){const q={};for(const name of ['select','is','eq','neq','in','order','or'])q[name]=()=>q;
 q.then=(yes,no)=>Promise.resolve().then(()=>{
  if(offlineRead)throw networkError();
  if(table==='subtasks'&&offlineChild)return {data:null,error:networkError()};
  return {data:table==='tasks'?[structuredClone(row)]:table==='subtasks'?structuredClone(child):[],error:null};
 }).then(yes,no);return q;},
 async rpc(name,args){writeCalls++;if(offlineWrite)throw networkError();
  if(conflict){conflict=false;row.notes='other user note';row.revision++;return {data:null,error:new Error('ATWAR_CONFLICT: task changed')};}
  assert.equal(args.p_expected_revision,row.revision);
  Object.assign(row,args.p_patch,{revision:row.revision+1});return {data:structuredClone(row),error:null};},
 functions:{invoke:async()=>({error:null})}
};
const onlineHandlers=new Set(),visibilityHandlers=new Set();
const document={visibilityState:'visible',addEventListener:(_,fn)=>visibilityHandlers.add(fn),removeEventListener:(_,fn)=>visibilityHandlers.delete(fn)};
let channelStatus,timerCallback,clock=0;
class TestDate extends Date {static now(){return clock;}}
sb.channel=()=>({on(){return this},subscribe(fn){channelStatus=fn;fn('SUBSCRIBED');return this}});
const ctx={Date:TestDate,document,setInterval:(fn,ms)=>{assert.equal(ms,15000);timerCallback=fn;return 1},clearInterval:()=>{timerCallback=null},window:{atwarGetSupabase:async()=>sb,addEventListener:(_,fn)=>onlineHandlers.add(fn),removeEventListener:(_,fn)=>onlineHandlers.delete(fn)},location:{pathname:'/tasks/index.html',search:''},URLSearchParams,structuredClone,createRefreshCoordinator,createSharedInFlightReads,console,crypto:globalThis.crypto};
const bridge=await vm.runInNewContext(`(async()=>{${source}\nreturn {runTransaction,onValue};})()`,ctx);
const ref={path:'tasksByUser/user/test-task'};
const edit=task=>({...task,desc:'saved after reconnect'});
offlineRead=true;await assert.rejects(bridge.runTransaction(ref,edit),/Failed to fetch/);assert.equal(writeCalls,0);
offlineRead=false;offlineChild=true;await assert.rejects(bridge.runTransaction(ref,edit),/Failed to fetch/);assert.equal(writeCalls,0,'A failed subtask read must block writing an empty collection');
offlineChild=false;offlineWrite=true;await assert.rejects(bridge.runTransaction(ref,edit),/Failed to fetch/);assert.equal(row.description,'original');assert.equal(writeCalls,1,'Transport errors must not automatically duplicate writes');
offlineWrite=false;const recovered=await bridge.runTransaction(ref,edit);assert.equal(recovered.committed,true);assert.equal(row.description,'saved after reconnect');assert.equal(recovered.snapshot.val().subtasks.length,1);
conflict=true;const concurrent=await bridge.runTransaction(ref,t=>({...t,desc:'local edit after conflict'}));assert.equal(concurrent.committed,true);assert.equal(row.notes,'other user note','Retry must retain changes to unrelated fields');assert.equal(row.description,'local edit after conflict');
// 28 simultaneous subscribers share one network read; an outage is not cached.
const shared=createSharedInFlightReads();let reads=0;let release;
const pending=Array.from({length:28},()=>shared.read('same-task-scope',()=>{reads++;return new Promise(resolve=>{release=resolve;});}));
await Promise.resolve();assert.equal(reads,1);release('fresh');assert.equal((await Promise.all(pending)).length,28);
await assert.rejects(shared.read('same-task-scope',()=>Promise.reject(networkError())),/Failed to fetch/);
assert.equal(await shared.read('same-task-scope',()=> 'reconnected'),'reconnected');
console.log('Real bridge: offline reads/writes reject, child-read failures block destructive saves, reconnect recovers, conflict retry preserves unrelated edits, 28 consumers coalesce.');

// Exercise reconnect events through the actual bridge subscription lifecycle.
const delivered=[],errors=[];
const settle=async()=>{for(let i=0;i<8;i++)await new Promise(resolve=>setImmediate(resolve));};
const stop=bridge.onValue(ref,snapshot=>delivered.push(snapshot.val().title),error=>errors.push(error.message));
await settle();assert.deepEqual(delivered,['Test']);
offlineRead=true;for(const refresh of onlineHandlers)refresh();await settle();
assert.deepEqual(delivered,['Test'],'A failed refresh must retain the last displayed snapshot');
assert.deepEqual(errors,['Failed to fetch']);
offlineRead=false;row.title='updated while disconnected';
for(const refresh of onlineHandlers)refresh();await settle();
assert.deepEqual(delivered,['Test','updated while disconnected'],'Returning online must refresh without waiting for polling');
document.visibilityState='hidden';row.title='hidden change';
for(const refresh of onlineHandlers)refresh();await settle();assert.equal(delivered.length,2);
document.visibilityState='visible';for(const refresh of visibilityHandlers)refresh();await settle();
assert.equal(delivered.at(-1),'hidden change');
row.title='missed realtime update';channelStatus('CHANNEL_ERROR');
clock+=15000;timerCallback();await settle();assert.equal(delivered.at(-1),'missed realtime update');
row.title='reconnected channel';channelStatus('SUBSCRIBED');await settle();
assert.equal(delivered.at(-1),'reconnected channel','Subscription recovery must reload missed changes');
row.title='healthy polling';clock+=15000;timerCallback();await settle();
assert.equal(delivered.at(-1),'reconnected channel','Healthy channels must retain the slower polling interval');
clock+=120000;timerCallback();await settle();assert.equal(delivered.at(-1),'healthy polling');
stop();assert.equal(timerCallback,null);assert.equal(onlineHandlers.size,0);assert.equal(visibilityHandlers.size,0);
console.log('Actual bridge subscriptions: online recovery, retained data on failure, hidden-tab recovery and listener cleanup passed.');
