import assert from 'node:assert/strict';
import {createRefreshCoordinator} from '../assets/js/supabase-sync.mjs';

let reads=0;
let releaseFirst;
const delivered=[];
const coordinator=createRefreshCoordinator({
  load:async()=>{
    reads+=1;
    if(reads===1)await new Promise(resolve=>{releaseFirst=resolve;});
    return reads;
  },
  onValue:value=>delivered.push(value)
});

const first=coordinator.refresh();
coordinator.refresh();
coordinator.refresh();
await Promise.resolve();
assert.equal(reads,1,'same-turn refresh requests must share one read');

coordinator.refresh();
coordinator.refresh();
releaseFirst();
await first;
await new Promise(resolve=>setTimeout(resolve,0));
assert.equal(reads,2,'in-flight requests must collapse into one follow-up read');
assert.deepEqual(delivered,[1,2]);

coordinator.dispose();
coordinator.refresh();
await Promise.resolve();
assert.equal(reads,2,'disposed listeners must not issue more reads');

let disposedReads=0;
const disposedBeforeStart=createRefreshCoordinator({
  load:async()=>{disposedReads+=1;return 1;},
  onValue:()=>assert.fail('disposed listener must not deliver data')
});
const pending=disposedBeforeStart.refresh();
disposedBeforeStart.dispose();
await pending;
assert.equal(disposedReads,0,'disposal must cancel a scheduled but not yet started read');

let attempts=0;
const errors=[];
const recovered=[];
const errorCoordinator=createRefreshCoordinator({
  load:async()=>{
    attempts+=1;
    if(attempts===1)throw new Error('temporary network failure');
    return 'recovered';
  },
  onValue:value=>recovered.push(value),
  onError:error=>errors.push(error.message)
});
await errorCoordinator.refresh();
await errorCoordinator.refresh();
assert.deepEqual(errors,['temporary network failure'],'failed reads must report an error');
assert.deepEqual(recovered,['recovered'],'a failed read must not prevent subsequent refreshes');
errorCoordinator.dispose();

console.log('Task refresh coalescing audit passed.');
