import {cp,mkdir,readFile,writeFile,rm} from 'node:fs/promises';
import path from 'node:path';
const source='node_modules/pdfjs-dist',version='6.5.438',target='assets/vendor/pdfjs-'+version;
if(JSON.parse(await readFile(source+'/package.json','utf8')).version!==version)throw Error('Unexpected PDF.js version');
await rm(target,{recursive:true,force:true});await mkdir(target,{recursive:true});
for(const name of ['cmaps','standard_fonts','iccs','wasm','LICENSE'])await cp(path.join(source,name),path.join(target,name),{recursive:true});
for(const file of ['pdf.min.mjs','pdf.worker.min.mjs']){await mkdir(target+'/build',{recursive:true});await cp(source+'/legacy/build/'+file,target+'/build/'+file);}
// PDF scripts are never executed; the scripting sandbox is intentionally not shipped.
for(const name of ['quickjs-eval.js','quickjs-eval.wasm'])await rm(path.join(target,'wasm',name),{force:true});
await writeFile(target+'/PROVENANCE.md',`# PDF.js ${version}\n\nLegacy browser builds and decoding resources copied without library edits from the exact npm dev dependency pdfjs-dist@${version}, maintained at https://github.com/mozilla/pdf.js. The Apache-2.0 license and resource licenses are included. Reproduce with node scripts/vendor-pdfjs.mjs after npm ci.\n\nThe renderer and decoding resources are served from this repository. Only protected bytes are passed to the renderer; no PDF file is sent to an external viewer. No scripting sandbox or PDF action handlers are enabled.\n`);
console.log('PDF.js viewer assets prepared');
