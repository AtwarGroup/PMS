// Internal QA transport: synthetic data and isolated PostgreSQL only.
import http from "node:http";
import fs from "node:fs/promises";
import path from "node:path";
import { createTestDB, ids } from "./fleet-test-db.mjs";
const root = path.resolve(import.meta.dirname, "..");
const { db } = await createTestDB();
await db.exec(
  "alter table public.job_descriptions add column published_snapshot jsonb;",
);
for (const file of [
  "20261023142622_recruitment_foundation.sql",
  "20261023142952_recruitment_salary_reference_metadata.sql",
  "20261023143441_recruitment_resume_storage.sql",
  "20261023150534_recruitment_public_upload_session.sql",
  "20261023191845_recruitment_approved_workflow.sql",
  "20261023194438_recruitment_batch_validation.sql","20261025163934_admin_only_action_history.sql",
])
  await db.exec(
    await fs.readFile(path.join(root, "supabase/migrations", file), "utf8"),
  );
await db.exec(
  'update public.profiles set allowed_modules=array_append(allowed_modules,\'recruitment\');insert into public.job_descriptions(id,job_code,title,published_snapshot)values(\'20000000-0000-4000-8000-000000000001\',\'JOB-QA\',\'أخصائي توظيف تجريبي\',\'{"title":"أخصائي توظيف تجريبي","purpose":"تنظيم أعمال الاستقطاب والتوظيف وتقييم المرشحين","content":{"qualifications":{"education":"بكالوريوس مناسب","experience":"خبرة في التوظيف","skills":"إجراء المقابلات والتواصل"}}}\');insert into private.recruitment_salary_reference(id,title,grade,saudi_min,saudi_max,expat_min,expat_max,source_revision)values(\'20000000-0000-4000-8000-000000000002\',\'أخصائي توظيف تجريبي\',\'T7\',5000,8000,4000,6000,\'synthetic-only\');',
);
let queue = Promise.resolve();
async function call(actor, name, args = {}) {
  const task = queue.then(async () => {
    if (!/^recruitment_[a-z_]+$|^account_module_context$/.test(name)) return {};
    await db.exec("begin");
    try {
      await db.exec("set local role authenticated");
      await db.query("select set_config('request.jwt.claims',$1,true)", [
        JSON.stringify({ sub: ids[actor] || ids.admin, role: "authenticated" }),
      ]);
      const keys = Object.keys(args);
      if (keys.some((k) => !/^p_[a-z_]+$/.test(k))) throw Error("Invalid args");
      const result = await db.query(
        `select public.${name}(${keys.map((k, i) => `${k}=>$${i + 1}`).join(",")}) result`,
        Object.values(args).map((x) =>
          x && typeof x === "object" ? JSON.stringify(x) : x,
        ),
      );
      await db.exec("commit");
      return result.rows[0].result;
    } catch (e) {
      await db.exec("rollback");
      throw e;
    }
  });
  queue = task.catch(() => {});
  return task;
}
await db.exec(`update private.recruitment_salary_reference set benefits='{"text":"مزايا تجريبية معتمدة"}';`);
const seed = {
  job_id: "20000000-0000-4000-8000-000000000001",
  salary_id: "20000000-0000-4000-8000-000000000002",
  department_id: "10000000-0000-4000-8000-000000000001",
  section_id: "10000000-0000-4000-8000-000000000002",
  company: "أطوار · بيانات تجريبية",
  location: "جدة",
  headcount: 1,
  reason: "احتياج تجريبي للتحقق من دورة العمل",
  route: "referral",
  target_date: "2027-01-01",
  request_type:"new", department_approver_id:ids.admin,supervisor_id:ids.admin,recruiter_id:ids.admin,development_id:ids.admin,
  hr_id: ids.admin,
  finance_id: ids.admin,
  approver_id: ids.admin,
  interviewer_ids: [ids.manager],
  criteria: [{ key: "technical", label: "الكفاءة الفنية", weight: 100 }],
};
const rid = await call("admin", "recruitment_request_create", { p_data: seed });
await call("admin","recruitment_request_action",{p_id:rid,p_revision:1,p_action:"submit",p_data:{note:"إرسال الطلب التجريبي"}});
for (let revision = 2; revision <= 5; revision++)
  await call("admin", "recruitment_request_action", {
    p_id: rid,
    p_revision: revision,
    p_action: "approve",
    p_data: {note:"اعتماد المرحلة التجريبية",request_type_checked:true,saudization_checked:true,profession_checked:true},
  });
await call("admin", "recruitment_candidate_add", {
  p_request: rid,
  p_data: {
    full_name: "مرشح تجريبي",
    email: "qa@example.test",
    phone: "0500000000",
    saudi: true,
    source: "ترشيح الإدارة",
    resume_text: "خبرة مهنية تجريبية في التوظيف والمقابلات",
  },
});
const runtime = `const actor=new URLSearchParams(location.search).get('qa')||'admin',uid=${JSON.stringify(ids)}[actor];const profile={id:uid,full_name:'حساب تجريبي',role:actor==='admin'?'admin':actor==='manager'?'manager':'employee',active:true,status:'active'};localStorage.setItem('atwarSession',JSON.stringify({...profile,name:profile.full_name,uid}));const query=new Proxy({},{get:(_,k)=>k==='then'?(resolve)=>resolve({data:[],error:null}):()=>query});const sb={auth:{getSession:async()=>({data:{session:{user:{id:uid}}}})},rpc:async(name,args={})=>(await fetch('/__qa/rpc',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({actor,name,args})})).json(),from:()=>query};window.atwarGetSupabase=async()=>sb;window.AtwarSession={require:async()=>({sb,profile,user:{id:uid}})};window.atwarGetCurrentProfile=async()=>({authUser:{id:uid},profile});`;
const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://localhost");
    if(url.pathname === "/__qa/mobile"){res.writeHead(200,{"Content-Type":"text/html"});res.end('<html><body style="margin:0;background:#ddd"><iframe title="معاينة الجوال" src="/recruitment/index.html" style="width:390px;height:844px;border:0"></iframe></body></html>');return;}
    if (url.pathname === "/__qa/rpc" && req.method === "POST") {
      let body = "";
      for await (const chunk of req) body += chunk;
      const x = JSON.parse(body);
      try {
        res.setHeader("Content-Type", "application/json");
        res.end(
          JSON.stringify({
            data: await call(x.actor, x.name, x.args),
            error: null,
          }),
        );
      } catch (e) {
        res.end(JSON.stringify({ data: null, error: { message: e.message } }));
      }
      return;
    }
    let route = url.pathname === "/" ? "/recruitment/index.html" : url.pathname;
    if (["/assets/js/supabase-runtime.js"].includes(route)) {
      res.setHeader("Content-Type", "text/javascript");
      res.end(runtime);
      return;
    }
    if (
      [
        "/assets/js/session-service.js",
        "/assets/js/supabase-config.js",
      ].includes(route)
    ) {
      res.setHeader("Content-Type", "text/javascript");
      res.end("// isolated QA");
      return;
    }
    if (route === "/assets/js/communication-global.mjs") {
      res.setHeader("Content-Type", "text/javascript");
      res.end("export function startCommunicationAlerts(){}");
      return;
    }
    const file = path.resolve(root, "." + decodeURIComponent(route));
    if (!file.startsWith(root + path.sep)) {
      res.writeHead(403);
      res.end();
      return;
    }
    const ext = path.extname(file);
    res.setHeader(
      "Content-Type",
      {
        ".html": "text/html; charset=utf-8",
        ".js": "text/javascript",
        ".mjs": "text/javascript",
        ".css": "text/css",
        ".svg": "image/svg+xml",
      }[ext] || "application/octet-stream",
    );
    res.end(await fs.readFile(file));
  } catch (e) {
    res.writeHead(404);
    res.end("Not found");
  }
});
server.listen(Number(process.env.PORT) || 4173, "0.0.0.0", () =>
  console.log("Recruitment synthetic QA ready"),
);
