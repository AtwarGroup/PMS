import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {renderPolicyBody} from '../assets/js/policy-content.mjs';
const rendered=renderPolicyBody('### عنوان\n\n| الوظيفة | الراتب |\n| --- | --- |\n| بائع | 2,600–4,500 |\n\n<script>alert(1)</script>');
assert.match(rendered,/<table/);assert.match(rendered,/data-label="الراتب"/);assert.match(rendered,/2,600–4,500/);assert.ok(!rendered.includes('<script>'));assert.match(rendered,/&lt;script&gt;/);
assert.ok(!renderPolicyBody('| <img onerror=bad> |\n| --- |\n| <svg/onload=bad> |').includes('<img'));
const ui=readFileSync('assets/js/policies-page.js','utf8');assert.match(ui,/policy_set_review_access/);assert.match(ui,/canComment/);assert.match(ui,/editable&&editing/);assert.match(ui,/renderPolicyBody\(s.body\)/);
console.log('PASS policy review access UI and safe text/table renderer');
