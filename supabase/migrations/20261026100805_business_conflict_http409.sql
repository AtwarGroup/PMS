-- Business revision conflicts must not masquerade as database serialization
-- failures: PostgREST 14 retries SQLSTATE 40001 indefinitely. PT409 returns a
-- terminal HTTP 409 while preserving every revision check and error message.
-- Only explicit errcode assignments are replaced; genuine database errors and
-- exception handlers, function attributes, ownership and ACLs are untouched.
do $migration$
declare f record; definition text; patched text;
begin
 for f in
  select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','private') and p.prokind='f'
    and p.prosrc ~ $pattern$errcode[[:space:]]*=[[:space:]]*'40001'$pattern$
 loop
  definition := pg_get_functiondef(f.oid);
  patched := regexp_replace(definition,
    $pattern$errcode[[:space:]]*=[[:space:]]*'40001'$pattern$,
    'errcode=''PT409''', 'g');
  execute patched;
 end loop;
end
$migration$;
