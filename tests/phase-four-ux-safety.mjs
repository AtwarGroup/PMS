import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const read=file=>readFileSync(resolve(root,file),'utf8');
const html=read('tasks/index.html');
const page=read('assets/js/tasks-page.js');

const contracts=[
  [html,'id="quickAddSubmit"','Quick-add submit button must be addressable'],
  [html,'aria-controls="quickAddBox"','Quick-add trigger must describe its controlled region'],
  [html,'aria-expanded="false"','Quick-add trigger must expose expansion state'],
  [html,'role="status" aria-live="polite" aria-atomic="true"','Toast updates must be announced accessibly'],
  [html,'aria-label="تفاصيل المهمة"','Task details panel must have an accessible label'],
  [page,'quickAddSubmitting','Quick-add must reject duplicate submissions'],
  [page,"submitButton.setAttribute('aria-busy','true')",'Quick-add must expose its busy state'],
  [page,'attachmentUploadBusy','Attachment upload must reject duplicate submissions'],
  [page,'attachmentDeleteLocks','Attachment deletion must be locked per attachment'],
  [page,"label.setAttribute('aria-disabled','true')",'Attachment upload control must expose its disabled state']
];

for(const [source,needle,message] of contracts)assert.ok(source.includes(needle),message);
console.log(`Phase-four UX safety audit passed: ${contracts.length} interaction contracts.`);
