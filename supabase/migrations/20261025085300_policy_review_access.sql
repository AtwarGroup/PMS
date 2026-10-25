begin;
alter table public.policies add column review_viewer_ids uuid[] not null default '{}', add column review_commenter_ids uuid[] not null default '{}';
create function private.policy_review_access(p uuid, commenting boolean default false) returns boolean language sql stable security definer set search_path='pg_catalog','public','private' as $$
 select private.module_allowed('policies') and private.current_user_is_active() and (private.policy_worker(p) or exists(select 1 from public.policies x where x.id=p and (auth.uid()=any(x.review_commenter_ids) or (not commenting and auth.uid()=any(x.review_viewer_ids)))))
$$;
revoke all on function private.policy_review_access(uuid,boolean) from public,anon;
grant execute on function private.policy_review_access(uuid,boolean) to authenticated;
create or replace function private.policy_visible_version(v uuid) returns boolean language sql stable security definer set search_path='pg_catalog','public','private' as $$
 select private.module_allowed('policies') and private.current_user_is_active() and exists(select 1 from public.policy_versions x where x.id=v and (private.policy_worker(x.policy_id) or (x.status<>'APPROVED' and private.policy_review_access(x.policy_id,false)) or (
 x.id=(select y.id from public.policy_versions y where y.policy_id=x.policy_id and y.status='APPROVED' and y.effective_date<=current_date order by y.version_number desc limit 1)
 and (('MANAGEMENT'=any(x.audience_groups) and auth.uid()=any(x.management_viewer_ids)) or ('MANAGERS'=any(x.audience_groups) and private.current_user_role()='manager') or ('EMPLOYEES'=any(x.audience_groups) and private.current_user_role()='employee')))))
$$;
alter policy policy_comment_read on public.policy_comments using(exists(select 1 from public.policy_versions v where v.id=version_id and (private.policy_worker(v.policy_id) or (v.status<>'APPROVED' and private.policy_review_access(v.policy_id,false)))));
create or replace function private.policy_comment(p_id uuid,p_section text,p_body text) returns void language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v public.policy_versions%rowtype;
begin
 select * into v from public.policy_versions where id=p_id for share;
 if not found or not private.policy_review_access(v.policy_id,true) then raise exception 'Comment permission required' using errcode='42501';end if;
 if v.status='APPROVED' then raise exception 'Open a new version to review approved content';end if;
 if not exists(select 1 from jsonb_array_elements(v.content) s where s->>'id'=p_section) then raise exception 'Section not found';end if;
 if length(btrim(coalesce(p_body,''))) not between 2 and 2000 then raise exception 'Comment requires 2–2000 characters';end if;
 insert into public.policy_comments(version_id,section_id,actor_id,actor_name,body) select v.id,p_section,auth.uid(),full_name,btrim(p_body) from public.profiles where id=auth.uid();
end $$;
create function private.policy_set_review_access(p_id uuid,p_revision integer,p_viewers uuid[],p_commenters uuid[]) returns void language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare p public.policies%rowtype;
begin
 if not private.module_allowed('policies') or not private.current_user_is_active() or not private.is_admin() then raise exception 'Administrator required' using errcode='42501';end if;
 select * into p from public.policies where id=p_id for update;
 if not found then raise exception 'Policy not found';end if;
 if p_revision is null or p.revision<>p_revision then raise exception 'ATWAR_CONFLICT: review access changed';end if;
 if p_viewers is null or p_commenters is null or exists(select 1 from unnest(p_viewers||p_commenters) u where u is null or not exists(select 1 from public.profiles where id=u and active and status='active')) then raise exception 'Select active accounts';end if;
 update public.policies set review_viewer_ids=array(select distinct x from unnest(p_viewers) x where not x=any(p_commenters)),review_commenter_ids=array(select distinct x from unnest(p_commenters) x),revision=revision+1,updated_at=now() where id=p_id;
 perform private.policy_log(p_id,null,'REVIEW_ACCESS',null,null,'تحديث صلاحيات الاطلاع والملاحظات قبل الاعتماد');
end $$;
create function public.policy_set_review_access(p_id uuid,p_revision integer,p_viewers uuid[],p_commenters uuid[]) returns void language sql security invoker set search_path='pg_catalog','private' as $$select private.policy_set_review_access(p_id,p_revision,p_viewers,p_commenters)$$;
revoke all on function private.policy_set_review_access(uuid,integer,uuid[],uuid[]),public.policy_set_review_access(uuid,integer,uuid[],uuid[]) from public,anon;
grant execute on function private.policy_set_review_access(uuid,integer,uuid[],uuid[]),public.policy_set_review_access(uuid,integer,uuid[],uuid[]) to authenticated;
create or replace function private.policy_save(p_id uuid,p_revision integer,p_content jsonb,p_label text) returns void language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v public.policy_versions%rowtype;p public.policies%rowtype;
begin
 select policy_id into p.id from public.policy_versions where id=p_id;
 select * into p from public.policies where id=p.id for update;select * into v from public.policy_versions where id=p_id for update;
 if v.id is null or p.id is null or not private.module_allowed('policies') or not private.current_user_is_active() or not coalesce((private.is_admin() or auth.uid()=p.preparer_id),false) then raise exception 'Assigned preparer required' using errcode='42501';end if;
 if v.status<>'PREPARATION' then raise exception 'Editing is allowed only during preparation';end if;
 if p_revision is null or v.revision<>p_revision then raise exception 'ATWAR_CONFLICT: version changed';end if;
 perform private.policy_validate_content(p_content);
 update public.policy_versions set content=p_content,version_label=left(coalesce(p_label,''),100),revision=revision+1,updated_at=now() where id=p_id;
 perform private.policy_log(p.id,v.id,'EDIT',v.status,v.status,'حفظ محتوى المسودة');
end $$;
notify pgrst,'reload schema';
commit;
