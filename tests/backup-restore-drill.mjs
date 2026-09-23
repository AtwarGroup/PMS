import fs from 'node:fs';
import assert from 'node:assert/strict';

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

console.log('Guarded backup restore drill checks passed.');
