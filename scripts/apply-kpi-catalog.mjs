import {readFileSync,writeFileSync} from 'node:fs';
import vm from 'node:vm';
import {pathToFileURL} from 'node:url';

// Operator-only, one-time data update requested by the system owner.
// Keeps published snapshots and historical acknowledgements immutable.
const window={};
vm.runInNewContext(readFileSync(new URL('../assets/js/job-kpi-proposals.js',import.meta.url),'utf8'),{window});
export const catalog=window.AtwarKpiProposals.catalog;
const signature=k=>JSON.stringify([k.name||k.text||'',k.target||'',k.measure||'']);
export function applyCatalog(jobs){
 if(jobs.length!==catalog.length)throw Error('Job coverage changed; review before applying');
 return catalog.map(entry=>{
  const job=jobs.find(j=>j.job_code===entry.jobCode);
  if(!job||job.kpis.length!==entry.indicators.length||job.kpis.some((k,i)=>signature(k)!==entry.indicators[i].signature))throw Error('Indicator mismatch: '+entry.jobCode);
  const kpis=job.kpis.map((k,i)=>{const p=entry.indicators[i];return {...k,weight:p.weight,unit:p.unit,source:p.source,scale:p.scale.map(s=>({...s})),scale_basis:p.basis,scale_note:p.note,measurement_note:p.measurementNote,measurement_review_note:entry.reviewNote};});
  if(kpis.reduce((sum,k)=>sum+k.weight,0)!==100)throw Error('Invalid weight total: '+entry.jobCode);
  return {job_code:job.job_code,revision:job.revision,original_kpis:job.kpis,kpis};
 });
}
export function buildSql(jobs){
 const rows=JSON.stringify(applyCatalog(jobs));
 return `begin;
-- Resolve the existing active draft-stage owner; never grant new privileges.
select set_config('request.jwt.claim.sub',p.id::text,true),
 set_config('request.jwt.claims',jsonb_build_object('sub',p.id,'role','authenticated')::text,true)
from public.job_stage_owners s join public.profiles p on p.id=s.profile_id
where s.stage='DRAFT' and p.role='admin' and p.active and p.status='active';
set local role authenticated;
do $apply$
declare r jsonb; j public.job_descriptions%rowtype; count_applied integer:=0;
 payload jsonb:=$catalog$${rows}$catalog$::jsonb;
begin
 if not private.can_job_stage('DRAFT') then raise exception 'Active draft-stage permission required'; end if;
 -- Lock and validate every record before changing any record.
 for r in select value from jsonb_array_elements(payload) loop
  select * into j from public.job_descriptions where job_code=r->>'job_code' for update;
  if not found or j.revision<>(r->>'revision')::integer or j.content->'kpis' is distinct from r->'original_kpis' then
   raise exception 'ATWAR_CONFLICT: KPI catalogue changed for %',r->>'job_code';
  end if;
 end loop;
 for r in select value from jsonb_array_elements(payload) loop
  update public.job_descriptions set
   content=jsonb_set(content,'{kpis}',r->'kpis'),
   status=case when status='PUBLISHED' then 'DRAFT' else status end,
   final_reviewed_at=null,final_reviewed_by=null,
   review_note=concat_ws(chr(10),nullif(review_note,''),'تطبيق أوزان ومصادر قياس وحدود تقييم جميع المؤشرات وفق المقترح بطلب صاحب النظام؛ يُنشر الإصدار المحدّث عبر مسار الاعتماد المعتاد.')
  where job_code=r->>'job_code';
  if not found then raise exception 'KPI update was denied'; end if;
  count_applied:=count_applied+1;
 end loop;
 if count_applied<>57 then raise exception 'Incomplete KPI application'; end if;
end $apply$;
commit;
`;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const [input,output]=process.argv.slice(2);
 if(!input||!output)throw Error('Usage: node scripts/apply-kpi-catalog.mjs CURRENT_JOBS_JSON OUTPUT_SQL');
 writeFileSync(output,buildSql(JSON.parse(readFileSync(input,'utf8'))),{mode:0o600});
 console.log('Prepared guarded update: 57 jobs / 253 KPIs; published snapshots retained.');
}
