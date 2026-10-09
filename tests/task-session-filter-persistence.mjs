import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const tasks=readFileSync(new URL('../assets/js/tasks-page.js',import.meta.url),'utf8');
const html=readFileSync(new URL('../tasks/index.html',import.meta.url),'utf8');
assert.match(tasks,/if\(incomingUid&&incomingUid===initializedAuthUid\)return;[\s\S]*?assigneeFilterValue='ALL';/,'Auth refresh must not reset the assignee filter or users');
assert.match(tasks,/if\(initializedAuthUid===incomingUid\)initializedAuthUid=null;/,'A failed initial load must remain retryable');
const pageVersion=html.match(/tasks-page\.js\?v=(\d+)\.(\d+)\.(\d+)/);
assert.ok(pageVersion,'Task page must have an explicit cache version');
assert.ok(Number(pageVersion[1])>2 || (Number(pageVersion[1])===2 && (Number(pageVersion[2])>5 || (Number(pageVersion[2])===5 && Number(pageVersion[3])>=53))), 'Task page must not revert to a version before the corrected script');
