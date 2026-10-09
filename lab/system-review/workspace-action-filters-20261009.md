# Workspace action filters — 2026-10-09

Continued after PR #97, without repeating the dependency fix or history work. Add independent action-type and priority selectors above the Required from me inbox. Document reviews include workflow tasks and policy reviews; ordinary completion approvals and requests/decisions have separate types. The overdue filter uses documented workflow review deadlines only.

Filtering uses already authorized in-memory rows, preserves existing ordering, and does not refetch. The overall action count remains visible, with a filtered/total status. Automatic refresh preserves selection. An unavailable source cannot be made to look current by changing a filter; retry resumes the same selection.

Validation covers filter intersection, policy classification, overdue semantics, invalid values, local filtering, selected-state retention, total counts, and failed-read recovery. No database, notification, or task completion/approval changes. Live acceptance is pending because the browser runtime stopped safely resuming its authenticated state; file selection failed before any upload.

PR #97 history and reconnect improvements were merged and successfully deployed. More-than-100-row history behavior has automated coverage, not full live acceptance. Cross-account message receipt, attachment upload/download authorization and an actual restore of a backup into a disposable database remain outstanding. Restore dispatch is not exposed by the available GitHub connector.
