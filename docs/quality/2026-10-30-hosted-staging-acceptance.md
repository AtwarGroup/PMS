# Hosted staging acceptance and fixes — 30 October 2026
## Verified on the actual hosted staging site
At https://test.atwargroup.com, signed in using the existing name-only test-account flow.
- IT specialist account: home, support active list, detail, Kanban, overdue badge, completed archive and new-request form opened. Only procurement was labelled as requiring approval. No request was saved and no existing request action was submitted.
- IT specialist direct entry to recruitment redirected to home?access=denied and displayed the module access-denied message.
- Personnel account: recruitment dashboard and existing open request detail loaded, without administrator action history. Account switching returned to login and then showed the new account.
- Personnel account support archive showed zero records, while specialist archive showed two. This demonstrates these two observed scopes; it is not a proof of all role permutations.

## Fixes published only to staging
v42 source 6e039c12c4fa592d3281f3f6a132fb8473ea44d1, deployment appgdep_6ae44626d5f88191b6825472b0e1f1bb succeeded.
Support archive used document.querySelector('h1'), modifying the injected sidebar brand. Scoped selector to page heading and bumped the module cache version. Verified actual headings: ATWAR ONE / طلبات الدعم المكتملة والمنتهية.

v43 source 4b67154f5021998cf23e85fda8d85fb2931c98d9, deployment appgdep_6ae4479f18588191a233c96b28f2781f succeeded.
Existing database function inspection confirmed approved department -> finance -> personnel -> CEO transitions, but frontend progress omitted finance, labelled personnel as recruiter, omitted budget/need/vacancy confirmations, and offer reviewer controls omitted department review and used recruiter permission for personnel.
Updated frontend presentation and confirmation payloads to match the existing backend:
- Finance confirmation budget_checked; five explicit personnel confirmations need_checked, vacancy_checked, request_type_checked, saudization_checked, profession_checked.
- Correct progress order and exception positions, personnel/finance labels and assigned actor fields.
- Offer reviewer controls use personnel permission and assigned personnel, requesting department, development or CEO actor; preparer cannot approve their own offer.
- Versioned imports avoid stale frontend modules.
No database schema, approval transitions, salary data, password, role grants or historical assignments were changed.

## Validation
node --check recruitment-page.mjs; tests/recruitment-approval-ui.mjs; npm run build; npm run validate all passed.
Regression test executes the actual requestAction handler with test doubles, verifies required checkboxes and true boolean RPC payloads, rejects implicit confirmations, and tests reviewer scope/self-approval denial and stage positions.
Post-publication browser verified current finance/personnel progress and finance actor field in the existing request. Archive brand fix verified independently. These are observed UI reads, not a complete committed recruitment cycle.
Source backup branch backup/before-recruitment-ui-20261030 preserves v42. v41/v42 remain saved rollback versions. Existing concurrent IT/recruitment source was fetched before both edits.

## Remaining acceptance / resume
No existing hiring request, candidate decision, salary, approval or support record was altered. No outbound test email/message or production deployment occurred. Test-account login may create ordinary authentication sessions.
The existing old request retains its historical personnel assignment; no reassignment was performed. Do not silently rewrite historical assignments.
Next: isolated synthetic current-schema request/offer lifecycle tests with outbound delivery blocked; hosted field validation for pending finance/personnel fixtures; remaining module/role acceptance and physical Android. Full system 10/10 and production readiness are not yet claimed.
