begin;
alter table public.job_descriptions alter column reviewer_mode set default 'auto';
create function private.check_job_authoring_content(p_job public.job_descriptions)
returns void language plpgsql security invoker set search_path='pg_catalog','public','private' as $$
declare k jsonb; total numeric:=0;
begin
 if p_job.reviewer_mode='legacy' then return; end if;
 if char_length(btrim(p_job.purpose))<40 or jsonb_array_length(coalesce(p_job.content->'responsibilities','[]'))=0
  or jsonb_array_length(coalesce(p_job.content->'authorities','[]'))=0 or jsonb_array_length(coalesce(p_job.content->'kpis','[]'))=0
  or jsonb_array_length(coalesce(p_job.content->'reports','[]'))=0 or nullif(btrim(p_job.content#>>'{qualifications,education}'),'') is null then
  raise exception 'أكمل محتوى الوصف قبل إنهاء المراجعة أو نشره'; end if;
 for k in select value from jsonb_array_elements(p_job.content->'kpis') loop
  if nullif(btrim(k->>'name'),'') is null or nullif(btrim(k->>'measure'),'') is null or nullif(btrim(k->>'source'),'') is null or nullif(btrim(k->>'target'),'') is null or coalesce(k->>'weight','')!~'^[0-9]+(\.[0-9]+)?$' then
   raise exception 'أكمل بيانات قياس كل مؤشر قبل إنهاء المراجعة'; end if;
  if (k->>'weight')::numeric<=0 then raise exception 'وزن المؤشر يجب أن يكون موجبًا'; end if;
  total:=total+(k->>'weight')::numeric;
 end loop;
 if abs(total-100)>0.001 then raise exception 'مجموع أوزان المؤشرات يجب أن يساوي ١٠٠٪'; end if;
end $$;
revoke all on function private.check_job_authoring_content(public.job_descriptions) from public,anon;
grant execute on function private.check_job_authoring_content(public.job_descriptions) to authenticated;
create function private.check_job_final_content()
returns trigger language plpgsql security invoker set search_path='pg_catalog','public','private' as $$
begin
 if (old.final_reviewed_at is null and new.final_reviewed_at is not null) or (old.status<>'PUBLISHED' and new.status='PUBLISHED') then
  perform private.check_job_authoring_content(new);
 end if;
 return new;
end $$;
revoke all on function private.check_job_final_content() from public,anon,authenticated;
create trigger zz_check_job_final_content before update on public.job_descriptions for each row execute function private.check_job_final_content();
create function private.guard_archived_job_assignment()
returns trigger language plpgsql security invoker set search_path='pg_catalog','public','private' as $$
begin
 if (tg_op='INSERT' or old.job_description_id is distinct from new.job_description_id) and exists(select 1 from public.job_descriptions where id=new.job_description_id and status='ARCHIVED') then
  raise exception 'الوصف مؤرشف ولا يمكن إسناده إلى موظف جديد'; end if;
 return new;
end $$;
revoke all on function private.guard_archived_job_assignment() from public,anon,authenticated;
create trigger guard_archived_job_assignment before insert or update on public.employee_job_assignments for each row execute function private.guard_archived_job_assignment();
commit;
