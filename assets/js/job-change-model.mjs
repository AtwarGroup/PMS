export const kpiFields = [['name','اسم المؤشر'],['perspective','محور بطاقة الأداء'],['measure','طريقة / معادلة القياس'],['unit','وحدة القياس'],['target','المستهدف'],['source','مصدر القياس'],['weight','الوزن %'],['frequency','دورية القياس']];
export const sectionKeys = {RESPONSIBILITIES:'responsibilities',AUTHORITIES:'authorities',KPIS:'kpis',REPORTS:'reports'};
export const valueText = value => typeof value === 'string' ? value : value?.text || value?.name || value?.title || '';
const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(key=>[key,canonical(value[key])])) : typeof value === 'string' ? value.trim() : value;
export function sameValue(a,b){return JSON.stringify(canonical(a))===JSON.stringify(canonical(b));}
export function referencedKpi(snapshot,reason){
 const normalize=v=>String(v||'').normalize('NFKC').replace(/[\u064B-\u065F\u0670]/g,'').replace(/[إأآ]/g,'ا').replace(/\s+/g,' ').trim();
 const note=normalize(reason),matches=(snapshot?.content?.kpis||[]).map((kpi,index)=>({kpi,index,revision:snapshot.revision})).filter(x=>normalize(x.kpi.name).length>=4&&note.includes(normalize(x.kpi.name)));
 return matches.length===1?matches[0]:null;
}
export function changedFields(a,b,section){if(section!=='KPIS')return sameValue(a,b)?[]:['النص'];return kpiFields.filter(([key])=>!sameValue(a?.[key],b?.[key])).map(([,label])=>label).concat(sameValue(a?.scale,b?.scale)?[]:['سلم التقييم']);}
export function validProposal(section,action,value,original){
 if(!['PURPOSE',...Object.keys(sectionKeys)].includes(section)||!['ADD','MODIFY','DELETE'].includes(action))return 'حدد القسم والإجراء المطلوب.';
 if(action==='DELETE')return original==null?'حدد البند المطلوب حذفه.':'';
 if(action==='MODIFY'&&sameValue(original,value))return 'لم يتغير البند؛ المبررات وحدها لا تمثل تعديلًا.';
 if(section==='KPIS'){
  for(const key of ['name','measure','unit','target','source','frequency'])if(!String(value?.[key]??'').trim())return 'أكمل اسم المؤشر والمعادلة والوحدة والمستهدف والمصدر والدورية.';
  if(!Number.isFinite(Number(value?.weight))||Number(value.weight)<=0||Number(value.weight)>100)return 'أدخل وزنًا أكبر من صفر ولا يتجاوز 100%.';
  if(!Array.isArray(value?.scale)||value.scale.length!==5||value.scale.some(level=>!level.label?.trim()))return 'أكمل حدود سلم التقييم الخماسي.';
 }else if(valueText(value).trim().length<2)return 'اكتب التعديل المطلوب.';
 return '';
}
export function cleanKpiProposal(original,values){
 const result={...(original||{}),...values,weight:Number(values.weight)};
 // A changed target, measure or scale invalidates the old explanatory basis.
 if(['target','measure','scale'].some(key=>!sameValue(original?.[key],result[key]))){result.scale_basis=result.target;result.scale_note='سلم مقترح؛ يعتمد مع قرار صاحب الصلاحية';result.measurement_review_note='';}
 return result;
}

// One readiness rule for the review page and the workspace inbox.
export function changeReadiness(request){
 const pending=['MANAGER_REVIEW','ADMIN_REVIEW','NEEDS_CHANGES','STALE'].includes(request.status);
 const issue=pending&&request.section&&request.action?validProposal(request.section,request.action,request.proposed_value,request.original_value):'';
 const expected={section:request.section,action:request.action,index:request.item_index??null,original:request.original_value,proposed:request.proposed_value,impact:request.impact_note||''};
 const approved=!!request.manager_decided_at&&sameValue(request.approval_snapshot,expected);
 const needsDecision=pending&&request.status==='ADMIN_REVIEW'&&!issue&&!approved;
 return {issue,approved,needsDecision,incomplete:!!issue,state:issue?'يحتاج استكمال التعديل':needsDecision?'يحتاج قرارًا على الصيغة الحالية':null};
}
