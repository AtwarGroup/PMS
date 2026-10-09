import assert from 'node:assert/strict';
import {readAllRows} from '../assets/js/paged-read.mjs';
const data=Array.from({length:1203},(_,id)=>({id}));const ranges=[];let builds=0;
const rows=await readAllRows(()=>{builds++;return {order(key){assert.equal(key,'id');return this},async range(from,to){ranges.push([from,to]);return {data:data.slice(from,to+1),error:null};}};});
assert.equal(rows.length,1203);assert.equal(builds,3);assert.deepEqual(ranges,[[0,499],[500,999],[1000,1499]]);assert.equal(new Set(rows.map(x=>x.id)).size,1203);
let reads=0;await assert.rejects(readAllRows(()=>({order(){return this},async range(){return ++reads===1?{data:data.slice(0,500)}:{error:new Error('Disconnected')};}})),/Disconnected/,'A failed later page must not be shown as a complete list');
assert.deepEqual(await readAllRows(()=>({order(){return this},async range(){return {data:[]};}})),[]);
console.log('Paginated reads: complete 1203-row collection, stable ordering, independent builders and failed-page rejection passed');
