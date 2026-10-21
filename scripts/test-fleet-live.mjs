import assert from 'node:assert/strict';
import {createLiveClient} from './fleet-live-client.mjs';
const {rpc,ids,employeeIds}=await createLiveClient();
const snapshot = (u) => rpc(u, "fleet_snapshot");
const detail = (u, id) => rpc(u, "fleet_detail", { p_id: id });
const cmd = async (u, id, action, data = {}) => {
  const r = (await detail(u, id)).request;
  return rpc(u, "fleet_command", {
    p_id: id,
    p_revision: r.revision,
    p_action: action,
    p_data: data,
  });
};
const vehicle = await rpc("fleet", "fleet_vehicle_save", {
  p_id: null,
  p_revision: null,
  p_data: {
    plate: "LIVE "+Date.now(),
    vin: "LIVE-"+Date.now(),
    vehicle_type: "تويوتا",
    model: "2025",
    city: "جدة",
    driver_id: employeeIds.driver,
    odometer: 100,
    active: true,
  },
  p_reason: "سيارة اختبار",
});
const upload = (u, id, kind = "quote") =>
  rpc(u, "fleet_upload", {
    p_request: id,
    p_kind: kind,
    p_name: "اختبار.pdf",
    p_mime: "application/pdf",
    p_base64: Buffer.from("%PDF-1.4\nQA").toString("base64"),
  });
async function draft(amount, count = 3) {
  const data = {
    vehicle_id: vehicle,
    accountant_id: ids.accountant,
    description: "إصلاح اختبار كامل",
    fault_notes: "تشخيص العطل",
    request_type: "repair",
    odometer: 200,
    quotes: [],
    selected_quote: 0,
  };
  const id = await rpc("driver", "fleet_request_save", {
    p_id: null,
    p_revision: null,
    p_data: data,
  });
  for (let i = 0; i < count; i++)
    data.quotes.push({
      supplier: "ورشة " + i,
      parts: amount,
      labor: 0,
      tax: 0,
      file_id: await upload("driver", id),
    });
  const r = (await detail("driver", id)).request;
  await rpc("driver", "fleet_request_save", {
    p_id: id,
    p_revision: r.revision,
    p_data: data,
  });
  return id;
}
const deny = async (fn, pattern) => {
  await assert.rejects(fn, pattern);
};
let id = await draft(300);
await cmd("driver", id, "submit");
assert.equal((await detail("manager", id)).request.state, "manager_review");
await deny(() => cmd("driver", id, "approve"), /غير مسموح/);
await cmd("manager", id, "approve");
assert.equal((await detail("driver", id)).request.state, "repair");
await deny(
  async () =>
    cmd("driver", id, "confirm_repair", {
      total: 301,
      invoice_id: await upload("driver", id, "invoice"),
      received: true,
    }),
  /تتجاوز/,
);
await cmd("driver", id, "confirm_repair", {
  total: 290,
  invoice_id: await upload("driver", id, "invoice"),
  received: true,
});
await cmd("fleet", id, "approve");
await deny(
  () => cmd("accountant2", id, "settle", {}),
  /Access denied|غير مسموح/,
);
await cmd("accountant", id, "settle", {
  amount: 290,
  reference: "QA-REIMBURSE",
  evidence_id: await upload("accountant", id, "payment"),
});
assert.equal((await detail("driver", id)).request.state, "closed");
await deny(() => cmd("driver", id, "submit"), /مقفل/);
console.log(
  "PASS: 300 SAR manager -> repair -> fleet -> reimbursement -> read-only.",
);
id = await draft(301);
await cmd("driver", id, "submit");
await cmd("fleet", id, "approve");
await deny(() => cmd("driver", id, "confirm_repair", {}), /غير مسموح/);
await deny(
  () =>
    cmd("accountant", id, "confirm_advance", {
      amount: 300,
      reference: "wrong",
    }),
  /يساوي/,
);
await cmd("accountant", id, "confirm_advance", {
  amount: 301,
  reference: "QA-ADVANCE",
  evidence_id: await upload("accountant", id, "payment"),
});
await cmd("driver", id, "request_increase", {
  total: 450,
  reason: "قطع إضافية قبل التنفيذ",
});
await deny(() => cmd("driver", id, "confirm_repair", {}), /غير مسموح/);
await cmd("fleet", id, "approve_increase");
await cmd("accountant", id, "confirm_advance", {
  amount: 149,
  reference: "QA-INCREASE",
  evidence_id: await upload("accountant", id, "payment"),
});
await cmd("driver", id, "confirm_repair", {
  total: 400,
  invoice_id: await upload("driver", id, "invoice"),
  received: true,
});
await deny(
  () => cmd("accountant", id, "reject", { reason: "لا يمكن إسقاط العهدة" }),
  /عهدة مصروفة/,
);
await cmd("accountant", id, "settle", {
  amount: 50,
  reference: "QA-REFUND",
  evidence_id: await upload("accountant", id, "refund"),
});
assert.equal((await detail("driver", id)).request.state, "closed");
assert.deepEqual(
  (await detail("driver", id)).payments.map((x) => [x.kind, Number(x.amount)]),
  [
    ["advance", 301],
    ["advance", 149],
    ["refund", 50],
  ],
);
console.log(
  "PASS: >300 advance, increase approval before work, incremental payment, invoice, refund and settlement.",
);
id = await draft(200, 1);
await cmd("driver", id, "submit");
assert.equal((await detail("fleet", id)).request.state, "quote_exception");
await deny(() => cmd("manager", id, "approve"), /غير مسموح/);
await deny(() => cmd("fleet", id, "approve_exception", {}), /الاستثناء/);
await cmd("fleet", id, "approve_exception", {
  reason: "تعذر الحصول على عروض أخرى",
});
await cmd("manager", id, "return", { reason: "تعديل بيانات الطلب" });
assert.equal((await detail("driver", id)).request.state, "returned");
const number = (await detail("driver", id)).request.number;
await cmd("driver", id, "submit");
assert.equal((await detail("driver", id)).request.number, number);
await cmd("fleet", id, "reject", { reason: "غير مطلوب" });
console.log(
  "PASS: quote exception, required reason, return preserving number, final rejection.",
);
await deny(
  () => rpc("outsider", "fleet_detail", { p_id: id }),
  /Access denied/,
);
assert.equal((await snapshot("outsider")).requests.length, 0);

console.log('Live GoTrue + PostgREST workflow tests passed.');
