# Task query load: investigation and validation

## Confirmed code paths

- `assets/js/supabase-firebase-compat.js`: `loadChildren(ids)` queries `task_activity` for every ID in the supplied task set; `visibleTasks()` invokes it for the whole fetched list.
- The same compatibility layer subscribes to `tasks`, `subtasks`, `task_activity`, and `task_attachments`; all four trigger `emitLocal('tasks')`, which refreshes task listeners.
- Every `onValue()` listener also polls every 60 seconds.
- `assets/js/tasks-core.mjs`: `calcDelay()` needs the activity history to subtract paused approval periods. Do **not** remove activity from list reads without preserving that calculation.

## Change in this branch

`assets/js/supabase-sync.mjs` now coalesces refresh requests arriving in the same JavaScript turn, in addition to the existing in-flight coalescing. This reduces redundant loads from synchronous notification bursts *within each listener*. It does not deduplicate independent listeners or remove the periodic poll. The new `tests/task-refresh-coalescing.mjs` checks these behaviors.

## Before merging / deployment

1. Run `node tests/phase-two-core.mjs` and `node tests/task-refresh-coalescing.mjs`.
2. Verify list, kanban, task detail, delegation, approval/reopening, and delay metrics with representative activity histories.
3. Measure `task_activity` query count, Realtime load, and Supabase CPU over equivalent traffic windows before and after deployment. This branch alone is **not** a demonstrated resolution of the high-CPU incident.
4. Investigate scoping of `visibleTasks()`/`loadChildren()` and periodic polling separately, preserving RLS and delay semantics.
