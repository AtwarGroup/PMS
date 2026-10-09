// Rebuild each read so offsets never leak into another request; preserve caller RLS and filters.
export async function readAllRows(makeQuery,{size=500,key='id'}={}){
 const keys=Array.isArray(key)?key:[key];
 if(!keys.length||keys.some(k=>typeof k!=='string'||!k))throw new TypeError('A stable pagination key is required');
 const rows=[];
 for(let offset=0;;offset+=size){
  let query=makeQuery();
  for(const column of keys)query=query.order(column);
  const {data,error}=await query.range(offset,offset+size-1);
  if(error)throw error;
  rows.push(...(data||[]));
  if((data||[]).length<size)return rows;
 }
}
