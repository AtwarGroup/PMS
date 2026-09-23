import fs from 'node:fs';
import assert from 'node:assert/strict';

const team = fs.readFileSync('team/employee.html', 'utf8');

assert.equal(fs.existsSync('profile/financial-manager.html'), false);
assert.doesNotMatch(team, /financial-manager\.html/);
assert.doesNotMatch(team, /SK9kgX3MHlOWQMwmnJbfGjCvtha2/);
assert.doesNotMatch(team, /HAMZA_FIREBASE_UID/);
assert.match(team, /eq\('id',uid\)/);
assert.match(team, /target\.full_name/);

console.log('Legacy financial profile removal checks passed.');
