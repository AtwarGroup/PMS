import assert from 'node:assert/strict';
import fs from 'node:fs';
import {nextOccurrence,previewDates,validateRule,localInput,riyadhISO} from '../assets/js/recurrence-core.mjs';
const base={mode:'calendar',pattern:'day',endMode:'never'};
const cases=[
 [{...base},'daily',2,'2026-10-03T06:00:00Z','2026-10-03T06:00:00Z','2026-10-05T06:00:00.000Z'],
 [{...base,pattern:'workdays',days:[0,1,2,3,4]},'daily',1,'2026-10-01T06:00:00Z','2026-10-01T06:00:00Z','2026-10-04T06:00:00.000Z'],
 [{...base,pattern:'days',days:[0,2]},'weekly',2,'2026-10-04T06:00:00Z','2026-10-06T06:00:00Z','2026-10-18T06:00:00.000Z'],
 [{...base,day:31},'monthly',1,'2026-01-31T06:00:00Z','2026-01-31T06:00:00Z','2026-02-28T06:00:00.000Z'],
 [{...base,day:31},'monthly',1,'2026-01-31T06:00:00Z','2026-02-28T06:00:00Z','2026-03-31T06:00:00.000Z'],
 [{...base,pattern:'ordinal',ordinal:-1,weekday:0},'monthly',1,'2026-01-01T06:00:00Z','2026-02-01T06:00:00Z','2026-02-22T06:00:00.000Z'],
 [{...base,pattern:'ordinal',ordinal:2,weekday:1},'monthly',3,'2026-01-01T06:00:00Z','2026-01-12T06:00:00Z','2026-04-13T06:00:00.000Z'],
 [{...base,day:29,month:2},'yearly',1,'2024-02-29T06:00:00Z','2024-02-29T06:00:00Z','2025-02-28T06:00:00.000Z'],
 [{...base,pattern:'ordinal',ordinal:1,weekday:0,month:10},'yearly',1,'2026-10-03T06:00:00Z','2026-10-04T06:00:00Z','2027-10-03T06:00:00.000Z'],
 [{...base,endMode:'date',endDate:'2026-10-03'},'daily',1,'2026-10-03T06:00:00Z','2026-10-03T06:00:00Z',null],
];
for(const [r,k,n,s,a,want] of cases)assert.equal(nextOccurrence(r,k,n,s,a),want);
assert.equal(localInput('2026-10-02T22:30:00Z'),'2026-10-03T01:30');
assert.equal(riyadhISO('2026-10-03T01:30'),'2026-10-02T22:30:00.000Z');
assert.equal(previewDates({...base,endMode:'count',endCount:2},'daily',1,'2026-10-03T06:00:00Z').length,2);
assert.equal(previewDates({...base,mode:'completion'},'daily',1,'2026-10-03T06:00:00Z').length,0);
assert.throws(()=>validateRule({...base,pattern:'days',days:[]},'weekly',1,'2026-10-03T06:00:00Z'));
assert.throws(()=>validateRule({...base,endMode:'date',endDate:'2026-10-01'},'daily',1,'2026-10-03T06:00:00Z'));
const html=fs.readFileSync(new URL('../recurring/index.html',import.meta.url),'utf8');
assert.match(html,/<option value="">اختر الموظف<\/option>/);
assert.match(html,/getElementById\('assignee'\)\.value=''/);
assert.doesNotMatch(html,/assignee'\)\.selectedIndex=0/);
assert.match(html,/delete payload\.next_run_at/);
console.log('PASS recurrence dates, ranges, Riyadh timezone and explicit assignee');
// Shared vectors let the SQL test verify that saved schedules match the preview.
if(process.argv.includes('--vectors'))console.log(JSON.stringify(cases));
