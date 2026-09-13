import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const read=file=>readFileSync(resolve(root,file),'utf8');
const migration=read('supabase/migrations/20260912_phase_three_work_engine_foundation.sql');
const indexes=read('supabase/migrations/20260912_phase_three_work_engine_actor_indexes.sql');

const contracts=[
  [/create table if not exists public\.work_item_relations/i,'Work relations table must exist'],
  [/source_task_id<>target_task_id/i,'Self relations must be rejected'],
  [/RELATED_TO.*BLOCKS.*DEPENDS_ON.*FOLLOWS_FROM/s,'Supported relation semantics must be explicit'],
  [/work_item_relations_related_pair_uidx/i,'Symmetric related-to duplicates must be rejected'],
  [/private\.can_modify_task\(source_task_id\)/i,'Relation writes must follow task modification authority'],
  [/private\.can_view_task\(target_task_id\)/i,'Relation targets must remain inside task visibility'],
  [/create table if not exists public\.work_relation_history/i,'Relation history must exist'],
  [/revoke all on table public\.work_relation_history from public,anon,authenticated/i,'History must reject direct writes'],
  [/security definer[\s\S]*?private\.audit_work_item_relation/i,'Only the private audit trigger may bypass RLS'],
  [/before_data jsonb[\s\S]*after_data jsonb/i,'Audit history must retain before and after states'],
  [/new\.revision:=old\.revision\+1/i,'Relation corrections must increment revision']
];

for(const [pattern,message] of contracts) assert.match(migration,pattern,message);

assert.doesNotMatch(migration,/service_role/i,'Public Work Engine migration must not expose service-role access');
assert.doesNotMatch(migration,/user_metadata/i,'Authorization must not depend on editable user metadata');
const deferredClassification=new RegExp(['work','type'].join('_')+'s?','i');
assert.doesNotMatch(migration,deferredClassification,'Deferred classification must not exist in this batch');
assert.match(indexes,/work_item_relations_created_by_idx/i,'Relation creator foreign key must be indexed');
assert.match(indexes,/work_item_relations_updated_by_idx/i,'Relation updater foreign key must be indexed');
assert.match(indexes,/work_relation_history_actor_id_idx/i,'History actor foreign key must be indexed');

console.log(`Phase-three shared relations foundation audit passed: ${contracts.length+6} contracts.`);
