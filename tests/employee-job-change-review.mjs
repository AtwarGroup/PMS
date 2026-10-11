import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const source=readFileSync(new URL('../assets/js/employee-job-changes.js',import.meta.url),'utf8').replaceAll('export ','');
const context=vm.createContext({document:{createElement:()=>({}),head:{append(){}}},window:{},location:{search:''},URLSearchParams});
vm.runInContext(source,context);
const requests=[{id:'manager-pending',manager_id:'manager',status:'MANAGER_REVIEW',section:'KPIS',action:'MODIFY',original_value:{name:'مؤشر قديم'},proposed_value:{name:'مؤشر جديد'},reason:'مراجعة المؤشر',published_revision:1},{id:'unchanged',status:'ADMIN_REVIEW',section:'PURPOSE',action:'MODIFY',original_value:'الغرض الحالي',proposed_value:' الغرض الحالي ',reason:'ملاحظات دون تعديل',published_revision:1}];
const sb={from(table){return {select(){return this},order(){return Promise.resolve({data:requests})},in(){return Promise.resolve({data:[{id:'manager',full_name:'المدير المسؤول'}]})}}}};
async function render(profile){const host={innerHTML:'',querySelectorAll:()=>[]};await context.mountChangeReview(host,{sb,profile,embedded:true});return host.innerHTML;}
function article(html,id){return html.split(`data-request="${id}"`)[1].split('</article>')[0];}
const admin=await render({id:'admin',role:'admin'});
assert.match(article(admin,'manager-pending'),/الإجراء الحالي لدى المدير المسؤول/);
assert.doesNotMatch(article(admin,'manager-pending'),/data-decision=/);
assert.match(article(admin,'unchanged'),/لا يوجد تغيير في نص البند المقترح/);
assert.match(article(admin,'unchanged'),/data-decision="true" disabled/);
assert.match(article(admin,'unchanged'),/data-decision="false"/);
const manager=await render({id:'manager',role:'manager'});
assert.match(article(manager,'manager-pending'),/data-decision="true" >/);
assert.doesNotMatch(article(manager,'unchanged'),/data-decision=/);
console.log('PASS: assigned manager actions, admin stage isolation, unchanged proposal warning and rejection availability.');
// Verify that an unchanged submission cannot create a request or workflow task.
context.crypto={randomUUID:()=> 'request-key'};
const fields={section:{value:'PURPOSE'},action:{value:'MODIFY',options:[]},index:{value:'0'},text:{value:'',focus(){}},reason:{value:'سبب المراجعة'}};
const button={disabled:false},status={textContent:''};
const form={elements:fields,reportValidity:()=>true,querySelector:()=>button};
const nodes={'form':form,'[data-change-status]':status,'[data-item-label]':{},'[data-text-label]':{},'[data-original]':{},'[data-change-history]':{}};
const host={innerHTML:'',querySelector:s=>nodes[s]};
let submitted=0;
const submitSB={from(){return {select(){return this},eq(){return this},order(){return Promise.resolve({data:[]})}}},rpc:async(name,payload)=>{submitted++;assert.equal(payload.p_section,'PURPOSE');assert.equal(payload.p_text,'غرض معدل');return {data:'request',error:null}}};
await context.mountEmployeeChanges(host,{sb:submitSB,profile:{id:'employee'},job:{id:'job',published_snapshot:{revision:1,purpose:'الغرض الحالي',content:{}}}});
await form.onsubmit({preventDefault(){}});
assert.equal(submitted,0);
assert.match(status.textContent,/لم يتغير نص البند/);
fields.text.value='غرض معدل';
await form.onsubmit({preventDefault(){}});
assert.equal(submitted,1);
console.log('PASS: unchanged submission blocked before RPC; actual change submitted.');
