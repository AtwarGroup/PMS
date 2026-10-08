import assert from 'node:assert/strict';import {proposalDecisions,proposalNeedsAction,proposalNext} from '../assets/js/improvements-core.mjs';import {requestModel,renderRequests} from '../assets/js/workspace-core.mjs';
const admin={id:'a',role:'admin',active:true,status:'active'},employee={id:'e',role:'employee',active:true,status:'active'};
const proposal={id:'p',title:'<script>bad</script>',status:'SUBMITTED',requester_id:'e'};
assert.deepEqual(proposalDecisions(proposal,admin),['STUDY']);assert.deepEqual(proposalDecisions({...proposal,status:'STUDY'},admin),['ACCEPTED','DEFERRED','NOT_SUITABLE']);assert.deepEqual(proposalDecisions({...proposal,status:'ACCEPTED',task_id:'t'},admin),[]);assert.deepEqual(proposalDecisions(proposal,employee),[]);
assert.equal(proposalNeedsAction({...proposal,status:'DEFERRED'},admin),false);assert.equal(proposalNeedsAction({...proposal,status:'ACCEPTED'},admin),true);assert.equal(proposalNeedsAction(proposal,{...admin,active:false}),false);
const actions=requestModel({profile:admin,proposals:[proposal]}).actions;assert.equal(actions.length,1);assert.ok(actions[0].href.includes('improvements.html?id=p'));assert.ok(!renderRequests(actions,'').includes('<script>'));
assert.equal(requestModel({profile:employee,proposals:[proposal]}).tracking.length,1);assert.equal(requestModel({profile:{id:'other',role:'manager'},proposals:[proposal]}).tracking.length,0);
assert.ok(proposalNext({...proposal,task_id:'t'}).includes('التنفيذ'));
console.log('Improvement action scope, employee tracking, stages, links and escaping passed');
