# Closed live pilot: work integration

Implemented with production task/project permissions, keeping the three-account gate.

- Create a real task from a message using `create_task_safe`. The state row lock, task insertion, message link and revision update share one transaction. Retrying the same message returns its existing task.
- Link existing tasks after the same access checks as the tasks SELECT policy. Message membership does not grant task access.
- Fresh task cards come from the caller's authenticated RLS queries; inaccessible/deleted tasks display a restricted card. Cards open the production task page.
- Project links come from authenticated RLS queries and open the existing project discussion. They do not copy messages into another discussion.
- New pilot notifications enter the standard notification table with generic text, not message previews. Opening rechecks current membership.
- Shared-shell pages listen for pilot revisions and claim alerts atomically through the existing Edge CAS flow, honoring mute/DND/quiet/sound preferences. Auth changes remove alerts and subscriptions. A 20-second polling fallback recovers missed realtime events.
- No broader rollout. Task creation can assign only active pilot accounts; production task rules still apply. Catalogues show the latest 500 accessible tasks and 200 projects; linked older tasks are checked separately.

Validation: live SQL transaction rolled back after assertions for real task creation, retry idempotency, forbidden task access, standard notification insertion/routing, recipient isolation and anonymous rejection. Root regression suite passed. Mock-backed browser tests passed for send/files, actual-page task/project navigation, excluded-account global gate and sign-out cleanup. Existing user-confirmed live chat/file tests predate this integration; new integrated flows still need manual live acceptance.

Deployment: migration 20261003210357; Edge communication-trial v3. Frontend publish tracked in the associated Git commit.
