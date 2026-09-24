import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const migration=readFileSync(new URL('../supabase/migrations/20260924230348_clear_obsolete_delegation_notifications.sql',import.meta.url),'utf8');
const shell=readFileSync(new URL('../assets/js/shell-components.js',import.meta.url),'utf8');
const tasks=readFileSync(new URL('../tasks/index.html',import.meta.url),'utf8');

assert.match(migration,/delete from public\.notifications[\s\S]*type='TASK_DELEGATED'/,
  'A return or new transfer must withdraw old delegation alerts');
assert.match(migration,/type='assigned' and recipient_id=v_task\.assignee_id/,
  'The previous assignee must not keep an obsolete assignment alert');
assert.match(migration,/v_event := case when v_return then 'reclaimed'/,
  'The return event must remain in the task activity history');
assert.match(shell,/if\(opening\)\{list\.innerHTML=[^\n]+void refresh\(\)/,
  'Opening the bell must fetch the current notifications');
assert.match(tasks,/shell-components\.js\?v=2\.5\.10/,
  'The task page must load the refreshed bell');
console.log('Delegation notification lifecycle audit passed.');
