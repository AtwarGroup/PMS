# Account access administration

The employee record is the source for organizational data; an optional Auth/profile link activates login. Account administration does not edit the employee's name, title, department, manager or employment type. Existing system roles (`employee`, `manager`, `admin`) and record relationships remain authoritative. The current administrator role retains its existing full access, including sensitive employee data; additional roles do not replace or narrow this baseline.

## Reusable roles

`private.access_catalog` defines supported permission keys, labels, modules, scopes, operations and manager prerequisites. The role editor and effective-access view render this registry dynamically. A custom role contains permission/scope rules. Accounts can hold multiple roles. Active role grants and existing direct grants are additive. Disabling a role or removing an assignment removes that source; another independent source can still grant the same permission. The UI lists these sources separately. Manager-only task assignment still requires the base manager role.

HR permissions are evaluated per operation by `private.hr_allowed`. Read-all plus write-team must never become write-all. Direct HR grants retain their existing shared scope; use roles for independent read/write scopes. Task permissions are projected into `profiles.permissions` for compatibility with existing clients and RLS. `private.access_direct_tasks` retains independent direct grants so removing a role cannot accidentally revoke them. Existing task and project ownership, reporting, membership and approval rules remain in force.

Role edits use a revision check, and assignment edits compare the expected role IDs. Role/profile row locks serialize projection changes. Direct grant bundles are transactional. The UI blocks duplicate submissions. Only checked administrator RPCs may change roles, assignments and grants; private tables deny raw client access. Newly created accounts capture their initial direct task permissions. Legacy direct-task setters delegate to this same source and rebuild the effective projection.

## Adding a permission or module

1. Define a stable permission key and register its display metadata, valid scopes and prerequisites in a migration.
2. Implement its server-side checks in every applicable API/RLS/write path. A catalog entry alone must never be treated as sufficient enforcement.
3. Connect effective access to the relevant client behavior. Non-HR permissions currently use the existing `profiles.permissions` projection; HR operations use the role-aware evaluator. New authorization models must supply their own checked evaluator.
4. Add client-role SQL tests for allowed and denied operations, scope boundaries, inactive users, role removal, overlapping sources, and invalid inputs.
5. Verify no access changes for unassigned accounts. Registration makes the permission appear in the existing role editor without adding another form.

New roles can be created and assigned through the UI without code changes. New application capabilities require explicit server enforcement and deployment; they are not arbitrary client-defined permission strings.

## Audit and workflow settings

`private.access_audit` records role definitions, assignments, direct grants, account access state and subsequent account creation/password/reset actions. The existing `admin_audit_log` is preserved. Audit history starts when the new mechanism is enabled; prior history is not fabricated. The UI paginates by event ID and shows readable before/after values.

Job stage owners are maintained under `job-library/settings.html`; changing an owner uses the existing checked workflow RPC and preserves its task reassignment behavior. Permission to act and the actual assigned owner remain distinct concepts.

## Validation

Run `node tests/access-model.mjs` and the complete `tests/*.mjs` quality gate. Execute `supabase/tests/scalable_account_roles.sql` and `supabase/tests/employee_master_access.sql` against a database with the named QA accounts. SQL fixtures and grants roll back. Do not assign test roles to production employees, create Auth accounts, send email or request employee approval during regression testing.

## Employee workspace (21 October 2026)

`admin/employees.html` is the single employee workspace. The directory and reporting hierarchy share the same server-authorized `employee_master_list` response, search and filters. Relationships use the existing employee and manager codes, including employees without login accounts. Missing managers are shown as outside the displayed results; no extra profile lookup expands the scope. Legacy `team/index.html` bookmarks redirect here. Published job descriptions and measurement history remain on their existing scoped employee-profile route.

Login activation, account suspension, system roles, reusable scoped roles, direct exceptions and access auditing remain exclusively in `admin/users.html`. The employee page contains only an administrator navigation link to that page. Account summary counts are derived from `access_admin_context` and do not change grants.

This release changes presentation and navigation only. It contains no migration, employee import, account activation, notification, email or job acknowledgement operation. Existing database authorization and record revisions remain authoritative.

Validation: all 116 JavaScript suites pass. `tests/browser/employee-access.cjs` exercises both views, paging, separate inactive/unactivated filters, scoped manager results, read-only detail and sensitive-field omission, legacy redirect, account totals, effective access, draft cancellation and responsive layouts at 1440px and 390px. Run a static server on port 8765 and execute the script with Playwright available; `ATWAR_PLAYWRIGHT_MODULE` and `ATWAR_CHROMIUM_PATH` can select installed test tools. Browser tests mock all Supabase calls and block external requests. They do not certify a new production-authenticated session. Database policies and RPC contracts are unchanged.
