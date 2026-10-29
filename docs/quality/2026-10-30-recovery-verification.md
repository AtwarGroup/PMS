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
- The captured storage policies are recreated in their original form; no blanket policy relaxation is intended. Third attempt run 40973875603 sets an explicit name-resolution context before policy recreation. It succeeded: hosted application schema/data restore completed and rolled back at 2026-10-30 02:46:09 Saudi time. Post-checks again matched the original security fingerprints and counts, with zero active restore transactions.
- Hosted rehearsal restores only public/private/migration inside a transaction ending ROLLBACK. Auth, managed schemas and Storage bytes are not permanently replaced. This is not a completed full production-to-staging restore.

## Backup permission defect and correction
Raw database dumps used --no-privileges, omitting GRANT/REVOKE statements. Table RLS checks alone cannot establish restored RPC authorization. This limitation applies to existing archives and is not repaired retroactively.
PR 184 removed that option while keeping --no-owner, schedule, destination, encryption and retention. Local restore contract/execution guards and premerge quality/assets checks passed; merged main is 23aa58989848c9c68c56c5560f9360b57a92a909. Postmerge assets (40973881770), Pages (40973880784), and both quality jobs (40973881790) succeeded.
Fresh production backup run 40973928636 succeeded. It read production only and stored ATWAR_ONE_2026-10-29T23-33-43Z.tar.gz.gpg, including 8 buckets/76 objects, all 76 checksummed with manifest v2, with database grants/revocations retained. Fresh isolated verification run 40974163511 succeeded after remote readback and decryption: 435 tasks, 79 profiles, no public table without RLS, 46 public SECURITY DEFINER functions and zero executable by anon (matching the live production authorization baseline). It also repeated the isolated staging archive restore successfully. These tests do not constitute a complete function-by-function permission audit.

## Important boundaries / resume
No permanent hosted restore has been committed. Do not launch the original restore-drill.sh against the shared staging project: its unmanaged full clean restore lacks the preservation/maintenance/rollback protections required for this environment.
The source.tar.gz in these archive jobs is the tooling repository checkout, not a complete export of the deployed staging Worker, platform configuration, Edge Functions or provider secrets. Current staging source remains version 41 / bade46b13e30e69afa052e70d9a6a7a0019f08f1.
All named backup/verification/rehearsal jobs have completed; no hosted restore transaction remains open. Database recovery and hosted rollback-only application-schema rehearsal have concrete passing evidence. A full hosted restore still needs preservation of current ACLs/configuration, a fresh staging checkpoint, suppression of all write channels and external deliveries, tested return to staging-specific state, and application/Storage acceptance. Do not claim a 10/10 or complete platform disaster recovery from these database tests.
Authorized window ends 31 October 2026 22:00 Saudi time; leave rollback time.

## Final outcome
Database archive restore and hosted staging application-schema rollback rehearsal passed. Staging data and authorization returned to the verified baseline; production data/schema were not written. No external test messages were sent and no paid project/branch was created. Full platform disaster recovery, a permanent production-to-staging replacement, hosted Storage re-upload verification, platform configuration/Edge Function restoration and application acceptance of a permanently restored environment remain unperformed. Existing staging archive grants are still omitted; take a new permissions-preserving staging checkpoint before any future destructive restore. No 10/10 certification is claimed.
