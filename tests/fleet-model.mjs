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
