import fs from 'node:fs';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const workflow = fs.readFileSync('.github/workflows/restore-drill.yml', 'utf8');
const script = fs.readFileSync('scripts/backup/restore-drill.sh', 'utf8');
const weekly = fs.readFileSync('.github/workflows/weekly-backup.yml', 'utf8');

assert.match(workflow, /workflow_dispatch:/);
assert.match(workflow, /environment: backup-restore-drill/);
assert.match(workflow, /RESTORE_DRILL_DB_URL/);
assert.match(workflow, /Encrypted backup checksum mismatch/);
assert.match(script, /ALLOW_RESTORE_DRILL/);
assert.match(script, /Refusing to restore into the production database/);
assert.match(script, /production_fingerprint/);
assert.match(script, /drill_fingerprint/);
assert.match(script, /pg_restore/);
assert.match(script, /due_date < start_date/);
assert.match(weekly, /sha256sum "\$name\.tar\.gz\.gpg"/);

// Exercise the shell script with a disposable Docker substitute. No database
// connections, credentials, or containers are used by these regression cases.
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'atwar-restore-drill-'));
try {
  const bin = path.join(scratch, 'bin');
  const backup = path.join(scratch, 'backup');
  fs.mkdirSync(bin);
  fs.mkdirSync(backup);
  fs.writeFileSync(path.join(backup, 'database.dump'), 'test archive');
  fs.writeFileSync(path.join(bin, 'docker'), `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2);
const interactive = args.includes('-i') || args.includes('--interactive');
const sql = args.includes('psql') && interactive ? fs.readFileSync(0, 'utf8') : '';
fs.appendFileSync(process.env.DRILL_CALL_LOG, JSON.stringify({args, sql}) + '\\n');
if (args.includes('pg_restore') && process.env.DRILL_FAILURE === 'restore') process.exit(1);
if (args.includes('psql') && sql && process.env.DRILL_FAILURE === 'verification') process.exit(3);
`);
  fs.chmodSync(path.join(bin, 'docker'), 0o700);
  const production = 'postgresql://tester@production.invalid:5432/postgres';
  const target = 'postgresql://tester@disposable.invalid:5432/postgres';
  function run(overrides = {}) {
    const log = path.join(scratch, 'calls.jsonl');
    fs.writeFileSync(log, '');
    const result = spawnSync('bash', ['scripts/backup/restore-drill.sh', backup], {
      encoding: 'utf8',
      env: {
        ...process.env,
        PATH: `${bin}${path.delimiter}${process.env.PATH}`,
        ALLOW_RESTORE_DRILL: 'yes',
        SUPABASE_DB_URL: production,
        RESTORE_DRILL_DB_URL: target,
        DRILL_CALL_LOG: log,
        DRILL_FAILURE: '',
        ...overrides,
      },
    });
    return {...result, calls: fs.readFileSync(log, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse)};
  }
  const healthy = run();
  assert.equal(healthy.status, 0, healthy.stderr);
  const verification = healthy.calls.find(call => call.args.includes('psql'));
  assert.ok(verification?.sql.trim(), 'The verification SQL must reach psql through Docker stdin');
  assert.ok(verification.args.includes('-X'), 'User psql startup files must not alter verification');
  assert.ok(verification.args.includes('ON_ERROR_STOP=1'));
  assert.match(verification.sql, /raise exception/i, 'False integrity checks must fail instead of printing false');
  const restoration = healthy.calls.find(call => call.args.includes('pg_restore'));
  assert.ok(restoration.args.includes('--exit-on-error'), 'Restoration must stop on the first SQL error');
  for (const failure of ['restore', 'verification']) {
    const result = run({DRILL_FAILURE: failure});
    assert.notEqual(result.status, 0, `${failure} failure must fail the drill`);
    assert.doesNotMatch(result.stdout, /restore drill passed/i);
    if (failure === 'restore') assert.ok(!result.calls.some(call => call.args.includes('psql')));
  }
  for (const overrides of [{ALLOW_RESTORE_DRILL: 'no'}, {RESTORE_DRILL_DB_URL: production}]) {
    const blocked = run(overrides);
    assert.notEqual(blocked.status, 0);
    assert.equal(blocked.calls.length, 0, 'Safety guards must stop before invoking any client');
  }
} finally {
  fs.rmSync(scratch, {recursive: true, force: true});
}

console.log('Guarded restore drill behavior checks passed: stdin, client failures and production guards.');
