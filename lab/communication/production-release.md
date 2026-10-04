# Communication production release — 2026-10-04

User authorized general release after personally accepting the closed pilot.

Production route `/communication/`, Edge function `communication` (JWT verification enabled). Active profiles can use communication. Shared navigation adds التواصل. Task assignment uses the existing guarded task creation routine and the caller's server-calculated assignment directory. Project discussions open in their existing project record.

Storage is separate from trial data: one row per conversation/message/user preferences/notification/file/task link, with actor-scoped reads and current-membership file checks. Public realtime rows expose only the current user's revision. No trial groups, messages or attachments are copied into company conversations. Private tables deny direct anon/authenticated access; only guarded functions and the authenticated Edge backend access them.

Messages initially load in pages of 300; older pages remain stored and are available through an authorized history endpoint. Presence is written separately without loading message history or broadcasting company-wide revisions. Group changes/message events notify affected members. Text retries remain idempotent, and CAS conflicts retry through the Edge function. Files retain the tested 10MB limit.

Verification: rollback SQL suite covers an ordinary active employee outside the pilot allowlist, private-message isolation, stale version rejection, authorized/unauthorized files and history, real task creation/retry, restricted task denial, notification routing, membership removal and inactive-account denial. Authenticated-role SQL verifies revision rows are visible only to their owner. Node production command tests cover direct/message retry, member removal, group owner and preference isolation. Browser tests with a mock backend cover empty production startup, new conversation, message/file send and download, task/project navigation, global alerts and sign-out cleanup. Root regression suite passes.

Advisors reviewed: private-table no-policy notices are intentional deny-by-default; guarded authenticated RPCs are intentional security-definer boundaries. Existing leaked-password protection warning is unrelated to this release. No authenticated-browser live interaction was claimed; the user's live integrated acceptance remains separate from automated and SQL checks.
