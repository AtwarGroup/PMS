# Live project pagination correction — 2026-10-09

A signed-in test manager created a synthetic project successfully. Opening the project then failed with `column project_dependencies.id does not exist`. The dependencies table has the composite primary key `(task_id, predecessor_id)`, while the shared paginated reader defaulted to `id`.

The reader now accepts multiple stable key columns. The project dependency query explicitly orders by both actual primary-key columns. The projects page and imports use cache version 2.5.56.

Regression coverage reads 1,203 composite-key rows over three pages, checks both order columns on every page, rejects an empty key, and verifies the project query uses the schema's actual key. This is a correction to the previously approved pagination increment; task completion/approval rules are unchanged.

Synthetic fixture: project 0444c016-3c16-4f96-90fb-0a437c8bcf9a, created only with E2E test accounts. Live post-deployment verification remains pending at the time of this commit.

## Verified after deployment

PR #96 merged as `76babc56b4a6669208212c57ac0f25a00f43c97f`. GitHub Quality Gate and Pages deployment both succeeded. The live projects module contains the composite-key query; the browser loaded cache version 2.5.56 after reload.

The same test manager opened the same project successfully: Gantt rendered, chat reported connected/live updates with three test members, files rendered an empty collection plus uploader, and the change log showed the creation event. Workspace also loaded and listed the test project. Screenshot: `atwar-project-live-20261009.jpg`.

No message was sent and no attachment was uploaded in this check. Cross-account message receipt, upload/download permission checks, older history paging, inbox filters and an actual backup restore remain open. The synthetic project is retained for subsequent checks. Self-created task completion rules were not modified.
