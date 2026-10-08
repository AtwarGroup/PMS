# Approved development sequence

User approved the sequence: verify existing workflow, complete job-description development, unified action inbox, work links, exception follow-up, daily usability details.

First increment: publication impact confirmation. Compares actual content, including KPI source/weight and organizational metadata, against published snapshot. Key ordering is ignored; list ordering remains significant. Counts all authoritative linked profiles from a guarded private aggregation, even where publisher does not have ASSIGN access. Counts separate active/inactive profiles. Stale job revision is rejected; existing revision-checked publication remains in place. Legacy library publication routes to dedicated review page.

Validation: full JavaScript regression suite; authenticated database role tests for aggregate consistency and matching authoritative assignment count, stale revision rejection and employee denial. SQL tests roll back. No business job was published or reassigned during tests.

Pending: scheduled effective publication (must defer snapshot and acknowledgement tasks together), periodic review without content revision, exception follow-up, then unified action inbox and other approved stages. None are claimed implemented by this increment. Current acknowledgement behavior is unchanged.
