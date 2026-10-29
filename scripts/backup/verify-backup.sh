#!/usr/bin/env bash
set -Eeuo pipefail

backup_dir="${1:?Backup directory is required}"
required=(database.dump roles.sql storage/storage-manifest.json source.tar.gz backup-info.txt)
for file in "${required[@]}"; do
  test -s "$backup_dir/$file" || { echo "Missing or empty backup component: $file" >&2; exit 1; }
done

docker run --rm --volume "$backup_dir:/backup:ro" postgres:17.6 pg_restore --list /backup/database.dump >/dev/null
node scripts/backup/verify-storage-backup.mjs "$backup_dir/storage"
(cd "$backup_dir" && sha256sum database.dump roles.sql storage/storage-manifest.json source.tar.gz > manifest.sha256)
echo "Backup verification passed."
