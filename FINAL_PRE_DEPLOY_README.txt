ATWAR ONE V0.37 — FINAL PRE-DEPLOY
=================================
VERDICT: READY

Application:
- Entry routing: PASS
- Task core: PASS
- Profile fallback: PASS
- Broken links: 0
- Demo account remnants: 0

Firebase Free Tier:
- Employee reads own profile/user scope.
- Manager reads direct team using managerUid query.
- Admin reads all users only where organization-wide scope is needed.
- Live notifications: last 50 only.
- Proposed Rules include .indexOn managerUid but remain REVIEW ONLY.

Database clean candidate:
Original: {'users': 9, 'tasksByUser': 85, 'notificationsByUser': 150, 'createdTaskIndex': 85, 'financial_manager_tasks': 51, 'tasks': 2}
Clean:    {'users': 9, 'tasksByUser': 85, 'notificationsByUser': 114, 'createdTaskIndex': 85, 'financial_manager_tasks': 51, 'tasks': 2}
Protected production nodes unchanged: True
Test notifications removed: 36
Non-test notifications removed: 0

IMPORTANT:
1. Upload application V0.37 first and test.
2. Take a NEW Firebase export immediately before database cleanup.
3. Do not upload proposed Rules yet.
4. Only then import/apply the reviewed clean candidate.
5. Legacy financial_manager_tasks and tasks are preserved.
