-- Reference weights transcribed from the three user-supplied scorecards.
-- They are review data for unpublished descriptions; publication remains in
-- the normal manager/admin approval workflow.
create table public.job_scorecard_weight_references (
  job_description_id uuid not null references public.job_descriptions(id) on delete cascade,
  source_revision integer not null check (source_revision > 0),
  kpi_position integer not null check (kpi_position between 1 and 50),
  indicator_name text not null check (length(btrim(indicator_name)) between 2 and 250),
  weight_percent numeric(5,2) not null check (weight_percent > 0 and weight_percent <= 100),
  source_note text not null default 'بطاقة مرجعية أرسلها صاحب النظام في 2026-09-23',
  created_at timestamptz not null default now(),
  primary key (job_description_id,source_revision,kpi_position)
);
alter table public.job_scorecard_weight_references enable row level security;
revoke all on public.job_scorecard_weight_references from public,anon;
grant select on public.job_scorecard_weight_references to authenticated;
create policy job_scorecard_weight_references_read on public.job_scorecard_weight_references
  for select to authenticated using (
    private.job_library_role()='admin'
    or exists (
      select 1 from public.job_descriptions j
      where j.id=job_description_id and j.reviewer_id=(select auth.uid())
    )
  );

-- Match by job code and the revision inspected when the images were received.
-- This deliberately does not change the draft KPI content or published snapshot.
do $$
begin
 if (select count(*) from public.job_descriptions
     where (job_code='JOB-037' and revision=13 and status='IN_REVIEW')
        or (job_code='JOB-005' and revision=12 and status='IN_REVIEW')
        or (job_code='JOB-008' and revision=10 and status='IN_REVIEW')) <> 3
 then raise exception 'Job descriptions changed since the scorecard reference was reviewed';
 end if;
end $$;

insert into public.job_scorecard_weight_references
  (job_description_id,source_revision,kpi_position,indicator_name,weight_percent)
select j.id,j.revision,v.position,v.indicator,v.weight
from (values
 ('JOB-037',1,'توفر الأصناف ومواجهة الطلب (OTIF)',20.00),
 ('JOB-037',2,'قياس وتقييم أداء الموردين',7.50),
 ('JOB-037',3,'معدل دوران المخزون وخفض التكلفة',20.00),
 ('JOB-037',4,'أتمتة وحوكمة العمليات عبر ERP',15.00),
 ('JOB-037',5,'تخفيض المخزون الراكد وبطيء الحركة',30.00),
 ('JOB-037',6,'إدارة وتطوير فريق العمل',7.50),
 ('JOB-005',1,'الالتزام بإصدار التقارير المالية في موعدها',20.00),
 ('JOB-005',2,'الالتزام بالإقفال المالي الشهري',20.00),
 ('JOB-005',3,'تنفيذ خطة الجرد السنوية والدورية',15.00),
 ('JOB-005',4,'نسبة مطابقة الصناديق والحسابات البنكية',15.00),
 ('JOB-005',5,'نسبة إغلاق الملاحظات المالية والرقابية',15.00),
 ('JOB-005',6,'دقة البيانات المالية',15.00),
 ('JOB-008',1,'دقة وجودة القيود المحاسبية',20.00),
 ('JOB-008',2,'الالتزام بمواعيد الإقفال المالي الشهري والسنوي',25.00),
 ('JOB-008',3,'إنجاز المطابقات البنكية وتسويات العهد',20.00),
 ('JOB-008',4,'الامتثال الضريبي والزكوي (VAT & Zakat)',15.00),
 ('JOB-008',5,'فعالية التنسيق مع المراجع الخارجي',10.00),
 ('JOB-008',6,'إدارة وتطوير فريق المحاسبين',10.00)
) as v(code,position,indicator,weight)
join public.job_descriptions j on j.job_code=v.code;

-- Each reference card must be complete and balanced before the migration ends.
do $$
begin
 if exists (
  select j.job_code
  from public.job_descriptions j
  join public.job_scorecard_weight_references r on r.job_description_id=j.id
  where j.job_code in ('JOB-037','JOB-005','JOB-008')
  group by j.job_code
  having count(*) <> 6 or sum(r.weight_percent) <> 100
 ) or (select count(*) from public.job_scorecard_weight_references) <> 18
 then raise exception 'Scorecard references must contain six rows and total 100 percent per role';
 end if;
end $$;
