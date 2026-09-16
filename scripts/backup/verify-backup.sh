#!/usr/bin/env bash
set -Eeuo pipefail

backup_dir="${1:?Backup directory is required}"
required=(database.dump roles.sql storage/storage-manifest.json source.tar.gz backup-info.txt)
for file in "${required[@]}"; do
  test -s "$backup_dir/$file" || { echo "Missing or empty backup component: $file" >&2; exit 1; }
done

pg_restore --list "$backup_dir/database.dump" >/dev/null
node -e "const fs=require('fs');const p=process.argv[1];const m=JSON.parse(fs.readFileSync(p));if(!Array.isArray(m.buckets))process.exit(1)" "$backup_dir/storage/storage-manifest.json"
(cd "$backup_dir" && sha256sum database.dump roles.sql storage/storage-manifest.json source.tar.gz > manifest.sha256)
echo "Backup verification passed."
