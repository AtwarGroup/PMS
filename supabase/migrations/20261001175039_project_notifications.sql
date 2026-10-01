alter table public.notifications add column project_id uuid references public.projects(id);
create index on public.notifications(project_id);
do $$ declare s text;begin
 s:=pg_get_functiondef('private.project_command(uuid,integer,text,jsonb)'::regprocedure);
 s:=replace(s,'insert into public.notifications(recipient_id,task_id,type,title,message) select u,null,', 'insert into public.notifications(recipient_id,project_id,task_id,type,title,message) select u,p.id,null,');
 s:=replace(s,'delete from public.project_members where project_id=p.id;', $q$insert into public.notifications(recipient_id,project_id,type,title,message) select u,p.id,'project_member','انضمام إلى مشروع','أضيفت إلى فريق المشروع: '||p.title from (select distinct unnest(v_members||array[p.manager_id,p.sponsor_id]) u) x where u<>v_uid and not exists(select 1 from public.project_members m where m.project_id=p.id and m.user_id=u) and (p_action='create' or u not in(p.manager_id,p.sponsor_id)); delete from public.project_members where project_id=p.id;$q$);
 execute s;
end $$;
