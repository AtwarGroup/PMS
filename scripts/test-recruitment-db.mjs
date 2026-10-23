import { createTestDB, ids } from "./fleet-test-db.mjs";
import fs from "node:fs/promises";
import assert from "node:assert/strict";
const { db } = await createTestDB();
await db.exec(
  "alter table public.job_descriptions add column published_snapshot jsonb; alter table public.profiles add column allowed_dummy text;",
);
await db.exec(
  await fs.readFile(
    "supabase/migrations/20261023142622_recruitment_foundation.sql",
    "utf8",
  ),
);
await db.exec(
  await fs.readFile(
    "supabase/migrations/20261023142952_recruitment_salary_reference_metadata.sql",
    "utf8",
  ),
);
await db.exec(
  await fs.readFile(
    "supabase/migrations/20261023143441_recruitment_resume_storage.sql",
    "utf8",
  ),
);
await db.exec(
  "update public.profiles set allowed_modules=array_append(allowed_modules,'recruitment');",
);
async function rpc(user, name, args = {}) {
  await db.exec("begin");
  try {
    await db.exec("set local role authenticated");
    await db.query("select set_config('request.jwt.claims',$1,true)", [
      JSON.stringify({ sub: ids[user], role: "authenticated" }),
    ]);
    const keys = Object.keys(args);
    const result = await db.query(
      `select public.${name}(${keys.map((k, i) => `${k}=>$${i + 1}`).join(",")}) result`,
      Object.values(args).map((x) =>
        typeof x === "object" && x !== null ? JSON.stringify(x) : x,
      ),
    );
    await db.exec("commit");
    return result.rows[0].result;
  } catch (e) {
    await db.exec("rollback");
    throw e;
  }
}
await db.exec(
  `insert into public.job_descriptions(id,job_code,title,published_snapshot)values('20000000-0000-4000-8000-000000000001','TEST','وظيفة اختبار','{"title":"وظيفة اختبار","content":{"qualifications":{"skills":"مهارة اختبار"}}}');insert into private.recruitment_salary_reference(id,title,grade,saudi_min,saudi_max,expat_min,expat_max,source_revision)values('20000000-0000-4000-8000-000000000002','وظيفة اختبار','T7',5000,8000,4000,6000,'fixture');`,
);
const data = {
  job_id: "20000000-0000-4000-8000-000000000001",
  salary_id: "20000000-0000-4000-8000-000000000002",
  department_id: "10000000-0000-4000-8000-000000000001",
  section_id: "10000000-0000-4000-8000-000000000002",
  company: "شركة اختبار",
  location: "جدة",
  headcount: 1,
  reason: "إحلال موظف",
  route: "referral",
  target_date: "2027-01-01",
  hr_id: ids.admin,
  finance_id: ids.admin,
  approver_id: ids.admin,
  interviewer_ids: [ids.manager],
  criteria: [{ key: "technical", label: "الكفاءة الفنية", weight: 100 }],
};
await assert.rejects(
  rpc("driver", "recruitment_request_create", { p_data: data }),
);
await rpc("admin", "access_direct_save", {
  p_profile: ids.fleet,
  p_rules: [{ permission: "recruitment.manage", scope: "all" }],
});
assert.equal((await rpc("fleet", "recruitment_context")).manage, true);
const id = await rpc("admin", "recruitment_request_create", { p_data: data });
await assert.rejects(rpc("outsider", "recruitment_detail", { p_request: id }));
await assert.rejects(
  rpc("manager", "recruitment_request_action", {
    p_id: id,
    p_revision: 1,
    p_action: "approve",
    p_data: {},
  }),
);
for (let version = 1; version <= 3; version++)
  await rpc("admin", "recruitment_request_action", {
    p_id: id,
    p_revision: version,
    p_action: "approve",
    p_data: {},
  });
await assert.rejects(
  rpc("admin", "recruitment_request_action", {
    p_id: id,
    p_revision: 1,
    p_action: "cancel",
    p_data: { note: "اختبار تعارض" },
  }),
);
const aid = await rpc("admin", "recruitment_candidate_add", {
  p_request: id,
  p_data: {
    full_name: "مرشح تجريبي",
    email: "candidate@example.test",
    phone: "0500000000",
    saudi: true,
    resume_text: "خبرة مهنية تجريبية مناسبة",
    source: "ترشيح الإدارة",
  },
});
await rpc("admin", "recruitment_stage", {
  p_application: aid,
  p_revision: 1,
  p_stage: "interview",
  p_note: "اجتاز الفرز الأولي",
});
await assert.rejects(
  rpc("admin", "recruitment_stage", {
    p_application: aid,
    p_revision: 2,
    p_stage: "assessment",
    p_note: "بدون تقييم",
  }),
);
await rpc("admin", "recruitment_interview_save", {
  p_application: aid,
  p_data: {
    interviewer_id: ids.admin,
    scheduled_at: "2026-01-01T10:00:00Z",
    kind: "previous",
    state: "completed",
    scores: { technical: 4 },
    notes: "مقابلة سابقة موثقة",
    recommendation: "suitable",
  },
});
await rpc("admin", "recruitment_stage", {
  p_application: aid,
  p_revision: 2,
  p_stage: "assessment",
  p_note: "استكمال التقييم",
});
await rpc("admin", "recruitment_stage", {
  p_application: aid,
  p_revision: 3,
  p_stage: "recommended",
  p_note: "كفاءة مناسبة للتعيين",
});
await assert.rejects(
  rpc("admin", "recruitment_offer_create", {
    p_application: aid,
    p_data: {
      basic: 9000,
      housing: 0,
      transport: 0,
      start_date: "2027-01-01",
      expires_on: "2027-01-01",
      benefits: "",
    },
  }),
);
const oid = await rpc("admin", "recruitment_offer_create", {
  p_application: aid,
  p_data: {
    basic: 5000,
    housing: 1000,
    transport: 500,
    start_date: "2027-01-01",
    expires_on: "2027-01-01",
    benefits: "مزايا اختبار",
  },
});
await assert.rejects(
  rpc("admin", "recruitment_offer_action", {
    p_id: oid,
    p_action: "sent",
    p_note: "اختبار تجاوز الاعتماد",
  }),
);
for (const action of ["approve", "approve", "sent", "accepted"])
  await rpc("admin", "recruitment_offer_action", {
    p_id: oid,
    p_action: action,
    p_note: "توثيق الإجراء التجريبي",
  });
const detail = await rpc("manager", "recruitment_detail", { p_request: id });
assert.equal(detail.offers.length, 0);
assert.equal(detail.request.salary_snapshot, undefined);
const eid = await rpc("admin", "recruitment_join", {
  p_application: aid,
  p_data: {
    join_date: "2026-10-23",
    employee_code: "99999",
    documents_complete: true,
    note: "اكتملت المستندات وتمت المباشرة",
  },
});
assert.ok(eid);
assert.equal(
  (await rpc("admin", "recruitment_detail", { p_request: id })).request.status,
  "closed",
);
await assert.rejects(
  rpc("admin", "recruitment_join", {
    p_application: aid,
    p_data: {
      join_date: "2026-10-23",
      employee_code: "99999",
      documents_complete: true,
      note: "مباشرة مكررة",
    },
  }),
);
// Public projection and upload tickets never expose internal records.
const advertised = await rpc("admin", "recruitment_request_create", {
  p_data: { ...data, route: "advertised" },
});
for (let version = 1; version <= 3; version++)
  await rpc("admin", "recruitment_request_action", {
    p_id: advertised,
    p_revision: version,
    p_action: "approve",
    p_data: {},
  });
await rpc("admin", "recruitment_request_action", {
  p_id: advertised,
  p_revision: 4,
  p_action: "publish",
  p_data: { advertisement: "إعلان وظيفة تجريبية بمتطلبات واضحة" },
});
const publicRows = await rpc("admin", "recruitment_public_jobs");
assert.equal(publicRows.length, 1);
assert.equal(publicRows[0].salary_snapshot, undefined);
const publicPayload = {
  full_name: "مرشح خارجي تجريبي",
  email: "external@example.test",
  phone: "0500000000",
  saudi: true,
  resume_text: "خبرة مهنية مناسبة للوظيفة التجريبية مع مهارات عملية مثبتة",
  consent: true,
};
const ticket = await rpc("admin", "recruitment_public_apply", {
  p_token: publicRows[0].token,
  p_data: publicPayload,
});
assert.ok(ticket);
const repeatTicket = await rpc("admin", "recruitment_public_apply", {
  p_token: publicRows[0].token,
  p_data: publicPayload,
});
assert.notEqual(ticket, repeatTicket);
await db.exec(
  "alter table storage.objects enable row level security;grant usage on schema storage to anon,authenticated;grant select,insert on storage.objects to anon,authenticated;",
);
await db.exec("begin;set local role anon");
assert.equal(
  (
    await db.query("select public.recruitment_resume_allowed($1,true) yes", [
      ticket + "/resume.pdf",
    ])
  ).rows[0].yes,
  true,
);
assert.equal(
  (
    await db.query("select public.recruitment_resume_allowed($1,false) yes", [
      ticket + "/resume.pdf",
    ])
  ).rows[0].yes,
  false,
);
await assert.rejects(
  db.query("select public.recruitment_detail($1)", [advertised]),
);
await db.exec("rollback");
await db.exec("begin;set local role anon");
await db.query(
  "insert into storage.objects(bucket_id,name,metadata)values('recruitment-resumes',$1,'{}')",
  [ticket + "/resume.pdf"],
);
assert.equal(
  (
    await db.query(
      "select * from storage.objects where bucket_id='recruitment-resumes'",
    )
  ).rows.length,
  0,
);
await db.exec("rollback");
await db.exec("begin;set local role anon");
await assert.rejects(
  db.query(
    "insert into storage.objects(bucket_id,name,metadata)values('recruitment-resumes',$1,'{}')",
    [repeatTicket + "/resume.pdf"],
  ),
);
await db.exec("rollback");
await db.exec(
  `update public.profiles set allowed_modules=array_remove(allowed_modules,'recruitment')where id='${ids.manager}'`,
);
await assert.rejects(rpc("manager", "recruitment_detail", { p_request: id }));
console.log(
  "Recruitment database: permissions, referrals, interviews, salary exceptions, approvals, hiring and concurrency guards passed",
);
await db.close();
