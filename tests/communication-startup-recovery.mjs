import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {withReadTimeout} from '../communication/read-timeout.mjs';
const source=readFileSync(new URL('../communication/app.mjs',import.meta.url),'utf8');
const start=source.slice(source.indexOf('let startingCommunication=false;'),source.indexOf('\ninitializeCommunication();'));
function harness(){
 const nodes={account:{value:'',innerHTML:''}},counts={calls:0,connect:0,sync:0},handlers={};
 const context=vm.createContext({nodes,counts,handlers,navigator:{onLine:true},innerWidth:1000,
 setInterval:f=>handlers.tick=f,window:{addEventListener:(event,f)=>handlers[event]=f},
 document:{hidden:false,querySelector:()=>null},CSS:{escape:x=>x}});
 vm.runInContext(`let state=null,active=null,notificationTarget=null,threadRoot=null,failed=true,pending=null;
 const $=id=>nodes[id],esc=x=>x,status=()=>{},notice=()=>{},selectConversation=()=>{},heartbeat=()=>{},openThread=()=>{},renderMessages=()=>{},flush=()=>{},markRead=()=>{};
 async function api(){counts.calls++;if(pending)await pending;if(failed)throw Error('temporary failure');return [{id:'test',name:'Test'}];}
 async function sync(){counts.sync++;state={me:{id:'test'},messages:[]};active='A';}
 function connect(){counts.connect++;}
 `+start,context);
 for(const line of source.split('\n').filter(x=>x.startsWith("window.addEventListener('online'")||x.startsWith('setInterval(()=>{if(!navigator.onLine)')))vm.runInContext(line,context);
 return {context,counts,handlers,start:()=>vm.runInContext('initializeCommunication()',context),recover:()=>vm.runInContext('failed=false',context)};
}
{
 const h=harness();await h.start();assert.equal(h.counts.connect,0);h.recover();await h.start();assert.equal(h.counts.connect,1);assert.equal(h.counts.calls,2);await h.start();assert.equal(h.counts.calls,2);
}
{
 const h=harness();await h.start();h.recover();h.handlers.tick();await new Promise(r=>setImmediate(r));assert.equal(h.counts.connect,1);
}
{
 const h=harness();await h.start();h.recover();h.handlers.online();await new Promise(r=>setImmediate(r));assert.equal(h.counts.connect,1);
}
{
 const h=harness();h.recover();let release;h.context.pending=new Promise(r=>release=r);const first=h.start();await h.start();assert.equal(h.counts.calls,1);release();await first;assert.equal(h.counts.connect,1);
}
{
 const h=harness();h.context.navigator.onLine=false;await h.start();h.handlers.tick();assert.equal(h.counts.calls,0);
}
assert.equal(await withReadTimeout(Promise.resolve('ok'),20),'ok');
await assert.rejects(withReadTimeout(new Promise(()=>{}),5),/تأخر الاتصال/);
await assert.rejects(withReadTimeout(Promise.reject(Error('failure')),20),/failure/);
console.log('PASS startup recovery: transient failure, periodic retry, online recovery, single-flight, offline guard, bounded reads');
