-- Separate preparation, personnel review and finance review. No automatic user/module grants.
begin;
do $$declare legacy uuid;u uuid;spec record;rid uuid;prior jsonb;begin
 select id into legacy from private.access_roles where name='مسؤول التوظيف وشؤون الموظفين' for update;
 if legacy is not null then
  if exists(select 1 from private.access_roles where name='مسؤول التوظيف'and id<>legacy)then raise exception 'Resolve the existing recruitment role before separating permissions';end if;
  select to_jsonb(r)into prior from private.access_roles r where id=legacy;
  update private.access_roles set name='مسؤول التوظيف',description='الاستقطاب والتنسيق وإعداد العروض والمستندات والمباشرة؛ لا يمنح مراجعة شؤون الموظفين أو اعتماد عرضه.',revision=revision+1,updated_at=now()where id=legacy;
  delete from private.access_role_rules where role_id=legacy and permission='recruitment.personnel';
  for u in select profile_id from private.access_assignments where role_id=legacy loop perform private.access_rebuild_tasks(u);end loop;
  perform private.access_log('ROLE_SAVED',legacy::text,prior,(select to_jsonb(r)from private.access_roles r where id=legacy));
 end if;
 for spec in select * from(values
 ('مسؤول التوظيف','الاستقطاب والتنسيق وإعداد العروض والمستندات والمباشرة.','recruitment.manage'),
 ('مراجع شؤون الموظفين للتوظيف','مراجعة الاحتياج والشاغر والتوطين، ومراجعة العرض قبل الإدارة الطالبة والرئيس التنفيذي.','recruitment.personnel'),
 ('مراجع موازنة التوظيف','مراجعة موازنة الاحتياج قبل شؤون الموظفين؛ الرفض يحال للرئيس التنفيذي للاستثناء.','recruitment.finance')
 )v(name,description,permission)loop
 select id into rid from private.access_roles where name=spec.name;
 if rid is null then
 insert into private.access_roles(name,description)values(spec.name,spec.description)returning id into rid;
 insert into private.access_role_rules(role_id,permission,scope)values(rid,spec.permission,'all');
 perform private.access_log('ROLE_SAVED',rid::text,null,(select to_jsonb(r)from private.access_roles r where id=rid));
 end if;
 end loop;
 update private.access_catalog set label='مراجعة موازنة احتياج التوظيف'where key='recruitment.finance';
 update private.access_catalog set label='مراجعة شؤون الموظفين والاحتياج والشاغر والتوطين والعروض'where key='recruitment.personnel';
end $$;
commit;
