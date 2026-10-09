import assert from 'node:assert/strict';
import {mountMeasurements} from '../assets/js/kpi-measurement-page.mjs';
const nodes=new Map(),named=new Map();let recordButtons=[];
const decode=s=>s.replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&amp;/g,'&');
class Element{
 constructor(){this.value='';this.textContent='';this.hidden=false;this.disabled=false;this.events={};this.markup='';}
 addEventListener(type,fn){this.events[type]=fn;}scrollIntoView(){}
 set innerHTML(html){this.markup=html;if(html.includes('data-measurement'))recordButtons=[];
  for(const m of html.matchAll(/<(input|select|textarea|button|fieldset|form|div|section|span|p)[^>]*>/g)){
   const tag=m[1],attrs=m[0],id=attrs.match(/\bid="([^"]+)"/)?.[1],name=attrs.match(/\bname="([^"]+)"/)?.[1],data=attrs.match(/\bdata-measurement="([^"]+)"/)?.[1];
   if(!id&&!name&&!data)continue;const e=new Element();e.value=decode(attrs.match(/\bvalue="([^"]*)"/)?.[1]||'');
   if(tag==='textarea')e.value=decode(html.slice(m.index+attrs.length).split('</textarea>')[0]);
   if(tag==='select'){const options=html.slice(m.index+attrs.length).split('</select>')[0];e.value=decode(options.match(/<option value="([^"]*)"[^>]*selected/)?.[1]??options.match(/<option value="([^"]*)"/)?.[1]??'');}
   if(id)nodes.set(id,e);if(name)named.set(name,e);if(data){e.dataset={measurement:data};recordButtons.push(e);}
  }
 }get innerHTML(){return this.markup;}
}
const host=new Element();host.querySelector=id=>nodes.get(id.slice(1))||null;host.querySelectorAll=()=>recordButtons;
globalThis.FormData=class{[Symbol.iterator](){return [...named].map(([key,e])=>[key,e.value])[Symbol.iterator]();}};
globalThis.window={AtwarUI:{confirm:async()=>false}};globalThis.location={search:''};
let version=2,fail=false,hold=false,release;const calls=[];
const indicators=[{name:'Original A',target:'95%',weight:25},{name:'Original B',target:'10',weight:75}];
const sb={async rpc(name,args){if(name==='kpi_measurement_context')return {data:{employee:{id:'e',full_name:'Employee'},job:{id:'job',revision:version,indicators:version===2?indicators:[{name:'Changed A'},{name:'Changed B'}]}}};calls.push(args);return fail?{error:{message:'ATWAR_CONFLICT'}}:{data:{id:args.p_id,employee_id:'e',job_description_id:'job',job_revision:args.p_job_revision,indicator_index:args.p_indicator_index,indicator_snapshot:indicators[args.p_indicator_index],revision:1,...args.p_data}};},from(table){return {select(){return this},eq(){return this},is(){return this},order(){return this},async range(){if(hold&&table==='kpi_measurements'){hold=false;await new Promise(r=>release=r);}return {data:[],error:null};}};}};
const controller=await mountMeasurements({sb,employeeId:'e',host});
await nodes.get('kmNew').onclick();named.get('result_text').value='draft result';named.get('period_start').value='2026-10-01';named.get('period_end').value='2026-10-31';nodes.get('kmForm').events.input();
version=3;await controller.refresh();assert.equal(named.get('result_text').value,'draft result','Refreshing history must preserve draft input');
nodes.get('kmIndicator').value='1';nodes.get('kmIndicator').onchange();assert.match(nodes.get('kmIndicatorDetails').innerHTML,/Original B/,'A draft retains the published definition selected at opening');
fail=true;await nodes.get('kmForm').onsubmit({preventDefault(){}});assert.equal(calls[0].p_job_revision,2);assert.equal(calls[0].p_indicator_index,1);assert.equal(named.get('result_text').value,'draft result');assert.match(nodes.get('kmFormStatus').textContent,/تغيّر/);assert.equal(nodes.get('kmFields').disabled,false);
hold=true;const pending=controller.refresh();await new Promise(r=>setImmediate(r));const before=calls.length;await nodes.get('kmForm').onsubmit({preventDefault(){}});assert.equal(calls.length,before,'A refresh in flight must not race a save');release();await pending;
fail=false;await nodes.get('kmForm').onsubmit({preventDefault(){}});assert.equal(nodes.get('kmEditor').hidden,true);assert.match(nodes.get('kmStatus').textContent,/تم حفظ/);assert.match(nodes.get('kmRows').innerHTML,/draft result/);
console.log('KPI measurement controller: preserved drafts/definitions, version payload, conflict recovery, save-refresh exclusion and form close passed');
