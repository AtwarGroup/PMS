// Database RPCs remain the authority for user/module/record access.
export async function archiveFleetFile(id,kind='request') {
 try {
  const sb=await window.atwarGetSupabase();
  if(!sb.functions?.invoke)return false;
  const {data,error}=await sb.functions.invoke('fleet-files',{body:{action:'archive',id,kind}});
  if(error||data?.error)console.warn('Fleet attachment retained in database; storage transfer will retry on read.');
  return !error&&!data?.error;
 }catch{return false;}
}
export async function fleetFile(rpc,id,kind='request') {
 const file=await rpc(kind==='request'?'fleet_download':'fleet_handover_photo',{p_id:id});
 if(!file.stored){void archiveFleetFile(id,kind);return file;}
 const sb=await window.atwarGetSupabase();
 const {data,error}=await sb.functions.invoke('fleet-files',{body:{action:'download',id,kind}});
 if(error||!(data instanceof Blob))throw Error('تعذر تنزيل الملف. أعد المحاولة.');
 const bytes=new Uint8Array(await data.arrayBuffer());let binary='';
 for(let offset=0;offset<bytes.length;offset+=32768)binary+=String.fromCharCode(...bytes.subarray(offset,offset+32768));
 return {...file,base64:btoa(binary)};
}
