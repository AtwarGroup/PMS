# Project history pagination — 2026-10-09

Continued from merged PR #96 and the recorded live verification; no repeated dependency fix.

Project chat and audit history previously exposed only the newest 100 rows. They now load 100-row pages on demand with a (created_at, id) cursor and one lookahead row. Both reads remain scoped to the current project and subject to existing RLS. Timestamp precision is preserved, and cursor fields are validated before raw PostgREST filtering.

Older chat pages retain the current draft and reading anchor. Live refresh merges with loaded history instead of discarding it. Reconnection fills a multi-page gap before merging into cached messages. Requests coalesce and stale responses cannot overwrite another project/tab. Errors retain visible content and allow retry.

Tests cover 205 tied-timestamp records, head insertion between pages, preserved microseconds, no duplication, retained older rows, invalid cursors, duplicate clicks, scroll/draft preservation, stale responses, and reconnect catch-up for 204 missed messages. The full JavaScript suite passed. No task approval, schema, RLS, or notification delivery changes are included.

Live older-page acceptance with more than 100 real records is not yet claimed. Cross-account message receipt and actual backup restoration remain outstanding.
