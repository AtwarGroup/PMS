# Application route acceptance matrix — 29 October 2026

51 application routes: 45 content pages and six legacy redirects. The 47-page content CI total includes two additional lab previews; it must not be presented as 47 application pages. All 45 application content pages are included in that successful static desktop/mobile pass. The six redirects are now explicitly covered by a required isolated browser gate using the actual redirect documents and synthetic destination pages.

This matrix distinguishes layout coverage from functional and connected coverage. A static pass is not a claim that every dynamic workflow/state of that route ran live. Functional families use the actual application scripts and isolated PostgreSQL/synthetic transport, with external delivery blocked; connected checks are limited to the single authorized manager identity. No unavailable role is marked as a successful connected test. Final GitHub gate results for the released head are authoritative for the added redirect test.

| Application route | Layout/redirect evidence | Functional evidence family | Connected evidence |
|---|---|---|---|
| `admin/announcements.html` | desktop/mobile content gate passed (40916925405) | read-state browser suite | not connected under this role; isolated/source evidence only |
| `admin/employees.html` | desktop/mobile content gate passed (40916925405) | employee/account suite | authorized manager read-only check |
| `admin/forms.html` | desktop/mobile content gate passed (40916925405) | read-state browser suite | not connected under this role; isolated/source evidence only |
| `admin/index.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `admin/maintenance.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `admin/templates/job-review.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `admin/templates/kpi-measurement.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `admin/templates/periodic-report.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `admin/templates/task-handover.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `admin/users.html` | desktop/mobile content gate passed (40916925405) | employee/account suite | not connected under this role; isolated/source evidence only |
| `approvals/index.html` | six-route redirect smoke; required final CI gate | static/source contract only | not connected under this role; isolated/source evidence only |
| `attachments/index.html` | desktop/mobile content gate passed (40916925405) | read-state browser suite | not connected under this role; isolated/source evidence only |
| `communication/index.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `communication-trial/index.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `completed/index.html` | six-route redirect smoke; required final CI gate | static/source contract only | not connected under this role; isolated/source evidence only |
| `fleet/completed.html` | desktop/mobile content gate passed (40916925405) | fleet role/workflow suite | not connected under this role; isolated/source evidence only |
| `fleet/index.html` | desktop/mobile content gate passed (40916925405) | fleet role/workflow suite | manager denied as expected |
| `fleet/user-guide.html` | desktop/mobile content gate passed (40916925405) | fleet role/workflow suite | not connected under this role; isolated/source evidence only |
| `follow-up/index.html` | six-route redirect smoke; required final CI gate | static/source contract only | not connected under this role; isolated/source evidence only |
| `home.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | authorized manager read-only check |
| `index.html` | six-route redirect smoke; required final CI gate | static/source contract only | not connected under this role; isolated/source evidence only |
| `job-library/create.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `job-library/employee-changes.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `job-library/index.html` | desktop/mobile content gate passed (40916925405) | read-state browser suite | authorized manager read-only check |
| `job-library/review.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `job-library/settings.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `landing.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `login.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `my-day/index.html` | six-route redirect smoke; required final CI gate | static/source contract only | not connected under this role; isolated/source evidence only |
| `notifications/index.html` | desktop/mobile content gate passed (40916925405) | read-state browser suite | authorized manager read-only check |
| `organization/index.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `policies/index.html` | desktop/mobile content gate passed (40916925405) | read-state browser suite | authorized manager read-only check |
| `privacy.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `profile/index.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `profile/job-description.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | authorized manager read-only check |
| `profile/measurements.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `profile/security.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `projects/index.html` | desktop/mobile content gate passed (40916925405) | read-state browser suite | authorized manager read-only check |
| `recruitment/candidate.html` | desktop/mobile content gate passed (40916925405) | recruitment workflow/dialog suite | not connected under this role; isolated/source evidence only |
| `recruitment/careers.html` | desktop/mobile content gate passed (40916925405) | recruitment workflow/dialog suite | not connected under this role; isolated/source evidence only |
| `recruitment/index.html` | desktop/mobile content gate passed (40916925405) | recruitment workflow/dialog suite | authorized manager read-only check |
| `recruitment/user-guide.html` | desktop/mobile content gate passed (40916925405) | recruitment workflow/dialog suite | not connected under this role; isolated/source evidence only |
| `recurring/index.html` | desktop/mobile content gate passed (40916925405) | read-state browser suite | not connected under this role; isolated/source evidence only |
| `search/index.html` | desktop/mobile content gate passed (40916925405) | read-state browser suite | not connected under this role; isolated/source evidence only |
| `tasks/executive.html` | desktop/mobile content gate passed (40916925405) | task regressions/workflow suites | not connected under this role; isolated/source evidence only |
| `tasks/index.html` | desktop/mobile content gate passed (40916925405) | task regressions/workflow suites | authorized manager read-only check |
| `tasks/user-guide.html` | desktop/mobile content gate passed (40916925405) | task regressions/workflow suites | not connected under this role; isolated/source evidence only |
| `team/employee.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `team/index.html` | six-route redirect smoke; required final CI gate | static/source contract only | not connected under this role; isolated/source evidence only |
| `workspace/improvements.html` | desktop/mobile content gate passed (40916925405) | static/source contract only | not connected under this role; isolated/source evidence only |
| `workspace/index.html` | desktop/mobile content gate passed (40916925405) | read-state browser suite | authorized manager read-only check |
