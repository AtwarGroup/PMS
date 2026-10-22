import { PGlite } from "@electric-sql/pglite";
import { readFile } from "node:fs/promises";
export const ids = Object.fromEntries(
  [
    "admin",
    "manager",
    "driver",
    "fleet",
    "accountant",
    "outsider",
    "accountant2",
  ].map((key, i) => [
    key,
    `00000000-0000-4000-8000-${String(i + 1).padStart(12, "0")}`,
  ]),
);
export async function createTestDB() {
  const db = new PGlite();
  for (const file of [
    "tests/fixtures/fleet-base.sql",
    "supabase/migrations/20261020112323_employee_master_phase_two.sql",
    "supabase/migrations/20261020113022_employee_profile_consistency.sql",
    "supabase/migrations/20261020113254_employee_master_edit_guards.sql",
    "supabase/migrations/20261020122048_scalable_account_roles.sql",
    "supabase/migrations/20261021075735_fleet_management.sql",
    "supabase/migrations/20261021085736_fleet_document_alerts.sql",
  ]) {
    try {
      await db.exec(
        await readFile(new URL("../" + file, import.meta.url), "utf8"),
      );
    } catch (e) {
      e.message = `${file}: ${e.message}`;
      throw e;
    }
  }
  // Load the unchanged account/unit directory from main, without unrelated task,
  // project and storage policies (those tables are outside this fleet fixture).
  const units = await readFile(new URL('../supabase/migrations/20261021082206_account_module_access.sql', import.meta.url), 'utf8');
  await db.exec(units.split('-- Record-level boundaries')[0]);
  await db.exec(await readFile(new URL('../supabase/migrations/20261021135046_fleet_account_module_boundary.sql', import.meta.url),'utf8'));
  await db.exec('grant execute on function private.require_module(text),private.module_allowed(text) to authenticated');
  await db.exec(await readFile(new URL('../supabase/migrations/20261021143312_fleet_manager_requests_and_maintenance_types.sql', import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../supabase/migrations/20261022074348_fleet_responsibility_access.sql', import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../supabase/migrations/20261022081939_fleet_owner_admin_resolution.sql', import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../supabase/migrations/20261022091804_account_activation_service_validation.sql', import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../supabase/migrations/20261022092257_account_activation_service_guard.sql', import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../supabase/migrations/20261022132635_fleet_workflow_integrity.sql', import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../supabase/migrations/20261022133620_fleet_designated_approver.sql', import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../supabase/migrations/20261022161526_fleet_operations_handovers.sql',import.meta.url),'utf8'));
  for (const [key, id] of Object.entries(ids))
    await db.query(
      "insert into public.profiles(id,full_name,email,role)values($1,$2,$3,$4)",
      [
        id,
        {
          admin: "مسؤول النظام التجريبي",
          manager: "مدير السائق التجريبي",
          driver: "السائق التجريبي",
          fleet: "مسؤول الأسطول التجريبي",
          accountant: "المحاسب التجريبي",
          outsider: "موظف خارج الفريق",
          accountant2: "محاسب آخر",
        }[key],
        key + "@fleet.atwargroup.test",
        key === "admin" ? "admin" : key === "manager" ? "manager" : "employee",
      ],
    );
  await db.exec("update public.profiles set allowed_modules=array_append(allowed_modules,'fleet')");
  await db.exec(`insert into private.hr_departments(id,name)values('10000000-0000-4000-8000-000000000001','إدارة الاختبار');
 insert into private.hr_sections(id,department_id,name)values('10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','قسم الاختبار');
 insert into private.hr_titles(id,title)values('10000000-0000-4000-8000-000000000003','موظف تجريبي');`);
  for (const [i, [key, id]] of Object.entries(Object.entries(ids))) {
    await db.query(
      `insert into private.hr_employees(id,employee_code,full_name,email,department_id,section_id,title_id,profile_id,manager_id,join_date,effective_from)select $1,$2,full_name,email,'10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000003',id,$3,current_date,current_date from public.profiles where id=$1`,
      [id, String(99000 + Number(i)), key === "driver" ? ids.manager : null],
    );
  }
  await db.exec(
    `update private.access_direct_tasks set permissions=array['fleet.approve','fleet.vehicles.read','fleet.vehicles.write']where profile_id='${ids.fleet}';update private.access_direct_tasks set permissions=array['fleet.finance']where profile_id in('${ids.accountant}','${ids.accountant2}');`,
  );
  const rpc = async (user, name, args = {}) => {
    if (!/^fleet_[a-z_]+$|^access_[a-z_]+$|^account_(module_context|access_save)$/.test(name))
      throw Error("Unsupported test RPC");
    let result;
    await db.exec("begin");
    try {
      await db.exec("set local role authenticated");
      await db.query("select set_config('request.jwt.claims',$1,true)", [
        JSON.stringify({ sub: ids[user] || user, role: "authenticated" }),
      ]);
      const keys = Object.keys(args);
      if (keys.some((k) => !/^p_[a-z0-9_]+$/.test(k)))
        throw Error("Bad test parameter");
      const sql = `select public.${name}(${keys.map((k, i) => `${k} => $${i + 1}`).join(",")}) result`;
      const values = Object.values(args).map((v) =>
        v !== null && typeof v === "object" && !Array.isArray(v)
          ? JSON.stringify(v)
          : v,
      );
      result = (await db.query(sql, values)).rows[0].result;
      await db.exec("commit");
      return result;
    } catch (e) {
      await db.exec("rollback");
      throw e;
    }
  };
  return { db, rpc };
}
