import { chromium, expect } from "@playwright/test";
import { mkdir } from "node:fs/promises";
import { startPreview } from "./fleet-preview.mjs";
import assert from "node:assert/strict";
import { ids } from "./fleet-test-db.mjs";
process.on("uncaughtException", (e) => {
  console.error(e.stack);
  process.exit(1);
});
const app = await startPreview();
let browser;
const errors = [];
const external = [];
try {
  const args = ["--no-sandbox", "--disable-dev-shm-usage"];
  if (process.env.FLEET_CHROMIUM_ARGS)
    args.push(...JSON.parse(process.env.FLEET_CHROMIUM_ARGS));
  browser = await chromium.launch({
    headless: true,
    args,
    executablePath: process.env.FLEET_CHROMIUM_PATH || undefined,
  });
  const pages = {};
  async function pageFor(actor) {
    if (!pages[actor]) {
      const p = await browser.newPage({
        viewport: { width: 1440, height: 1000 },
      });
      p.on("pageerror", (e) => errors.push(e.message));
      await p.route("**/*", (route) => {
        const url = route.request().url();
        if (
          url.startsWith(app.url) ||
          url.startsWith("data:") ||
          url.startsWith("blob:")
        )
          return route.continue();
        external.push(url);
        return route.abort();
      });
      pages[actor] = p;
    }
    await pages[actor].goto(app.url + "/fleet/index.html?qa=" + actor);
    await expect(pages[actor].locator("#fleetStatus")).toHaveText("");
    return pages[actor];
  }
  const pdf = {
    name: "qa.pdf",
    mimeType: "application/pdf",
    buffer: Buffer.from("%PDF-1.4\nQA"),
  };
  async function create(amount, actor = "driver") {
    const p = await pageFor(actor);
    await p.locator("#newRequest").click();
    await p
      .locator("[name=accountant_id]")
      .selectOption({ label: "المحاسب التجريبي" });
    await p.locator("[name=description]").fill("صيانة تجريبية " + amount);
    for (let i = 0; i < 3; i++) {
      const q = p.locator("[data-quote]").nth(i);
      await q.locator("[name=supplier]").fill("ورشة تجريبية " + i);
      await q.locator("[name=parts]").fill(String(amount + i));
      await q.locator("[type=file]").setInputFiles(pdf);
    }
    await p.getByRole("button", { name: "حفظ المسودة والمرفقات" }).click();
    await expect(p.locator("#fleetDialog")).not.toBeVisible();
    await expect(p.locator("#fleetStatus")).toContainText("تم حفظ المسودة");
    await open(actor,"صيانة تجريبية " + amount);
    await act(p, "submit");
    return p;
  }
  async function act(p, action, fill) {
    const description=await p.locator("#dialogBody h3").first().innerText();
    await p.locator(`[data-action=${action}]`).click();
    if (fill) await fill(p.locator("#actionForm"));
    await p.locator("#actionForm button[type=submit]").click();
    await expect(p.locator("#fleetDialog")).not.toBeVisible();
    await expect(p.locator("#fleetStatus")).toHaveText("تم تنفيذ الإجراء وتوثيقه.");
    await p.locator("[data-tab=requests]").click();
    await p.locator("#requestRows tr").filter({hasText:description}).getByRole("button",{name:"عرض الطلب"}).click();
    await expect(p.locator("#fleetDialog")).toBeVisible();
  }
  async function open(actor, description) {
    const p = await pageFor(actor);
    await p.locator("[data-tab=requests]").click();
    await p
      .locator("#requestRows tr")
      .filter({ hasText: description })
      .getByRole("button", { name: "عرض الطلب" })
      .click();
    await expect(p.locator("#dialogBody h3").first()).toHaveText(description);
    await expect(p.locator("#fleetDialog")).toBeVisible();
    return p;
  }
  await create(300);
  let p = await open("manager", "صيانة تجريبية 300");
  await act(p, "approve");
  p = await open("driver", "صيانة تجريبية 300");
  await act(p, "confirm_repair", async (f) => {
    await f.locator("[name=total]").fill("290");
    await f.locator("[name=invoice]").setInputFiles(pdf);
    await f.locator("[name=received]").check();
  });
  p = await open("fleet", "صيانة تجريبية 300");
  await act(p, "approve");
  p = await open("accountant", "صيانة تجريبية 300");
  await act(p, "settle", async (f) => {
    await f.locator("[name=reference]").fill("QA-REIMBURSEMENT");
    await f.locator("[name=evidence]").setInputFiles(pdf);
  });
  await expect(p.locator("#dialogBody .fleet-tag").first()).toHaveText("مغلق");
  console.log(
    "PASS UI: small request created with 3 uploads -> manager -> receipt/invoice -> fleet -> accountant reimbursement.",
  );
  await create(301);
  p = await open("fleet", "صيانة تجريبية 301");
  await act(p, "approve");
  p = await open("accountant", "صيانة تجريبية 301");
  await act(p, "confirm_advance", async (f) => {
    await f.locator("[name=reference]").fill("QA-ADVANCE");
    await f.locator("[name=evidence]").setInputFiles(pdf);
  });
  p = await open("driver", "صيانة تجريبية 301");
  await act(p, "request_increase", async (f) => {
    await f.locator("[name=total]").fill("450");
    await f.locator("[name=reason]").fill("قطع إضافية قبل التنفيذ");
  });
  p = await open("fleet", "صيانة تجريبية 301");
  await act(p, "approve_increase");
  p = await open("accountant", "صيانة تجريبية 301");
  await act(p, "confirm_advance", async (f) => {
    await f.locator("[name=reference]").fill("QA-INCREASE");
    await f.locator("[name=evidence]").setInputFiles(pdf);
  });
  p = await open("driver", "صيانة تجريبية 301");
  await act(p, "confirm_repair", async (f) => {
    await f.locator("[name=total]").fill("400");
    await f.locator("[name=invoice]").setInputFiles(pdf);
    await f.locator("[name=received]").check();
  });
  p = await open("accountant", "صيانة تجريبية 301");
  await act(p, "settle", async (f) => {
    await f.locator("[name=reference]").fill("QA-REFUND-50");
    await f.locator("[name=evidence]").setInputFiles(pdf);
  });
  await expect(p.locator("#dialogBody .fleet-tag").first()).toHaveText("مغلق");
  console.log(
    "PASS UI: large request -> fleet -> advance -> increase -> additional advance -> invoice -> refund -> closed.",
  );
  p = await pageFor("fleet");
  await p.locator("[data-tab=vehicles]").click();
  await p.locator("#newVehicle").click();
  await p.locator("[name=plate]").fill("QA 9876");
  await p.locator("[name=vehicle_type]").fill("سيارة ثانية");
  await p
    .locator("[name=driver_id]")
    .selectOption({ label: "السائق التجريبي — 99002" });
  await p.locator("[name=reason]").fill("تجربة تعدد سيارات السائق");
  await p.locator("#vehicleForm button[type=submit]").click();
  await expect(p.locator("#fleetDialog")).not.toBeVisible();
  p = await pageFor("driver");
  await p.locator("#newRequest").click();
  await expect(p.locator("[name=vehicle_id] option")).toHaveCount(2);
  await p.locator("#closeDialog").click();
  p = await pageFor("fleet");
  await p.locator("[data-tab=vehicles]").click();
  await p.locator("#importVehicles").click();
  await p.locator("[name=source]").setInputFiles({
    name: "qa-import.json",
    mimeType: "application/json",
    buffer: Buffer.from(
      JSON.stringify({
        source_sha256: "c".repeat(64),
        rows: [
          {
            plate: "QA IMPORT 3",
            vin: "QA-IMPORT-003",
            vehicle_type: "سيارة مستوردة",
            driver_id: null,
            active: false,
            odometer: 0,
          },
        ],
        issues: [],
      }),
    ),
  });
  await p.locator("#importForm button[type=submit]").click();
  await expect(p.locator("#dialogStatus")).toHaveText(
    "اكتملت المعاينة دون حفظ.",
  );
  await p.locator("#confirmImport").click();
  await expect(p.locator("#fleetDialog")).not.toBeVisible();
  await expect(p.locator("#vehicleRows tr")).toHaveCount(3);
  p = await pageFor("outsider");
  await expect(p.locator("#newRequest")).toBeDisabled();
  await p.locator("[data-tab=requests]").click();
  await expect(p.locator("#requestEmpty")).toBeVisible();
  const admin = await pageFor("admin");
  await admin.goto(app.url + "/admin/users.html?qa=admin");
  await expect(admin.locator("#accessStatus")).toHaveAttribute(
    "data-ready",
    "true",
  );
  await admin.locator("#accountSearch").fill("outsider@");
  await admin.locator("[data-account]").click();
  await admin.locator("#accountDirectTab").click();
  await admin
    .locator('#directRules [data-permission="fleet.requests.read"]')
    .selectOption("all");
  await admin.locator("#directForm button[type=submit]").click();
  await expect(admin.locator("#accountState")).toHaveText(
    "تم حفظ المنح المباشر.",
  );
  await expect(
    admin.locator('#directRules [data-permission="fleet.requests.read"]'),
  ).toHaveValue("all");
  p = await pageFor("outsider");
  await p.locator("[data-tab=requests]").click();
  await expect(p.locator("#requestRows tr")).toHaveCount(2);
  await admin
    .locator('#directRules [data-permission="fleet.requests.read"]')
    .selectOption("");
  await admin.locator("#directForm button[type=submit]").click();
  await expect(admin.locator("#accountState")).toHaveText(
    "تم حفظ المنح المباشر.",
  );
  p = await pageFor("outsider");
  await p.locator("[data-tab=requests]").click();
  await expect(p.locator("#requestEmpty")).toBeVisible();
  console.log(
    "PASS UI: existing account administration grants and revokes fleet access, with persisted direct-grant scope.",
  );
  // Activation failures keep the form; successful activation closes it before list refresh.
  const activationEmails=['activation-ui@fleet.atwargroup.test','activation-refresh@fleet.atwargroup.test'];
  for(let i=0;i<2;i++)await app.db.query("insert into private.hr_employees(id,employee_code,full_name,email,department_id,section_id,title_id,manager_id,join_date,effective_from)select gen_random_uuid(),$1,$2,$3,department_id,section_id,title_id,manager_id,current_date,current_date from private.hr_employees where id=$4",[String(99980+i),'تفعيل الواجهة '+i,activationEmails[i],ids.driver]);
  let activationFails=true,refreshFails=false;
  await admin.route('**/functions/v1/admin-create-user',async route=>{
    const body=route.request().postDataJSON();
    if(activationFails)return route.fulfill({status:400,contentType:'application/json',body:JSON.stringify({error:'تعذر التفعيل التجريبي'})});
    assert.deepEqual(body.allowed_modules.sort(),['fleet','policies']);
    const id=(await app.db.query('insert into auth.users(id,email)values(gen_random_uuid(),$1)returning id',[body.email])).rows[0].id;
    await app.db.exec("begin;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true)");
    await app.db.query("insert into public.profiles(id,email,full_name,role,allowed_modules)values($1,$2,$3,'employee',array['fleet','policies'])",[id,body.email,body.full_name]);
    await app.db.exec('commit');
    return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({id,email:body.email})});
  });
  await admin.route('**/__qa/rpc',route=>refreshFails&&route.request().postDataJSON().name==='access_admin_context'?route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({data:null,error:{message:'refresh failed'}})}):route.continue());
  await admin.goto(app.url+'/admin/users.html?qa=admin');
  await expect(admin.locator('#accessStatus')).toHaveAttribute('data-ready','true');
  async function activationFormFor(email){
    await admin.locator('#openActivation').click();
    const e=(await app.db.query('select id from private.hr_employees where email=$1',[email])).rows[0];
    await admin.locator('#activationEmployee').selectOption(e.id);
    for(const checkbox of await admin.locator('#activationModules input').all())await checkbox.uncheck();
    await admin.locator('#activationModules input[value=fleet]').check();await admin.locator('#activationModules input[value=policies]').check();
    await admin.locator('#activationPassword').fill('Synthetic-test-only-123!');
  }
  await activationFormFor(activationEmails[0]);
  await admin.locator('#activationForm button[type=submit]').click();
  await expect(admin.locator('#activationState')).toHaveText('تعذر التفعيل التجريبي');
  await expect(admin.locator('#activationDialog')).toBeVisible();
  activationFails=false;
  await admin.locator('#activationForm button[type=submit]').click();
  await expect(admin.locator('#activationDialog')).not.toBeVisible();
  await expect(admin.locator('#accessStatus')).toHaveText('تم تفعيل حساب الموظف وربطه بسجله المعتمد.');
  await activationFormFor(activationEmails[1]);refreshFails=true;
  await admin.locator('#activationForm button[type=submit]').click();
  await expect(admin.locator('#activationDialog')).not.toBeVisible();
  await expect(admin.locator('#accessStatus')).toContainText('تم تفعيل الحساب بنجاح، لكن تعذر تحديث القائمة');
  refreshFails=false;
  console.log('PASS UI: successful activation closes and refreshes; activation errors keep the form; refresh failures cannot reopen or misreport a successfully created account.');
  p = await pageFor("fleet");
  await p.locator("[data-tab=documents]").click();
  await expect(p.locator("#documentRows tr")).toHaveCount(3);
  await expect(p.locator("#documentSettings")).toBeHidden();
  await p.locator("[data-documents]").first().click();
  const docForm = p.locator("[data-document-kind=insurance]");
  const expiration = (
    await app.db.query(
      "select (timezone('Asia/Riyadh',now())::date+40)::text d",
    )
  ).rows[0].d;
  await docForm.locator("[name=expires]").fill(expiration);
  await docForm.locator("[name=reason]").fill("تجديد التأمين للاختبار");
  await docForm.locator("button[type=submit]").click();
  await expect(p.locator("#fleetDialog")).not.toBeVisible();
  await expect(p.locator("#fleetStatus")).toContainText("تم تحديث الوثيقة");
  p = await pageFor("admin");
  await p.locator("[data-tab=documents]").click();
  await p.locator("#documentSettings").click();
  const insuranceSettings = p.locator("[data-setting-kind=insurance]");
  await insuranceSettings.locator("[name=days]").fill("45");
  await insuranceSettings.locator("button[type=submit]").click();
  await expect(p.locator("#fleetDialog")).not.toBeVisible();
  await expect(p.locator("#fleetStatus")).toContainText("تم حفظ مدة التنبيه");
  assert.equal(
    (
      await app.db.query(
        "select count(*) n from public.notifications where type='FLEET_DOCUMENT'",
      )
    ).rows[0].n,
    3,
  );
  p = await pageFor("manager");
  await p.locator("[data-tab=documents]").click();
  await expect(p.locator("#documentRows")).toContainText(expiration);
  await expect(p.locator("[data-documents]")).toHaveCount(0);
  await expect(p.locator("#documentSettings")).toBeHidden();
  console.log(
    "PASS UI: document dates, admin changes 30 to 45 days, three reminders created, manager read-only documents, fleet cannot change system settings.",
  );
  await create(150,'manager');
  p=await open('manager','صيانة تجريبية 150');
  await act(p,'approve');
  await app.db.exec("update private.hr_employees set manager_id='00000000-0000-4000-8000-000000000001'where profile_id='00000000-0000-4000-8000-000000000002'");
  await app.rpc('fleet','fleet_vehicle_save',{p_id:null,p_revision:null,p_data:{plate:'MANAGER 888',vin:'QA-MANAGER-888',vehicle_type:'سيارة المدير',driver_id:'00000000-0000-4000-8000-000000000002',odometer:0,active:true},p_reason:'اختبار سيارة المدير'});
  p=await pageFor('manager');
  await expect(p.locator('#dashboardScope option')).toHaveCount(2);
  await p.locator('#dashboardScope').selectOption('team');
  await expect(p.locator('#openCount')).toHaveText('1');
  await p.locator('#dashboardScope').selectOption('personal');
  await expect(p.locator('#openCount')).toHaveText('0');
  await p.locator('#newRequest').click();
  await expect(p.locator('[name=request_type] option')).toHaveCount(2);
  await expect(p.locator('[name=vehicle_id] option')).toHaveCount(3);
  await p.locator('#closeDialog').click();
  p=await pageFor('driver');
  assert.equal(/[٠-٩۰-۹]/.test(await p.locator('.fleet-page').innerText()),false,'Non-English digits in fleet screen');
  console.log('PASS UI: manager creates and submits for direct report; own/team dashboards are separate; only two request types; dialogs auto-close and digits are English.');
  p=await pageFor('accountant2');
  await expect(p.locator('#newRequest')).toBeHidden();
  await expect(p.locator('[data-tab=vehicles]')).toBeHidden();
  await expect(p.locator('[data-tab=documents]')).toBeHidden();
  await expect(p.locator('[data-tab=requests]')).toHaveAttribute('aria-selected','true');
  await expect(p.locator('#requestRows tr')).toHaveCount(0);
  p=await pageFor('fleet');
  await expect(p.locator('#newRequest')).toBeEnabled();
  await expect(p.locator('.atwar-nav a[href$="fleet/index.html"]')).toHaveCount(1);
  await p.locator('#newRequest').click();
  await expect(p.locator('[name=vehicle_id] option')).toHaveCount(3);
  await p.locator('#closeDialog').click();
  await create(175,'fleet');
  p=await open('fleet','صيانة تجريبية 175');
  await act(p,'approve');
  await act(p,'confirm_repair',async f=>{await f.locator('[name=total]').fill('175');await f.locator('[name=invoice]').setInputFiles(pdf);await f.locator('[name=received]').check();});
  await act(p,'approve');
  await expect(p.locator('[data-action=settle]')).toHaveCount(0);
  p=await open('admin','صيانة تجريبية 175');
  await act(p,'settle',async f=>{await f.locator('[name=reference]').fill('ADMIN-REIMBURSE');await f.locator('[name=evidence]').setInputFiles(pdf);});
  await expect(p.locator('#dialogBody .fleet-tag').first()).toHaveText('مغلق');
  await app.rpc('fleet','fleet_vehicle_save',{p_id:null,p_revision:null,p_data:{plate:'FINANCE 999',vehicle_type:'سيارة المحاسب',driver_id:'00000000-0000-4000-8000-000000000007',active:true,odometer:0},p_reason:'اختبار ظهور خدمات السيارة لمالكها'});
  p=await pageFor('accountant2');
  await expect(p.locator('#newRequest')).toBeVisible();
  await expect(p.locator('[data-tab=vehicles]')).toBeVisible();
  await expect(p.locator('[data-tab=documents]')).toBeVisible();
  console.log('PASS UI: fleet owner requests and operates any car without financial controls; admin completes finance; accountant without car has assigned requests only, and own-car services appear when assigned.');
  p = await pageFor("fleet");
  await mkdir("test-results", { recursive: true });
  await p.screenshot({
    path: "test-results/fleet-desktop.png",
    fullPage: true,
  });
  await p.setViewportSize({ width: 390, height: 844 });
  await p.screenshot({ path: "test-results/fleet-mobile.png", fullPage: true });
  const overflow = await p.evaluate(
    () => document.documentElement.scrollWidth > innerWidth + 2,
  );
  assert.equal(overflow, false, "Mobile page overflows");
  await p.locator('[data-tab=documents]').click();
  assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth+2),false,'Document screen overflows on mobile');
  await p.screenshot({path:'test-results/fleet-documents-mobile.png',fullPage:true});
  assert.deepEqual(errors, []);
  assert(
    !external.some((u) => u.includes("supabase.co")),
    "Production Supabase must never be contacted",
  );
  console.log(
    "PASS UI: vehicle management, multiple cars, outsider boundaries, desktop/mobile layout, no page exceptions, no production connections.",
  );
} finally {
  await browser?.close();
  await app.close();
}
