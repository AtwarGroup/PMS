import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const tasks=readFileSync(resolve(root,'tasks/index.html'),'utf8');
const shell=readFileSync(resolve(root,'assets/js/shell-components.js'),'utf8');

assert.doesNotMatch(tasks,/cdn\.tailwindcss\.com/,'Production tasks page must not load Tailwind Play CDN');
assert.match(tasks,/tasks-tailwind\.min\.css\?v=2\.5\.6/,'Production tasks stylesheet must be cache-versioned');
assert.doesNotMatch(shell,/data-lucide="archive-check"/,'Unsupported Lucide icon must be removed');
assert.match(shell,/data-lucide="archive"/,'Completed tasks must use a supported Lucide icon');

console.log('Production console cleanup passed.');
