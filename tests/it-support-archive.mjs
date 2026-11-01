import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {archived,terminal} from '../assets/js/it-support-model.mjs';
const completed=Date.parse('2026-11-01T08:00:00Z'),week=7*86400000;
for(const service_key of ['device_fault','purchase']){
 const t={state:'closed',service_key,updated_at:new Date(completed).toISOString(),state_since:'2026-10-01T08:00:00Z'};
 assert.equal(archived(t,completed),false);
 assert.equal(archived(t,completed+week-1),false);
 assert.equal(archived(t,completed+week),true);
 assert.equal(archived(t,completed+week+1),true);
 assert.equal(terminal(t.state),true); // A visible completed request is not an open quota slot.
 assert.equal(archived({...t,state:'resolved'},completed+week*2),false);
 assert.equal(archived({...t,state:'working'},completed+week*2),false);
 assert.equal(archived({...t,state:'cancelled'},completed),true);
 assert.equal(archived({...t,state:'rejected'},completed),true);
}
const page=await readFile(new URL('../assets/js/it-support-page.mjs',import.meta.url),'utf8');
const metrics=page.slice(page.indexOf("$('supportMetrics').innerHTML="),page.indexOf("$('capacityInfo')"));
assert.doesNotMatch(metrics,/<button|<a\b|it-metric-link/);
assert.match(page,/openRows=all.filter\(t=>!terminal\(t.state\)\)/);
assert.match(page,/archived\(t\)===archiveMode/);
console.log('PASS support/purchase seven-day archive boundary, resolved/open states, completed quota exclusion, and metrics without links.');
