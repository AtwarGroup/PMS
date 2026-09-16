import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const compat=readFileSync(resolve(root,'assets/js/supabase-firebase-compat.js'),'utf8');
const page=readFileSync(resolve(root,'assets/js/tasks-page.js'),'utf8');
const html=readFileSync(resolve(root,'tasks/index.html'),'utf8');

assert.match(compat,/function taskPatch\(next,previous=null\)/,'Task patches must compare against the authoritative previous row');
assert.match(compat,/taskPatch\(next,current\)/,'Transactions must send only changed fields');
assert.match(compat,/manager_notes',next\.managerNotes\?\?'',previous\?\.managerNotes\?\?''/,'Unchanged manager notes must be excluded from employee writes');
assert.match(compat,/JSON\.stringify\(v\)!==JSON\.stringify\(old\)/,'Patch fields must be included only when their values changed');
assert.match(page,/supabase-firebase-compat\.js\?v=1\.9\.20/,'The fixed compatibility module must bypass the browser cache');
assert.match(html,/tasks-page\.js\?v=1\.9\.23/,'The fixed task module must bypass the browser cache');
console.log('Minimal task patch and protected manager-note audit passed.');
