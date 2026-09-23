import fs from 'node:fs';
import assert from 'node:assert/strict';

const team = fs.readFileSync('team/employee.html', 'utf8');
const financial = fs.readFileSync('profile/financial-manager.html', 'utf8');
const productionPages = [
  'admin/roles.html',
  'organization/index.html',
  'admin/index.html',
  'search/index.html',
  'admin/users.html',
  'profile/financial-manager.html',
];

assert.doesNotMatch(team, /SK9kgX3MHlOWQMwmnJbfGjCvtha2/);
assert.doesNotMatch(team, /HAMZA_FIREBASE_UID/);
assert.doesNotMatch(financial, /SK9kgX3MHlOWQMwmnJbfGjCvtha2/);
assert.doesNotMatch(financial, /TARGET_FIREBASE_UID/);
assert.doesNotMatch(financial, /حمزة يوسف عبدالله المزهري/);
assert.doesNotMatch(financial, /const employeeId/);
assert.match(team, /target\.job_title/);
assert.match(team, /financial-manager\.html\?uid=/);
assert.match(financial, /eq\('id',targetId\)/);
assert.match(financial, /ATWAR_FINANCIAL_PROFILE_NAME=target\.full_name/);
assert.match(financial, /isFinancialManager/);

for (const page of productionPages) {
  const source = fs.readFileSync(page, 'utf8');
  assert.doesNotMatch(source, /Production 1\.7[A-Z]?/, page);
}

console.log('Person-independent profile routing checks passed.');
