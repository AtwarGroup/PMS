import assert from 'node:assert/strict';
import {readFileSync,readdirSync,statSync} from 'node:fs';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..');
const read=file=>readFileSync(resolve(root,file),'utf8');
const design=read('assets/css/design-system.css');
const shell=read('assets/js/shell-components.js');
const feedback=read('assets/js/ui-feedback.js');
const session=read('assets/js/session-service.js');

for(const token of ['--atwar-navy-900','--atwar-blue-600','--atwar-success-600','--atwar-warning-600','--atwar-danger-600','--atwar-font','--atwar-radius-card','--atwar-shadow-card'])assert.match(design,new RegExp(token),`Missing design token ${token}`);
for(const component of ['.atwar-page-head','.atwar-hero','.atwar-metric','.atwar-btn','.atwar-toolbar','.atwar-state','.atwar-toast','.atwar-save-state','.atwar-dialog'])assert.match(design,new RegExp(component.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')),`Missing shared component ${component}`);
assert.match(design,/prefers-reduced-motion/,'Reduced-motion accessibility must be supported');
assert.match(shell,/design-system\.css\?v=2\.5\.2/,'The shell must load the canonical design system');
assert.match(feedback,/window\.AtwarUI=Object\.freeze\(\{toast,saveState,confirm:confirmDialog,prompt:promptDialog\}\)/,'Unified feedback API is incomplete');
assert.match(feedback,/aria-live/,'Feedback must be announced to assistive technology');
assert.match(session,/window\.AtwarSession=Object\.freeze/,'Shared session API is missing');
assert.match(session,/\.select\('id,email,full_name,role,job_title,department,manager_id,permissions,active,status,employee_code,join_date,work_location,employment_type,job_description_id'\)/,'Session service must request only required profile columns');
const html=[];function walk(dir){for(const name of readdirSync(dir)){if(['node_modules','.git'].includes(name))continue;const file=resolve(dir,name);if(statSync(file).isDirectory())walk(file);else if(file.endsWith('.html'))html.push(file)}}walk(root);
for(const file of html){const source=readFileSync(file,'utf8'),versions=[...source.matchAll(/shell-components\.js\?v=([^"']+)/g)].map(match=>match[1]);for(const version of versions)assert.equal(version,'2.5.2',`${file} uses stale shell ${version}`);if(versions.length){assert.match(source,/ui-feedback\.js\?v=2\.5\.2/,`${file} must load unified feedback synchronously`);assert.match(source,/session-service\.js\?v=2\.5\.2/,`${file} must load session service synchronously`)}}
console.log('Unified system foundation audit passed.');
