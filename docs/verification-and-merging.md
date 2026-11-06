# Verification and merging

Every pull request retains the same three required checks:

- **System and workflow audit** runs all fast JavaScript regressions.
- **Production assets are current** verifies generated assets against source.
- **Fleet database and browser workflow** is now the final verification gate. Its legacy name is retained for existing branch protection; it verifies classification, audit and all selected module suites.

The change planner selects fleet, IT support, recruitment, policies or communication from module-owned paths. Multiple affected modules are combined. A CSS/HTML-only module change is identified as design work but still runs its module verification. Shared assets, database migrations/functions, dependencies, tests, CI configuration and unknown paths run **all suites**. Missing/unreadable diffs also run all suites. Renames include both old and new paths.

The core suite retains the shared permissions, notifications, attachments, shell, theme and access tests. Full runs preserve every check from the original quality workflow, split into independent module jobs with at most four jobs running together.

Full verification also runs daily at **02:30 Asia/Riyadh** and can be started manually from Actions. The assets workflow runs at the same time. Merge-queue events are supported and always run the full plan if a queue is enabled in repository settings.

The final gate always runs. Failure, cancellation, missing outputs, an invalid plan or an unexpectedly skipped selected suite fails the gate. Documentation-only changes may skip module browser jobs, while audit and assets checks still run. There are no workflow-level path filters that could leave required checks indefinitely pending.

Branch protection, strict up-to-date requirements, access permissions and deployment settings are unchanged. The plan and results are recorded in each workflow run. Superseded runs for the same pull request are cancelled; independent suites run in parallel. Group related edits in one pull request and merge a shared-source change before updating dependent pull requests to avoid repeated synchronizations. This change supports a merge queue but does not enable one or add automatic merge authority.

## Validation

`node tests/ci-verification-plan.mjs` tests real git diffs, cross-module renames, conservative fallbacks and failure propagation through the gate command. `node scripts/ci/run-suite.mjs <suite>` executes a selected suite. Browser tests use local synthetic previews without production data.

Keep new paths conservative: add a module mapping only when its tests cover that path's dependencies. Otherwise retain full verification. To restore the original serial verification workflow, revert this change through a reviewed pull request; do not disable required checks.
