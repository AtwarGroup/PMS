begin;

alter table public.follow_ups
  add column if not exists task_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='follow_ups_task_id_fkey'
      and conrelid='public.follow_ups'::regclass
  ) then
    alter table public.follow_ups
      add constraint follow_ups_task_id_fkey
      foreign key (task_id) references public.tasks(id) on delete set null;
  end if;
end $$;

create index if not exists follow_ups_owner_task_idx
  on public.follow_ups(owner_id,task_id)
  where task_id is not null;

alter policy follow_ups_insert_policy on public.follow_ups
with check (
  private.current_user_is_active()
  and owner_id=(select auth.uid())
  and (task_id is null or private.can_view_task(task_id))
);

alter policy follow_ups_update_policy on public.follow_ups
using (
  private.current_user_is_active()
  and owner_id=(select auth.uid())
)
with check (
  private.current_user_is_active()
  and owner_id=(select auth.uid())
  and (task_id is null or private.can_view_task(task_id))
);

drop function if exists public.workspace_add_followup(text,date,text);

create function public.workspace_add_followup(
  p_title text,
  p_follow_date date default null,
  p_note text default '',
  p_task_id uuid default null
)
returns uuid
language plpgsql
security invoker
set search_path to 'public','pg_temp'
as $$
declare
  v_uid uuid:=(select auth.uid());
  v_id uuid;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if nullif(btrim(p_title),'') is null then raise exception 'Title required'; end if;
  if p_task_id is not null and not exists(
    select 1 from public.tasks t
    where t.id=p_task_id and t.deleted_at is null
  ) then
    raise exception 'Linked task not found or not visible';
  end if;

  insert into public.follow_ups(owner_id,title,follow_date,note_text,status,task_id)
  values(v_uid,btrim(p_title),p_follow_date,coalesce(p_note,''),'soon',p_task_id)
  returning id into v_id;
  return v_id;
end $$;

revoke all on function public.workspace_add_followup(text,date,text,uuid) from public,anon;
grant execute on function public.workspace_add_followup(text,date,text,uuid) to authenticated;

commit;
