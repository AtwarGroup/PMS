import assert from 'node:assert/strict';
import {renderPolicyCard} from '../assets/js/policy-cards.mjs';
const policy={id:'x&"',code:'POL-<TEST>',title:'عنوان <script>test</script>'};
const draft=renderPolicyCard(policy);
assert.match(draft,/data-state="DRAFT"/);assert.match(draft,/لم تعتمد للنشر بعد/);assert.match(draft,/الإصدار <b>1<\/b>/);assert.match(draft,/href="\?id=x%26%22"/);assert(!draft.includes('<script>'));assert.match(draft,/POL-&lt;TEST&gt;/);
const approved=renderPolicyCard(policy,{status:'APPROVED',version_number:3,effective_date:'2026-10-25'},()=>'<date>');
assert.match(approved,/معتمدة/);assert.match(approved,/&lt;date&gt;/);assert.match(approved,/الإصدار <b>3<\/b>/);assert(!approved.includes('لم تعتمد للنشر بعد'));
console.log('PASS policy catalog escaping, safe detail link, draft defaults and published version metadata');
