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
