import {readAllRows} from './paged-read.mjs?v=2.8.0';

// Keep URL filters bounded as well as paging every child collection.
export async function readRelatedRows(makeQuery, ids, {chunkSize = 100} = {}) {
  const keys = [...new Set(ids.filter(Boolean))], rows = [];
  for (let start = 0; start < keys.length; start += chunkSize) {
    const chunk = keys.slice(start, start + chunkSize);
    rows.push(...await readAllRows(() => makeQuery(chunk)));
  }
  return rows;
}
