# Hosted database workflow acceptance — 30 October 2026
Target: staging only, project eeaedzisysjarwvolbwq. Frontend reference v43 / 4b67154f5021998cf23e85fda8d85fb2931c98d9. No new deployment was required in this test-only follow-up.

## Executed and passed
1. Isolated recruitment database, policy, release and email suites: `npm run test:recruitment:db && npm run test:recruitment:release`, exit 0. Includes approved finance -> personnel -> CEO order, independent roles, exceptions, interviews, offers, portal and hiring.
2. Actual current hosted staging normal recruitment lifecycle, using synthetic actors and cloned synthetic request in BEGIN/ROLLBACK: department/finance/personnel/CEO approvals, required explicit confirmations, wrong-owner/self-approval denial, manager assessment, second interview, recruiter selection denial, restricted salary visibility, offer terms, HR/department/CEO review, portal acceptance, joining prerequisites, synthetic hiring and closure.
3. Actual hosted staging exception lifecycle: finance rejection -> CEO exception -> personnel; personnel rejection -> development exception -> CEO; offer HR rejection -> development -> department -> CEO; through synthetic hiring and closure.
4. Actual hosted staging final-offer rejection: returns for revision and recruiter sending is blocked.
5. Actual hosted staging IT support lifecycle: ordinary request skips approval; P1 due in four elapsed hours; requester cannot write internal notes; outsider read/action denied; operator processing, stale-revision rejection, internal note filtering, employee reply resumes processing, vendor wait, minimum solution length, requester-only closure/rating, reopening resets resolution/rating; procurement approval required and its SLA begins only after approval; purchase rejection and requester cancellation; admin retains audit while nonadmin sees none; MIME/size validation and unuploaded-file finalization denial, pending-file abort.
6. Actual PostgreSQL roles: authenticated could not SELECT five private tables (support tickets/messages, recruitment candidates/outbox, compensation); anon could not call internal support/recruitment creation RPCs.

## Isolation and final state
Checked application triggers for net/http/dblink candidates before hosted testing; none found. Recruitment tables had clock triggers only. No Edge Function or mail-provider call was made. Email claim/finalize exercised synthetic database queue records inside an uncommitted transaction; this does not assert an actual provider delivery.
Every hosted mutation transaction ended ROLLBACK. Internal notifications were never committed and thus unavailable to normal external delivery workers.
Independent final query: support requests 3, support file metadata 2 (both match baseline); QA support rows 0; synthetic candidates 0; synthetic hires 0; synthetic-provider outbox rows 0; open idle test transactions 0.
Sequences can advance despite rollback; never reset shared sequences to hide test-number gaps.
No production DB or deployment changes, no permanent changes to permissions/settings/approval transitions/salaries/passwords, no purchases, no external test messages.

## Limits and resume
Hosted lifecycle tests call current public RPC functions under simulated JWT claims from the privileged test session; business authorization assertions are exercised, but they are not a browser/REST replay of every role. Actual SQL-role denial tests above separately cover the five raw-table and two anonymous-RPC cases.
IT tests cover metadata validation, not a fresh camera/file-byte upload. Prior hosted Storage roundtrip results remain separate evidence.
Physical Android full workflows and remaining authenticated browser acceptance across modules are still open. v43 fixes remain staging only; no full system 10/10 or unrestricted production release is claimed.
Reproducible rollback scripts are preserved beside this report. They are for the named staging environment only, and must not be scheduled or pointed at production.
