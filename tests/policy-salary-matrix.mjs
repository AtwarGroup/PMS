import assert from 'node:assert/strict';
import {progressionRecords,filterSalaryRecords} from '../assets/js/policy-salary-tables.mjs';
const salary=[['N4','بائع','2,600–4,500','4,397–6,821'],['T8','أخصائي موارد بشرية','—','6,500–9,000']];
const bands=[['2,600–4,500','2,600 / 2,730 / 4,500'],['4,397–6,821','4,397 / 4,617 / 6,821'],['6,500–9,000','6,500 / 6,825 / 9,000']];
const records=progressionRecords(salary,bands);assert.equal(records.length,3);assert.equal(records[0].points[0],'2,600');assert.equal(records[0].points.at(-1),'4,500');assert.equal(filterSalaryRecords(records,{nation:'sa'}).length,2);assert.equal(filterSalaryRecords(records,{query:'اخصائي',grade:'T8',nation:'sa'}).length,1);assert.equal(filterSalaryRecords(records,{query:'بائع',grade:'T8'}).length,0);assert.throws(()=>progressionRecords(salary,[]),/غير متاحة/);
console.log('PASS job-based progression records, exact approved points, nationality restrictions and combined filters');
