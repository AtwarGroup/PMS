import assert from 'node:assert/strict';
import {hasPolicyDraftChanges as changed} from '../assets/js/policy-draft-state.mjs';
const version={version_label:'للمراجعة',content:[{body:'نص أول\r\nسطر ثان',id:'first',title:'البند الأول'},{body:'نص آخر',id:'second',title:'البند الثاني'}]};
const editor=[{id:'first',title:'البند الأول',body:'نص أول\nسطر ثان'},{id:'second',title:'البند الثاني',body:'نص آخر'}];
assert.equal(changed(version,editor,'للمراجعة'),false,'JSONB key order and textarea newlines do not create edits');
for(const field of ['title','body','id']){const edited=structuredClone(editor);edited[0][field]+=' تعديل';assert.equal(changed(version,edited,'للمراجعة'),true,field);}
assert.equal(changed(version,editor,'نسخة جديدة'),true,'Label-only edit must be saved');
assert.equal(changed(version,editor,' للمراجعة'),true,'Label is saved verbatim');
assert.equal(changed(version,[...editor].reverse(),'للمراجعة'),true,'Section order matters');
assert.equal(changed(version,editor.slice(1),'للمراجعة'),true,'Deleted section');
assert.equal(changed(version,[...editor,{id:'third',title:'جديد',body:'جديد'}],'للمراجعة'),true,'Added section');
assert.equal(changed({content:[]},[],''),false,'Missing label is an empty editor field');
assert.equal(changed(version,editor,'للمراجعة'),false,'Input objects remain unchanged');
console.log('PASS policy draft content/key order/newlines, real field edits, label edits and section changes');
