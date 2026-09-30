#!/usr/bin/env bash
set -Eeuo pipefail

backup_dir="${1:?Backup directory is required}"
drill_url="${RESTORE_DRILL_DB_URL:?RESTORE_DRILL_DB_URL is required}"
production_url="${SUPABASE_DB_URL:?SUPABASE_DB_URL is required}"

test "${ALLOW_RESTORE_DRILL:-}" = "yes" || {
  echo "Restore drill is locked. Set ALLOW_RESTORE_DRILL=yes for a disposable target." >&2
  exit 1
}

fingerprint() {
  node -e "const u=new URL(process.argv[1]); console.log([u.hostname,u.port||'5432',u.pathname.replace(/^\\//,'')].join(':'))" "$1"
}

production_fingerprint="$(fingerprint "$production_url")"
drill_fingerprint="$(fingerprint "$drill_url")"
test "$production_fingerprint" != "$drill_fingerprint" || {
  echo "Refusing to restore into the production database." >&2
  exit 1
}

test -s "$backup_dir/database.dump" || {
  echo "database.dump is missing or empty." >&2
  exit 1
}

docker run --rm postgres:17.6 pg_isready --dbname="$drill_url"
docker run --rm --volume "$backup_dir:/backup:ro" postgres:17.6 \
  pg_restore --dbname="$drill_url" --clean --if-exists --no-owner --no-privileges --exit-on-error \
  /backup/database.dump

docker run --rm -i postgres:17.6 psql -X "$drill_url" -v ON_ERROR_STOP=1 <<'SQL'
do $verify$
begin
  if to_regclass('public.tasks') is null then
    raise exception 'Restored tasks table is missing';
  end if;
  if to_regclass('public.profiles') is null then
    raise exception 'Restored profiles table is missing';
  end if;

  -- These reads must also fail the drill if the restored tables are inaccessible.
  perform count(*) from public.tasks;
  perform count(*) from public.profiles;
  if exists (
    select 1 from public.tasks
    where start_date is not null
      and due_date is not null
      and due_date < start_date
  ) then
    raise exception 'Restored task dates are invalid';
  end if;
end;
$verify$;
SQL

echo "Disposable database restore drill passed."
