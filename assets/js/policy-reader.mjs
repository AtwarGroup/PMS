const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const normalizePolicySearch = value => String(value ?? '').normalize('NFKD').replace(/[\u064b-\u065f\u0670\u0640]/g, '').replace(/[أإآٱ]/g,'ا').replace(/ى/g,'ي').replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-1632)).toLowerCase();
export function searchPolicy(sections, query) {
 const term = normalizePolicySearch(query.trim());
 if(term.length < 2) return [];
 return sections.flatMap(({section,number}) => {
  const clauses = section.body.split(/\n\s*\n/).map(text=>text.trim()).filter(Boolean);
  const matches = clauses.filter(text=>normalizePolicySearch(text).includes(term));
  if(!matches.length && normalizePolicySearch(section.title).includes(term)) matches.push(clauses[0] || section.title);
  return matches.map(text=>({id:section.id,number,title:section.title,clause:text.match(/^(\d+\.\d+)/)?.[1] || '',text}));
 });
}
const groups = [ ['نظرة عامة',[1,2]], ['التعريفات والإجراءات',[3,4,5]], ['الانتداب ومستحقاته',[6,7]], ['النقل الوظيفي',[8,9]], ['أحكام التنفيذ',[10,11,12,13]], ['الحوكمة والتوثيق',[14,15,16]] ];
export function renderTravelReader(sections, renderBody, notes) {
 return `<div class="travel-reader"><section class="travel-search" aria-label="البحث داخل السياسة"><label for="travelSearch">البحث في السياسة</label><div class="travel-search-field"><input id="travelSearch" type="search" placeholder="ابحث برقم البند أو كلمة في كامل السياسة…" autocomplete="off" aria-controls="travelResults"><button type="button" class="atwar-btn" id="travelClear">مسح البحث</button></div><p class="travel-search-status" id="travelSearchStatus" role="status" aria-live="polite"></p><div id="travelResults" class="travel-results" hidden></div></section><div class="travel-reader-grid"><aside class="travel-index" id="travelIndex" tabindex="-1"><h2>فهرس السياسة</h2><p>${sections.length} قسمًا · صفحة قراءة واحدة</p><nav aria-label="فهرس السياسة">${groups.map(([title,numbers])=>`<details open><summary>${title}</summary>${sections.filter(s=>numbers.includes(s.number)).map(({section,number})=>`<button type="button" data-travel-target="${esc(section.id)}"><span>${String(number).padStart(2,'0')}</span>${esc(section.title)}</button>`).join('')}</details>`).join('')}</nav></aside><div class="travel-reading"><div class="travel-controls"><button class="atwar-btn" type="button" id="travelExpand">فتح جميع الأقسام</button><button class="atwar-btn" type="button" id="travelCollapse">طيّ الجميع</button></div>${sections.map(({section,number},index)=>`<details class="travel-section" data-travel-panel="${esc(section.id)}" ${index===0?'open':''}><summary><span class="travel-section-number">${String(number).padStart(2,'0')}</span><h2>${esc(section.title)}</h2></summary><div class="travel-section-content"><div class="policy-body">${renderBody(section.body)}</div>${notes(section)}<button type="button" class="travel-back-index">العودة للفهرس ↑</button></div></details>`).join('')}</div></div></div>`;
}
export function wireTravelReader(host, sections) {
 const input=host.querySelector('#travelSearch'); if(!input)return;
 const results=host.querySelector('#travelResults'),status=host.querySelector('#travelSearchStatus');
 const panels=[...host.querySelectorAll('[data-travel-panel]')];
 const nav=[...host.querySelectorAll('[data-travel-target]')];
 let matches=[],timer;
 const scroll=el=>el?.scrollIntoView({behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'auto':'smooth',block:'start'});
 function clearHighlights(){host.querySelectorAll('mark.travel-match').forEach(mark=>mark.replaceWith(document.createTextNode(mark.textContent)));panels.forEach(p=>p.normalize());}
 function highlight(panel,query){
  const term=normalizePolicySearch(query.trim());if(term.length<2)return;
  const walker=document.createTreeWalker(panel.querySelector('.policy-body'),NodeFilter.SHOW_TEXT);
  const nodes=[];while(walker.nextNode())nodes.push(walker.currentNode);
  nodes.forEach(node=>{
   let norm='',positions=[];
   for(let i=0;i<node.textContent.length;i++){const unit=normalizePolicySearch(node.textContent[i]);norm+=unit;for(let n=0;n<unit.length;n++)positions.push(i);}
   let pos=0,start;const frag=document.createDocumentFragment();let previous=0,found=false;
   while((start=norm.indexOf(term,pos))!==-1){const a=positions[start],b=positions[start+term.length-1]+1;frag.append(node.textContent.slice(previous,a));const mark=document.createElement('mark');mark.className='travel-match';mark.textContent=node.textContent.slice(a,b);frag.append(mark);previous=b;pos=start+term.length;found=true;}
   if(found){frag.append(node.textContent.slice(previous));node.replaceWith(frag);}
  });
 }
 function openSection(id,match){
  const panel=panels.find(p=>p.dataset.travelPanel===id);if(!panel)return;
  panel.open=true;results.hidden=true;nav.forEach(button=>{const current=button.dataset.travelTarget===id;button.classList.toggle('active',current);if(current)button.setAttribute('aria-current','location');else button.removeAttribute('aria-current');});
  clearHighlights();if(input.value.trim())highlight(panel,input.value);
  const clause=match?.clause;
  const target=clause?[...panel.querySelectorAll('.policy-body p')].find(p=>p.textContent.trim().startsWith(clause+' ')):null;
  const focus=target||panel.querySelector('mark.travel-match')||panel.querySelector('summary');
  focus.setAttribute('tabindex','-1');focus.focus({preventScroll:true});scroll(focus);
 }
 function runSearch(){
  clearTimeout(timer);clearHighlights();const query=input.value.trim();matches=searchPolicy(sections,query);
  results.hidden=!query||normalizePolicySearch(query).length<2;
  status.textContent=!query?'':normalizePolicySearch(query).length<2?'اكتب حرفين على الأقل للبحث.':matches.length?`${matches.length} نتيجة في كامل السياسة`:'لا توجد نتائج مطابقة. جرّب كلمة أخرى أو رقم البند.';
  results.replaceChildren();
  matches.forEach((match,index)=>{const button=document.createElement('button');button.type='button';button.dataset.travelResult=String(index);const label=document.createElement('strong');label.textContent=`${match.clause||'القسم '+match.number} — ${match.title}`;const excerpt=document.createElement('span');const text=match.text.replace(/^\|.*\n\|[\s|:-]+\|\n/,'');const at=normalizePolicySearch(text).indexOf(normalizePolicySearch(query));const offset=Math.max(0,at-65);excerpt.textContent=(offset?'…':'')+text.slice(offset,offset+230)+(text.length>offset+230?'…':'');button.append(label,excerpt);results.append(button);});
 }
 input.addEventListener('input',()=>{clearTimeout(timer);timer=setTimeout(runSearch,120);});
 input.addEventListener('keydown',e=>{if(e.key==='Escape'){input.value='';runSearch();}if(e.key==='Enter'){e.preventDefault();runSearch();if(matches[0])openSection(matches[0].id,matches[0]);}});
 results.addEventListener('click',e=>{const button=e.target.closest('[data-travel-result]');if(button){const match=matches[Number(button.dataset.travelResult)];openSection(match.id,match);}});
 host.querySelector('#travelClear').onclick=()=>{input.value='';runSearch();input.focus();};
 nav.forEach(button=>button.onclick=()=>openSection(button.dataset.travelTarget));
 host.querySelector('#travelExpand').onclick=()=>panels.forEach(panel=>panel.open=true);
 host.querySelector('#travelCollapse').onclick=()=>{panels.forEach(panel=>panel.open=false);nav.forEach(button=>{button.classList.remove('active');button.removeAttribute('aria-current');});};
 host.querySelectorAll('.travel-back-index').forEach(button=>button.onclick=()=>{const index=host.querySelector('#travelIndex');index.focus({preventScroll:true});scroll(index);});
 const print=()=>{const state=panels.map(p=>p.open);panels.forEach(p=>p.open=true);return()=>panels.forEach((p,i)=>p.open=state[i]);};
 let restore;const before=()=>{if(!restore)restore=print();},after=()=>{restore?.();restore=null;};
 window.addEventListener('beforeprint',before);window.addEventListener('afterprint',after);
 host._disposeTravelReader=()=>{clearTimeout(timer);window.removeEventListener('beforeprint',before);window.removeEventListener('afterprint',after);};
}
