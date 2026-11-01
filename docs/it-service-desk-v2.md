# IT service desk v2 — staging release

Target: `https://test.atwargroup.com`, Supabase `eeaedzisysjarwvolbwq`. Production is outside this release.

## Behavior

Support uses one description and a single conversation with an inline reply composer. Each reply links its own private files; system state changes appear in the thread. The five categories are network, devices/printers/attendance, Odoo, office software, and suggestions. Priority is explicit: normal P4 (5 workdays), medium P3 (2 workdays), high P2 (8 working hours), emergency P1 (4 elapsed hours and work-stopped confirmation).

An employee can have three non-emergency and two emergency support requests. Resolved requests remain open until the beneficiary confirms closure and rates the service. Suggestions and purchases are excluded. Operator-owned support requests require supervisor confirmation. Quotas are checked on creation, reopening closed requests, and reprioritization under ordered profile row locks. Creation accepts an idempotency token. Stale revisions are rejected.

Waiting for employee information pauses SLA; a public employee reply resumes processing. Escalation records the recipient and reason and does not pause SLA. Existing waiting records begin their pause at rollout, without inventing historical pause periods.

Purchases have their own page and workflow: quote provider -> technical review -> independent direct manager -> supply -> employee receipt -> supplier payment. Payment routing is operator -> business development supervisor -> chief accountant -> assigned accountant. Reference and private proof are required to record payment. Supplier reference must be verified by the chief. A documented full or partial advance uses the same approvals before supply. Receipt shortages block the balance. The purchase closes only after complete receipt, invoice and full recorded payment. This records approvals and evidence; it does not initiate a bank transfer.

Configuration and role grants remain in users and permissions. Akram Youssef is the staging chief. Existing staging finance users Hussam Shibl and Mohammad Al-Aliyani can receive assignments; their previous permissions are preserved.

## Verification

Run `npm ci --ignore-scripts` and `node scripts/test-it-v2.mjs` in the PMS feature branch. The suite builds an isolated PostgreSQL-compatible PGlite fixture with prior migrations and the complete new migration. It exercises quotas, resolved closure, emergency caps, suggestion/purchase exclusions, SLA pause/resume, calendar, normal purchase, partial advance, receipt shortage, invoice-driven balance, supplier verification, assignment, proof, automatic closure, authorization, attachment isolation, internal-note visibility, revision rejection, and creation idempotency.

On staging, an authenticated-role transaction verified create/resolve/independent close and purchase routing, then rolled back. Existing three requests were preserved; no test purchase remains. Public RPC wrappers are invoker-only and anonymous execution is revoked. Security advisor returned no IT module findings. Foreign-key indexes cover the new tables and owner settings. Unused new indexes are expected before trial traffic.

Worker build and artifact validation passed. Browser interaction remains unverified: the managed preview refuses this Worker-only project because it has no dev script or static.directory. No alternative preview server or sign-in bypass was used.

## Operational limits

A quote replacement before financial requests invalidates approval and restarts review. Once a financial request exists, quote replacement is blocked with an accounting-resolution message. Reversals, refunds, and changing supplier/value after a financial request are not implemented in this release. No historical purchase existed at rollout. Changes to staff hierarchy and revocation of access during a running purchase require an administrator to review routing; request snapshots retain the approved actors.

Database release was applied as sequential named staging migrations (schema, calendar, support commands, purchase commands, API/files, indexes and independent finance routing), with client execution revoked on internal helpers between steps. The single source migration is the equivalent fresh-install schema. Do not apply the single migration again to this staging database.

## Role-based presentation correction

System-owned role labels use IT department, business development supervisor, chief accountant and assigned accountant. Human names remain only in actual user attribution and selection. Legacy generated messages are displayed with role labels without rewriting the audit. Metrics reuse the fleet tones and card structure. Support, purchase and payment journeys reuse fleet journey CSS, show the current role and next action, and wrap on mobile. Presentation tests cover every supported phase, including waiting, shortage, cancellation and rejection. Native migration corrected future generated payment messages. Managed browser preview remains unavailable for the Worker-only project; build and presentation tests passed.

## Seven-day archive correction

Metrics contain label and count only, without links or embedded controls. Closed support and purchase requests remain in the main list and the completed filter for exactly seven elapsed days after closing, then appear in Archive. Pending beneficiary confirmation is still open. Cancelled/rejected requests follow the fleet's immediate archive behavior. The closed record's updated_at is stable because terminal comments are prohibited, and purchase closure sets updated_at at completion. There is no data deletion or new scheduled task. Both list and kanban retain recent completions. Boundary tests cover immediately before and at seven days.

## Unified support action composer

Support actions are one native dropdown within one reply form. The same textarea is used for reply, processing notes, information requests, escalation, solution, priority reason, closure and reopening. Escalation shows its destination input; priority and rating appear only for their actions. Options preserve existing role/state permissions. Comment attachments and internal notes are conditional; selected attachments are never silently dropped when switching actions. The composer is in normal document flow to avoid covering the action form on mobile. Purchase business commands remain unchanged. Presentation tests verify role choices, escalation, one textarea and submit button, closed/reopened states, and normal-flow CSS.

## Solution reminders and supervisor summary

Solution submission creates one in-app notice for the beneficiary who can confirm closure; an operator-owned request routes confirmation to the supervisor. The notice opens the exact request through an authorized RPC and is marked read. The first reminder is due after 24 hours, subsequent reminders at least 48 hours apart, checked hourly by the project-local `it-support-solution-reminders` pg_cron job. Notices are deduplicated per resolution cycle and recipient. Closing, cancelling or reopening stops that cycle. Inactive recipients are skipped. No email is sent and no automatic closure is introduced.

The supervisor summary appears within the support page for `it_support.supervise` or administrators. Counts cover all support requests (purchase excluded), and show overdue, escalated, waiting for information and awaiting confirmation. Mean resolution time covers current resolutions in the last 30 days in elapsed hours minus employee-information pauses. Ratings use closed requests rated in the last 30 days. Null samples display a dash and sample counts are shown. The queue shows at most 20 attention requests ordered by priority then age. No links are embedded in metric cards.

Native staging migrations are mirrored using their actual server-generated versions: 20261101004614, 20261101004618 and 20261101004622. Run `node scripts/test-it-followup.mjs` in the PMS branch for PostgreSQL fixture tests; run the presentation tests for the HTML. A live authenticated rollback transaction verified notice creation, independent recipient, request opening, summary and closure without retaining a test ticket or notice. The cron job is enabled. Security advisor returned no IT findings. Browser interaction remains unverified because the managed Worker preview is unavailable.

The follow-up notification regression is covered by migration 20261101004932: replies made after resolution still send their own generic update notice, while the initial solution notification remains once per cycle. Its database test verifies both notices and prevents silent loss of a resolved-thread reply.

## Production release — 2026-11-01

IT-only source was integrated onto the current production main without importing staging configuration or unrelated theme changes. New request submission closes the dialog after successful record creation and all attachments; failures keep the form available for retry without duplicating the request. List-refresh failure after saving still reports success.

Production schema was installed in 16 checked native migrations (`it_live_release_01` through `it_live_release_16`) while the module remained hidden. Original source migration versions were recorded after the complete schema was applied, preserving future migration tracking. Existing permissions were preserved; 75 active employee-linked profiles received request access. The specialist, supervisor, chief and two accountants use the approved role grants. No staging users or sample requests were copied. Production smoke tests were rolled back. The module is activated only after the reviewed frontend is published.
