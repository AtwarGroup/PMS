import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve(new URL('..',import.meta.url).pathname);
const css=fs.readFileSync(path.join(root,'assets/css/shared.css'),'utf8');
const required=['ATWAR ONE V0.32 — STABILIZATION DESIGN SYSTEM','--atwar-control-height:40px','--atwar-dialog-width:520px','.dialog-backdrop','.password-dialog','.workspace-shell',':focus-visible','@media(max-width:560px)'];
for(const token of required)if(!css.includes(token))throw new Error(`Missing unified design token: ${token}`);
const htmlFiles=[];
function walk(dir){for(const entry of fs.readdirSync(dir,{withFileTypes:true})){if(['.git','node_modules','tmp'].includes(entry.name))continue;const full=path.join(dir,entry.name);if(entry.isDirectory())walk(full);else if(entry.name.endsWith('.html'))htmlFiles.push(full)}}
walk(root);
const shellPages=htmlFiles.filter(file=>fs.readFileSync(file,'utf8').includes('atwar-shell'));
const missing=shellPages.filter(file=>!fs.readFileSync(file,'utf8').includes('assets/css/shared.css'));
if(missing.length)throw new Error(`Shell pages missing shared.css: ${missing.map(x=>path.relative(root,x)).join(', ')}`);
console.log(`Unified UI design-system audit passed: ${shellPages.length} authenticated pages.`);
