import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import {createRunControl,stopMessage} from '../assets/js/performance-probe.mjs';
const control=createRunControl(360);control.resize(360);assert.equal(control.reason,null);control.resize(360.5);assert.equal(control.reason,null);control.resize(412);control.stop('user-stop');assert.equal(control.reason,'viewport-changed');
assert.match(stopMessage(control.reason),/عرض الصفحة/);
const source=(await readFile('assets/js/performance-probe.mjs','utf8')).replaceAll('export ','');
async function scenario(mode){
 let now=0,sequence=0,loads=0,hooked=false;const timers=[],listeners=new Map(),nodes=new Map();
 const node=()=>({textContent:'',disabled:false,value:'android-device',clientWidth:312,clientHeight:540,children:[],append(x){this.children.push(x)},replaceChildren(...x){this.children=x}});
 for(const id of ['probe','start','stop','cohort','download','results','report','status'])nodes.set(id,node());
 const frame=nodes.get('probe');let current=null;
 Object.defineProperty(frame,'src',{set(url){if(url==='about:blank'){current=null;return;}loads++;const path=new URL(url).pathname;current={body:{},location:{pathname:path},documentElement:{dataset:{taskMeasureState:'ready'}},querySelector(selector){return ({'.atwar-data-status':{hidden:true,querySelector:()=>({disabled:false})},'#appShell':{classList:{contains:()=>false}},'#spaceSync':{textContent:'محدّث الآن · تحديث تلقائي'}})[selector]||null;}};}});
 Object.defineProperty(frame,'contentDocument',{get(){return current}});
 const ctx=vm.createContext({console,URL,Blob,document:{hidden:false,getElementById:id=>nodes.get(id),createElement:node},location:{href:'https://fixture.invalid/lab/performance.html',origin:'https://fixture.invalid'},innerWidth:360,innerHeight:716,performance:{now:()=>now},setTimeout(fn,ms){timers.push({fn,at:now+ms,id:sequence++});return sequence;},requestAnimationFrame(fn){timers.push({fn,at:now+16,id:sequence++});},addEventListener:(name,fn)=>listeners.set(name,fn),removeEventListener:name=>listeners.delete(name)});
 vm.runInContext(source,ctx);
 let done=false,error;nodes.get('start').onclick().then(()=>done=true,e=>{error=e;done=true;});
 for(let i=0;i<10000&&!done;i++){
  await Promise.resolve();await Promise.resolve();await Promise.resolve();
  if(!hooked&&loads===10){
   hooked=true;
   if(mode==='height'){ctx.innerHeight=620;listeners.get('resize')();}
   if(mode==='width'){ctx.innerWidth=412;listeners.get('resize')();}
   if(mode==='stop')nodes.get('stop').onclick();
  }
  timers.sort((a,b)=>a.at-b.at||a.id-b.id);const next=timers.shift();if(next){now=next.at;next.fn();}
 }
 assert.ok(done,'synthetic run must terminate');if(error)throw error;
 assert.ok(!listeners.has('resize'),'listener removed');assert.equal(nodes.get('start').disabled,false);
 return JSON.parse(nodes.get('report').textContent);
}
const height=await scenario('height');assert.equal(height.complete,true);assert.equal(Object.values(height.pages).reduce((n,p)=>n+p.samples.length,0),90);assert.equal(height.stop_reason,undefined);
for(const [mode,reason] of [['width','viewport-changed'],['stop','user-stop']]){const r=await scenario(mode);assert.equal(r.complete,false);assert.equal(r.stop_reason,reason);assert.ok(r.interruptions.some(x=>x.state===reason));assert.ok(Object.values(r.pages).every(p=>p.samples.every(s=>s.state==='ready')),'interruptions are not data failures');}
console.log('PASS actual runner: mobile height-only resize completes 90 synthetic samples; width/manual stop preserve cause and partial evidence. No browser, backend or external requests.');
