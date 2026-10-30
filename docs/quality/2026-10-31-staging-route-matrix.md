# Staging route verification matrix — 2026-10-31 (Saudi)

## Outcome and scope
Inventory: 57 HTML source paths. On published staging v48, all 55 paths other than the two owner-protected entry pages returned HTTP 200 after bounded serial retries. No unresolved transport timeout or HTTP 404 remains among those 55.
Anonymous owner-page checks behaved as designed: admin-access.html=302 and trial-admin.html=404. Both owner pages rendered in the authenticated owner browser.
This certifies HTTP reachability and the observed browser outcomes below. HTTP 200 alone does not certify authenticated data, every control, every role or a complete business workflow.
Earlier parallel timeouts were transport observations; bounded sequential requests resolved them. No site failure is inferred from those timeouts.

Published source: 20a5455506391cf1348e512395b554c11e35427d, Sites v48.
Deployment appgdep_6ae51ab050b48191accbb3c95b44ffce.
Origin https://atwar-one-staging.mbasunbol.chatgpt.site
No source or production changes were made in this route-verification continuation.

## Browser checks in this continuation
Authoring, valid job-review detail, settings, requests redirect, proposals, public careers, personal description empty state, security page, four form templates, two lab previews, privacy, owner entry pages and public entry points were observed.
Verified canonical redirects for organizational hierarchy, team directory, employee no-ID, today, approvals, completed and follow-up.
Waited for specific loading states when verifying data readiness. Initial shell observations alone are not promoted to functional pass.
Account-specific denials and missing-record/token messages are expected guard outcomes. No authorization was broadened to make a page pass.
Tasks approval data: 36 cards; completed: 204 cards. Public name list: 13. No task/offer/job approval or business form was submitted.
Prior administrator, non-admin and rollback-only workflow coverage remains in the preceding dated quality reports.

## Path matrix
HTTP column is the direct anonymous HTTP response, without following redirects.
For owner-protected pages, a non-200 is the expected access guard.

| Source path | HTTP | Browser evidence / limit |
|---|---:|---|
| `admin-access.html` | 302 | Anonymous 302 to platform sign-in; owner page renders. |
| `admin/announcements.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `admin/employees.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `admin/forms.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `admin/index.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `admin/maintenance.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `admin/templates/job-review.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `admin/templates/kpi-measurement.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `admin/templates/periodic-report.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `admin/templates/task-handover.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `admin/users.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `approvals/index.html` | 200 | Redirect verified: tasks scope=APPROVAL; 36 cards loaded. |
| `attachments/index.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `communication-trial/index.html` | 200 | Separate trial interface explicitly denies current account; no permission expansion. |
| `communication/index.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `completed/index.html` | 200 | Redirect verified: tasks scope=COMPLETED; 204 cards loaded. |
| `fleet/completed.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `fleet/index.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `fleet/user-guide.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `follow-up/index.html` | 200 | Redirect verified to workspace/index.html. |
| `home.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `index.html` | 200 | Browser redirects to landing.html. |
| `it-support/index.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `job-library/create.html` | 200 | Draft authoring form rendered; no save. |
| `job-library/employee-changes.html` | 200 | Redirect verified: library requests view. |
| `job-library/index.html` | 200 | 58 job cards loaded for administrator. |
| `job-library/review.html` | 200 | Missing ID gives clear error; existing library card opened valid review detail. |
| `job-library/settings.html` | 200 | Workflow settings rendered; no change. |
| `lab/job-authoring-preview.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `lab/job-lifecycle-preview.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `landing.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `login.html` | 200 | Trial-name entry shell; no account switching submitted. |
| `my-day/index.html` | 200 | Redirect verified: tasks scope=TODAY&owner=me; owner filter applied. |
| `notifications/index.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `organization/index.html` | 200 | v48 fix verified: admin/employees.html#hierarchy; 147 employee controls. |
| `policies/index.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `privacy.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `profile/index.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `profile/job-description.html` | 200 | Valid empty state: no published description for current account. |
| `profile/measurements.html` | 200 | Measurement history loaded; valid zero-results state. |
| `profile/security.html` | 200 | Security page rendered only; no credential entered or changed. |
| `projects/index.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `recruitment/candidate.html` | 200 | Missing/invalid token rejected with renewal guidance; no real offer response. |
| `recruitment/careers.html` | 200 | Public careers page finished loading; no application submitted. |
| `recruitment/index.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `recurring/index.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `search/index.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `staging-start.html` | 200 | Trial-name entry shell; same Worker login alias. |
| `tasks/executive.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `tasks/index.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `tasks/user-guide.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |
| `team/employee.html` | 200 | No-ID route redirects to employee directory. |
| `team/index.html` | 200 | Redirect verified to employee directory. |
| `trial-admin.html` | 404 | Anonymous 404; owner page renders. No invite issued. |
| `trial-login.html` | 200 | Names loaded: 13; no administrator added to public list. |
| `workspace/improvements.html` | 200 | Proposals finished loading; no proposal submitted. |
| `workspace/index.html` | 200 | HTTP shell confirmed; representative hosted UI evidence is in the prior acceptance reports. |

## Remaining broader acceptance
Physical Android end-to-end and every route/control/role combination remain outside this completed route-reachability check. Production rollout gates remain separate.
No real test email/message, credential update, salary edit, approval-flow change, new cost or production database write.
All HTTP checker processes finished. No background check remains. Restart at the retained administrator task approvals page.
