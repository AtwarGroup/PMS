create table if not exists private.important_email_invocations(
 token_hash text primary key,expires_at timestamptz not null,used_at timestamptz
);
alter table private.important_email_invocations enable row level security;
revoke all on private.important_email_invocations from public,anon,authenticated;

create or replace function public.important_email_claim(p_token text,p_probe boolean default false)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare cfg private.important_email_settings; item record; batch uuid; lease uuid:=gen_random_uuid(); rows jsonb; recipient uuid;
begin
 select * into strict cfg from private.important_email_settings where id;
 if p_token is null then raise exception 'Unauthorized'using errcode='42501';end if;
 if p_probe then
  update private.important_email_invocations set used_at=now()where token_hash=encode(extensions.digest(p_token,'sha256'),'hex')and used_at is null and expires_at>now();
  if not found then raise exception 'Unauthorized'using errcode='42501';end if;
  return jsonb_build_object('enabled',cfg.enabled,'ready',true);
 end if;
 if not exists(select 1 from private.important_email_invocations where token_hash=encode(extensions.digest(p_token,'sha256'),'hex')and used_at is not null and expires_at>now())then raise exception 'Unauthorized'using errcode='42501';end if;
 if not cfg.enabled then return jsonb_build_object('disabled',true);end if;
 perform pg_advisory_xact_lock(hashtext('important-email-claim'));
 -- Any ambiguous attempt older than 20h is quarantined, never retried past provider dedupe retention.
 update private.important_email_outbox set status='failed',last_error='delivery_unknown_manual_review'where status in('sending','pending')and first_attempt_at<now()-interval '20 hours';
 update private.important_email_outbox set status='pending'where status='sending'and claimed_at<now()-interval '5 minutes';
 -- Cancel obsolete work, renewed documents, changed owners and disabled recipients before sending.
 update private.important_email_outbox o set status='cancelled',last_error='action_no_longer_current'
 where o.status='pending'and not exists(select 1 from private.important_email_candidates()c where c.event_key=o.event_key);
 insert into private.important_email_outbox(event_key,module,entity_id,recipient_id,payload)
 select c.event_key,c.module,c.entity_id,c.recipient_id,c.payload from private.important_email_candidates()c
 where not exists(select 1 from private.important_email_outbox o where o.event_key=c.event_key)
 on conflict(event_key)do nothing;
 select * into item from private.important_email_outbox where status='pending'and next_attempt_at<=now()and attempts<5 order by created_at,id limit 1 for update skip locked;
 if not found then return jsonb_build_object('items','[]'::jsonb);end if;
 batch:=coalesce(item.batch_id,item.id);recipient:=item.recipient_id;
 -- Freeze a document digest on its first attempt so retries use identical content and key.
 if item.batch_id is null then
  update private.important_email_outbox o set batch_id=batch where o.id in(
   select id from private.important_email_outbox where status='pending'and next_attempt_at<=now()and batch_id is null and recipient_id=recipient
   and(case when item.event_key like 'document:%'then event_key like 'document:%'else id=item.id end)order by created_at,id limit 50);
 end if;
 -- A partial cancellation changes a frozen digest: quarantine rather than reuse a provider key with different data.
 if exists(select 1 from private.important_email_outbox where batch_id=batch and status not in('pending','sending'))then
  update private.important_email_outbox set status='cancelled',last_error='digest_changed'where batch_id=batch and status='pending';
  return jsonb_build_object('items','[]'::jsonb);
 end if;
 update private.important_email_outbox o set status='sending',attempts=attempts+1,claimed_at=now(),claim_token=lease,
 first_attempt_at=coalesce(first_attempt_at,now()),recipient_email=coalesce(o.recipient_email,(select lower(btrim(email))from public.profiles where id=o.recipient_id))
 where batch_id=batch and status='pending';
 select jsonb_agg(jsonb_build_object('id',id,'payload',payload)order by event_key)into rows from private.important_email_outbox where batch_id=batch and claim_token=lease;
 return jsonb_build_object('batch_id',batch,'claim_token',lease,'recipient',(select recipient_email from private.important_email_outbox where batch_id=batch limit 1),'items',rows);
end$$;
revoke all on function public.important_email_claim(text,boolean)from public,anon,authenticated;
grant execute on function public.important_email_claim(text,boolean)to service_role;


create or replace function private.invoke_important_email_worker(p_probe boolean default false)returns bigint
language plpgsql security definer set search_path=pg_catalog,private as $$
declare cfg private.important_email_settings; rid bigint; nonce text:=encode(extensions.gen_random_bytes(32),'hex');
begin
 select * into strict cfg from private.important_email_settings where id;
 if not p_probe and not cfg.enabled then return null;end if;
 if cfg.function_url!~'^https://[a-z]+\.supabase\.co/functions/v1/send-important-emails$'then raise exception 'Worker URL is not configured';end if;
 insert into private.important_email_invocations(token_hash,expires_at)values(encode(extensions.digest(nonce,'sha256'),'hex'),now()+interval '5 minutes');
 select net.http_post(url:=cfg.function_url,headers:=jsonb_build_object('Content-Type','application/json','x-atwar-worker',nonce),body:=jsonb_build_object('probe',p_probe),timeout_milliseconds:=120000)into rid;
 update private.important_email_settings set last_invoked_at=now(),last_request_id=rid where id;
 return rid;
end$$;
revoke all on function private.invoke_important_email_worker(boolean)from public,anon,authenticated;
