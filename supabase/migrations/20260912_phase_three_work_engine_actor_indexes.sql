begin;

-- Direct covering indexes for Work Engine profile foreign keys.
create index if not exists work_item_relations_created_by_idx
  on public.work_item_relations(created_by);

create index if not exists work_item_relations_updated_by_idx
  on public.work_item_relations(updated_by);

create index if not exists work_relation_history_actor_id_idx
  on public.work_relation_history(actor_id);

commit;
