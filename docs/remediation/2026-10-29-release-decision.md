# Release decision and rollback — 29 October 2026

Scope: shared CSS/typography startup and read-state recovery, notification waiting/empty semantics, date-digit presentation and local delivery of the unchanged pinned Lucide runtime. No database migration, application-data transfer, password/permission/approval/salary change, paid resource, or external test delivery is part of this release. Concurrent staging-only recruitment/IT features are retained on staging and are not merged into production by this package.

The user authorized completion through the final result. Release is conditional on the final head's required CI jobs succeeding, an unchanged production base or safe integration of concurrent changes, and production-asset verification after deployment. The working window allows redistribution within its bounds. No maintenance or server write suspension is needed for an atomic static-source release with compatible existing APIs; no migration or data freeze is being attempted.

## Evidence and limits

- Previous application head e64afb0 passed Quality Gate 40916925405 and asset verification 40916925410. Final head adds redirect coverage and release documentation; its full gates must pass before merge.
- Current application route matrix covers 45 content pages via the desktop/mobile static gate and six legacy redirect documents via the added isolated smoke test. The prior 47-page total includes two lab previews. Dynamic scenarios and connected coverage are explicitly scoped, not extrapolated to every possible state.
- Isolated tests cover task conflicts, history restrictions across six roles, fleet driver/manager/owner/accountant workflows, recruitment approvals/exception/offer flows, dialogs, failures and read recovery. No real test emails are sent.
- Authorized manager-connected checks and measured homepage samples are in the connected-checks report and performance JSON. Ten sequential samples before/after local icon delivery show readiness medians 4142.05/3625.9 ms, FCP medians 1232/1044 ms and observed CLS <=0.0378. This is not a randomized or controlled cold/warm comparison. The 3-second readiness goal remains unmet, and no universal speed improvement is claimed. Further performance work remains an engineering follow-up, not a hidden successful acceptance result.
- Android results are viewport emulation, not a physical device. Live connected testing did not submit business writes or cover every identity. Full database recovery is unverified and is not claimed by the source rollback test.
- Final staging version 37, source e5106b8de1c72fea9c1d9ef36a708865add0895d, retains the fixes and removes temporary measurement code; its asset returns 404. Home date digits, three recruitment date lines and rendered icons were visibly verified.

## Source rollback

Baseline: 21e6af36044be30861152ee81fbb08a0399f8733, retained on backup/remediation-baseline-20261029. The isolated reverse-patch dry run restored all baseline tracked source exactly. It deliberately retained the three new pinned Lucide files so cached new HTML continues to resolve its icon dependency after rollback. The recorded 0.053-second source-apply time excludes publication and cache propagation and is not an operational RTO.

If a critical release regression appears, reverse the release's application changes onto the then-current source through an isolated branch/PR, preserving concurrent work and retaining the new vendor files. Run applicable gates, publish atomically and verify baseline source assets and cached/new entry paths. Do not restore the database for a source-only issue. Reserve at least two hours before the approved window ends; do not attempt a broad new repair at the cutoff. Baseline/current public API contracts and local icon bytes are compatible with the cached HTML variants involved here.

## Post-publication checks

Record the merge and Pages deployment reference; compare all changed application files served by one.atwargroup.com byte-for-byte to the merged source (using cache-busting where needed), including the new vendor asset, shared scripts and HTML. Confirm the public entry and asset availability. Do not sign into production as a different identity or submit real transactions/messages for release smoke. Record any cache propagation delay and distinguish published-byte verification from authenticated end-user testing.
