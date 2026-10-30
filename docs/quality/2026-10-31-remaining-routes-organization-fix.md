# Remaining routes and legacy organization fix — 2026-10-31 Saudi

## Staging fix deployed and verified
Legacy /organization/index.html remained on its loading screen through repeated browser observations. This page independently fetched the legacy account directory. The current employee-directory hierarchy had already loaded successfully.
The old page now redirects to /admin/employees.html#hierarchy, with a matching noscript-compatible link and meta refresh. This reuses the existing canonical directory, its authorization boundary and approved visual identity; no access grant or data mutation.
Sites source was refreshed before editing; parent 9c5c037783f3b1db2fb40c6cb4dc20b2787333f9 had no concurrent source changes. Only app/organization/index.html changed.
Build and ESM validation passed.
Published staging version 48, source 20a5455506391cf1348e512395b554c11e35427d.
Version ID: appgprj_6adbeb43670c819196d6b09dec5ef91e~appgver_242c6b7cc92481918416c91870df64a0
Deployment: appgdep_6ae51ab050b48191accbb3c95b44ffce, succeeded.
After reloading the actual legacy URL, browser arrived at canonical URL, hierarchy tab selected, 147 employee controls visible, no visible alert.
Rollback: deploy saved staging v47. Production was not modified.

## Additional checks
- Profile job view rendered; measurements history finished loading with a valid zero-results state. No measurement or acknowledgement submitted.
- Attachments loading finished.
- Notifications loading finished with 15 cards; no notification clicked, marked, cleared or sent.
- Search loading finished with its ready-to-search guidance; no sensitive query submitted.
- Task and fleet user guides rendered.
- Pre-change local packaged Worker served all 213 non-protected packaged paths with status 200. This is a local packaging check, not hosted acceptance.
- Hosted bounded HTTP sweep completed: 55 HTML URLs, 25 returned 200, 30 timed out (curl exit 28, no HTTP response). A separate serial privacy request returned 200. No 404 was observed; no pass is claimed for the timed-out requests. Browser successes remain separate evidence.
- Rebuilt package contains 215 assets including the two owner-protected paths.

## Remaining gates
No full all-route/all-role certification or physical Android end-to-end certification. Timed-out HTTP paths remain an incomplete hosted gate.
Recent staging-only IT/recruitment and owner/trial auth are not a production release candidate as a bundle.
No password, salary, approval workflow or production database changes. No real test messages or new paid resources.
Browser is retained at the canonical hierarchy. No HTTP sweep or background job remains.
