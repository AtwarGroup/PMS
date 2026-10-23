import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'atwar-restore-'));
try {
  fs.writeFileSync(path.join(dir,'database.dump'),'fixture');
  fs.writeFileSync(path.join(dir,'roles.sql'),'CREATE ROLE fixture_role;\n');
  fs.mkdirSync(path.join(dir,'storage'));fs.writeFileSync(path.join(dir,'storage','storage-manifest.json'),JSON.stringify({buckets:[]}));
  fs.writeFileSync(path.join(dir,'offline.mjs'),"globalThis.fetch=async()=>new Response('[]',{headers:{'Content-Type':'application/json'}});");
  fs.writeFileSync(path.join(dir,'docker'),`#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *" pg_restore "*) [[ " $* " == *" --exit-on-error "* ]] || exit 20; test "\${FAIL_RESTORE:-}" != yes || exit 21;;
  *" psql "*) [[ " $* " == *" -i "* ]] || exit 22; cat > "$SQL_CAPTURE"; test -s "$SQL_CAPTURE" || exit 23; test "\${FAIL_SQL:-}" != yes || exit 24;;
esac
`,{mode:0o755});
  const env={...process.env,PATH:dir+path.delimiter+process.env.PATH,ALLOW_RESTORE_DRILL:'yes',SUPABASE_DB_URL:'postgres://user:unused@production.invalid/app',RESTORE_DRILL_DB_URL:'postgres://user:unused@db.aaaaaaaaaaaaaaaaaaaa.supabase.co/app',RESTORE_DRILL_PROJECT_REF:'aaaaaaaaaaaaaaaaaaaa',SUPABASE_URL:'https://production.supabase.co',RESTORE_DRILL_SUPABASE_URL:'https://aaaaaaaaaaaaaaaaaaaa.supabase.co',RESTORE_DRILL_SERVICE_ROLE_KEY:'fixture',NODE_OPTIONS:'--import '+path.join(dir,'offline.mjs'),SQL_CAPTURE:path.join(dir,'check.sql')};
  const run=extra=>spawnSync('bash',['scripts/backup/restore-drill.sh',dir],{env:{...env,...extra},encoding:'utf8'});
  let result=run({}); assert.equal(result.status,0,result.stderr);
  const sql=fs.readFileSync(env.SQL_CAPTURE,'utf8');
  assert.match(sql,/RAISE EXCEPTION 'Restored database is missing/);
  assert.match(sql,/RAISE EXCEPTION 'Restored tasks contain invalid/);
  for(const extra of [{FAIL_RESTORE:'yes'},{FAIL_SQL:'yes'},{RESTORE_DRILL_DB_URL:env.SUPABASE_DB_URL},{ALLOW_RESTORE_DRILL:'no'}]) {
    result=run(extra); assert.notEqual(result.status,0); assert.doesNotMatch(result.stdout,/restore drill passed/);
  }
  console.log('Restore execution guards and failure propagation passed.');
} finally {fs.rmSync(dir,{recursive:true,force:true});}
