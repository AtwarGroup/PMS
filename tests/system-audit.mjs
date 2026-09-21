import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, extname, join, relative, resolve } from 'node:path';

const root = resolve(new URL('..', import.meta.url).pathname);
const ignoredDirectories=new Set(['.git','node_modules']);
const collectFiles=(directory=root)=>readdirSync(directory,{withFileTypes:true}).flatMap(entry=>{
  if(entry.isDirectory()){
    if(ignoredDirectories.has(entry.name))return [];
    return collectFiles(join(directory,entry.name));
  }
  const extension=extname(entry.name);
  return ['.html','.js','.mjs'].includes(extension)
    ? [relative(root,join(directory,entry.name))]
    : [];
});
const files=collectFiles();
const htmlFiles = files.filter(file => extname(file) === '.html');
const jsFiles = files.filter(file => ['.js','.mjs'].includes(extname(file)));
const failures = [];
const temp = mkdtempSync(join(tmpdir(), 'atwar-audit-'));

try {
  for (const file of jsFiles) {
    try { execFileSync(process.execPath, ['--check', resolve(root, file)], { stdio: 'pipe' }); }
    catch (error) { failures.push(`JavaScript syntax: ${file}\n${error.stderr || error.message}`); }
  }

  for (const file of htmlFiles) {
    const source = readFileSync(resolve(root, file), 'utf8');
    const base = dirname(resolve(root, file));
    const refs = [...source.matchAll(/(?:href|src)=["']([^"']+)["']/g)].map(match => match[1]);
    for (const ref of refs) {
      if (/^(?:https?:|data:|mailto:|tel:|#|javascript:)/i.test(ref) || ref.includes('${')) continue;
      const clean = ref.split(/[?#]/)[0];
      if (!clean) continue;
      const target = resolve(base, clean);
      if (!existsSync(target)) failures.push(`Broken local reference: ${relative(root, resolve(root, file))} -> ${ref}`);
    }

    let index = 0;
    for (const match of source.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)) {
      const body = match[1].trim();
      if (!body) continue;
      if (/type=["']text\/babel["']/i.test(match[0])) continue;
      const moduleScript = /<script[^>]*type=["']module["']/i.test(match[0]);
      const tempFile = join(temp, `${file.replaceAll('/', '_')}-${index++}.${moduleScript ? 'mjs' : 'js'}`);
      writeFileSync(tempFile, body);
      try { execFileSync(process.execPath, ['--check', tempFile], { stdio: 'pipe' }); }
      catch (error) { failures.push(`Inline JavaScript syntax: ${file}\n${error.stderr || error.message}`); }
    }
  }

  const combined = files.map(file => readFileSync(resolve(root, file), 'utf8')).join('\n');
  const secretPatterns = [
    /service_role\s*[:=]\s*["'][^"']+/i,
    /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
    /sb_secret_[A-Za-z0-9_-]+/
  ];
  if (secretPatterns.some(pattern => pattern.test(combined))) failures.push('Potential server secret found in public files.');

  if (failures.length) {
    console.error(failures.join('\n\n'));
    process.exitCode = 1;
  } else {
    console.log(`ATWAR audit passed: ${htmlFiles.length} HTML files, ${jsFiles.length} JavaScript modules.`);
  }
} finally {
  rmSync(temp, { recursive: true, force: true });
}
