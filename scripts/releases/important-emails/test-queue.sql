begin;
do $$
declare token text; b jsonb; b2 jsonb; n int; total int; denied boolean:=false; first_key text; doc uuid;
begin
 token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into private.important_email_invocations(token_hash,expires_at)values(encode(extensions.digest(token,'sha256'),'hex'),now()+interval '5 minutes');
 perform public.important_email_claim(token,true);
 denied:=false;begin perform public.important_email_claim(token,true);exception when insufficient_privilege then denied:=true;end;
 assert denied,'scheduler token replay accepted';denied:=false;
 begin perform public.important_email_claim(repeat('0',64),true);exception when insufficient_privilege then denied:=true;end;
 assert denied,'wrong scheduler token accepted';
 assert not has_function_privilege('anon','public.important_email_claim(text,boolean)','execute'),'anonymous queue access';
 assert not has_function_privilege('authenticated','public.important_email_finish(uuid,uuid,text,text,boolean)','execute'),'user finalize access';
 assert not has_table_privilege('authenticated','private.important_email_outbox','select'),'queue exposed';
 update private.important_email_settings set enabled=false where id;
 assert (public.important_email_claim(token,false)->>'disabled')::boolean,'disabled sender claimed mail';
 update private.important_email_settings set enabled=true where id;
 b:=public.important_email_claim(token,false);
 assert jsonb_array_length(b->'items')>0,'fixture requires current important actions';
 assert public.important_email_validate((b->>'batch_id')::uuid,(b->>'claim_token')::uuid),'fresh claim invalid';
 assert not public.important_email_validate((b->>'batch_id')::uuid,gen_random_uuid()),'wrong lease validated';
 select count(*)into total from private.important_email_outbox;
 b2:=public.important_email_claim(token,false);
 select count(*)into n from private.important_email_outbox;
 assert n=total,'duplicate collection';
 assert b->>'batch_id' is distinct from b2->>'batch_id','parallel claim duplicated a batch';
 -- A lease cannot be finished by a stale or unrelated worker.
 perform public.important_email_finish((b->>'batch_id')::uuid,gen_random_uuid(),'test-only',null,false);
 assert exists(select 1 from private.important_email_outbox where batch_id=(b->>'batch_id')::uuid and status='sending'),'wrong lease finalized';
 -- Current recipient deactivation must invalidate the complete frozen digest before provider access.
 update public.profiles set active=false,status='inactive' where id=(select recipient_id from private.important_email_outbox where batch_id=(b->>'batch_id')::uuid limit 1);
 assert not public.important_email_validate((b->>'batch_id')::uuid,(b->>'claim_token')::uuid),'inactive recipient allowed';
 assert not exists(select 1 from private.important_email_outbox where batch_id=(b->>'batch_id')::uuid and status='sending'),'stale mail not cancelled';
 -- Digest rows all belong to the same recipient and retry with an identical batch and payload.
 if jsonb_array_length(b2->'items')>0 then
  assert(select count(distinct recipient_id)=1 from private.important_email_outbox where batch_id=(b2->>'batch_id')::uuid),'mixed recipients';
  perform public.important_email_finish((b2->>'batch_id')::uuid,(b2->>'claim_token')::uuid,null,'simulated_timeout',true);
  assert not exists(select 1 from private.important_email_outbox where batch_id=(b2->>'batch_id')::uuid and status='sent'),'failed mail marked sent';
 end if;
 -- An ambiguous old attempt is quarantined before provider idempotency expires.
 update private.important_email_outbox set status='sending',first_attempt_at=now()-interval '21 hours',claimed_at=now()-interval '21 hours'where batch_id=(b2->>'batch_id')::uuid;
 perform public.important_email_claim(token,false);
 assert not exists(select 1 from private.important_email_outbox where batch_id=(b2->>'batch_id')::uuid and status in('pending','sending')),'unsafe aged retry';
 raise notice 'PASS queue: auth, RLS, disabled flag, current candidates, dedupe, claims, lease validation, inactive recipient, digest isolation, retries, 20h quarantine';
end$$;
rollback;
