-- Validate batch input before counting, and preserve application-before-request locking.
create or replace function private.recruitment_batch_action(p_request uuid,p_action text,p_data jsonb)returns void language plpgsql security definer set search_path=pg_catalog,private,public as $$declare r private.recruitment_requests;b private.recruitment_batches;cnt int;begin
if not private.recruitment_visible(p_request)then raise exception 'السجل غير متاح'using errcode='42501';end if;if p_action='submit'then if jsonb_typeof(p_data->'application_ids')is distinct from 'array'then raise exception 'حدد مرشحي الدفعة';end if;perform 1 from private.recruitment_applications where request_id=p_request and id in(select value::uuid from jsonb_array_elements_text(p_data->'application_ids'))order by id for update;end if;select * into strict r from private.recruitment_requests where id=p_request for update;
if r.status<>'open'or r.route<>'advertised'then raise exception 'الدفعات لمسار البحث المفتوح فقط';end if;
select * into b from private.recruitment_batches where request_id=r.id order by number desc limit 1 for update;
if p_action='submit'and auth.uid()=r.recruiter_id and private.recruitment_permission('recruitment.manage')and b.state='sourcing'then
cnt:=jsonb_array_length(p_data->'application_ids');if cnt<>b.quota or(select count(distinct value)from jsonb_array_elements_text(p_data->'application_ids'))<>cnt then raise exception 'حدد % مرشحين جدد بالضبط',b.quota;end if;
if exists(select 1 from jsonb_array_elements_text(p_data->'application_ids')x where not exists(select 1 from private.recruitment_applications where id=x.value::uuid and request_id=r.id and batch_number is null and stage not in('hired','rejected','withdrawn','no_show')))then raise exception 'مرشح مكرر أو غير متاح';end if;
update private.recruitment_applications set batch_number=b.number where id in(select value::uuid from jsonb_array_elements_text(p_data->'application_ids'));
update private.recruitment_batches set state='review',submitted_at=now()where request_id=r.id and number=b.number;update private.recruitment_tasks set done=true where key='batch:'||r.id;perform private.recruitment_task('batch-review:'||r.id,r.id,null,r.department_approver_id,'تقييم دفعة المرشحين',3);
elsif p_action='none_selected'and auth.uid()=r.department_approver_id and b.state='review'then
if length(btrim(coalesce(p_data->>'note','')))<5 then raise exception 'وثق سبب عدم الاختيار';end if;
if exists(select 1 from private.recruitment_applications where request_id=r.id and batch_number=b.number and(stage<>'rejected'or rejection_reason is null))then raise exception 'سجل سبب رفض كل مرشح في الدفعة أولًا';end if;
update private.recruitment_batches set state='exhausted',note=p_data->>'note'where request_id=r.id and number=b.number;update private.recruitment_tasks set done=true where key='batch-review:'||r.id;
if b.number<3 then insert into private.recruitment_batches(request_id,number,quota)values(r.id,b.number+1,5);perform private.recruitment_task('batch:'||r.id,r.id,null,r.recruiter_id,'توفير ٥ مرشحين جدد',5);else perform private.recruitment_event(r.id,null,'sourcing_suspended','توقف توفير المرشحين بعد استنفاد الدفعات؛ يظل الطلب مفتوحًا');end if;
elsif p_action='resume'and auth.uid()=r.development_id and private.recruitment_permission('recruitment.development')and b.state='exhausted'and b.number>=3 then
if length(btrim(coalesce(p_data->>'note','')))<5 then raise exception 'وثق مراجعة المتطلبات والراتب والتقييم ومبرر الاستئناف';end if;
insert into private.recruitment_batches(request_id,number,quota,note)values(r.id,b.number+1,(p_data->>'quota')::int,p_data->>'note');perform private.recruitment_task('batch:'||r.id,r.id,null,r.recruiter_id,'دفعة إضافية معتمدة',5);
else raise exception 'الإجراء غير متاح'using errcode='42501';end if;perform private.recruitment_event(r.id,null,'batch_'||p_action,p_data->>'note');end$$;

revoke all on function private.recruitment_batch_action(uuid,text,jsonb)from public,anon;
grant execute on function private.recruitment_batch_action(uuid,text,jsonb)to authenticated;
create index recruitment_tasks_request_idx on private.recruitment_tasks(request_id);
-- Explicit deny policies document that private records are available only through checked commands.
do $$declare t text;begin foreach t in array array['recruitment_batches','recruitment_documents','recruitment_portal_links','recruitment_candidate_updates','recruitment_holidays','recruitment_tasks']loop execute format('create policy internal_only on private.%I to authenticated using(false)with check(false)',t);end loop;end$$;
