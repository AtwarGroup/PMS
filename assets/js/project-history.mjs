// Keyset pagination keeps inserts at the head from shifting older pages.
export function historyQuery(sb,table,projectId,before=null){
 if(!['project_messages','project_events'].includes(table))throw new TypeError('Invalid project history table');
 let q=sb.from(table).select('*').eq('project_id',projectId);
 if(before){
  if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(before.created_at)||!Number.isFinite(Date.parse(before.created_at))||!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(before.id))throw new TypeError('Invalid history cursor');
  q=q.or(`created_at.lt.${before.created_at},and(created_at.eq.${before.created_at},id.lt.${before.id})`);
 }
 return q.order('created_at',{ascending:false}).order('id',{ascending:false}).limit(101);
}
export function historyPage(data){const rows=(data||[]).slice(0,100);return {rows,more:(data||[]).length>100,cursor:rows.at(-1)||null};}
export function mergeHistory(existing,incoming){
 const rows=new Map(existing.map(row=>[row.id,row]));for(const row of incoming)rows.set(row.id,row);
 return [...rows.values()].sort((a,b)=>a.created_at.localeCompare(b.created_at)||a.id.localeCompare(b.id));
}
