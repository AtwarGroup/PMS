import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {composerHTML,composerActions,actionFields,actionView} from '../assets/js/it-support-composer.mjs';
const t={state:'working',priority:3,service_key:'device_fault',requester_id:'employee',beneficiary_id:'employee',specialist_id:'it',supervisor_id:'supervisor'};
const operator={user_id:'it',operator:true},employee={user_id:'employee'};
for(const c of [operator,employee]){const html=composerHTML(t,c,true);assert.equal((html.match(/<form\b/g)||[]).length,1);assert.equal((html.match(/<textarea\b/g)||[]).length,1);assert.equal((html.match(/type="submit"/g)||[]).length,1);assert.match(html,/<select name="request_action"/);assert.doesNotMatch(html,/data-action=|actionSlot/);}
assert(composerActions(t,operator).includes('waiting_vendor'));assert(!composerActions(t,employee).includes('waiting_vendor'));
assert.match(composerHTML(t,operator,true),/<option value="waiting_vendor">تصعيد المشكلة<\/option>/);
assert.match(actionFields('waiting_vendor',t),/name="escalation_to" required/);
assert.equal(actionFields('comment',t),'');assert.equal(actionView('resolve').minimum,10);
assert.match(actionFields('priority',t),/<option value="3" selected>/);
assert.match(actionFields('close',t),/name="rating" required/);
const resolved={...t,state:'resolved'};assert(composerActions(resolved,employee).includes('close'));assert(!composerActions(resolved,operator).includes('close'));
const closed={...t,state:'closed'};assert.deepEqual(composerActions(closed,employee),['reopen']);assert.match(composerHTML(closed,employee,false),/حفظ الإجراء/);assert.equal(composerHTML(closed,operator,false),'');
assert.deepEqual(composerActions({...t,service_key:'purchase'},operator),['comment']);
const css=await readFile(new URL('../assets/css/it-support.css',import.meta.url),'utf8');assert.match(css,/\.it-composer\{position:static;/);assert.doesNotMatch(css,/\.it-composer\{position:sticky/);
console.log('PASS one action dropdown, one message field, escalation inputs, role choices, closure/reopen, purchase replies and non-overlapping composer.');
