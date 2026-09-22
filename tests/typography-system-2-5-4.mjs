import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(import.meta.dirname,'..');
const read=file=>readFileSync(resolve(root,file),'utf8');
const typography=read('assets/css/typography.css');
const shell=read('assets/js/shell-components.js');

for(const token of [
  '--atwar-type-page-title:26px',
  '--atwar-type-section-title:20px',
  '--atwar-type-card-title:16px',
  '--atwar-type-body:14px',
  '--atwar-type-control:13px',
  '--atwar-type-meta:12px',
  '--atwar-type-caption:11px'
])assert.ok(typography.includes(token),`Missing typography token: ${token}`);

for(const selector of ['.atwar-nav a','.atwar-side-link','.atwar-main :where(h1)','.atwar-main :where(h2)','.atwar-main :where(p,li,dd,dt,label,td)','.atwar-main :where(button,.btn,input,select,textarea)']){
  assert.ok(typography.includes(selector),`Missing typography coverage: ${selector}`);
}
assert.match(shell,/typography\.css\?v=2\.5\.4/,'The canonical typography layer must be loaded by the shared shell');
assert.match(shell,/DOMContentLoaded/,'Typography must load after page-local styles');
assert.doesNotMatch(typography,/--atwar-type-(?:body|control|meta|caption):(?:[0-9]|10)px/,'Canonical readable text must not be smaller than 11px');

for(const page of ['landing.html','login.html','privacy.html','Chief_Accountant.html','Financial_Manager.html','Purchasing_Inventory_Supv.html']){
  assert.match(read(page),/typography\.css\?v=2\.5\.4/,`${page} must load the canonical typography layer`);
}

console.log('ATWAR ONE V2.5.4 typography-system audit passed.');
