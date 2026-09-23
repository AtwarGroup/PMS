import fs from 'node:fs';
import assert from 'node:assert/strict';

const read = (path) => fs.readFileSync(path, 'utf8');

const migration = read('supabase/migrations/20260923001739_harden_job_library_child_rls.sql');
assert.match(migration, /job_description_versions_select_policy/);
assert.match(migration, /job_description_forms_select_policy/);
assert.match(migration, /private\.can_view_published_job\(j\.id\)/);
assert.match(migration, /j\.reviewer_id\s*=\s*\(select auth\.uid\(\)\)/);

const bridge = read('assets/js/supabase-firebase-compat.js');
assert.match(bridge, /document\.visibilityState==='visible'/);
assert.match(bridge, /setInterval\(refreshWhenVisible,120000\)/);
assert.match(bridge, /removeEventListener\('visibilitychange',onVisibilityChange\)/);
assert.doesNotMatch(bridge, /setInterval\(refresh,60000\)/);

const login = read('login.html');
assert.match(login, /<label for="email">/);
assert.match(login, /autocomplete="username"/);
assert.match(login, /<label for="password">/);
assert.match(login, /autocomplete="current-password"/);
assert.match(login, /aria-describedby="loginHelp"/);

const landing = read('landing.html');
assert.match(landing, /Production 2\.5\.7/);
assert.doesNotMatch(landing, /Production 1\.7E/);

console.log('System rating hardening checks passed.');
