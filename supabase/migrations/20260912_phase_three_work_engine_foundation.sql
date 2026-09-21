begin;

-- Batch 3.1: invisible shared-relation foundation for future projects.
-- No work classification or additional user-facing task field is introduced.

create table if not exists public.work_item_relations (
  id uuid primary key default gen_random_uuid(),
  source_task_id uuid not null references public.tasks(id) on delete cascade,
  target_task_id uuid not null references public.tasks(id) on delete cascade,
  relation_type text not null,
  change_reason text not null default 'إنشاء العلاقة',
  revision integer not null default 1,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_by uuid not null references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  constraint work_item_relations_distinct_tasks check (source_task_id<>target_task_id),
  constraint work_item_relations_type_check check (
    relation_type in ('RELATED_TO','BLOCKS','DEPENDS_ON','FOLLOWS_FROM')
  ),
  constraint work_item_relations_reason_length check (
    char_length(btrim(change_reason)) between 1 and 500
  ),
  constraint work_item_relations_revision_check check (revision>0),
  constraint work_item_relations_unique unique(source_task_id,target_task_id,relation_type)
);

create unique index if not exists work_item_relations_related_pair_uidx
  on public.work_item_relations(
    least(source_task_id,target_task_id),
    greatest(source_task_id,target_task_id)
  )
  where relation_type='RELATED_TO';

create index if not exists work_item_relations_source_idx
  on public.work_item_relations(source_task_id);
create index if not exists work_item_relations_target_idx
  on public.work_item_relations(target_task_id);

alter table public.work_item_relations enable row level security;
revoke all on table public.work_item_relations from public,anon;
grant select,insert,update,delete on table public.work_item_relations to authenticated;

drop policy if exists work_item_relations_select_policy on public.work_item_relations;
create policy work_item_relations_select_policy on public.work_item_relations
for select to authenticated
using (
  private.can_view_task(source_task_id)
  and private.can_view_task(target_task_id)
);

drop policy if exists work_item_relations_insert_policy on public.work_item_relations;
create policy work_item_relations_insert_policy on public.work_item_relations
for insert to authenticated
with check (
  private.can_modify_task(source_task_id)
  and private.can_view_task(target_task_id)
  and created_by=(select auth.uid())
  and updated_by=(select auth.uid())
  and revision=1
);

drop policy if exists work_item_relations_update_policy on public.work_item_relations;
create policy work_item_relations_update_policy on public.work_item_relations
for update to authenticated
using (private.can_modify_task(source_task_id))
with check (
  private.can_modify_task(source_task_id)
  and private.can_view_task(target_task_id)
  and updated_by=(select auth.uid())
);

drop policy if exists work_item_relations_delete_policy on public.work_item_relations;
create policy work_item_relations_delete_policy on public.work_item_relations
for delete to authenticated
using (private.can_modify_task(source_task_id));

create table if not exists public.work_relation_history (
  id bigint generated always as identity primary key,
  relation_id uuid not null,
  source_task_id uuid not null,
  target_task_id uuid not null,
  action text not null check (action in ('CREATED','UPDATED','DELETED')),
  before_data jsonb,
  after_data jsonb,
  change_reason text not null,
  actor_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists work_relation_history_relation_idx
  on public.work_relation_history(relation_id,created_at desc);
create index if not exists work_relation_history_source_idx
  on public.work_relation_history(source_task_id);
create index if not exists work_relation_history_target_idx
  on public.work_relation_history(target_task_id);

alter table public.work_relation_history enable row level security;
revoke all on table public.work_relation_history from public,anon,authenticated;
grant select on table public.work_relation_history to authenticated;

drop policy if exists work_relation_history_select_policy on public.work_relation_history;
create policy work_relation_history_select_policy on public.work_relation_history
for select to authenticated
using (
  private.can_view_task(source_task_id)
  and private.can_view_task(target_task_id)
);

create or replace function private.prepare_work_item_relation()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog','public','private'
as $$
declare
  v_uid uuid:=(select auth.uid());
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  new.change_reason:=btrim(new.change_reason);
  if tg_op='INSERT' then
    new.created_by:=v_uid;
    new.updated_by:=v_uid;
    new.created_at:=now();
    new.updated_at:=now();
    new.revision:=1;
  else
    new.created_by:=old.created_by;
    new.created_at:=old.created_at;
    new.updated_by:=v_uid;
    new.updated_at:=now();
    new.revision:=old.revision+1;
  end if;
  return new;
end $$;

revoke all on function private.prepare_work_item_relation() from public,anon,authenticated;

create or replace function private.audit_work_item_relation()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $$
declare
  v_row public.work_item_relations;
begin
  v_row:=case when tg_op='DELETE' then old else new end;
  insert into public.work_relation_history(
    relation_id,source_task_id,target_task_id,action,
    before_data,after_data,change_reason,actor_id
  ) values (
    v_row.id,v_row.source_task_id,v_row.target_task_id,
    case tg_op when 'INSERT' then 'CREATED' when 'UPDATE' then 'UPDATED' else 'DELETED' end,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end,
    v_row.change_reason,(select auth.uid())
  );
  return v_row;
end $$;

revoke all on function private.audit_work_item_relation() from public,anon,authenticated;

drop trigger if exists work_item_relations_prepare on public.work_item_relations;
create trigger work_item_relations_prepare
before insert or update on public.work_item_relations
for each row execute function private.prepare_work_item_relation();

drop trigger if exists work_item_relations_audit on public.work_item_relations;
create trigger work_item_relations_audit
after insert or update or delete on public.work_item_relations
for each row execute function private.audit_work_item_relation();

comment on table public.work_item_relations is
  'Editable links and dependencies between visible work items.';
comment on table public.work_relation_history is
  'Immutable audit trail for work relation corrections.';

commit;
