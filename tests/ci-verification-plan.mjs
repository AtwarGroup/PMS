import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,rmSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {SUITES,planChanges,eventPlan} from '../scripts/ci/plan.mjs';
import {verifyGate} from '../scripts/ci/check-gate.mjs';
import {SUITE_COMMANDS} from '../scripts/ci/run-suite.mjs';

const fullCommands=Object.values(SUITE_COMMANDS).flat().map(c=>c.join(' ').replace(/^python3 /,'python '));
const legacy=JSON.parse(readFileSync(new URL('./fixtures/ci-legacy-checks.json',import.meta.url),'utf8'));
assert(legacy.length>=30,'Preserve the original verification inventory');
for(const command of legacy)assert(fullCommands.includes(command),'Missing original verification: '+command);
assert.deepEqual(Object.keys(SUITE_COMMANDS),SUITES);

assert.deepEqual(planChanges(['communication/theme.css']).suites,['communication']);
assert.equal(planChanges(['communication/theme.css']).kind,'design');
assert.deepEqual(planChanges(['communication/app.mjs']).suites,['communication']);
assert.equal(planChanges(['communication/app.mjs']).kind,'module');
assert.deepEqual(planChanges(['fleet/index.html','policies/index.html']).suites,['fleet','policies']);
assert.deepEqual(planChanges(['assets/js/it-support-page.js']).suites,['it']);
assert.deepEqual(planChanges(['assets/js/policies-page.js']).suites,['policies']);
assert.deepEqual(planChanges(['assets/js/recruitment-page.js']).suites,['recruitment']);
for(const file of ['supabase/migrations/change.sql','assets/css/app-theme.css','assets/js/module-access.js','assets/js/communication-global.mjs','package-lock.json','.github/workflows/quality-gate.yml','new-module/app.js','tests/example.mjs']){
  assert.deepEqual(planChanges([file]).suites,SUITES,file);
}
assert.deepEqual(planChanges(['docs/usage.md']).suites,[]);
assert.deepEqual(planChanges(['docs/run.js']).suites,SUITES);
assert.deepEqual(planChanges(['communication/theme.css','assets/css/shared.css']).suites,SUITES);
assert.deepEqual(planChanges([]).suites,SUITES);
assert.deepEqual(eventPlan('schedule',{}).suites,SUITES);
assert.deepEqual(eventPlan('workflow_dispatch',{}).suites,SUITES);
assert.deepEqual(eventPlan('merge_group',{}).suites,SUITES);
assert.deepEqual(eventPlan('push',{before:'0'.repeat(40),after:'1'.repeat(40)}).suites,SUITES);
assert.deepEqual(eventPlan('pull_request',{pull_request:{base:{sha:'$(bad)'},head:{sha:'1'.repeat(40)}}}).suites,SUITES);

const needs=(suites,kind,result='success')=>({plan:{result:'success',outputs:{suites:JSON.stringify(suites),kind}},audit:{result:'success'},checks:{result}});
assert(verifyGate(needs(['communication'],'design')));
assert(verifyGate(needs(SUITES,'full')));
assert(verifyGate(needs([],'docs','skipped')));
for(const result of ['failure','cancelled','skipped','timed_out'])assert.throws(()=>verifyGate(needs(['fleet'],'module',result)));
const missing=needs(['fleet'],'module');delete missing.checks.result;assert.throws(()=>verifyGate(missing));
for(const result of ['failure','cancelled','skipped']){
  const n=needs(['fleet'],'module');n.plan.result=result;assert.throws(()=>verifyGate(n));
  const a=needs(['fleet'],'module');a.audit.result=result;assert.throws(()=>verifyGate(a));
}
assert.throws(()=>verifyGate(needs([],'full','skipped')));
assert.throws(()=>verifyGate(needs(['fleet'],'full')));
assert.throws(()=>verifyGate(needs([],'module','skipped')));
assert.throws(()=>verifyGate(needs(['unknown'],'module')));
assert.throws(()=>verifyGate({}));
// Exercise the actual gate entry point: it must return a failing exit status.
const cli=spawnSync(process.execPath,['scripts/ci/check-gate.mjs'],{env:{...process.env,CI_NEEDS:JSON.stringify(needs(['communication'],'design','failure'))},encoding:'utf8'});
assert.notEqual(cli.status,0);assert.match(cli.stderr,/Module checks must be success/);
assert.notEqual(spawnSync(process.execPath,['scripts/ci/check-gate.mjs'],{env:{...process.env,CI_NEEDS:'{}'},encoding:'utf8'}).status,0);

// Real git diff, including a rename across modules and documentation-only changes.
const dir=mkdtempSync(path.join(tmpdir(),'atwar-ci-plan-')),previous=process.cwd();
try{
  const git=(...args)=>{const r=spawnSync('git',args,{cwd:dir,encoding:'utf8'});assert.equal(r.status,0,r.stderr);return r.stdout.trim();};
  git('init','-q');git('config','user.name','CI test');git('config','user.email','ci@example.invalid');
  writeFileSync(path.join(dir,'README.md'),'start\n');git('add','.');git('commit','-qm','base');const base=git('rev-parse','HEAD');
  writeFileSync(path.join(dir,'README.md'),'docs change\n');git('add','.');git('commit','-qm','docs');const docs=git('rev-parse','HEAD');
  process.chdir(dir);assert.equal(eventPlan('push',{before:base,after:docs}).kind,'docs');
  // Unavailable base does not accidentally select no tests.
  assert.equal(eventPlan('push',{before:'a'.repeat(40),after:docs}).kind,'full');
  process.chdir(previous);
  const fs=await import('node:fs');fs.mkdirSync(path.join(dir,'communication'));fs.mkdirSync(path.join(dir,'fleet'));
  writeFileSync(path.join(dir,'communication','example.css'),'body{}\n');git('add','.');git('commit','-qm','module');const old=git('rev-parse','HEAD');
  git('mv','communication/example.css','fleet/example.css');git('commit','-qm','move');const head=git('rev-parse','HEAD');
  process.chdir(dir);assert.deepEqual(eventPlan('pull_request',{pull_request:{base:{sha:old},head:{sha:head}}}).suites,['fleet','communication']);
}finally{process.chdir(previous);rmSync(dir,{recursive:true,force:true});}
console.log('PASS CI scope: module/design/full/docs, shared/unknown fallback, real diff/rename, schedule, gate failure/cancellation/missing-result blocking');
