create table private.communication_trial_files(id uuid primary key,conversation_id text not null,file jsonb not null,created_at timestamptz not null default now(),check(octet_length(file::text)<=14500000));
alter table private.communication_trial_files enable row level security;
revoke all on private.communication_trial_files from public,anon,authenticated;
create function public.communication_trial_save(p_actor uuid,p_version bigint,p_state jsonb,p_files jsonb) returns boolean language plpgsql security definer set search_path='' as $f$
declare f jsonb;begin
 if not private.communication_trial_actor(p_actor) then raise exception 'التجربة مغلقة أو الحساب غير متاح';end if;
 if p_state is null or jsonb_typeof(p_state)<>'object' or jsonb_typeof(p_files)<>'array' then raise exception 'حالة غير صحيحة';end if;
 update private.communication_trial_state set state=p_state,version=version+1,updated_at=now() where singleton and version=p_version;
 if not found then return false;end if;
 for f in select value from jsonb_array_elements(p_files) loop
 insert into private.communication_trial_files(id,conversation_id,file) values((f->>'id')::uuid,f->>'conversation',f->'file') on conflict(id) do nothing;
 end loop;return true;end $f$;
create function public.communication_trial_file(p_actor uuid,p_file uuid) returns jsonb language plpgsql security definer set search_path='' as $f$
declare v jsonb; begin
 if not private.communication_trial_actor(p_actor) then raise exception 'التجربة مغلقة أو الحساب غير متاح';end if;
 select f.file into v from private.communication_trial_files f where f.id=p_file and exists(select 1 from private.communication_trial_state s cross join lateral jsonb_array_elements(s.state->'conversations') c where s.singleton and c->>'id'=f.conversation_id and c->'members' @> jsonb_build_array(p_actor::text));
 if v is null then raise exception 'الملف غير متاح لهذه العضوية';end if;return v;end $f$;
revoke all on function public.communication_trial_save(uuid,bigint,jsonb,jsonb),public.communication_trial_file(uuid,uuid) from public,anon,authenticated;
grant execute on function public.communication_trial_save(uuid,bigint,jsonb,jsonb),public.communication_trial_file(uuid,uuid) to service_role;
