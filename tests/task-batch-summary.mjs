import assert from 'node:assert/strict';
import {summarizeBatch} from '../assets/js/task-batches.mjs';
assert.deepEqual(summarizeBatch([{status:'قيد الانتظار',overdue:true},{status:'قيد التنفيذ',overdue:false},{status:'بانتظار الاعتماد',overdue:true},{status:'مكتملة',overdue:true},{status:'ملغاة',overdue:true},{status:'قيد الانتظار',overdue:true,deleted:true}]),{total:6,remaining:2,pending:1,completed:1,overdue:1,cancelled:1,deleted:1});
assert.deepEqual(summarizeBatch([]),{total:0,remaining:0,pending:0,completed:0,overdue:0,cancelled:0,deleted:0});
console.log('Batch counters exclude approval, completed, cancelled and deleted tasks from remaining/overdue.');
