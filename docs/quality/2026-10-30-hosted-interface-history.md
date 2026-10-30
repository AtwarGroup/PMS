# Hosted interface and history acceptance — 30 October 2026

## Actual hosted browser checks
At https://test.atwargroup.com, using approved name-only accounts:
- Personnel/manager account: tasks loaded, task detail opened, protected task dates disabled, detail closed without save.
- Workspace Daily, Tracking and Personal Notes tabs loaded; personal notes were not edited or saved.
- Projects showed an explicit permission-scoped empty state for this account.
- Policies showed an explicit empty state for both tested manager accounts. Privileged inventory found two policies/two versions and two projects/two memberships; no records or memberships were added to make the browser test pass.
- Supervisory manager: employee directory displayed seven allowed records, organizational hierarchy tab selected, own employee detail opened with organizational fields disabled; no HR field was changed.
- Job library loaded four available job cards. Own job description opened; responsibilities, authority matrix and performance indicator tabs rendered. No employee acknowledgement or change proposal was submitted.
- Account switch through logout/login verified distinct account identity.

## Observed staging drift and bounded fixes
v44: source b364f3ceb2a946380b637b605f9f35a60d0f77f3, deployment appgdep_6ae46edb7e548191a8c6b125ae4bda47 succeeded.
Staging tasks still rendered the activity-history section for nonadmin users. Ported the existing main-reference render/toggle guard, cleared residual content, default-hid the HTML section and bumped the module URL. Regression covers admin rendering and nonadmin clearing/toggle denial. Hosted browser after deploy: detail visible true; history visible false; history content empty.

v45: source cc0108f3e36b6b47c391b98e9dd2f35dfdc4cbe5, deployment appgdep_6ae470d0ebdc819190fbb8ad48c1066e succeeded.
Employee detail and project source differed from main only in the relevant administrator-history guards; ported those guards. Policy source has separate design changes, so only patched its history fetch/render condition rather than replacing the file. Versioned all three entry modules.
Hosted post-deployment employee check: normal detail visible, history heading count zero. Project/policy detailed-history UI could not be reached through these accounts' empty lists; those two guards are source-verified, not claimed as live detail-browser passes.
Existing recruitment/IT changes and current Site audience preserved. No role/approval/schema/salary/password change and no production deployment.

## Validation and database evidence
Syntax checks of changed modules, task-history regression, recruitment-approval regression, build and artifact validation all passed.
Using actual PostgreSQL SET LOCAL ROLE authenticated, seven pre-existing synthetic nonadmin actor claims across eight public action-history tables returned zero visible rows in 56 combinations. Synthetic admin recognized by private.is_admin(). Transaction rolled back.
Catalog independently confirms all eight tables have RESTRICTIVE admin_only_action_history SELECT policies for authenticated using private.is_admin(). A zero-row observation alone would not prove a policy; the catalog confirmation is recorded separately.

## Limits / resume
The 13 approved name-only browser accounts contain eight manager roles and five employee roles, no administrator. No name or role grant was added to bypass this limitation. Actual administrator UI acceptance is still open; programmatic admin-render regression and database admin recognition are narrower evidence.
Full physical Android workflows remain open. Prior fleet browser viewport simulation and the user's successful drawer check are separate evidence and do not certify all Android workflows.
Remaining priorities: administrator browser acceptance through an authorized existing sign-in path; representative project/policy details with already authorized membership; remaining error/slow-network/keyboard/device acceptance. No claim of complete remediation or 10/10.
All browser actions in this follow-up were navigation/read-only except ordinary test-account authentication; no business record saves or outbound test messages. No background test job remains.
