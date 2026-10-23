-- Backwards-compatible byte fallback. Offloading never removes bytes before object verification.
do $$declare t text;begin
 foreach t in array array['fleet_files','fleet_handover_photos']loop
 execute format('alter table private.%I add column size_bytes integer,add column content_hash text,add column storage_path text',t);
 execute format('update private.%I set size_bytes=octet_length(bytes),content_hash=encode(sha256(bytes),''hex'')',t);
 execute format('alter table private.%I alter column size_bytes set not null,alter column content_hash set not null,alter column bytes drop not null,add check(size_bytes between 1 and 5242880),add check(length(content_hash)=64),add check(bytes is not null or storage_path is not null)',t);
 end loop;
end$$;
create function private.fleet_file_fingerprint()returns trigger language plpgsql set search_path=pg_catalog as $$begin if new.bytes is not null then new.size_bytes:=octet_length(new.bytes);new.content_hash:=encode(sha256(new.bytes),'hex');end if;return new;end$$;
revoke all on function private.fleet_file_fingerprint()from public,anon,authenticated;
create trigger fleet_files_fingerprint before insert or update of bytes on private.fleet_files for each row execute function private.fleet_file_fingerprint();
create trigger fleet_handover_photos_fingerprint before insert or update of bytes on private.fleet_handover_photos for each row execute function private.fleet_file_fingerprint();

-- Preserve quota enforcement and photo retry deduplication after bytes have been offloaded.
do $$declare p record;definition text;begin
 for p in select oid from pg_proc where pronamespace='private'::regnamespace and proname in('fleet_upload','fleet_handover_upload')loop
 definition:=pg_get_functiondef(p.oid);
 definition:=replace(definition,'sum(octet_length(bytes))','sum(size_bytes)');
 definition:=replace(definition,'and bytes=v','and content_hash=encode(sha256(v),''hex'') and size_bytes=octet_length(v)');
 execute definition;
 end loop;
end$$;
create or replace function private.fleet_download(p_id uuid)returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare f private.fleet_files%rowtype;r private.fleet_requests%rowtype;begin
 perform private.require_module('fleet');select * into strict f from private.fleet_files where id=p_id;select * into strict r from private.fleet_requests where id=f.request_id;
 if not private.fleet_visible(r)then raise exception 'Access denied'using errcode='42501';end if;
 return jsonb_build_object('name',f.name,'mime',f.mime,'base64',encode(f.bytes,'base64'),'stored',f.storage_path is not null,'size',f.size_bytes,'hash',f.content_hash);end$$;
create or replace function private.fleet_handover_photo(p_id uuid)returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare f private.fleet_handover_photos%rowtype;h private.fleet_handovers%rowtype;begin
 perform private.require_module('fleet');select * into strict f from private.fleet_handover_photos where id=p_id;select * into strict h from private.fleet_handovers where id=f.handover_id;
 if not private.fleet_handover_visible(h)then raise exception 'Access denied'using errcode='42501';end if;
 return jsonb_build_object('name',f.name,'mime',f.mime,'base64',encode(f.bytes,'base64'),'stored',f.storage_path is not null,'size',f.size_bytes,'hash',f.content_hash);end$$;

do $$begin if exists(select 1 from storage.buckets where id='fleet-files' and public)then raise exception 'Fleet bucket must be private';end if;end$$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)values('fleet-files','fleet-files',false,5242880,array['application/pdf','image/png','image/jpeg'])on conflict(id)do nothing;

create function private.fleet_file_archive_complete(p_id uuid,p_kind text,p_hash text)returns void language plpgsql security definer set search_path=pg_catalog,private,storage as $$
declare t text;f record;object_path text;begin
 if p_kind not in('request','handover')then raise exception 'Invalid file kind';end if;
 t:=case when p_kind='request' then 'fleet_files' else 'fleet_handover_photos'end;object_path:=p_kind||'/'||p_id::text;
 execute format('select content_hash,size_bytes,storage_path from private.%I where id=$1 for update',t)into strict f using p_id;
 if f.content_hash<>p_hash or not exists(select 1 from storage.objects where bucket_id='fleet-files'and name=object_path and(metadata->>'size')::bigint=f.size_bytes)then raise exception 'Verified storage object required';end if;
 execute format('update private.%I set storage_path=$2,bytes=null where id=$1',t)using p_id,object_path;
end$$;
create function public.fleet_file_archive_complete(p_id uuid,p_kind text,p_hash text)returns void language sql security invoker set search_path=pg_catalog,private as $$select private.fleet_file_archive_complete(p_id,p_kind,p_hash)$$;
revoke all on function private.fleet_file_archive_complete(uuid,text,text),public.fleet_file_archive_complete(uuid,text,text)from public,anon,authenticated;
grant usage on schema private to service_role;
grant execute on function private.fleet_file_archive_complete(uuid,text,text),public.fleet_file_archive_complete(uuid,text,text)to service_role;
