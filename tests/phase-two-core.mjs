import assert from 'node:assert/strict';
import {
  calcDelay,
  calcDuration,
  normalizeProgress,
  sortTaskRows,
  validateTaskFieldValue
} from '../assets/js/tasks-core.mjs';
import {createRefreshCoordinator} from '../assets/js/supabase-sync.mjs';

assert.equal(calcDuration('2026-09-10','2026-09-12'),3);
assert.equal(calcDuration('2026-09-12','2026-09-10'),0);
assert.equal(normalizeProgress(-5),0);
assert.equal(normalizeProgress(130),100);
assert.equal(normalizeProgress('55'),55);

const fixedNow=new Date('2026-09-15T10:00:00Z');
assert.equal(calcDelay('2026-09-12','','قيد التنفيذ',null,[],fixedNow),3);
assert.equal(calcDelay('2026-09-12','','بانتظار الاعتماد',new Date('2026-09-13T10:00:00Z').getTime(),[],fixedNow),1);
assert.equal(calcDelay('2026-09-12','','مكتملة',null,[],fixedNow),0);

assert.equal(validateTaskFieldValue({start:'2026-09-12'},'end','2026-09-11').ok,false);
assert.equal(validateTaskFieldValue({},'title','  ').ok,false);
assert.equal(validateTaskFieldValue({},'priority','urgent').ok,true);

const sorted=sortTaskRows([
  {id:1,status:'قيد التنفيذ',priority:'normal',createdAt:3},
  {id:2,status:'بانتظار الاعتماد',priority:'normal',createdAt:1},
  {id:3,status:'قيد التنفيذ',priority:'urgent',createdAt:2}
],{sortFilterValue:'PRIORITY',isManagerView:true});
assert.deepEqual(sorted.map(row=>row.id),[2,3,1]);

let releaseFirst;
let reads=0;
const delivered=[];
const coordinator=createRefreshCoordinator({
  load:async()=>{
    reads+=1;
    if(reads===1)await new Promise(resolve=>{releaseFirst=resolve});
    return reads;
  },
  onValue:value=>delivered.push(value)
});
const first=coordinator.refresh();
await Promise.resolve();
coordinator.refresh();
coordinator.refresh();
releaseFirst();
await first;
await new Promise(resolve=>setTimeout(resolve,0));
assert.equal(reads,2,'Realtime bursts must collapse into one queued refresh');
assert.deepEqual(delivered,[1,2]);
coordinator.dispose();

console.log('Phase-two task core and synchronization audit passed.');
