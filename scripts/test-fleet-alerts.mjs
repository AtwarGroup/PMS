import { createTestDB, ids, seedAssignedVehicle } from "./fleet-test-db.mjs";
import assert from "node:assert/strict";
process.on("uncaughtException", (e) => {
  console.error(e.message, e.where || "");
  process.exit(1);
});
const { db, rpc } = await createTestDB();
await rpc('admin','access_direct_save',{p_profile:ids.admin,p_rules:[{permission:'fleet.approve',scope:'all'}]});
assert.equal((await db.query('select private.fleet_owner() id')).rows[0].id,ids.fleet);
const vehicle = await seedAssignedVehicle(db,rpc,"fleet", {
  p_id: null,
  p_revision: null,
  p_data: {
    plate: "ALERT 1",
    vin: "ALERT-00001",
    vehicle_type: "QA",
    driver_id: ids.driver,
    active: true,
    odometer: 0,
  },
  p_reason: "تجربة الوثائق",
});
const date = async (days) =>
  (
    await db.query(
      "select (timezone('Asia/Riyadh',now())::date+$1::integer)::text d",
      [days],
    )
  ).rows[0].d;
const save = async (kind, days, revision = null) =>
  rpc("fleet", "fleet_document_save", {
    p_vehicle: vehicle,
    p_kind: kind,
    p_expires: await date(days),
    p_revision: revision,
    p_reason: "تجربة تاريخ الانتهاء",
  });
await save("insurance", 40);
assert.equal(
  (await db.query("select count(*) n from public.notifications")).rows[0].n,
  0,
);
await assert.rejects(
  () =>
    rpc("fleet", "fleet_alert_setting_save", {
      p_kind: "insurance",
      p_days: 45,
      p_revision: 1,
    }),
  /Administrator/,
);
await rpc("admin", "fleet_alert_setting_save", {
  p_kind: "insurance",
  p_days: 45,
  p_revision: 1,
});
let rows = (await db.query("select * from public.notifications")).rows;
assert.equal(rows.length, 3);
assert.deepEqual(
  rows.map((r) => r.recipient_id).sort(),
  [ids.fleet, ids.driver, ids.manager].sort(),
);
await db.query("select private.process_fleet_document_alerts()");
assert.equal(
  (await db.query("select count(*) n from public.notifications")).rows[0].n,
  3,
);
const own = rows.find((r) => r.recipient_id === ids.driver);
assert.equal(
  await rpc("driver", "fleet_document_open", { p_notification: own.id }),
  vehicle,
);
await assert.rejects(
  () => rpc("outsider", "fleet_document_open", { p_notification: own.id }),
  /متاحة/,
);
assert.equal(
  (await rpc("outsider", "fleet_documents_context")).documents.length,
  0,
);
assert.equal(
  (await rpc("manager", "fleet_documents_context")).documents.length,
  1,
);
await assert.rejects(
  async () =>
    rpc("driver", "fleet_document_save", {
      p_vehicle: vehicle,
      p_kind: "insurance",
      p_expires: await date(20),
      p_revision: 1,
      p_reason: "محاولة ممنوعة",
    }),
  /denied/,
);
await save("insurance", 200, 1);
assert.equal(
  (await db.query("select count(*) n from public.notifications")).rows[0].n,
  3,
);
await save("insurance", -1, 2);
assert.equal(
  (await db.query("select count(*) n from public.notifications")).rows[0].n,
  6,
);
await assert.rejects(() => save("insurance", 10, 1), /حدّث الصفحة/);
for (const kind of ["authorization", "registration", "inspection"])
  await save(kind, 30);
assert.equal(
  (await db.query("select count(*) n from public.notifications")).rows[0].n,
  15,
);
await rpc("admin", "fleet_alert_setting_save", {
  p_kind: "registration",
  p_days: 0,
  p_revision: 1,
});
await save("registration", 1, 1);
await db.query("select private.process_fleet_document_alerts()");
assert.equal(
  (await db.query("select count(*) n from public.notifications")).rows[0].n,
  15,
);
await save("registration", 0, 2);
assert.equal(
  (await db.query("select count(*) n from public.notifications")).rows[0].n,
  18,
);
await db.query("update public.profiles set active=false where id=$1", [
  ids.manager,
]);
await save("inspection", 20, 1);
assert.equal(
  (await db.query("select count(*) n from public.notifications")).rows[0].n,
  20,
);
await db.query("update private.fleet_vehicles set driver_id=$1 where id=$2", [
  ids.outsider,
  vehicle,
]);
assert(
  !(await rpc("fleet", "fleet_documents_context")).documents.some(
    (d) => d.kind === "authorization",
  ),
);
await assert.rejects(
  () => rpc("driver", "fleet_document_open", { p_notification: own.id }),
  /متاحة/,
);
await db.exec("begin;set local role authenticated;");
await assert.rejects(
  () => db.query("select private.process_fleet_document_alerts()"),
  /permission denied/,
);
await db.exec("rollback");
console.log(
  "PASS: four document types, 30/45/custom windows, exact three recipients, duplicate prevention, renewed/expired/today, inactive recipients, admin-only settings, unauthorized access and transfer invalidates old driver authorization.",
);

const datesBefore=(await db.query('select count(*) n from private.fleet_documents')).rows[0].n;
const notificationsBefore=(await db.query('select count(*) n from public.notifications')).rows[0].n;
const importRows=[{plate:'DOC IMPORT',vin:'DOC-IMPORT-00001',vehicle_type:'QA',driver_id:null,active:true,odometer:0,documents:{insurance:await date(10),authorization:await date(10)}}];
await rpc('fleet','fleet_import',{p_rows:importRows,p_source_hash:'d'.repeat(64),p_dry_run:true});
assert.equal((await db.query('select count(*) n from private.fleet_documents')).rows[0].n,datesBefore);assert.equal((await db.query('select count(*) n from public.notifications')).rows[0].n,notificationsBefore);
await rpc('fleet','fleet_import',{p_rows:importRows,p_source_hash:'d'.repeat(64),p_dry_run:false});assert.equal((await db.query('select count(*) n from private.fleet_documents')).rows[0].n,datesBefore+1);
await assert.rejects(()=>rpc('fleet','fleet_import',{p_rows:[{...importRows[0],plate:'BAD DATE',vin:'BAD-DATE-00001',documents:{insurance:'2026-99-99'}}],p_source_hash:'e'.repeat(64),p_dry_run:false}),/date|range/);
assert.equal((await db.query("select count(*) n from private.fleet_vehicles where plate='BAD DATE'")).rows[0].n,0);
console.log('PASS: vehicle and date import atomicity, dry-run notification rollback and malformed-date rollback.');
await db.close();
