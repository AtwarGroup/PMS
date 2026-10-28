// Compare editor fields, not JSON object serialization order from jsonb.
const editorText=value=>String(value??'').replace(/\r\n?/g,'\n').trim();
const sections=content=>(content||[]).map(section=>({
  id:String(section.id??''),
  title:editorText(section.title),
  body:editorText(section.body),
}));

export function hasPolicyDraftChanges(version,content,label){
  return String(label??'')!==String(version.version_label??'') ||
    JSON.stringify(sections(content))!==JSON.stringify(sections(version.content));
}
