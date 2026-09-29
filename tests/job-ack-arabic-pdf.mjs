import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=path=>readFileSync(new URL(`../${path}`,import.meta.url),'utf8');
const renderer=read('assets/js/job-ack-pdf.js');
for(const path of ['assets/js/job-profile-page.js','assets/js/job-library-page.js']){
 const page=read(path);
 assert.match(page,/createJobAcknowledgementPdf/);
 assert.doesNotMatch(page,/doc\.text\(/,'Both send paths must use the Arabic-safe renderer');
}
assert.match(renderer,/ctx\.direction='rtl'/);
assert.match(renderer,/canvas\.toDataURL\('image\/jpeg'/);
assert.match(renderer,/if\(encoded\.length>10\*1024\*1024\)/);
const email=read('supabase/functions/send-job-acknowledgement/index.ts');
assert.match(email,/span dir="rtl">عرض الوصف في<\/span>/);
assert.match(email,/span dir="ltr"[^>]*>ATWAR ONE<\/span>/);
console.log('Both acknowledgement send paths share Arabic-safe PDF rendering and isolated email direction.');
