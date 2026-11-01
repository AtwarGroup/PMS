import assert from 'node:assert/strict';
import {ownerRole,requestJourney,paymentJourney,systemText} from '../assets/js/it-support-presentation.mjs';
const t={state:'new',service_key:'device_fault',specialist_id:'it',beneficiary_id:'employee',supervisor_id:'supervisor',owner_id:'it'};
assert.equal(ownerRole(t),'قسم تقنية المعلومات');
for(const state of ['new','working','waiting_employee','waiting_vendor','resolved','closed','cancelled','rejected']){const html=requestJourney({...t,state});assert.equal((html.match(/aria-current="step"/g)||[]).length,1);assert.match(html,/المرحلة الحالية/);assert.match(html,/المسؤول الحالي/);assert.match(html,/الإجراء التالي/);if(['cancelled','rejected'].includes(state))assert.doesNotMatch(html,/تأكيد الحل/);}
assert.equal(ownerRole({...t,state:'resolved'}),'الموظف المستفيد');assert.equal(ownerRole({...t,state:'resolved',beneficiary_id:'it'}),'مشرف تطوير الأعمال');
for(const phase of ['quote','technical','manager','supply','receipt','receipt_issue','payment','closed','cancelled','rejected']){const state=['closed','cancelled','rejected'].includes(phase)?phase:'working';const html=requestJourney({...t,service_key:'purchase',state},{phase,quote_provider:'specialist'});assert.equal((html.match(/aria-current="step"/g)||[]).length,1);assert.doesNotMatch(html,/أسامة|محمد باسنبل|أكرم يوسف/);}
for(const state of ['technical','supervisor','chief','assigned','paid','cancelled']){const html=paymentJourney({state});assert.equal((html.match(/aria-current="step"/g)||[]).length,1);assert.doesNotMatch(html,/أسامة|محمد باسنبل|أكرم يوسف/);}
assert.equal(ownerRole({...t,service_key:'purchase'},{phase:'payment'},[{state:'chief'}]),'رئيس الحسابات');
assert.match(systemText('أحاله لمحمد باسنبل'),/لمشرف تطوير الأعمال/);
assert.match(requestJourney({...t,state:'waiting_vendor',escalation_to:'<script>'}),/تم تصعيد المشكلة/);
console.log('PASS IT role labels, support/purchase/payment journeys, waiting and terminal states, legacy system labels.');
