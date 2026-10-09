import assert from 'node:assert/strict';
import {readAllRows} from '../assets/js/paged-read.mjs';
const data=Array.from({length:1203},(_,id)=>({id}));const ranges=[];let builds=0;
const rows=await readAllRows(()=>{builds++;return {order(key){assert.equal(key,'id');return this},async range(from,to){ranges.push([from,to]);return {data:data.slice(from,to+1),error:null};}};});
assert.equal(rows.length,1203);assert.equal(builds,3);assert.deepEqual(ranges,[[0,499],[500,999],[1000,1499]]);assert.equal(new Set(rows.map(x=>x.id)).size,1203);
let reads=0;await assert.rejects(readAllRows(()=>({order(){return this},async range(){return ++reads===1?{data:data.slice(0,500)}:{error:new Error('Disconnected')};}})),/Disconnected/,'A failed later page must not be shown as a complete list');
assert.deepEqual(await readAllRows(()=>({order(){return this},async range(){return {data:[]};}})),[]);
console.log('Paginated reads: complete 1203-row collection, stable ordering, independent builders and failed-page rejection passed');

const composite=Array.from({length:1203},(_,n)=>({task_id:`task-${Math.floor(n/3)}`,predecessor_id:`previous-${n%3}`}));
const orders=[];
assert.deepEqual(await readAllRows(()=>({order(column){orders.push(column);assert(['task_id','predecessor_id'].includes(column));return this;},async range(from,to){return {data:composite.slice(from,to+1)};}}),{key:['task_id','predecessor_id']}),composite);
assert.deepEqual(orders,['task_id','predecessor_id','task_id','predecessor_id','task_id','predecessor_id']);
await assert.rejects(readAllRows(()=>{throw new Error('Must not query');},{key:[]}),/stable pagination key/);
const {readFile}=await import('node:fs/promises');
const projectPage=await readFile(new URL('../assets/js/projects-page.js',import.meta.url),'utf8');
assert(projectPage.includes("readAllRows(()=>sb.from('project_dependencies').select('*').eq('project_id',id),{key:['task_id','predecessor_id']})"),'Project dependencies must use both columns of their actual primary key');
console.log('Composite dependency pagination: both key columns ordered across three pages passed');
