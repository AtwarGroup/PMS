import assert from 'node:assert/strict';
import {employeePopulation,loadHomeEmployeeCount} from '../assets/js/employee-population.mjs';

const records=[
  {id:'employee-1',profile_id:'account-1',login_active:true},
  {id:'employee-2',profile_id:'account-2',login_active:false},
  {id:'employee-3',profile_id:null,login_active:false},
];
assert.deepEqual(employeePopulation(records,[{id:'account-1'},{id:'account-2'},{id:'system-account'}]),
  {total:3,active:1,waiting:1,linked:2,otherAccounts:1});
const count={textContent:'—'},scope={textContent:''};
let calls=0;
const sb={rpc:async name=>{calls++;assert.equal(name,'employee_master_list');return {data:records.slice(1),error:null};}};
await loadHomeEmployeeCount(sb,false,count,scope);
assert.equal(calls,0,'Disabled employee unit must not fetch employee data');
await loadHomeEmployeeCount(sb,true,count,scope);
assert.equal(count.textContent,2,'Home uses the scoped directory, including staff without accounts');
assert.match(scope.textContent,/نطاق اطلاعك/);
await loadHomeEmployeeCount({rpc:()=>({then:resolve=>resolve({data:records,error:null})})},true,count,scope);
assert.equal(count.textContent,3,'PostgREST thenable without catch loads normally');
await loadHomeEmployeeCount({rpc:()=>({then:(_resolve,reject)=>reject(Error('offline'))})},true,count,scope);
assert.equal(count.textContent,'—','A rejected thenable is handled without interrupting the dashboard');
await loadHomeEmployeeCount({rpc:async()=>({data:null,error:{message:'denied'}})},true,count,scope);
assert.equal(count.textContent,'—','A failed request must not look like an empty directory');
assert.match(scope.textContent,/تعذر/);
console.log('PASS: employee/account populations, scoped home count and unavailable states');
