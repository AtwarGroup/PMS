import {readAllRows} from './paged-read.mjs?v=2.8.0';

// Preserve input order, complete pagination and caller RLS; bound independent reads.
export async function readRelatedRows(makeQuery, ids, {chunkSize=100,concurrency=1,paged=true}={}) {
 if(!Number.isInteger(chunkSize)||chunkSize<1||!Number.isInteger(concurrency)||concurrency<1||concurrency>4)throw new TypeError('Invalid read batch limits');
 const keys=[...new Set(ids.filter(Boolean))], chunks=[],rows=[];
 for(let start=0;start<keys.length;start+=chunkSize)chunks.push(keys.slice(start,start+chunkSize));
 for(let start=0;start<chunks.length;start+=concurrency){
  const results=await Promise.all(chunks.slice(start,start+concurrency).map(async chunk=>{
   if(paged)return readAllRows(()=>makeQuery(chunk));
   const {data,error}=await makeQuery(chunk);if(error)throw error;return data||[];
  }));
  for(const result of results)rows.push(...result);
 }
 return rows;
}
