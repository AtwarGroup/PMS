/* Reviewed KPI scale proposals, 2026-09-30. Exact indicator matching prevents stale suggestions. No published snapshot is modified. */
(() => {
const catalog=window.AtwarKpiProposalCatalog;
if(!Array.isArray(catalog))throw new Error("KPI reference catalog unavailable");
const signature=item=>JSON.stringify([item?.name||item?.text||'',item?.target||'',item?.measure||'']);
const find=(item,job)=>catalog.find(row=>row.jobId===job?.id)?.indicators.find(row=>row.signature===signature(item))||null;
const details=(rows,job)=>{
 const revision=Number(job?.published_snapshot?.revision??job?.revision);
 const entry=catalog.find(row=>row.jobId===job?.id&&row.revision===revision);
 return entry&&rows.length===entry.indicators.length&&rows.every((item,index)=>signature(item)===entry.indicators[index].signature)?entry:null;
};
window.AtwarKpiProposals={find,catalog,details};
})();
