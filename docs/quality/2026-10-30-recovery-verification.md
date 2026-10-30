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
Database archive restore and hosted staging application-schema rollback rehearsal passed. Staging data and authorization returned to the verified baseline; production data/schema were not written. No external test messages were sent and no paid project/branch was created. Full platform disaster recovery, a permanent production-to-staging replacement, platform configuration/Edge Function redeployment and application acceptance of a permanently restored environment remain unperformed. Hosted Storage upload/download restoration is now verified in private temporary buckets (see follow-up below). The initial staging archive omitted grants; a new permissions-preserving staging checkpoint is now available and verified as described below. No 10/10 certification is claimed.

## Follow-up completion — 30 October 2026, 03:27 Saudi time

### New staging rollback archive
Run 40975987786 succeeded and stored ATWAR_STAGING_ACL_2026-10-29T23-52-24Z.tar.gz.gpg in the existing encrypted staging checkpoint destination. It retains database object permissions and includes 9 buckets/109 checksummed objects. This supersedes the earlier grant-free staging archive for future restore preparation.

### Actual hosted attachment restoration
Run 40977968971 succeeded:
- Production archive: 76 objects / 25,013,636 bytes uploaded to a new private temporary staging bucket, downloaded again, checked against manifest SHA-256, byte sizes and MIME types.
- Staging archive: 109 objects / 31,683,788 bytes passed the same checks.
- SQL checks with anon and authenticated roles returned zero visible restored objects while the temporary buckets were populated.
- All temporary objects and buckets were removed; final independent verification found 9 original buckets, 109 original objects and 31,683,788 original bytes, with zero test buckets/objects. Original paths and ownership were not overwritten.
- First run 40976623851 reached successful production object verification but bucket deletion returned HTTP 400 immediately after emptying. Scoped cleanup run 40977758784 removed only that confirmed empty private bucket. A bounded cleanup retry was added and covered by offline tests; the full repeated run then passed.
- Tests cover fixed staging target, rejection of corrupt archives before API writes, existing-bucket protection, cleanup after download corruption/access-check failure, delayed deletion and private visibility. Test code is on branch quality/hosted-storage-restore-20261030 at b36cda1a450a7ffd96d30abfc9dd9b1a1eddf2c2.

### Permission-preserving database recovery
Run 40979645895 succeeded for both current archives in isolated network-disabled Supabase containers:
- Production: 435 tasks / 79 profiles; staging: 425 tasks / 89 profiles; no public tables without RLS.
- A canonical hash of function identity, SECURITY DEFINER status and effective EXECUTE access for anon/authenticated/service_role across public/private/migration matched the live source baseline in each project.
- Source/restore hashes: production ff547fda0548505210490ad66f9ab0fd; staging afb2f3e31fd071c8572f5e813040ef1e.
- Production's 46 public SECURITY DEFINER routines retained zero anonymous execution grants.
- Two preliminary runs did not reach this comparison because of isolated database startup/readiness checks. Stable successful SQL readiness replaced a process-name assumption. Only the final passing run is used as comparison evidence.
- This is an effective routine-grant comparison, not proof of correctness of every routine's business authorization logic, every table/column grant or all application workflows.

### Backend source preservation
Exported all 12 staging Edge Functions (14 source files) with deployment versions, verify_jwt metadata and per-file SHA-256 into Atwar_Staging_Edge_Functions_20261030.zip. Archive structure and ZIP integrity were verified. The saved private file is libfile_b4c344337b608191b4ab77078d411b3b. A second deployment inventory check found no source/config metadata differences in the 12 functions. No Edge Function was redeployed and secret values were not exported.

### Final hosted staging state
425 tasks; 89 profiles; 137 application tables; 9 storage buckets; 109 objects; 1 active pre-existing cron job; no public table without RLS. Original policy and routine-ACL fingerprints still match the recorded pre-test values. No production database/schema writes or external test messages were performed.

### Exact remaining limits
No permanent production-to-staging replacement has been committed. A full reconstruction of a blank Supabase project, restoration of Auth/SMTP/provider secret settings, Edge Function redeployment, and full authenticated browser/physical Android workflow acceptance were not performed. The hosted login page was inspected, but no new account login was completed in this follow-up. Existing platform settings were kept in place.
Some legacy staging test SQL expects an older recruitment approval route (test-recruitment-release.sql asserts a direct approval transition); it was inspected but not executed as acceptance for the currently approved workflow. Do not change approved business cycles merely to satisfy outdated tests.
Recovery proof now covers database archives, hosted rollback-only application-schema restoration, hosted attachment byte/MIME/privacy roundtrips, source preservation and routine-grant comparison. It does not establish 10/10 system-wide acceptance or a complete platform disaster-recovery SLA.
