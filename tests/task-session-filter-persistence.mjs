import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const tasks=readFileSync(new URL('../assets/js/tasks-page.js',import.meta.url),'utf8');
const html=readFileSync(new URL('../tasks/index.html',import.meta.url),'utf8');
assert.match(tasks,/if\(incomingUid&&incomingUid===initializedAuthUid\)return;[\s\S]*?assigneeFilterValue='ALL';/,'Auth refresh must not reset the assignee filter or users');
assert.match(tasks,/if\(initializedAuthUid===incomingUid\)initializedAuthUid=null;/,'A failed initial load must remain retryable');
assert.match(html,/tasks-page\.js\?v=2\.5\.22/,'The page must load the corrected script');
