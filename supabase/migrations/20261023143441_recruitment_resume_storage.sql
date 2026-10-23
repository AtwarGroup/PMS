alter table private.recruitment_applications add column resume_token uuid not null default gen_random_uuid();
create unique index recruitment_resume_token_idx on private.recruitment_applications(resume_token);
-- One PDF per application; public upload tickets expire after one hour and grant no read/update access.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)values('recruitment-resumes','recruitment-resumes',false,5242880,array['application/pdf']);
create function private.recruitment_resume_allowed(p_name text,p_write boolean)returns boolean language plpgsql stable security definer set search_path=pg_catalog,private,public as $$
declare a private.recruitment_applications%rowtype;r private.recruitment_requests%rowtype;begin
 if p_name!~'^[0-9a-f-]{36}/resume.pdf$'then return false;end if;
 select * into a from private.recruitment_applications where resume_token=split_part(p_name,'/',1)::uuid;if not found then return false;end if;
 select * into strict r from private.recruitment_requests where id=a.request_id;
 if auth.uid()is null then return p_write and a.created_at>now()-interval '1 hour'and r.published and r.status='open'and r.route='advertised';end if;
 return private.recruitment_visible(r.id)and(not p_write or(private.recruitment_permission('recruitment.manage')or r.created_by=auth.uid()));end$$;
create function public.recruitment_resume_allowed(p_name text,p_write boolean)returns boolean language sql stable security invoker set search_path=pg_catalog,private as $$select private.recruitment_resume_allowed(p_name,p_write)$$;
revoke all on function private.recruitment_resume_allowed(text,boolean),public.recruitment_resume_allowed(text,boolean)from public;
grant usage on schema private to anon;
grant execute on function private.recruitment_resume_allowed(text,boolean),public.recruitment_resume_allowed(text,boolean)to authenticated,anon;
create policy recruitment_resume_insert on storage.objects for insert to anon,authenticated with check(bucket_id='recruitment-resumes'and public.recruitment_resume_allowed(name,true));
create policy recruitment_resume_read on storage.objects for select to authenticated using(bucket_id='recruitment-resumes'and public.recruitment_resume_allowed(name,false));
-- Change public submission response to a fresh opaque upload receipt. Duplicates get an unrelated token.
drop function public.recruitment_public_apply(uuid,jsonb);
drop function private.recruitment_public_apply(uuid,jsonb);
create function private.recruitment_public_apply(p_token uuid,p_data jsonb)returns uuid language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare r private.recruitment_requests%rowtype;cid uuid;aid uuid;ticket uuid;vemail text:=lower(btrim(p_data->>'email'));begin
 select * into strict r from private.recruitment_requests where public_token=p_token and status='open'and published and route='advertised'for update;
 if coalesce(p_data->>'consent','false')<>'true'or coalesce(vemail,'')!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'or coalesce(p_data->>'phone','')!~'^\+?[0-9 ()-]{8,20}$'or coalesce(length(p_data->>'resume_text'),0)not between 30 and 10000 or length(p_data::text)>20000 then raise exception 'تحقق من البيانات والموافقة وملخص السيرة الذاتية';end if;
 if(select count(*)from private.recruitment_applications where request_id=r.id and created_at>now()-interval '1 day')>=300 then raise exception 'تعذر استقبال الطلب الآن، حاول لاحقًا';end if;
 insert into private.recruitment_candidates(full_name,email,phone,city,saudi,experience,resume_text)values(btrim(p_data->>'full_name'),vemail,p_data->>'phone',left(coalesce(p_data->>'city',''),100),(p_data->>'saudi')::boolean,left(coalesce(p_data->>'experience',''),3000),p_data->>'resume_text')on conflict(lower(email))do nothing returning id into cid;
 if cid is null then select id into cid from private.recruitment_candidates where lower(email)=vemail;end if;
 insert into private.recruitment_applications(request_id,candidate_id,source)values(r.id,cid,'صفحة التقديم')on conflict(request_id,candidate_id)do nothing returning id,resume_token into aid,ticket;
 if aid is not null then perform private.recruitment_event(r.id,aid,'public_application','طلب تقديم من صفحة الوظائف');end if;
 return coalesce(ticket,gen_random_uuid());end$$;
create function public.recruitment_public_apply(p_token uuid,p_data jsonb)returns uuid language sql security invoker set search_path=pg_catalog,private as $$select private.recruitment_public_apply(p_token,p_data)$$;
revoke all on function private.recruitment_public_apply(uuid,jsonb),public.recruitment_public_apply(uuid,jsonb)from public;
grant execute on function private.recruitment_public_apply(uuid,jsonb),public.recruitment_public_apply(uuid,jsonb)to authenticated,anon;
-- Candidates' file tickets are detail-only, never part of dashboard listings.
do $$declare d text;begin select pg_get_functiondef('private.recruitment_list()'::regprocedure)into d;d:=replace(d,'to_jsonb(a)||','(to_jsonb(a)-''resume_token'')||');execute d;end$$;

-- Dashboard queues include interviews and offer approvals without disclosing financial amounts.
alter function private.recruitment_list()rename to recruitment_list_before_queues;
create function private.recruitment_list()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,private,public as $$
declare result jsonb;begin result:=private.recruitment_list_before_queues();return result||jsonb_build_object(
'interviews',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'application_id',a.id,'request_id',r.id,'candidate_name',c.full_name,'job_title',r.job_snapshot->>'title','interviewer_id',i.interviewer_id,'scheduled_at',i.scheduled_at,'state',i.state)order by i.scheduled_at),'[]')from private.recruitment_interviews i join private.recruitment_applications a on a.id=i.application_id join private.recruitment_requests r on r.id=a.request_id join private.recruitment_candidates c on c.id=a.candidate_id where private.recruitment_visible(r.id)),
'offer_queue',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'application_id',a.id,'request_id',r.id,'candidate_name',c.full_name,'job_title',r.job_snapshot->>'title','state',o.state,'version',o.version)order by o.created_at),'[]')from private.recruitment_offers o join private.recruitment_applications a on a.id=o.application_id join private.recruitment_requests r on r.id=a.request_id join private.recruitment_candidates c on c.id=a.candidate_id where private.recruitment_visible(r.id)and((o.state='finance_review'and r.finance_id=auth.uid()and private.recruitment_permission('recruitment.finance'))or(o.state='approval'and r.approver_id=auth.uid()and private.recruitment_permission('recruitment.approve'))or(private.recruitment_permission('recruitment.manage')and o.state in('approved','sent'))))
);end$$;
revoke all on function private.recruitment_list_before_queues()from public,anon,authenticated;
revoke all on function private.recruitment_list()from public,anon;
grant execute on function private.recruitment_list()to authenticated;
