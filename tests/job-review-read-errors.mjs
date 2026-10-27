import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const src=readFileSync(new URL('../assets/js/job-review-page.js',import.meta.url),'utf8');
const body=src.slice(src.indexOf('async function loadRelated()'),src.indexOf('async function tryLoadRelated()'));
let failed='';const empty=[];
const sb={from(name){return {select(){return this},eq(){return this},order(){return this},limit(){return this},maybeSingle(){return Promise.resolve({data:null,error:failed===name?new Error(name):null})},then(resolve){return Promise.resolve({data:empty,error:failed===name?new Error(name):null}).then(resolve)}}}};
const ctx=vm.createContext({sb,job:{id:'job'},me:{role:'admin'},canStage:()=>true,schedules:[],periodicReview:null,periodicEvents:[],proposals:['previous'],forms:[],comments:[],assignments:[],versions:[],weightReferences:[],openSchedule:()=>null});
vm.runInContext(body+'\nthis.loadRelated=loadRelated;',ctx);
for(const table of ['job_description_change_requests','job_description_forms','job_description_comments','employee_job_assignments']){failed=table;await assert.rejects(ctx.loadRelated(),new RegExp(table));assert.equal(ctx.proposals[0],'previous');}
failed='';await ctx.loadRelated();assert.equal(ctx.proposals.length,0);
console.log('PASS job review related reads distinguish failure from empty data');
