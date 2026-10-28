import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const ui=readFileSync('assets/js/policies-page.js','utf8'),css=readFileSync('assets/css/policies.css','utf8');
assert.match(ui,/policy-masthead/);assert.match(ui,/policy-section-nav/);assert.match(ui,/data-policy-panel/);assert.match(ui,/panel.hidden=!continuous/);assert.match(ui,/window.print\(\)/);assert.match(ui,/policy-review-notes/);assert.match(ui,/setSection\(activeSection\)/);
assert.match(css,/#policyApp \.policy-section\[hidden\]/);assert.match(css,/@media print/);assert.match(css,/\.policy-data-table thead\{display:table-header-group!important/);assert.match(css,/\.policy-section\[hidden\]\{display:block!important/);assert.match(css,/--policy-gold:#c5a25d/);assert.match(css,/--policy-navy:#142b49/);
const page=readFileSync('policies/index.html','utf8');assert.match(page,/policies.css\?v=2.8.16/);assert.match(page,/policies-page.js\?v=2.8.16/);
console.log('PASS shared approved policy design, section navigation and print contract');

