import assert from 'node:assert/strict';
import {priority,actions,esc} from '../assets/js/it-support-model.mjs';
assert.equal(priority(3,3),1);assert.equal(priority(1,1),4);assert.equal(priority(2,3),2);assert.equal(priority(2,1),3);
assert.equal(esc('<img onerror="x">'),'&lt;img onerror=&quot;x&quot;&gt;');
const t={state:'approval',requester_id:'employee',beneficiary_id:'employee',approver_id:'manager'};
assert(!actions(t,{user_id:'employee'}).includes('approve'));assert(actions(t,{user_id:'manager'}).includes('approve'));assert(!actions(t,{user_id:'it',operator:true}).includes('resolve'));
assert(actions({...t,state:'new'},{user_id:'it',operator:true}).includes('resolve'));
console.log('IT support priority and role-specific actions passed.');

const {archived}=await import('../assets/js/it-support-model.mjs');
for(const state of ['resolved','closed','cancelled','rejected'])assert.equal(archived(state),true);
for(const state of ['new','approval','working','waiting_employee','waiting_vendor'])assert.equal(archived(state),false);
