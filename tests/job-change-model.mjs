import assert from 'node:assert/strict';
import {sameValue,changedFields,cleanKpiProposal,validProposal,referencedKpi} from '../assets/js/job-change-model.mjs';
const original={name:'دوران المخزون',unit:'مرة',measure:'تكلفة ÷ متوسط المخزون',source:'Odoo',frequency:'ربع سنوي',target:'6',weight:10,scale_basis:'6',scale:Array.from({length:5},(_,i)=>({score:i+1,label:String(i+1)}))};
assert(sameValue({a:' نص ',b:2},{b:2,a:'نص'}));
assert.deepEqual(changedFields(original,{...original,target:'8'},'KPIS'),['المستهدف']);
const changed=cleanKpiProposal(original,{...original,target:'8'});
assert.equal(changed.scale_basis,'8');assert.equal(original.scale_basis,'6');
assert.equal(validProposal('KPIS','MODIFY',changed,original),'');
assert.match(validProposal('KPIS','MODIFY',original,original),/لم يتغير/);
assert.match(validProposal('KPIS','MODIFY',{...changed,weight:0},original),/وزن/);
assert.match(validProposal('KPIS','ADD',{...changed,measure:''},null),/أكمل/);
assert.match(validProposal('KPIS','MODIFY',{...changed,scale:[]},original),/الخماسي/);
assert.equal(validProposal('KPIS','DELETE',null,original),'');
assert(!sameValue(original,{...original,scale:[...original.scale].reverse()}));
console.log('PASS: semantic change detection, invalid proposal rejection, scale consistency and unchanged source.');

assert.equal(referencedKpi({revision:23,content:{kpis:[original]}},'مراجعة دوران المخزون').index,0);
assert.equal(referencedKpi({revision:23,content:{kpis:[original,{...original,name:original.name}]}},'مراجعة دوران المخزون'),null);
