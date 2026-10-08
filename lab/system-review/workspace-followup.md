# Workspace action and request follow-up — 2026-10-08

Existing workflow tables and RLS are reused; no schema, permissions or workflow transitions changed.
Required actions include task approval, job workflow, reschedule decisions, employee job change review/publication, and assigned policy stages. Linked workflow tasks are replaced by their request entry to avoid duplication. Workflow links open the actual document/request page.
Tracking shows own reschedule and job change requests, and involved policy versions, with current stage, next responsible role, decision notes and direct links. Applied changes remain actionable for administrators until publication.
All request rows are reachable in bounded scrolling panels; automatic refresh every minute, on reconnection and tab return. Query failures show unavailable state instead of zero counts.

Validation: 76 root tests passed; focused request-model regressions exercise authority, terminal status, deduplication, escaping and links. Populated real-script browser fixtures passed desktop/mobile with no page errors or horizontal overflow; visually inspected mobile screenshot. Authenticated database read queries for all four existing tables succeeded in rolled-back transaction. Browser uses fixtures, not a real login walkthrough.
