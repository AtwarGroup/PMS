-- Run in a transaction and roll back. No persistent test records or notifications.
create temporary table review_qa(p uuid,v uuid,a uuid,c uuid,r uuid,o uuid);
insert into review_qa(a,c,r,o) select
(select id from public.profiles where email='e2e-admin@atwargroup.test'),
(select id from public.profiles where email='e2e-manager@atwargroup.test'),
(select id from public.profiles where email='e2e-employee@atwargroup.test'),
(select id from public.profiles where role='employee' and active and status='active' and email<>'e2e-employee@atwargroup.test' limit 1);
grant all on review_qa to authenticated;
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true) from review_qa;
update review_qa set p=public.policy_create('QA-'||gen_random_uuid(),'QA review','[{"id":"s1","title":"QA section","body":"QA text"}]','QA');
update review_qa set v=(select id from public.policy_versions where policy_id=p);
select public.policy_set_review_access(p,1,array[r],array[c]) from review_qa;
select set_config('request.jwt.claims',jsonb_build_object('sub',r,'role','authenticated')::text,true) from review_qa;
do $$declare q record;begin select * into q from review_qa;
 if not exists(select 1 from public.policy_versions where id=q.v) then raise exception 'Viewer cannot read';end if;
 begin perform public.policy_comment(q.v,'s1','Viewer must not comment');raise exception 'Viewer commented';exception when insufficient_privilege then null;end;
 begin perform public.policy_save(q.v,1,'[{"id":"s1","title":"QA section","body":"Tampered"}]','QA');raise exception 'Viewer edited';exception when insufficient_privilege then null;end;
 begin perform public.policy_set_review_access(q.p,2,array[q.o],array[]::uuid[]);raise exception 'Viewer changed access';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',c,'role','authenticated')::text,true) from review_qa;
select public.policy_comment(v,'s1','QA reviewer comment') from review_qa;
do $$declare q record;begin select * into q from review_qa;
 if not exists(select 1 from public.policy_comments where version_id=q.v) then raise exception 'Comment not stored';end if;
 begin perform public.policy_decide(q.v,1,false,'Unauthorized advance',null);raise exception 'Commenter advanced';exception when insufficient_privilege then null;end;
 begin perform public.policy_save(q.v,1,'[{"id":"s1","title":"QA section","body":"Tampered"}]','QA');raise exception 'Commenter edited';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true) from review_qa;
do $$declare q record;begin select * into q from review_qa;
 if exists(select 1 from public.policies where id=q.p) or exists(select 1 from public.policy_versions where id=q.v) or exists(select 1 from public.policy_comments where version_id=q.v) then raise exception 'Unauthorized disclosure';end if;
 begin perform public.policy_comment(q.v,'s1','Outsider');raise exception 'Outsider commented';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true) from review_qa;
select public.policy_set_review_access(p,2,array[]::uuid[],array[]::uuid[]) from review_qa;
select set_config('request.jwt.claims',jsonb_build_object('sub',c,'role','authenticated')::text,true) from review_qa;
do $$declare q record;begin select * into q from review_qa;
 if exists(select 1 from public.policy_versions where id=q.v) then raise exception 'Revocation failed';end if;
 begin perform public.policy_comment(q.v,'s1','Revoked comment');raise exception 'Revoked user commented';exception when insufficient_privilege then null;end;
end $$;
reset role;
