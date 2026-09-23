import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync(new URL('../supabase/migrations/20260923163732_reference_scorecard_weights_20260923.sql',import.meta.url),'utf8');
const js=readFileSync(new URL('../assets/js/job-review-page.js',import.meta.url),'utf8');
const weights={};
for(const [,role,position,weight] of sql.matchAll(/\('(JOB-(?:037|005|008))',(\d+),'[^']+',([\d.]+)\)/g)){
  (weights[role] ||= [])[Number(position)-1]=Number(weight);
}
assert.deepEqual(weights['JOB-037'],[20,7.5,20,15,30,7.5]);
assert.deepEqual(weights['JOB-005'],[20,20,15,15,15,15]);
assert.deepEqual(weights['JOB-008'],[20,25,20,15,10,10]);
for(const values of Object.values(weights))assert.equal(values.reduce((sum,value)=>sum+value,0),100);
assert.match(sql,/enable row level security/);
assert.match(sql,/status='IN_REVIEW'/);
assert.match(js,/أسماء أو ترتيب مؤشرات المسودة يختلف/);
assert.match(js,/job_scorecard_weight_references/);
console.log('Three reference scorecards preserve all 18 pictured weights and flag mismatched drafts.');
