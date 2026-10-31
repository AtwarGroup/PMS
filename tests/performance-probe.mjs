import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {percentile,summarize,readiness} from '../assets/js/performance-probe.mjs';
assert.equal(percentile(Array.from({length:30},(_,i)=>30-i),.95),29);
assert.equal(percentile([], .95),null);
assert.equal(summarize([{state:'timeout'},{state:'ready',ms:10}]).complete,false);
assert.equal(summarize([{state:'timeout'},{state:'ready',ms:10}]).p95_ms,10);
assert.equal(summarize(Array.from({length:30},()=>({state:'ready',ms:17}))).complete,true);
const doc=(key,state)=>({body:{},location:{pathname:'/workspace/index.html'},documentElement:{dataset:{taskMeasureState:state}},querySelector:s=>s===key?state:null});
assert.equal(readiness(doc('#spaceSync',{textContent:'جاري تحديث مساحتك…'}),'workspace'),'pending');
assert.equal(readiness(doc('#spaceSync',{textContent:'بعض الأقسام غير متاحة؛ نعيد المحاولة تلقائيًا.'}),'workspace'),'error');
assert.equal(readiness(doc('#spaceSync',{textContent:'محدّث الآن · تحديث تلقائي'}),'workspace'),'ready');
const source=await readFile('assets/js/performance-probe.mjs','utf8');
assert.ok(!/fetch\(|sendBeacon|localStorage|sessionStorage|\.innerHTML/.test(source));
assert.ok(source.includes("if(document.hidden)return {state:'background'}"));
const tasks=await readFile('assets/js/tasks-page.js','utf8');
assert.match(tasks,/async function checkOverdueNotifications\(\)\{\s*if\(new URLSearchParams\(location.search\).get\('performance_probe'\)==='1'\)return;/);
console.log('Performance percentile, partial failure, readiness, privacy and notification guard checks passed.');

assert.equal(readiness({body:{},location:{pathname:'/trial-login.html'}},'home'),'login');
assert.equal(readiness({body:{},location:{pathname:'/tasks/index.html'},documentElement:{dataset:{taskMeasureState:'ready'}},querySelector:()=>null},'tasks'),'pending');

const markup=await readFile('lab/performance.html','utf8');assert.match(markup,/app-theme\.css/);assert.match(markup,/Tajawal/);
