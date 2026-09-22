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
console.log('Task refresh coalescing audit passed.');
