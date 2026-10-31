# Mobile diagnostic cancellation fix — 31 October 2026

The uploaded production Android report was incomplete (home warm-up only). A later owner screenshot showed eight successful home samples and a generic `cancelled` interruption. These partial observations do not establish a complete production P95 or prove whether the interruption was manual or automatic.

Source review found that any window resize cancelled the diagnostic, including height-only changes caused by mobile browser chrome. A subsequent cancelled sample overwrote the original `viewport-changed` reason. This exact distinction was therefore lost in schema 1 reports.

PR 187 fixes the diagnostic only:

- Ignore height-only resize; keep the fixed-height iframe and tolerate one pixel of width variation. A meaningful width/orientation change still stops the run so different layouts are not pooled.
- Preserve the first stop cause; show an explicit Arabic explanation for manual stopping, width changes, backgrounding and read failures.
- Store interrupted samples separately from data failures, initialize `complete=false`, and retain valid partial samples without certifying a complete cohort.
- Check for stop requests before starting the next navigation and before classifying an interrupted animation-frame wait as a paint failure.
- Increment the diagnostic module URL to `?v=2`; no automatic run, auth, schema, business workflow, salaries, notifications or password change.

Verification uses the actual runner in a Node VM with synthetic documents and a deterministic scheduler, with no browser, backend or external traffic. Height-only resizing completes 90 synthetic samples. Width changes, manual stopping during sampling, stopping during a stalled paint wait and stopping before first navigation all preserve the correct stop reason. The pre-navigation stop loads zero application pages. Interrupted samples are not counted as data failures. Existing readiness, privacy and percentile checks also pass.

Staging version 54 source: dee7a269a0c386463c3b7cc5471e1e16ebc04637. Worker build and validation passed and deployment succeeded. The diagnostic's updated instructions were observed on staging without starting another live-data measurement.

Production candidate: https://github.com/AtwarGroup/PMS/pull/187, head 9c6b22b33e151247fd07d6f8f2f874e09fb311b0. Publication/check outcomes are recorded below when complete. The owner requested stopping measurement; no new real-data benchmark cohort was started during this fix. Physical Android confirmation is not claimed.

Rollback is a revert of PR 187; the change has no database migration or business-data writes. The earlier timing report and raw evidence remain preserved independently.

## Publication checkpoint

- All three premerge required checks succeeded on 9c6b22b33e151247fd07d6f8f2f874e09fb311b0: quality run 41206704236 and generated-assets run 41206704261.
- PR 187 merged as 3266fac57cba42118ab5f740492cd2470009f941. Its tree ffc5ce3845a50bbe9d60ee72eccf5b651169ecbe exactly matches the fully tested candidate tree.
- Pages run 41207341075 succeeded. The actual production URL https://one.atwargroup.com/lab/performance.html displayed the new mobile-height instructions in the cloud browser, without starting measurement.
- Postmerge generated-assets run 41207341374 succeeded. Automatic postmerge quality run 41207341465 was still in progress at this publication checkpoint; no completed postmerge-quality result is claimed here. The full required premerge suite already passed on the identical source tree.
- No physical Android re-test or new real-data measurement was started. Refreshing an already open page is necessary to load the corrected module; refreshing does not automatically start the diagnostic.
