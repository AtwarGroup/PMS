import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const read=file=>readFileSync(resolve(root,file),'utf8');
const start=read('assets/js/start-page-config.js');
const home=read('home.html');
const myDay=read('my-day/index.html');
const tasks=read('assets/js/tasks-page.js');
const workspace=read('workspace/index.html');
const team=read('team/index.html');

const contracts=[
  [start,"employee: 'home.html'",'Employee start page must be the summary home'],
  [start,"manager: 'home.html'",'Manager start page must be the summary home'],
  [start,"admin: 'home.html'",'Admin start page must be the summary home'],
  [home,'id="homeTodayCount"','Home must show a count instead of duplicating today task rows'],
  [home,'id="homeFollowupCount"','Home must show a follow-up count instead of personal content'],
  [home,'id="homeTeamCount"','Home must link managers to the people directory'],
  [myDay,'tasks/index.html?scope=TODAY&amp;owner=me','Legacy My Day route must preserve links through the canonical task view'],
  [tasks,"'APPROVAL','TODAY'",'Canonical task page must accept the TODAY scope'],
  [tasks,"homeFilterValue==='TODAY'",'Canonical task page must enforce the TODAY scope'],
  [workspace,'id="personalNote"','Personal notes must remain in My Workspace'],
  [workspace,'id="workspaceFollowList"','Follow-ups must remain in My Workspace'],
  [team,'id="teamHierarchy"','People hierarchy must remain in the Team page']
];

for(const [source,needle,message] of contracts)assert.ok(source.includes(needle),message);
for(const duplicateId of ['homeNotesBody','homeAttentionBody','homeTodayBody']){
  assert.ok(!home.includes(duplicateId),`Home must not duplicate detailed content through ${duplicateId}`);
}

console.log(`Phase-two information architecture audit passed: ${contracts.length+3} contracts.`);
