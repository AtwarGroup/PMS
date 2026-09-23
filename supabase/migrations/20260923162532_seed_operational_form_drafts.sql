-- These are editable operational drafts, not approved corporate policies.
-- The dedicated test administrator is used as the attribution account so this
-- import cannot be mistaken for an action performed by an actual manager.
insert into public.form_library
  (form_code,title,description,form_type,file_url,version,status,owner_department,created_by,updated_by)
select source.code,source.title,source.description,source.kind,source.url,'1.0','DRAFT',null,actor.id,actor.id
from (
  values
    ('ATW-TPL-001','نموذج تكليف ومتابعة مهمة','قالب أولي قابل للتعبئة لتوثيق التكليف ومعايير القبول والتسليم.','FORM','https://one.atwargroup.com/admin/templates/task-handover.html'),
    ('ATW-TPL-002','سجل قياس مؤشر الأداء','قالب أولي لتوثيق المستهدف والنتيجة والدليل والمراجع دون احتساب تقييم تلقائي.','REGISTER','https://one.atwargroup.com/admin/templates/kpi-measurement.html'),
    ('ATW-TPL-003','تقرير متابعة العمل الدوري','قالب أولي للإنجازات والتحديات والقرارات والأولويات.','REPORT','https://one.atwargroup.com/admin/templates/periodic-report.html'),
    ('ATW-TPL-004','قائمة تحقق مراجعة الوصف الوظيفي','قالب أولي لمراجعة عناصر الوصف قبل اعتماده.','CHECKLIST','https://one.atwargroup.com/admin/templates/job-review.html')
) as source(code,title,description,kind,url)
cross join lateral (
  select id from public.profiles
  where email='e2e-admin@atwargroup.test' and role='admin' and active=true
  limit 1
) actor
on conflict (form_code) do nothing;
