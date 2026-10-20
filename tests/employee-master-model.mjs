import assert from 'node:assert/strict';
import {filterEmployees,normalizeGrant,escapeHTML}from '../assets/js/employee-master-model.mjs';
const rows=[{full_name:'موظف أول',employee_code:'1064',title:'مشرف',manager:'مدير',department:'مبيعات',section:'تجزئة',login_active:true},{full_name:'موظف ثان',employee_code:'2000',title:'فني',department:'عمليات',section:'تركيبات',login_active:false}];
assert.equal(filterEmployees(rows,{query:'1064'})[0],rows[0]);assert.equal(filterEmployees(rows,{query:'مدير'})[0],rows[0]);
assert.equal(filterEmployees(rows,{department:'مبيعات',section:'تركيبات'}).length,0);assert.equal(filterEmployees(rows,{login:'waiting'})[0],rows[1]);assert.equal(filterEmployees(rows,{login:'active'})[0],rows[0]);
assert.deepEqual(normalizeGrant({read:false,write:true,scope:'all'}),{read:true,write:true,scope:'all'});assert.deepEqual(normalizeGrant({read:false,write:false,scope:'other'}),{read:false,write:false,scope:'team'});
assert.equal(escapeHTML('<img onerror="x">'),'&lt;img onerror=&quot;x&quot;&gt;');console.log('Employee directory filters, staged login status and access controls passed');
