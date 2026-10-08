import assert from 'node:assert/strict';
import {riyadhToday,periodicDue,jobStage,addReviewMonths} from '../assets/js/job-workflow-model.mjs';
assert.equal(riyadhToday(new Date('2026-10-08T21:00:00Z')),'2026-10-09');
assert.equal(riyadhToday(new Date('2026-10-08T20:59:59Z')),'2026-10-08');
assert.equal(periodicDue({enabled:true,due_on:'2026-10-09'},'2026-10-09'),true);
assert.equal(periodicDue({enabled:false,due_on:'2026-10-09'},'2026-10-09'),false);
assert.equal(periodicDue({enabled:true,needs_changes:true,due_on:'2026-10-09'},'2026-10-09'),false);
assert.equal(periodicDue({enabled:true,due_on:'2026-10-10'},'2026-10-09'),false);
assert.equal(jobStage({status:'MANAGER_APPROVED',final_reviewed_at:'now',scheduled_effective_date:'2026-11-01',schedule_status:'PENDING'}),'معتمد بانتظار السريان');
assert.match(jobStage({status:'MANAGER_APPROVED',scheduled_effective_date:'2026-11-01',schedule_status:'BLOCKED'}),/تعذر/);
console.log('Riyadh date boundary, periodic due states and scheduled approval labels passed');

assert.equal(addReviewMonths('2026-10-09',12),'2027-10-09');assert.equal(addReviewMonths('2024-02-29',12),'2025-02-28');
