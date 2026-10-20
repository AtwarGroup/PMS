import assert from 'node:assert/strict';
import {renderJobFollowup,mountJobFollowup} from '../assets/js/job-followup-panel.mjs';
const rows=[{name:'<script>',published:true,accepted:true,title:'A',revision:2,job_id:'j',review_due:'2026-10-09',review_enabled:true},{name:'B',published:true,accepted:false,title:'A',revision:2,job_id:'j',review_due:'2026-10-09',review_enabled:true},{name:'C',published:false,accepted:false}];
const html=renderJobFollowup(rows,'2026-10-10');assert.match(html,/50%/);assert.match(html,/لم يقروا بعد \(1\)/);assert.match(html,/دون وصف منشور \(1\)/);assert.equal((html.match(/مستحقة للمراجعة/g)||[]).length,1);assert.ok(!html.includes('<script>'));
const exempted=renderJobFollowup([{name:'Administrative employee',published:true,accepted:false,waived:true}], '2026-10-20');assert.match(exempted,/لم يقروا بعد \(0\)/);assert.match(exempted,/لا توجد إقرارات مطلوبة/);assert.match(exempted,/تحديثًا إداريًا لا يتطلب إعادة إقرار/);assert.doesNotMatch(exempted,/100%/);
let host={innerHTML:''};await mountJobFollowup(host,{rpc:async()=>({error:new Error('offline')})});assert.match(host.innerHTML,/تعذر تحميل/);await mountJobFollowup(host,{rpc:async()=>({data:rows})});assert.match(host.innerHTML,/50%/);
console.log('Acknowledgement coverage, pending/unpublished separation, review deduplication, escaping and failure recovery passed');
