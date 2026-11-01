import assert from 'node:assert/strict';
import {supervisionHTML} from '../assets/js/it-support-supervision.mjs';
const summary={overdue:2,escalated:1,waiting_information:3,waiting_confirmation:4,attention:10,average_resolution_hours:5.5,resolution_count:2,average_rating:4.5,rating_count:2};
const html=supervisionHTML({summary,queue:[{id:'test-id',number:3,title:'<script>alert(1)</script>',state:'resolved',priority:4,beneficiary_name:'موظف'}]});
assert.equal((html.match(/class="task-suite-metric"/g)||[]).length,4);assert.match(html,/5.5 ساعة فعلية/);assert.match(html,/4.5 \/ 5/);assert.match(html,/بانتظار تأكيد الموظف/);assert.match(html,/&lt;script&gt;/);assert.doesNotMatch(html,/<script>/);assert.match(html,/data-ticket="test-id"/);
const metrics=html.slice(html.indexOf('it-supervision-metrics'),html.indexOf('it-service-quality'));assert.doesNotMatch(metrics,/<a\b|<button/);
assert.match(supervisionHTML({summary:{...summary,average_resolution_hours:null,average_rating:null},queue:[]}),/لا توجد طلبات/);
assert.match(supervisionHTML({error:true}),/تعذر تحميل/);
console.log('PASS compact supervisor metrics, accurate labels, empty/error states, escaped content and request links outside metrics.');
