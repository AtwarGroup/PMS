# Recovery verification checkpoint — 30 October 2026 (Saudi Arabia)

## Authorization and scope
The user authorized restoring on the existing staging project eeaedzisysjarwvolbwq, preserving ongoing recruitment/IT development, with no production writes, real test messages, new paid resources, or changes to approvals/salaries. The user separately authorized resetting only the staging database password; the user completed credential entry and updated GitHub Secrets. Password values were never read or recorded by this work.

## Completed evidence
- Staging checkpoint: Actions run 40967652174, attempt 3, succeeded. Encrypted archive ATWAR_STAGING_2026-10-29T22-53-03Z.tar.gz.gpg was uploaded to the existing Drive destination's Staging Checkpoints subfolder.
- That archive includes database.dump, password-free role inventory, 9 storage buckets and 109 objects, all 109 checked with SHA-256 (manifest v2).
- Remote readback/decryption/checksum verification: run 40970741655 succeeded for both the staging checkpoint and production archive ATWAR_ONE_2026-10-23T01-17-02Z.tar.gz.gpg. The older production archive has 4 buckets/73 objects, with no independent per-object hashes.
- Actual isolated restores: run 40971037837 succeeded for both database archives, in temporary supabase/postgres:17.6.1.136 containers with network disabled and cron jobs disabled. Production archive: 424 tasks/79 profiles; staging: 425 tasks/89 profiles; no public tables without RLS in either restored database.
- These container tests are not restores of the hosted staging environment and do not verify Storage upload/download against the hosted service.

## Hosted rollback-only rehearsal
- Run 40971391495 stopped safely because storage policies depend on public.task_batch_attachments. Five cross-schema storage policies depend on application tables. No CASCADE deletion was used.
- Run 40972132067 restored application schemas within a transaction but stopped when recreating captured storage policies with an empty search_path (relation projects did not resolve).
- Both failed attempts disconnected without COMMIT and rolled back. After the second: 425 tasks, 89 profiles, 137 application tables, 109 storage objects, 1 active cron job, no public table without RLS.
- Security fingerprints before/after the second attempt matched: policies 4730eb06791b864d38a31dad2232384d; routine names/execution ACLs 6286ab0b523db5a65732a01d74366e00.
- The captured storage policies are recreated in their original form; no blanket policy relaxation is intended. Third attempt run 40973875603 sets an explicit name-resolution context before policy recreation. Its final result is pending at this checkpoint.
- Hosted rehearsal restores only public/private/migration inside a transaction ending ROLLBACK. Auth, managed schemas and Storage bytes are not permanently replaced. This is not a completed full production-to-staging restore.

## Backup permission defect and correction
Raw database dumps used --no-privileges, omitting GRANT/REVOKE statements. Table RLS checks alone cannot establish restored RPC authorization. This limitation applies to existing archives and is not repaired retroactively.
PR 184 removed that option while keeping --no-owner, schedule, destination, encryption and retention. Local restore contract/execution guards and premerge quality/assets checks passed; merged main is 23aa58989848c9c68c56c5560f9360b57a92a909. Postmerge assets and Pages succeeded; postmerge quality was pending at this checkpoint.
Fresh production backup run 40973928636 is in progress. It reads production only. A subsequent isolated verification branch quality/fresh-restore-verification-20261030 requires a fresh manifest-v2 archive and fails if restored public SECURITY DEFINER functions are executable by anon. Live production baseline: 46 such functions, zero executable by anon.

## Important boundaries / resume
No permanent hosted restore has been committed. Do not launch the original restore-drill.sh against the shared staging project: its unmanaged full clean restore lacks the preservation/maintenance/rollback protections required for this environment.
The source.tar.gz in these archive jobs is the tooling repository checkout, not a complete export of the deployed staging Worker, platform configuration, Edge Functions or provider secrets. Current staging source remains version 41 / bade46b13e30e69afa052e70d9a6a7a0019f08f1.
Resume by checking the named running jobs, verifying rollback and security fingerprints, and recording final evidence. A full hosted restore still needs preservation of current ACLs/configuration, a fresh staging checkpoint, suppression of all write channels and external deliveries, tested return to staging-specific state, and application/Storage acceptance. Do not claim a 10/10 or complete platform disaster recovery from these database tests.
Authorized window ends 31 October 2026 22:00 Saudi time; leave rollback time.
