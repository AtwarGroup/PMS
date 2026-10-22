process.on("uncaughtException", (e) => {
  console.error(e.message, e.detail || "", e.where || "");
  process.exit(1);
});
import { createTestDB, ids } from "./fleet-test-db.mjs";
import assert from "node:assert/strict";
const { db, rpc } = await createTestDB();
console.log("HR/access migrations + fleet migration applied to PostgreSQL 17.");
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
    plate: "QA 123",
    vin: "QA-000001",
    vehicle_type: "تويوتا",
    model: "2025",
    city: "جدة",
    driver_id: ids.driver,
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
let id = await draft(400);
let r = (await detail("driver", id)).request;
const quotes = r.quotes.map(q => ({...q, file_id:r.quotes[0].file_id}));
await rpc("driver","fleet_request_save",{p_id:id,p_revision:r.revision,p_data:{...r,quotes}});
await deny(()=>cmd("driver",id,"submit"),/ملف مستقل/);
id = await draft(300);
await cmd("driver",id,"submit");await cmd("manager",id,"approve");
await deny(()=>cmd("driver",id,"request_increase",{total:400.004,reason:"زيادة تكلفة"}),/منزلتين/);
await deny(()=>cmd("driver",id,"confirm_repair",{total:300.004,received:true,invoice_id:null}),/منزلتين/);
id = await draft(400);
await cmd("driver",id,"submit");await cmd("fleet",id,"approve");
await cmd("accountant",id,"confirm_advance",{amount:400,reference:"QA-400",evidence_id:await upload("accountant",id,"payment")});
await cmd("driver",id,"request_increase",{total:450,reason:"زيادة معتمدة"});
await cmd("fleet",id,"approve_increase");
await cmd("accountant",id,"return",{reason:"مراجعة الصرف"});
assert.equal((await detail("driver",id)).request.state,"awaiting_advance");
await deny(()=>cmd("driver",id,"confirm_repair",{total:450,received:true}),/غير مسموح/);
await cmd("accountant",id,"confirm_advance",{amount:50,reference:"QA-50",evidence_id:await upload("accountant",id,"payment")});
await cmd("driver",id,"confirm_repair",{total:450,received:true,invoice_id:await upload("driver",id,"invoice")});
await cmd("accountant",id,"settle",{amount:0,reference:"QA-zero"});
assert.equal((await detail("driver",id)).request.state,"closed");
// A designated approver is used only when there is no HR manager.
await db.query("update private.hr_employees set manager_id=null where id=$1",[ids.driver]);
id=await draft(300);
await deny(()=>cmd("driver",id,"submit"),/المدير المباشر/);
await db.query("insert into private.fleet_designated_approvers values($1,$2)",[ids.driver,ids.fleet]);
await cmd("driver",id,"submit");
assert.equal((await detail("fleet",id)).request.manager_id,ids.fleet);
await deny(()=>cmd("driver",id,"approve"),/غير مسموح/);
await cmd("fleet",id,"approve");
assert.equal((await detail("driver",id)).request.state,"repair");
assert.equal((await db.query("select manager_id from private.hr_employees where id=$1",[ids.driver])).rows[0].manager_id,null);
await db.query("update private.hr_employees set manager_id=$1 where id=$2",[ids.manager,ids.driver]);
id=await draft(300);await cmd("driver",id,"submit");
assert.equal((await detail("driver",id)).request.manager_id,ids.manager);
// Direct RPC must enforce the same self-review restriction as the screen.
await db.query("update private.fleet_vehicles set driver_id=$1 where id=$2",[ids.fleet,vehicle]);
id=await draftForFleet();
async function draftForFleet(){
const data={vehicle_id:vehicle,accountant_id:ids.accountant,description:"صيانة سيارة مسؤول الأسطول",fault_notes:"عطل تجريبي",request_type:"repair",odometer:200,quotes:[],selected_quote:0};
const id=await rpc("fleet","fleet_request_save",{p_id:null,p_revision:null,p_data:data});
for(let i=0;i<3;i++)data.quotes.push({supplier:"ورشة "+i,parts:400,labor:0,tax:0,file_id:await upload("fleet",id)});
await rpc("fleet","fleet_request_save",{p_id:id,p_revision:(await detail("fleet",id)).request.revision,p_data:data});
await cmd("fleet",id,"submit");return id;
}
for(const action of ["return","reject"])await deny(()=>cmd("fleet",id,action,{reason:"اختبار فصل الصلاحيات"}),/Action denied/);
await db.close();console.log("Fleet adversarial integrity checks passed.");
