#!/usr/bin/env bash
set -Eeuo pipefail
# Requires a GitHub connection with repository administration permission.
test "${ATWAR_APPLY_BRANCH_PROTECTION:-}" = yes || { echo 'Set ATWAR_APPLY_BRANCH_PROTECTION=yes to apply the reviewed rule.' >&2; exit 1; }
gh api --method PUT repos/AtwarGroup/PMS/branches/main/protection --input - <<'JSON'
{"required_status_checks":{"strict":true,"contexts":["System and workflow audit","Fleet database and browser workflow","Production assets are current"]},"enforce_admins":true,"required_pull_request_reviews":{"dismiss_stale_reviews":true,"required_approving_review_count":0},"restrictions":null,"required_linear_history":true,"allow_force_pushes":false,"allow_deletions":false}
JSON
gh api repos/AtwarGroup/PMS/branches/main/protection --jq '{required_status_checks,enforce_admins,allow_force_pushes,allow_deletions}'
