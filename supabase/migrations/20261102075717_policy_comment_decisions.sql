begin;
alter table public.policy_comments add column decision text check (decision in ('ACCEPTED','DISMISSED')),
 add column decision_reason text not null default '', add column decision_by uuid references public.profiles(id),
 add column decision_by_name text, add column decided_at timestamptz,
 add column previous_text text, add column revised_text text;
create function private.policy_resolve_comment(p_comment uuid,p_revision integer,p_accept boolean,p_reason text,p_revised text)
returns void language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare c public.policy_comments%rowtype; v public.policy_versions%rowtype; p public.policies%rowtype; oldbody text; newcontent jsonb; actorname text;
begin
 select * into c from public.policy_comments where id=p_comment;
 if not found then raise exception 'Comment not found'; end if;
 select * into p from public.policies where id=(select policy_id from public.policy_versions where id=c.version_id) for update;
 select * into v from public.policy_versions where id=c.version_id for update;
 select * into c from public.policy_comments where id=p_comment for update;
 if not private.current_user_is_active() or auth.uid() is null or p.approver_id is distinct from auth.uid() or v.status <> 'APPROVAL' then raise exception 'Assigned approver required' using errcode='42501'; end if;
 if p_revision is null or v.revision<>p_revision then raise exception 'ATWAR_CONFLICT: version changed'; end if;
 if c.decision is not null then raise exception 'Comment already resolved'; end if;
 if p_accept is null or length(coalesce(p_reason,''))>2000 then raise exception 'Invalid decision'; end if;
 select s->>'body' into oldbody from jsonb_array_elements(v.content) s where s->>'id'=c.section_id;
 if oldbody is null then raise exception 'Section not found'; end if;
 select full_name into actorname from public.profiles where id=auth.uid();
 if p_accept then
  if length(btrim(coalesce(p_revised,''))) not between 2 and 60000 or btrim(p_revised)=btrim(oldbody) then raise exception 'يجب تعديل نص القسم قبل حفظه'; end if;
  select jsonb_agg(case when x.item->>'id'=c.section_id then jsonb_set(x.item,'{body}',to_jsonb(p_revised),false) else x.item end order by x.ord) into newcontent from jsonb_array_elements(v.content) with ordinality x(item,ord);
  perform private.policy_validate_content(newcontent);
  update public.policy_versions set content=newcontent,status='REVIEW',revision=revision+1,cycle=cycle+1,updated_at=now() where id=v.id;
 else
  update public.policy_versions set revision=revision+1,updated_at=now() where id=v.id;
 end if;
 update public.policy_comments set decision=case when p_accept then 'ACCEPTED' else 'DISMISSED' end, decision_reason=btrim(coalesce(p_reason,'')),decision_by=auth.uid(),decision_by_name=actorname,decided_at=now(),previous_text=case when p_accept then oldbody else null end,revised_text=case when p_accept then p_revised else null end where id=c.id;
 perform private.policy_log(p.id,v.id,'COMMENT_DECISION',v.status,case when p_accept then 'REVIEW' else v.status end,case when p_accept then 'الأخذ بالملاحظة وتعديل القسم وإعادة المراجعة' else 'عدم الأخذ بالملاحظة' end || case when btrim(coalesce(p_reason,''))<>'' then ': '||btrim(p_reason) else '' end);
end $$;
create function public.policy_resolve_comment(p_comment uuid,p_revision integer,p_accept boolean,p_reason text,p_revised text) returns void language sql security invoker set search_path='pg_catalog','private' as $$ select private.policy_resolve_comment(p_comment,p_revision,p_accept,p_reason,p_revised) $$;
revoke all on function private.policy_resolve_comment(uuid,integer,boolean,text,text),public.policy_resolve_comment(uuid,integer,boolean,text,text) from public,anon;
grant execute on function private.policy_resolve_comment(uuid,integer,boolean,text,text),public.policy_resolve_comment(uuid,integer,boolean,text,text) to authenticated;
commit;
