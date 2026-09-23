import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return walk(full);
    return /\.(?:html|js|mjs)$/.test(entry.name) ? [full] : [];
  });
}

const files = walk('.').filter((file) => !file.startsWith('node_modules'));
const violations = [];
for (const file of files) {
  const source = fs.readFileSync(file, 'utf8');
  const checks = [
    ['unpinned Lucide', /unpkg\.com\/lucide@latest/],
    ['unpinned Supabase client', /@supabase\/supabase-js@2\/\+esm/],
    ['unpinned React 18', /unpkg\.com\/react@18\/umd/],
    ['unpinned ReactDOM 18', /unpkg\.com\/react-dom@18\/umd/],
    ['unpinned Babel standalone', /unpkg\.com\/@babel\/standalone\/babel/],
    ['unpinned Tailwind Play CDN', /cdn\.tailwindcss\.com(?=[\"'])/],
  ];
  for (const [label, pattern] of checks) {
    if (pattern.test(source)) violations.push(`${file}: ${label}`);
  }
}
assert.deepEqual(violations, [], violations.join('\n'));
console.log(`Dependency pinning checks passed across ${files.length} source files.`);
