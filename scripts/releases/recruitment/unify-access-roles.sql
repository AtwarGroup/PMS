-- Promote existing grants into visible account roles without granting new access.
-- No profile IDs, new module access or recruitment route changes.
begin;
do $$
declare spec record;rid uuid;u record;prior jsonb;expected text[];actual text[];
begin
 for spec in select * from(values
 ('مسؤول التوظيف وشؤون الموظفين','إدارة الترشيح والمقابلات وإعداد العروض والتوطين والمستندات والمباشرة؛ الإجراءات مقيدة بالطلب المسند.',array['recruitment.manage','recruitment.personnel']),
 ('معتمد احتياجات وعروض التوظيف','اعتماد الاحتياج والعرض والاستثناء المحال لصاحب الصلاحية؛ لا يعتمد العرض الذي أعده بنفسه.',array['recruitment.approve']),
 ('مراجع استثناءات التوظيف والمزايا','مراجعة استثناءات التوظيف والراتب والمزايا واستئناف الدفعات الإضافية وتقويم العمل.',array['recruitment.development'])
 )v(name,description,permissions) loop
 select id into rid from private.access_roles where name=spec.name for update;
 if rid is null then
  insert into private.access_roles(name,description,active)values(spec.name,spec.description,true)returning id into rid;
  insert into private.access_role_rules(role_id,permission,scope)select rid,k,'all'from unnest(spec.permissions)k;
  perform private.access_log('ROLE_SAVED',rid::text,null,(select to_jsonb(r)||jsonb_build_object('source','recruitment role normalization')from private.access_roles r where id=rid));
 elsif not exists(select 1 from private.access_roles where id=rid and active)or (select array_agg(permission order by permission)from private.access_role_rules where role_id=rid)is distinct from (select array_agg(k order by k)from unnest(spec.permissions)k)then
  raise exception 'Existing recruitment role differs; review before migrating: %',spec.name;
 end if;
 for u in select p.id,p.permissions,p.allowed_modules from public.profiles p join private.access_direct_tasks d on d.profile_id=p.id where d.permissions @> spec.permissions order by p.id for update of p,d loop
  expected:=array(select k from unnest(u.permissions)k order by k);
  select jsonb_build_object('direct',d.permissions,'effective',p.permissions,'modules',p.allowed_modules)into prior from public.profiles p join private.access_direct_tasks d on d.profile_id=p.id where p.id=u.id;
  insert into private.access_assignments(profile_id,role_id)values(u.id,rid)on conflict(profile_id,role_id)do nothing;
  update private.access_direct_tasks set permissions=array(select k from unnest(permissions)k where not k=any(spec.permissions))where profile_id=u.id;
  perform private.access_rebuild_tasks(u.id);
  select array(select k from unnest(p.permissions)k order by k)into actual from public.profiles p where id=u.id;
  if actual is distinct from expected or (select allowed_modules from public.profiles where id=u.id)is distinct from u.allowed_modules then raise exception 'Effective access changed unexpectedly';end if;
  perform private.access_log('RECRUITMENT_ROLE_NORMALIZED',u.id::text,prior,jsonb_build_object('role_id',rid,'permissions',actual,'modules',u.allowed_modules));
 end loop;
 end loop;
end $$;
commit;
