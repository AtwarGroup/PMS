-- Staging only, transactionally rolled back; never sends mail.
begin;
do $$
declare r private.recruitment_requests; t private.it_support_tickets; d private.fleet_documents; owner uuid; n int; stage text;
begin
 select * into r from private.recruitment_requests order by number limit 1;
 assert r.id is not null,'recruitment fixture missing';
 foreach stage in array array['department_review','finance_review','hr_review','approval','hr_exception','finance_exception','cancellation_approval']loop
  update private.recruitment_requests set status=stage where id=r.id;
  select private.recruitment_owner(x)into owner from private.recruitment_requests x where x.id=r.id;
  assert exists(select 1 from private.important_email_actions()where module='recruitment'and entity_id=r.id and recipient_id=owner),'request stage owner missing';
 end loop;
 update private.recruitment_requests set status='closed'where id=r.id;
 assert not exists(select 1 from private.important_email_actions()where module='recruitment'and entity_id=r.id),'closed recruitment generated mail';
 select * into t from private.it_support_tickets where service_key not in('purchase','suggestion')limit 1;
 assert t.id is not null,'IT fixture missing';
 update private.it_support_tickets set priority=1,state='working'where id=t.id;
 assert exists(select 1 from private.important_email_actions()where module='it_support'and entity_id=t.id and recipient_id=private.it_support_owner(t.id)),'critical IT owner missing';
 update private.it_support_tickets set priority=2 where id=t.id;
 assert not exists(select 1 from private.important_email_actions()where module='it_support'and entity_id=t.id),'ordinary IT generated mail';
 select * into d from private.fleet_documents limit 1;
 assert d.id is not null,'document fixture missing';
 update private.fleet_documents set expires_on=(now()at time zone'Asia/Riyadh')::date+10 where id=d.id;
 assert exists(select 1 from private.important_email_candidates()where entity_id=d.id and payload->>'phase'='critical'),'15 day threshold missing';
 update private.fleet_documents set expires_on=(now()at time zone'Asia/Riyadh')::date-1 where id=d.id;
 assert exists(select 1 from private.important_email_candidates()where entity_id=d.id and payload->>'phase'='expired'),'expired phase missing';
 update private.fleet_documents set expires_on=current_date+1000 where id=d.id;
 assert not exists(select 1 from private.important_email_candidates()where entity_id=d.id),'renewed document generated mail';
 assert not exists(select 1 from private.important_email_candidates()where payload::text~'(basic|housing|salary|candidate_name)'),'sensitive offer fields leaked';
end$$;
rollback;
