# Live project pagination correction — 2026-10-09

A signed-in test manager created a synthetic project successfully. Opening the project then failed with `column project_dependencies.id does not exist`. The dependencies table has the composite primary key `(task_id, predecessor_id)`, while the shared paginated reader defaulted to `id`.

The reader now accepts multiple stable key columns. The project dependency query explicitly orders by both actual primary-key columns. The projects page and imports use cache version 2.5.56.

Regression coverage reads 1,203 composite-key rows over three pages, checks both order columns on every page, rejects an empty key, and verifies the project query uses the schema's actual key. This is a correction to the previously approved pagination increment; task completion/approval rules are unchanged.

Synthetic fixture: project 0444c016-3c16-4f96-90fb-0a437c8bcf9a, created only with E2E test accounts. Live post-deployment verification remains pending at the time of this commit.
