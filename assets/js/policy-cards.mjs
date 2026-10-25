// Catalog presentation only. Visibility and access remain enforced by the policy queries.
const escape=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const stages={PREPARATION:'إعداد',REVIEW:'مراجعة',APPROVAL:'موافقة',RATIFICATION:'اعتماد',APPROVED:'معتمدة',DRAFT:'مسودة'};
export function renderPolicyCard(policy,version,formatDate=value=>new Date(value).toLocaleDateString('ar-SA',{calendar:'gregory'})){
 const state=version?.status||'DRAFT';
 return `<article class="policy-box policy-card" data-state="${escape(state)}" data-search="${escape(policy.title+' '+policy.code)}">
 <div class="policy-card-top"><span class="policy-card-symbol" aria-hidden="true"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M14 3H6a1 1 0 0 0-1 1v16h14V8l-5-5Z"/><path d="M14 3v5h5M8 12h8M8 16h6"/></svg></span><span class="policy-card-code" dir="ltr">${escape(policy.code)}</span><span class="policy-card-state">${escape(stages[state]||'مسودة')}</span></div>
 <h2>${escape(policy.title)}</h2>
 <p class="policy-card-publication">${version?.effective_date?'تاريخ السريان · '+escape(formatDate(version.effective_date)):'لم تعتمد للنشر بعد'}</p>
 <div class="policy-card-footer"><span class="policy-card-version">الإصدار <b>${escape(version?.version_number||1)}</b></span><a class="policy-link" href="?id=${encodeURIComponent(policy.id)}">فتح السياسة<svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5m6-6-6 6 6 6"/></svg></a></div>
 </article>`;
}
