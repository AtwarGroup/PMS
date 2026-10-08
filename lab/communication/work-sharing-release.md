# Work sharing and source navigation — 2026-10-08

Existing production communication_task_command and create_task_safe are reused. No Edge function deployment or message schema change.

Composer now has a work-sharing picker for tasks/projects/policies. Selection adds a canonical public-system route to the unsent draft; actual sending uses existing conversation membership checks, idempotent message transport and notifications. Search uses caller RLS and returns up to 100 matches. Messages render up to five recognized canonical references as cards; titles and status are resolved through recipient authenticated RLS, in batches of 100 IDs. Restricted/deleted records show a generic restricted card; query failures show unavailable rather than restricted. Sender-supplied titles are never used for these cards.

Task creation retains original message preview and editable title/assignee/deadline; duplicate clicks disabled until completion, existing transactional database retry behavior retained. Link-only messages default title from accessible card rather than raw URL.

Task details show linked message routes through communication_task_sources. Private SECURITY DEFINER helper validates active communication account, task/project access and current conversation membership, returning only routing IDs (up to five). Public wrapper is SECURITY INVOKER; anon/PUBLIC execution revoked. Index added on private link task_id. Changing selected task during request discards stale response. Opening conversation already rechecks membership through existing production endpoint.

Validation: root tests, browser fixtures for all three sharing types, selection-before-send, cards, task creation, restricted recipient view, desktop/mobile overflow and no page errors. Live rolled-back SQL tests cover creator member, assignee without membership, assignee with membership, removed admin member, null actor. Authenticated function grants verified; anonymous execution denied. Advisors show only preexisting guarded public functions/private closed tables/password-protection settings, no newly exposed definer API. Manual real-user login acceptance was not performed. No fixture data persisted.
