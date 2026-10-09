// Rebuild each read so offsets never leak into another request; preserve caller RLS and filters.
export async function readAllRows(makeQuery,{size=500,key='id'}={}){
 const rows=[];
 for(let offset=0;;offset+=size){
  const {data,error}=await makeQuery().order(key).range(offset,offset+size-1);
  if(error)throw error;
  rows.push(...(data||[]));
  if((data||[]).length<size)return rows;
 }
}
