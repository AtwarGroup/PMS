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
  pg_restore --dbname="$drill_url" --exit-on-error --clean --if-exists --no-owner --no-privileges \
  /backup/database.dump

docker run --rm -i postgres:17.6 psql "$drill_url" -v ON_ERROR_STOP=1 <<'SQL'
DO $verify$
BEGIN
  IF to_regclass('public.tasks') IS NULL OR to_regclass('public.profiles') IS NULL THEN
    RAISE EXCEPTION 'Restored database is missing tasks or profiles';
  END IF;
  PERFORM count(*) FROM public.tasks;
  PERFORM count(*) FROM public.profiles;
  IF EXISTS (
    SELECT 1 FROM public.tasks
    WHERE start_date IS NOT NULL AND due_date IS NOT NULL AND due_date < start_date
  ) THEN
    RAISE EXCEPTION 'Restored tasks contain invalid date ranges';
  END IF;
END
$verify$;
SQL

echo "Disposable database restore drill passed."
