import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import {readRelatedRows} from '../assets/js/paged-related-read.mjs';
const flush=async()=>{for(let i=0;i<25;i++)await Promise.resolve();};
// Real batching helper: bounded concurrent calls, deterministic ordering and complete error propagation.
let pending=[],active=0,max=0;const calls=[];
const keys=Array.from({length:251},(_,i)=>String(i));
const result=readRelatedRows(chunk=>{calls.push(chunk);active++;max=Math.max(max,active);return new Promise(resolve=>pending.push(()=>{active--;resolve({data:chunk.map(id=>({id})),error:null});}));},keys,{concurrency:2,paged:false});
await flush();assert.equal(calls.length,2);assert.equal(max,2);pending.reverse().splice(0).forEach(fn=>fn());await flush();assert.equal(calls.length,3);pending.splice(0).forEach(fn=>fn());
assert.deepEqual((await result).map(r=>r.id),keys);assert(calls.every(ids=>ids.length<=100));
await assert.rejects(readRelatedRows(async()=>({error:Error('denied')}),keys,{concurrency:2,paged:false}),/denied/);
let serial=0,serialGate;const serialRead=readRelatedRows(chunk=>{serial++;return new Promise(resolve=>{serialGate=()=>resolve({data:chunk,error:null});});},['a','b'],{chunkSize:1,paged:false});
await flush();assert.equal(serial,1);serialGate();await flush();assert.equal(serial,2);serialGate();await serialRead;
const compat=await readFile(new URL('../assets/js/supabase-firebase-compat.js',import.meta.url),'utf8');
let childrenStarted=false,releaseNames;
const nameResponse=new Promise(resolve=>releaseNames=resolve);
const q={select(){return this},in(){return this},then(a,b){return nameResponse.then(a,b)}};
const scope={location:{pathname:'/tasks/index.html',search:''},URLSearchParams,readAllRows:async()=>[{id:'t',assignee_id:'u'}],sb:{from:()=>q},loadChildren:async()=>{childrenStarted=true;return {};},taskLegacy:(t,c,n)=>({id:t.id,name:n.get('u')})};
vm.createContext(scope);vm.runInContext(compat.slice(compat.indexOf('async function visibleTasks('),compat.indexOf('export async function get(')),scope);
const visible=scope.visibleTasks();await flush();assert(childrenStarted,'Children start while name read is still pending');releaseNames({data:[{id:'u',full_name:'Fixture'}]});assert.equal((await visible)[0].name,'Fixture');
// Execute the actual auth startup block; counts must not block subscribing to task data.
const taskSource=await readFile(new URL('../assets/js/tasks-page.js',import.meta.url),'utf8');
let releaseCounts,subscribed=false;const counts=new Promise(resolve=>releaseCounts=resolve);
const start=taskSource.slice(taskSource.indexOf('    const countsReady=refreshCompletedTaskCounts();'),taskSource.indexOf('    subscribeNotifications();'));
vm.runInNewContext(start,{refreshCompletedTaskCounts:()=>counts,subscribeVisibleTasks:p=>{assert.equal(p,counts);subscribed=true;}});assert(subscribed);
const markerBody=taskSource.slice(taskSource.indexOf('  clearTaskListeners();',taskSource.indexOf('function subscribeVisibleTasks(')),taskSource.indexOf('  const ownerData=',taskSource.indexOf('function subscribeVisibleTasks(')));
const markerDoc={documentElement:{dataset:{}}};
const marker=vm.runInNewContext(`(()=>{${markerBody};return {markReady,fail(){measureFailed=true;document.documentElement.dataset.taskMeasureState='error'}};})()`,{clearTaskListeners(){},document:markerDoc,currentUser:{uid:'me'},countsReady:counts});
marker.markReady();await flush();assert.equal(markerDoc.documentElement.dataset.taskMeasureState,'pending');releaseCounts();await flush();assert.equal(markerDoc.documentElement.dataset.taskMeasureState,'ready');marker.fail();marker.markReady();await flush();assert.equal(markerDoc.documentElement.dataset.taskMeasureState,'error');
// Actual workspace orchestration: auxiliary panels overlap main reads, but readiness still waits for both.
const workspace=(await readFile(new URL('../assets/js/workspace-page.mjs',import.meta.url),'utf8')).replace(/^import .*;\n/gm,'').replaceAll('export ','');
for(const role of ['admin','employee']){
 const nodes=new Map();const node=id=>{if(!nodes.has(id))nodes.set(id,{textContent:'',innerHTML:'',hidden:false,addEventListener(){}});return nodes.get(id)};
 let aux=0,releasePanels;const panels=new Promise(resolve=>releasePanels=resolve);
 const query={select(){return this},range(){return this},order(){return this},is(){return this},eq(){return this},limit(){return this},then(a,b){return Promise.resolve({data:[],error:null}).then(a,b)}};
 const context=vm.createContext({document:{hidden:false,getElementById:node,querySelectorAll:()=>[],addEventListener(){}},window:{},addEventListener(){},setInterval:()=>1,clearInterval(){},console,
 mountJobFollowup:()=>{aux++;return panels},mountApprovalSettings:()=>{aux++;return panels},workspaceModel:()=>({due:[],decisions:[],projects:[],day:'2026-10-31'}),renderWorkspace:()=>({}),requestModel:()=>({replaced:new Set(),actions:[],tracking:[]}),actionInbox:()=>[],filterActionInbox:()=>[],renderActionInbox:()=>'',renderRequests:()=>'',workspaceBriefing:()=>({waiting:[],upcoming:[],blockers:[]}),renderBriefing:()=>({}),managementBriefing:()=>({}),renderManagementBriefing:()=>''});
 vm.runInContext(workspace,context);const mounted=context.mountWorkspace({from:()=>query},{id:'me',role});assert.equal(aux,role==='admin'?2:0);await flush();
 if(role==='admin'){assert(!node('spaceSync').textContent.startsWith('محدّث الآن'),'Do not fake readiness before panels finish');releasePanels();}
 await mounted;assert(node('spaceSync').textContent.startsWith('محدّث الآن'));
}
console.log('PASS real loading code: bounded 100-ID reads, preserved ordering/errors, overlapping child/name/count/panel reads, role boundaries and readiness waits. No external traffic.');
