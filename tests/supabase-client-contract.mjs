import assert from 'node:assert/strict';
import {createClient} from '../assets/vendor/supabase-client.mjs';
import {loadHomeEmployeeCount} from '../assets/js/employee-population.mjs';
let requests=0;
const sb=createClient('https://client-contract.example.invalid','test-key',{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:async()=>{requests++;return new Response(JSON.stringify([{id:'one'}]),{status:200,headers:{'Content-Type':'application/json'}})}}});
const count={},scope={};await loadHomeEmployeeCount(sb,true,count,scope);
assert.equal(count.textContent,1);assert.equal(requests,1);
console.log('PASS: locally bundled real Supabase client loads dashboard directory without Promise.catch assumptions');
