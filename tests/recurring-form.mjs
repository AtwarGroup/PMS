import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import * as core from '../assets/js/recurrence-core.mjs';
const html=fs.readFileSync(new URL('../recurring/index.html',import.meta.url),'utf8');
const nodes=new Map();
class Node{
 constructor(value=''){this.value=value;this.hidden=false;this.checked=false;this.dataset={};this.classList={toggle(){}};this.listeners={};this.options=[];}
 addEventListener(type,fn){this.listeners[type]=fn;}
 setAttribute(){} scrollIntoView(){} focus(){} showModal(){this.open=true;} close(){this.open=false;}
}
for(const match of html.matchAll(/<(input|select|button|div|h2|strong|p|fieldset|legend|dialog|span)[^>]*\bid="([^"]+)"[^>]*>/g)){
 const [,tag,id]=match;let value=match[0].match(/\bvalue="([^"]*)"/)?.[1]||'';
 if(tag==='select')value=html.slice(match.index).split('</select>')[0].match(/<option value="([^"]*)"/)?.[1]||'';
 nodes.set(id,new Node(value));
}
const days=Array.from({length:7},(_,i)=>{const n=new Node(String(i));return n;});
const editButton=new Node();editButton.dataset.id='existing';
const doc={getElementById:id=>{assert(nodes.has(id),'Missing '+id);return nodes.get(id);},querySelectorAll:q=>q==='[name="repeatDay"]'?days:q==='[name="repeatDay"]:checked'?days.filter(x=>x.checked):q==='.edit'?[editButton]:[]};
const me={id:'manager',role:'manager',full_name:'مدير'};
const people=[me,{id:'employee',full_name:'موظف',manager_id:'manager'}];
const rows=[{id:'ended',title:'انتهى',assignee_id:'employee',recurrence:'daily',interval_count:1,active:false,created_count:2,next_run_at:'2030-01-01T06:00:00Z',recurrence_rule:{mode:'calendar',pattern:'day',endMode:'count',endCount:2}}, {id:'existing',title:'دورية محفوظة',description:'',assignee_id:'employee',priority:'normal',recurrence:'monthly',interval_count:1,next_run_at:'2030-02-28T06:00:00Z',schedule_start_at:'2030-01-31T06:00:00Z',due_offset_days:3,active:true,created_count:0,waiting_for_completion:false,recurrence_rule:{mode:'calendar',pattern:'day',day:31,endMode:'never',days:[]}}];
let inserted=null,updated=null;
function query(table){let op='select';const q={
 select(){return q;},eq(){return q;},order(){return q;},single(){return Promise.resolve({data:me});},maybeSingle(){return Promise.resolve({data:{id:'existing'}});},
 insert(payload){op='insert';inserted=payload;return q;},update(payload){op='update';updated=payload;return q;},
 then(resolve,reject){return Promise.resolve({data:op==='select'?(table==='profiles'?people:rows):null}).then(resolve,reject);}
};return q;}
const sb={from:query,auth:{getSession:async()=>({data:{session:{user:{id:'manager'}}}})}};
const context=vm.createContext({...core,document:doc,window:{atwarGetSupabase:async()=>sb,AtwarUI:{toast(){}}},localStorage:{getItem(){return null;},setItem(){}},location:{},lucide:{createIcons(){}},console,Date,Intl,setTimeout});
let script=html.split('<script type="module">')[1].split('</script>')[0].replace(/import .*?;\n/,'');
await vm.runInContext('(async()=>{'+script+'})()',context);
const el=id=>nodes.get(id);
assert.doesNotMatch(html,/id="run"|sb\.rpc\('run_recurring_tasks_safe'\)/,'No manual execution in the page');
assert.equal(el('assignee').value,'');assert.match(el('list').innerHTML,/انتهى التكرار/);
el('newRecurring').onclick();assert.equal(el('recurringDialog').open,true);assert.equal(el('taskDetailsStep').hidden,false);assert.equal(el('repeatSettingsStep').hidden,true);
el('title').value='اختبار';await el('add').onclick();assert.equal(inserted,null,'No silent assignee');
el('assignee').value='employee';el('next').value='2030-10-01T09:00';
el('recurrence').value='weekly';days.forEach(x=>x.checked=[0,2].includes(Number(x.value)));el('endMode').value='count';el('endCount').value='4';
el('configureRepeat').onclick();assert.equal(el('taskDetailsStep').hidden,true);assert.equal(el('repeatSettingsStep').hidden,false);
el('endMode').listeners.input();assert.equal(el('endCountField').hidden,false);assert.equal(el('endDateField').hidden,true);
el('confirmRepeat').onclick();assert.equal(el('taskDetailsStep').hidden,false);assert.equal(el('repeatSettingsStep').hidden,true);
await el('add').onclick();assert.equal(el('recurringDialog').open,false);assert.deepEqual(Array.from(inserted.recurrence_rule.days),[0,2]);assert.equal(inserted.assignee_id,'employee');assert.equal(inserted.schedule_start_at,'2030-10-01T06:00:00.000Z');assert.equal(inserted.recurrence_rule.endCount,4);assert.equal(el('assignee').value,'');
editButton.onclick();assert.equal(el('assignee').value,'employee');assert.equal(el('monthDay').value,31);assert.equal(el('next').value,'2030-01-31T09:00');
el('configureRepeat').onclick();el('patternYearly').onclick();assert.equal(el('recurrence').value,'yearly');el('backToDetails').onclick();assert.equal(el('recurrence').value,'monthly');assert.equal(el('title').value,'دورية محفوظة');el('configureRepeat').onclick();
el('repeatMode').value='completion';el('repeatMode').listeners.input();assert.equal(el('calendarOptions').hidden,true);assert.equal(el('completionHelp').hidden,false);
el('confirmRepeat').onclick();
await el('add').onclick();assert.equal(updated.recurrence_rule.mode,'completion');assert(!('owner_id' in updated));assert(!('next_run_at' in updated),'Do not overwrite scheduler state');
assert.equal(el('assignee').value,'');
console.log('PASS recurring form: required assignee, conditional controls, save/reset and editing');
