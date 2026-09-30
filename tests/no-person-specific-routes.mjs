import fs from 'node:fs';
import assert from 'node:assert/strict';

const team = fs.readFileSync('team/employee.html', 'utf8');

assert.equal(fs.existsSync('profile/financial-manager.html'), false);
assert.doesNotMatch(team, /financial-manager\.html/);
assert.doesNotMatch(team, /SK9kgX3MHlOWQMwmnJbfGjCvtha2/);
assert.doesNotMatch(team, /HAMZA_FIREBASE_UID/);
assert.match(team, /team-employee-page\.js/);
const teamPage=fs.readFileSync('assets/js/team-employee-page.js','utf8');
assert.match(teamPage, /p_profile_id:uid/);
assert.match(teamPage, /data\.full_name/);

console.log('Legacy financial profile removal checks passed.');
