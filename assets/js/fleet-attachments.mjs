export function quoteFileIds(quote, kind) {
  const ids = quote[kind + '_file_ids'];
  return Array.isArray(ids) ? ids : quote[kind + '_file_id'] ? [quote[kind + '_file_id']] : [];
}
export function validateFleetFiles(files) {
  for (const file of files) {
    if (!file.size || file.size > 5242880 || !['application/pdf','image/png','image/jpeg'].includes(file.type))
      throw Error('اختر PDF أو PNG أو JPEG بحد أقصى 5 ميجابايت لكل ملف.');
  }
  if (files.reduce((sum, file) => sum + file.size, 0) > 31457280)
    throw Error('الحد الإجمالي لمرفقات الطلب 30 ميجابايت.');
}
export async function uploadFleetFiles(files, uploadOne, existing = [], onSaved = () => {}) {
  validateFleetFiles(files);
  const ids = [...new Set(existing)];
  for (const file of files) {
    const id = await uploadOne(file);
    if (!ids.includes(id)) ids.push(id);
    onSaved([...ids]);
  }
  return ids;
}
export async function validateFleetUploadBudget(selections, stored = []) {
  validateFleetFiles(selections.map(s => s.file));
  if (selections.some(s => s.kind === 'repair_photo' && !['image/png','image/jpeg'].includes(s.file.type)))
    throw Error('صور الإصلاح PNG أو JPEG فقط.');
  let total = stored.reduce((sum, f) => sum + Number(f.size_bytes || 0), 0);
  const seen = new Set(stored.map(f => `${f.kind}:${f.content_hash}:${f.size_bytes}`));
  for (const {kind, file} of selections) {
    const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', await file.arrayBuffer()))].map(b => b.toString(16).padStart(2,'0')).join('');
    const key = `${kind}:${hash}:${file.size}`;
    if (!seen.has(key)) {total += file.size; seen.add(key);}
  }
  if (total > 31457280) throw Error('إجمالي المرفقات المحفوظة والمختارة يتجاوز 30 ميجابايت؛ قلّل الملفات المختارة قبل الرفع.');
}
