process.on("uncaughtException", (e) => {
  console.error(e.message, e.detail || "", e.where || "");
  process.exit(1);
});
import { createTestDB, ids, seedAssignedVehicle } from "./fleet-test-db.mjs";
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
const vehicle = await seedAssignedVehicle(db,rpc,"fleet", {
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
const car=await rpc('fleet','fleet_vehicle_save',{p_id:null,p_revision:null,p_data:{plate:'HANDOVER 123',vehicle_type:'سيارة معاينة',active:true,odometer:10},p_reason:'اختبار التسليم'});
const hdata={vehicle_id:car,kind:'issue',employee_id:ids.driver,odometer:20,fuel_level:50,keys_count:2,spare_tire:true,tools:true,marks:[{part:'front_bumper',severity:'scratch',note:'خدش ظاهر في الصدام'}],no_marks:false,notes:'صور وبيانات تجريبية فقط'};
await deny(()=>rpc('driver','fleet_handover_save',{p_id:null,p_revision:null,p_data:hdata}),/denied/);
await deny(()=>rpc('accountant','fleet_vehicle_profile',{p_vehicle:car}),/denied/);
let hid=await rpc('fleet','fleet_handover_save',{p_id:null,p_revision:null,p_data:hdata});
const hd=(u='fleet',id=hid)=>rpc(u,'fleet_handover_detail',{p_id:id});
const hc=async(u,action,reason='',id=hid)=>rpc(u,'fleet_handover_command',{p_id:id,p_revision:(await hd(u,id)).handover.revision,p_action:action,p_reason:reason});
await deny(()=>hd('driver'),/denied/);
await deny(()=>rpc('fleet','fleet_handover_save',{p_id:null,p_revision:null,p_data:hdata}),/duplicate key/);
await deny(()=>rpc('fleet','fleet_handover_save',{p_id:hid,p_revision:1,p_data:{...hdata,marks:[{part:'injected',severity:'scratch',note:'اختبار رفض'}]}}),/موضع/);
await deny(()=>rpc('fleet','fleet_handover_save',{p_id:hid,p_revision:1,p_data:{...hdata,no_marks:true}}),/لا يمكن الإقرار/);
const photo=await rpc('fleet','fleet_handover_upload',{p_id:hid,p_name:'inspection.png',p_mime:'image/png',p_base64:Buffer.from('89504e470d0a1a0a','hex').toString('base64')});
await deny(()=>rpc('fleet','fleet_handover_upload',{p_id:hid,p_name:'fake.png',p_mime:'image/png',p_base64:Buffer.from('%PDF').toString('base64')}),/صورة صالحة/);
await deny(()=>rpc('outsider','fleet_handover_photo',{p_id:photo}),/denied/);
await hc('fleet','submit');
assert.equal((await hd('driver')).can_acknowledge,true);
await deny(()=>hc('manager','accept'),/غير مسموح/);
await deny(()=>hc('admin','accept'),/غير مسموح/);
await hc('driver','accept');
assert.equal((await hd('driver')).handover.state,'accepted');
let profile=await rpc('driver','fleet_vehicle_profile',{p_vehicle:car});assert.equal(profile.vehicle.driver_id,ids.driver);assert.equal(profile.vehicle.odometer,20);
await deny(()=>rpc('fleet','fleet_handover_photo_delete',{p_id:photo}),/denied/);
await deny(()=>rpc('fleet','fleet_handover_upload',{p_id:hid,p_name:'late.png',p_mime:'image/png',p_base64:'iVBORw0KGgo='}),/denied/);
await deny(()=>rpc('fleet','fleet_vehicle_save',{p_id:car,p_revision:profile.vehicle.revision,p_data:{...profile.vehicle,driver_id:ids.outsider},p_reason:'محاولة تجاوز'}),/محضر تسليم/);
await deny(()=>rpc('outsider','fleet_vehicle_profile',{p_vehicle:car}),/denied/);
// A driver can dispute a return; it does not release their assignment.
const issueId=hid;
hid=await rpc('fleet','fleet_handover_save',{p_id:null,p_revision:null,p_data:{...hdata,kind:'return',marks:[],no_marks:true,odometer:25}});
await hc('fleet','submit');await hc('driver','dispute','توجد ملاحظة غير مسجلة');
assert.equal((await rpc('driver','fleet_vehicle_profile',{p_vehicle:car})).vehicle.driver_id,ids.driver);
// Changing the vehicle while awaiting acknowledgement invalidates the prepared snapshot.
hid=await rpc('fleet','fleet_handover_save',{p_id:null,p_revision:null,p_data:{...hdata,kind:'return',marks:[],no_marks:true,odometer:25}});await hc('fleet','submit');
profile=await rpc('fleet','fleet_vehicle_profile',{p_vehicle:car});
await deny(()=>rpc('driver','fleet_vehicle_operation_save',{p_vehicle:car,p_revision:profile.vehicle.revision,p_status:'maintenance',p_reason:'اختبار صلاحية'}),/denied/);
await rpc('fleet','fleet_vehicle_operation_save',{p_vehicle:car,p_revision:profile.vehicle.revision,p_status:'maintenance',p_reason:'دخول الورشة'});
await deny(()=>hc('driver','accept'),/تغير سجل السيارة/);await hc('fleet','cancel','إعادة المعاينة بعد تحديث حالة السيارة');
profile=await rpc('fleet','fleet_vehicle_profile',{p_vehicle:car});
await rpc('fleet','fleet_vehicle_operation_save',{p_vehicle:car,p_revision:profile.vehicle.revision,p_status:'available',p_reason:'الخروج من الورشة'});
profile=await rpc('fleet','fleet_vehicle_profile',{p_vehicle:car});assert.equal(profile.operation_periods.length,2);assert.ok(profile.operation_periods.find(p=>p.status==='maintenance').ended_at);
hid=await rpc('fleet','fleet_handover_save',{p_id:null,p_revision:null,p_data:{...hdata,kind:'return',marks:[],no_marks:true,odometer:25}});await hc('fleet','submit');await hc('driver','accept');
assert.equal((await rpc('fleet','fleet_vehicle_profile',{p_vehicle:car})).vehicle.driver_id,null);
assert.equal((await hd('driver',issueId)).handover.state,'accepted');
await deny(()=>rpc('driver','fleet_vehicle_profile',{p_vehicle:car}),/denied/);
console.log('PASS: mapped inspection, independent driver acknowledgement, dispute, return, immutable photos, stale vehicle guard, controlled assignment and operation periods.');
// Workflow transitions notify only the current responsible account and deduplicate reminders.
const rid=await draft(300);await cmd('driver',rid,'submit');
let note=(await db.query("select * from public.notifications where fleet_request_id=$1 and recipient_id=$2 order by created_at desc",[rid,ids.manager])).rows[0];assert.equal(note.type,'FLEET_WORKFLOW');
assert.equal((await rpc('manager','fleet_workflow_notification_open',{p_notification:note.id})).request_id,rid);
await deny(()=>rpc('outsider','fleet_workflow_notification_open',{p_notification:note.id}),/no rows|denied/);
assert.equal((await detail('manager',rid)).journey.responsibles[0].id,ids.manager);
await cmd('manager',rid,'approve');assert.equal((await detail('driver',rid)).journey.responsibles[0].id,ids.driver);
await db.query("update private.fleet_requests set state_changed_at=now()-interval '4 days'where id=$1",[rid]);
await db.query('select private.process_fleet_workflow_alerts()');const count=(await db.query("select count(*)::int n from public.notifications where fleet_request_id=$1 and title like 'تذكير:%'",[rid])).rows[0].n;assert.equal(count,1);
await db.query('select private.process_fleet_workflow_alerts()');assert.equal((await db.query("select count(*)::int n from public.notifications where fleet_request_id=$1 and title like 'تذكير:%'",[rid])).rows[0].n,count);
let ops=await rpc('driver','fleet_operations_context');assert.ok(ops.overdue_requests.some(r=>r.id===rid));assert.equal((await rpc('outsider','fleet_operations_context')).overdue_requests.length,0);
await deny(()=>rpc('fleet','fleet_workflow_settings_save',{p_revision:1,p_stage_days:2,p_advance_days:5,p_handover_days:2}),/Administrator/);
await rpc('admin','fleet_workflow_settings_save',{p_revision:1,p_stage_days:2,p_advance_days:5,p_handover_days:2});
await deny(()=>rpc('admin','fleet_workflow_settings_save',{p_revision:1,p_stage_days:2,p_advance_days:5,p_handover_days:2}),/تحديث الإعدادات/);
await db.query("update public.profiles set allowed_modules=array_remove(allowed_modules,'fleet')where id=$1",[ids.driver]);
await deny(()=>rpc('driver','fleet_operations_context'),/غير متاحة|Access|صلاحية/);
await deny(()=>rpc('driver','fleet_handover_photo',{p_id:photo}),/غير متاحة|Access|صلاحية/);
const raw=(await db.query("select count(*)::int n from information_schema.role_table_grants where table_schema='private'and table_name in('fleet_handovers','fleet_handover_photos','fleet_operation_periods','fleet_workflow_deliveries','fleet_workflow_settings')and grantee in('anon','authenticated')")).rows[0].n;assert.equal(raw,0);
console.log('PASS: current-owner workflow alerts, notification authorization, hourly reminder deduplication, scoped exceptions, admin-only settings and immediate module revocation.');
await db.close();
