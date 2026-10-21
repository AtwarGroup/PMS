import assert from "node:assert/strict";
import {
  quoteTotal,
  requestActions,
  summary,
  settlement,
  filterRequests,
  escapeHTML,
} from "../assets/js/fleet-model.mjs";
assert.equal(quoteTotal({ parts: 0.1, labor: 0.2, tax: 0 }), 0.3);
const r = {
  driver_id: "driver",
  accountant_id: "finance",
  manager_id: "manager",
  state: "repair",
  advance: 301,
  invoice_total: 280,
  route: "large",
};
assert.deepEqual(settlement(r), {
  amount: 21,
  kind: "refund",
  label: "استرداد المتبقي من السائق",
});
assert.deepEqual(
  requestActions(r, { employee_id: "driver", user_id: "driver" }),
  ["request_increase", "confirm_repair"],
);
assert.deepEqual(
  requestActions(
    { ...r, state: "settlement" },
    { employee_id: "else", user_id: "finance", can_finance: true },
  ),
  ["settle", "return"],
);
assert.deepEqual(
  requestActions(
    { ...r, state: "closed" },
    { employee_id: "driver", user_id: "driver", can_approve: true },
  ),
  [],
);
assert.deepEqual(
  requestActions(
    { ...r, state: "fleet_review" },
    { employee_id: "driver", user_id: "driver", can_approve: true },
  ),
  [],
);
assert.equal(summary([{ ...r, state: "closed" }, r]).cost, 280);
assert.equal(summary([{ ...r, state: "closed" }, r]).outstanding, 301);
assert.equal(
  filterRequests(
    [{ ...r, description: "إصلاح سيارة", plate: "ABC", number: 11 }],
    { query: "11", state: "repair" },
  ).length,
  1,
);
assert.equal(escapeHTML("<img>"), "&lt;img&gt;");
console.log(
  "Fleet currency, settlement, action boundaries, terminal states and scoped summaries passed.",
);

const {money,englishDigits,dashboardRequests,types}=await import('../assets/js/fleet-model.mjs');
assert.deepEqual(Object.keys(types),['repair','emergency']);
assert.equal(money(1234.5),'1,234.50');
assert.equal(englishDigits('١٢٣ ۴۵۶'),'123 456');
const ctx={employee_id:'manager',team_employee_ids:['driver'],requests:[{driver_id:'manager'},{driver_id:'driver'},{driver_id:'other'}]};
assert.equal(dashboardRequests(ctx,'personal').length,1);
assert.equal(dashboardRequests(ctx,'team').length,1);
assert.deepEqual(requestActions({driver_id:'driver',state:'draft'},{...ctx,user_id:'manager'}),['edit','submit']);
assert.deepEqual(requestActions({driver_id:'driver',state:'repair'},{...ctx,user_id:'manager'}),[]);
