import { chromium, expect } from "@playwright/test";
import { mkdir } from "node:fs/promises";
import { startPreview } from "./fleet-preview.mjs";
import assert from "node:assert/strict";
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
