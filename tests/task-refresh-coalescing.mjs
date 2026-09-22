import assert from 'node:assert/strict';
import {createRefreshCoordinator,createSharedInFlightReads} from '../assets/js/supabase-sync.mjs';

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

const shared=createSharedInFlightReads();
let sharedReads=0;
let releaseShared;
const loadShared=()=>{
  sharedReads++;
  return new Promise(resolve=>{releaseShared=resolve;});
};
const listenerA=shared.read('tasks:all',loadShared);
const listenerB=shared.read('tasks:all',loadShared);
const otherScope=shared.read('tasks:mine',()=>42);
await Promise.resolve();
assert.equal(sharedReads,1,'two listeners with the same key must issue one read');
assert.equal(listenerA,listenerB,'identical in-flight reads must return the same promise');
assert.equal(await otherScope,42,'different scopes must remain independent');
releaseShared('fresh');
assert.deepEqual(await Promise.all([listenerA,listenerB]),['fresh','fresh']);
assert.equal(await shared.read('tasks:all',()=>{sharedReads++;return 'new';}),'new');
assert.equal(sharedReads,2,'completed results must not be cached');

let failedReads=0;
const failed=()=>{failedReads++;throw new Error('transient');};
const failureA=shared.read('tasks:error',failed);
const failureB=shared.read('tasks:error',failed);
const settled=await Promise.allSettled([failureA,failureB]);
assert.equal(failedReads,1,'identical failed requests must share one read');
assert.deepEqual(settled.map(x=>x.status),['rejected','rejected']);
assert.equal(await shared.read('tasks:error',()=> 'retry'),'retry','failures must not be cached');

console.log('Task refresh coalescing audit passed.');
