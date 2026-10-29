# Connected staging checks — 29 October 2026

The user explicitly authorized the previously blocked named trial-account login. Sign-in through the staging name selector succeeded and the authenticated homepage was visibly verified. This supersedes the earlier login-authorization blocker; no password was required, read or changed.

Environment: test.atwargroup.com, existing staging database only. Checks below used the authorized trial manager account, not an administrator, and did not grant permissions or switch to another identity. No business form was submitted, record edited or message manually sent. Ordinary application page startup/subscription behavior remains in place; this is not a claim that page loads cause no background writes.

| Area | Actual connected check | Outcome |
|---|---|---|
| Home | Authenticated identity, summary and announcements rendered | passed |
| Tasks | Auth shell, populated list/kanban, Today empty filter, return to original All/kanban view | passed; desktop page has no horizontal overflow |
| Task details | Opened an existing task by its rendered link; inspected then closed details | title loaded; action-history label absent for this non-admin account |
| Workspace | Daily, work tracking, personal notes and management tabs | one selected tab / one visible panel; no horizontal overflow |
| Projects | Authorized empty state | explicit empty message, no failure |
| Policies | Account-scoped empty state | explicit empty message; no policy cycle was exercised |
| Recruitment | Dashboard, requisitions, candidates, interviews and reports | loaded; no visible error alerts or horizontal overflow |
| IT support | Active requests, list/kanban and completed requests | loaded; overdue/target-date indicators visible; no edits |
| Employee directory | Account-scoped directory | loaded, no visible error alert or horizontal overflow |
| Job library | Job descriptions, My reviews, employee-change tabs and own job-description detail | loaded; no visible error alert or horizontal overflow |
| Notifications | Initial read and settled list without opening records | initial loading with empty state hidden, followed by rows and no loading state |
| Access denial | Direct fleet URL using the same account | redirected to home.html?access=denied with explicit unavailable-module message; no permissions changed |

Two presentation defects were observed: home Gregorian/Hijri date digits and recruitment date/time digits used Arabic numerals. Added numberingSystem=latn without changing their existing locale/calendar, stored values, salaries or approval logic. Changes are mirrored by focused patches to the existing staging source; recruitment module cache reference is refreshed.

Measurement limits: the browser-control read-only evaluation surface does not expose performance.getEntriesByType. The attempted read returned an unavailable-API error before navigation; no navigation timing/CLS values were collected. These observations therefore do not satisfy ten comparable cold/warm readiness samples or CLS acceptance. Previously recorded HTTP samples remain static transport measurements only. Android coverage remains viewport emulation in isolated CI, not a physical Android device. Connected checks cover the one authorized role and the states shown above; no full cross-role or live write-cycle acceptance is claimed.

Continue with affected-code regression gates and staging publication/visible verification of the digit correction. Keep production unchanged until the remaining measured-performance, role/workflow and rollback requirements are satisfied. Preserve concurrent staging-only recruitment and IT work.
