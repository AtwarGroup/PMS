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
await db.exec("begin;set local role authenticated;");
await assert.rejects(
  () => db.query("select * from private.fleet_requests"),
  /permission denied/,
);
await db.exec("rollback");
await db.exec("begin;set local role anon;");
await assert.rejects(
  () => db.query("select public.fleet_snapshot()"),
  /permission denied/,
);
await db.exec("rollback");
assert.equal(
  (
    await db.query(
      "select count(*) n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relname like 'fleet_%'and c.relkind='r' and not c.relrowsecurity",
    )
  ).rows[0].n,
  0,
);
console.log(
  "PASS: outsider, raw table and anonymous access denied; RLS enabled on every fleet table.",
);

// An increase that crosses 300 SAR must enter the funded route before more work.
id = await draft(200);
await cmd("driver", id, "submit");
await cmd("manager", id, "approve");
await cmd("driver", id, "request_increase", {
  total: 301,
  reason: "زيادة تتجاوز الحد",
});
await cmd("fleet", id, "approve_increase");
let crossed = (await detail("driver", id)).request;
assert.equal(crossed.route, "large");
assert.equal(crossed.state, "awaiting_advance");
await cmd("accountant", id, "confirm_advance", {
  amount: 301,
  reference: "QA-CROSS-THRESHOLD",
  evidence_id: await upload("accountant", id, "payment"),
});
await cmd("driver", id, "confirm_repair", {
  total: 301,
  invoice_id: await upload("driver", id, "invoice"),
  received: true,
});
await cmd("accountant", id, "settle", {
  amount: 0,
  reference: "QA-ZERO-DIFFERENCE",
});
console.log(
  "PASS: crossing 300 via an approved increase requires funding, with zero-difference settlement supported.",
);
// Boundary, revocation, source composition and concurrency checks use the real access APIs.
id = await draft(301);
let before = (await detail("driver", id)).request;
await cmd("driver", id, "submit");
await deny(
  () =>
    rpc("driver", "fleet_command", {
      p_id: id,
      p_revision: before.revision,
      p_action: "submit",
      p_data: {},
    }),
  /حدّث الصفحة/,
);
await deny(
  () =>
    rpc("driver", "fleet_upload", {
      p_request: id,
      p_kind: "quote",
      p_name: "late.pdf",
      p_mime: "application/pdf",
      p_base64: "JVBERi0xLjQ=",
    }),
  /Upload denied/,
);
await deny(
  () =>
    rpc("outsider", "fleet_vehicle_save", {
      p_id: null,
      p_revision: null,
      p_data: {},
      p_reason: "محاولة ممنوعة",
    }),
  /denied/,
);
const adminDetail = await db.query(
  "select set_config('request.jwt.claims',$1,false)",
  [JSON.stringify({ sub: ids.admin, role: "authenticated" })],
);
const hr = (
  await db.query("select public.employee_master_detail($1) j", [ids.driver])
).rows[0].j;
assert.equal(hr.fleet_vehicles.length, 1);
await assert.rejects(
  () =>
    db.query(
      "select public.employee_master_save($1,'vehicles',1,'{}',current_date,'تعديل قديم')",
      [ids.driver],
    ),
  /إدارة الأسطول/,
);
await rpc("admin", "access_direct_save", {
  p_profile: ids.fleet,
  p_rules: [
    { permission: "fleet.vehicles.read", scope: "all" },
    { permission: "fleet.vehicles.write", scope: "all" },
  ],
});
await deny(() => cmd("fleet", id, "approve"), /Access denied|غير مسموح/);
await rpc("admin", "access_direct_save", {
  p_profile: ids.fleet,
  p_rules: [
    { permission: "fleet.approve", scope: "all" },
    { permission: "fleet.vehicles.read", scope: "all" },
    { permission: "fleet.vehicles.write", scope: "all" },
  ],
});
const role = await rpc("admin", "access_role_save", {
  p_id: null,
  p_revision: null,
  p_name: "QA team fleet follow-up",
  p_description: "اختبار النطاق",
  p_active: true,
  p_rules: [{ permission: "fleet.requests.read", scope: "team" }],
});
await rpc("admin", "access_assign_roles", {
  p_profile: ids.outsider,
  p_roles: [role],
  p_expected: [],
});
assert.equal((await snapshot("outsider")).requests.length, 0);
await db.query("update private.hr_employees set manager_id=$1 where id=$2", [
  ids.outsider,
  ids.driver,
]);
assert((await snapshot("outsider")).requests.length > 0);
await rpc("admin", "access_role_save", {
  p_id: role,
  p_revision: 1,
  p_name: "QA team fleet follow-up",
  p_description: "اختبار النطاق",
  p_active: false,
  p_rules: [{ permission: "fleet.requests.read", scope: "team" }],
});
// The current direct manager retains access independently of an optional role.
assert((await snapshot("outsider")).requests.length > 0);
await db.query("update private.hr_employees set manager_id=$1 where id=$2", [ids.manager,ids.driver]);
assert.equal((await snapshot("outsider")).requests.length, 0);
await rpc("admin", "access_direct_save", {
  p_profile: ids.outsider,
  p_rules: [{ permission: "fleet.requests.read", scope: "all" }],
});
assert((await snapshot("outsider")).requests.length > 0);
await rpc("admin", "access_direct_save", {
  p_profile: ids.outsider,
  p_rules: [],
});
assert.equal((await snapshot("outsider")).requests.length, 0);
await db.query("update private.hr_employees set manager_id=$1 where id=$2", [
  ids.manager,
  ids.driver,
]);
await db.query("update public.profiles set active=false where id=$1", [
  ids.accountant,
]);
await deny(() => snapshot("accountant"), /Authentication required|ATWAR_MODULE_DENIED/);
await db.query("update public.profiles set active=true where id=$1", [
  ids.accountant,
]);
await rpc("admin", "access_direct_save", {
  p_profile: ids.outsider,
  p_rules: [{ permission: "fleet.approve", scope: "all" }],
});
const duplicateOwner = await draft(200);
await deny(() => cmd("driver", duplicateOwner, "submit"), /مسؤول أسطول واحد/);
await rpc("admin", "access_direct_save", {
  p_profile: ids.outsider,
  p_rules: [],
});
console.log(
  "PASS: stale revisions, late uploads, vehicle authority, canonical HR display, immediate direct/role revocation, team scope, inactive accounts and single fleet owner.",
);
const rows = [
    {
      plate: "IMPORT 1",
      vin: "IMPORT-00001",
      vehicle_type: "QA imported",
      model: "2025",
      city: "جدة",
      driver_id: ids.driver,
      active: true,
      odometer: 0,
    },
  ],
  hash = "a".repeat(64);
const args = { p_rows: rows, p_source_hash: hash, p_dry_run: true };
let imported = await rpc("fleet", "fleet_import", args);
assert.equal(imported.added, 1);
assert.equal((await snapshot("driver")).vehicles.length, 1);
imported = await rpc("fleet", "fleet_import", { ...args, p_dry_run: false });
assert.equal((await snapshot("driver")).vehicles.length, 2);
await deny(
  () => rpc("fleet", "fleet_import", { ...args, p_dry_run: false }),
  /سابقًا/,
);
await deny(() => rpc("outsider", "fleet_import", args), /denied/);
await deny(
  () =>
    rpc("fleet", "fleet_import", {
      p_rows: [rows[0], { ...rows[0], vin: "IMPORT-00002" }],
      p_source_hash: "b".repeat(64),
      p_dry_run: false,
    }),
  /Duplicate source plates/,
);
await deny(() => detail("outsider", duplicateOwner), /Access denied/);
const invoice = await upload("driver", duplicateOwner, "quote");
const download = await rpc("driver", "fleet_download", { p_id: invoice });
assert.equal(download.mime, "application/pdf");
await deny(
  () => rpc("outsider", "fleet_download", { p_id: invoice }),
  /Access denied/,
);
await deny(
  () =>
    rpc("driver", "fleet_upload", {
      p_request: duplicateOwner,
      p_kind: "quote",
      p_name: "fake.png",
      p_mime: "image/png",
      p_base64: Buffer.from("not an image").toString("base64"),
    }),
  /صالح/,
);
console.log(
  "PASS: dry-run rollback, transactional import, duplicate-source prevention, upload signature validation and protected download.",
);

const security = await db.query(
  `select p.proname,n.nspname,p.prosecdef,has_function_privilege('anon',p.oid,'execute') anonymous,has_function_privilege('authenticated',p.oid,'execute') client,p.proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','private')and p.proname like 'fleet_%'`,
);
assert(security.rows.every((r) => !r.anonymous));
assert(
  security.rows
    .filter((r) => r.nspname === "public")
    .every((r) => !r.prosecdef),
);
assert(
  security.rows.every((r) =>
    r.proconfig?.some((s) => s.startsWith("search_path=")),
  ),
);
const tableGrants = await db.query(
  `select c.relname,has_table_privilege('authenticated',c.oid,'select,insert,update,delete') granted from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private'and c.relname like 'fleet_%'and c.relkind='r'`,
);
assert(tableGrants.rows.every((r) => !r.granted));
// Migration import handling must not leak real employee/vehicle data into repository fixtures.
console.log(
  "PASS: no anonymous function grants, public invoker wrappers, fixed search paths and no raw client table privileges.",
);
// Manager submission is scoped to the current direct reporting line and the car's employee.
const managerCar=await rpc('fleet','fleet_vehicle_save',{p_id:null,p_revision:null,p_data:{plate:'MANAGER 777',vin:'QA-MANAGER-777',vehicle_type:'سيارة المدير',driver_id:ids.manager,odometer:0,active:true},p_reason:'اختبار طلب المدير الشخصي'});
await db.query('update private.hr_employees set manager_id=$1 where id=$2',[ids.admin,ids.manager]);
async function managerDraft(targetVehicle=vehicle,type='repair'){
 const data={vehicle_id:targetVehicle,driver_id:ids.outsider,accountant_id:ids.accountant,description:'طلب المدير للفريق',fault_notes:'تشخيص',request_type:type,odometer:1000,quotes:[],selected_quote:0};
 const request=await rpc('manager','fleet_request_save',{p_id:null,p_revision:null,p_data:data});
 for(let i=0;i<3;i++)data.quotes.push({supplier:'ورشة المدير '+i,parts:200,labor:0,tax:0,file_id:await upload('manager',request)});
 await rpc('manager','fleet_request_save',{p_id:request,p_revision:(await detail('manager',request)).request.revision,p_data:data});
 return request;
}
const teamRequest=await managerDraft();
assert.equal((await detail('manager',teamRequest)).request.driver_id,ids.driver);
await cmd('manager',teamRequest,'submit');
assert.equal((await detail('manager',teamRequest)).request.manager_id,ids.manager);
await cmd('manager',teamRequest,'approve');
await deny(()=>cmd('manager',teamRequest,'confirm_repair',{}),/غير مسموح/);
const ownManagerRequest=await managerDraft(managerCar);
await cmd('manager',ownManagerRequest,'submit');
assert.equal((await detail('manager',ownManagerRequest)).request.manager_id,ids.admin);
await deny(()=>cmd('manager',ownManagerRequest,'approve'),/غير مسموح/);
await cmd('admin',ownManagerRequest,'approve');
await deny(()=>managerDraft(vehicle,'fuel'),/نوع الطلب/);
await deny(()=>managerDraft(vehicle,'inspection'),/نوع الطلب/);
const outsiderCar=await rpc('fleet','fleet_vehicle_save',{p_id:null,p_revision:null,p_data:{plate:'OUTSIDER 777',vehicle_type:'خارج الفريق',driver_id:ids.outsider,odometer:0,active:true},p_reason:'اختبار العزل'});
await deny(()=>managerDraft(outsiderCar),/السيارة ليست/);
const pendingTeam=await managerDraft();
const pendingFile=await upload('manager',pendingTeam);
await db.query('update private.hr_employees set manager_id=$1 where id=$2',[ids.outsider,ids.driver]);
await deny(()=>rpc('manager','fleet_download',{p_id:pendingFile}),/Access denied/);
await deny(()=>cmd('manager',pendingTeam,'submit'),/Access denied/);
await db.query('update private.hr_employees set manager_id=$1 where id=$2',[ids.manager,ids.driver]);
assert.ok((await snapshot('manager')).team_employee_ids.includes(ids.driver));
assert.equal((await snapshot('manager')).vehicles.find(v=>v.id===managerCar).can_request,true);
await db.query("update public.profiles set allowed_modules=array['policies'] where id=$1",[ids.manager]);
await deny(()=>snapshot('manager'),/ATWAR_MODULE_DENIED/);
await db.query("update public.profiles set allowed_modules=array['fleet','policies'] where id=$1",[ids.manager]);
console.log('PASS: manager own/team requests, correct employee assignment, quote uploads, separate supervisor approval, ordinary manager receipt denied, unrelated-team denial, fuel/inspection denied and reporting-line/unit revocation.');
await db.query("update public.profiles set allowed_modules=array['policies'] where id=$1",[ids.driver]);
await deny(()=>snapshot('driver'),/ATWAR_MODULE_DENIED/);
await deny(()=>rpc('driver','fleet_documents_context'),/ATWAR_MODULE_DENIED/);
await deny(()=>rpc('driver','fleet_download',{p_id:invoice}),/ATWAR_MODULE_DENIED/);
await db.query("update public.profiles set allowed_modules=array['fleet','policies'] where id=$1",[ids.driver]);
assert.ok((await snapshot('driver')).vehicles.length);
console.log('PASS: account unit revocation blocks fleet RPCs and protected files immediately; regrant restores access.');
// Fleet operations are global; finance is assigned-only; administrator covers both.
let c=await snapshot('fleet');
assert.equal(c.can_create,true);assert.equal(c.can_operate,true);assert.equal(c.can_finance,false);
assert.equal(c.vehicles.find(v=>v.id===outsiderCar).can_request,true);
const fullDraft=async(actor,car=outsiderCar)=>{
 const data={vehicle_id:car,accountant_id:ids.accountant,description:'اختبار مسؤوليات الأسطول',request_type:'repair',odometer:2000,quotes:[],selected_quote:0};
 const request=await rpc(actor,'fleet_request_save',{p_id:null,p_revision:null,p_data:data});
 for(let i=0;i<3;i++)data.quotes.push({supplier:'ورشة الصلاحيات '+i,parts:400,labor:0,tax:0,file_id:await upload(actor,request)});
 await rpc(actor,'fleet_request_save',{p_id:request,p_revision:(await detail(actor,request)).request.revision,p_data:data});return request;
};
const fleetForOther=await fullDraft('fleet');
await cmd('fleet',fleetForOther,'submit');
await cmd('fleet',fleetForOther,'approve');
await deny(()=>cmd('fleet',fleetForOther,'confirm_advance',{amount:400,reference:'DENIED'}),/غير مسموح/);
await deny(()=>upload('fleet',fleetForOther,'payment'),/Upload denied/);
await cmd('admin',fleetForOther,'confirm_advance',{amount:400,reference:'ADMIN-ADVANCE',evidence_id:await upload('admin',fleetForOther,'payment')});
await cmd('fleet',fleetForOther,'confirm_repair',{total:400,received:true,invoice_id:await upload('fleet',fleetForOther,'invoice')});
await cmd('admin',fleetForOther,'settle',{amount:0,reference:'ADMIN-SETTLEMENT'});
assert.equal((await detail('admin',fleetForOther)).request.state,'closed');
c=await snapshot('accountant2');assert.equal(c.finance_only,true);assert.equal(c.can_create,false);assert.equal(c.can_view_vehicles,false);assert.equal(c.can_view_documents,false);assert.equal(c.requests.length,0);
await deny(()=>detail('accountant2',fleetForOther),/Access denied/);
assert.equal((await rpc('accountant2','fleet_documents_context')).vehicles.length,0);
// A financial-only employee's incidental reporting line cannot widen their request access.
await db.query('update private.hr_employees set manager_id=$1 where id=$2',[ids.accountant2,ids.outsider]);
assert.equal((await snapshot('accountant2')).requests.length,0);
const financeCar=await rpc('fleet','fleet_vehicle_save',{p_id:null,p_revision:null,p_data:{plate:'FINANCE 222',vehicle_type:'سيارة المحاسب',driver_id:ids.accountant2,active:true,odometer:0},p_reason:'اختبار محاسب يملك سيارة'});
c=await snapshot('accountant2');assert.equal(c.can_create,true);assert.equal(c.can_view_documents,true);assert.equal(c.vehicles.length,1);
// A real system administrator need not have an employee/car record to operate the module.
const noEmployeeAdmin=(await db.query("insert into public.profiles(id,email,full_name,role)values(gen_random_uuid(),'no-employee-admin@fleet.atwargroup.test','مسؤول بلا سجل موظف','admin')returning id")).rows[0].id;
const adminForOther=await fullDraft(noEmployeeAdmin);
assert.equal((await detail(noEmployeeAdmin,adminForOther)).request.driver_id,ids.outsider);
c=await snapshot(noEmployeeAdmin);assert.equal(c.can_manage,true);assert.equal(c.can_approve,true);assert.equal(c.can_finance,true);
console.log('PASS: owner requests/operates for any employee without finance; admin finance overrides work without employee record; accountant without car sees assigned requests only and own-car sections appear when assigned a car.');
// System administrators can also hold explicit grants without becoming a second operational owner.
await rpc('admin','access_direct_save',{p_profile:ids.admin,p_rules:[{permission:'fleet.approve',scope:'all'}]});
assert.equal((await db.query('select private.fleet_owner() id')).rows[0].id,ids.fleet);
const withExplicitAdmin=await draft(301);
await cmd('driver',withExplicitAdmin,'submit');
await cmd('admin',withExplicitAdmin,'approve');
assert.equal((await detail('driver',withExplicitAdmin)).request.state,'awaiting_advance');
await db.query("update private.access_direct_tasks set permissions=array[]::text[] where profile_id=$1",[ids.fleet]);
assert.equal((await db.query('select private.fleet_owner() id')).rows[0].id,ids.admin);
await db.query("update private.access_direct_tasks set permissions=array[]::text[] where profile_id=$1",[ids.admin]);
await assert.rejects(()=>db.query('select private.fleet_owner()'),/مسؤول أسطول واحد/);
console.log('PASS: explicit administrator approval grants do not conflict with the operational fleet owner; sole explicit admin fallback and missing-owner guard remain valid.');

await db.close();
