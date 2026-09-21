import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const login=readFileSync(resolve(root,'login.html'),'utf8');
const home=readFileSync(resolve(root,'home.html'),'utf8');
const permissions=readFileSync(resolve(root,'assets/js/permissions.js'),'utf8');

assert.match(login,/<body class="auth-pending">/,'Login must start in a non-painted authentication state');
assert.match(login,/جاري التحقق من جلسة الدخول/,'A stable session-check screen is required');
assert.match(login,/location\.replace\(/,'Authenticated navigation must replace the login history entry');
assert.match(login,/classList\.remove\('auth-pending'\)/,'The form may appear only after session verification');
assert.match(home,/<body style="visibility:hidden">/,'Home must stay hidden until the authenticated profile is ready');
assert.match(home,/if\(a\)\{document\.body\.style\.visibility='visible'/,'Home must reveal only after profile verification');
assert.doesNotMatch(permissions,/location\.reload\(/,'Permission refresh must not reload the page');
console.log('Login and authenticated-startup no-flash audit passed.');
