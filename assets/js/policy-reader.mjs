const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const normalizePolicySearch = value => String(value ?? '').normalize('NFKD').replace(/[\u064b-\u065f\u0670\u0640]/g, '').replace(/[أإآٱ]/g,'ا').replace(/ى/g,'ي').replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-1632)).toLowerCase();
export function searchPolicy(sections, query, options = {}) {
 const term = normalizePolicySearch(query.trim());
 if(term.length < 2) return [];
 return sections.flatMap(({section,number}) => {
  const clauses = section.body.split(/\n\s*\n/).map(text=>text.trim()).filter(Boolean).flatMap(text=>{
   if(!['POL-COMPENSATION','POL-LEAVE'].includes(options.code)||!text.startsWith('|'))return [{text}];
   const lines=text.split('\n').filter(Boolean),isTable=/^\|[\s:|\-]+\|$/.test(lines[1]||'');
   return isTable?lines.slice(2).map(line=>({text:line.slice(1,-1).split('|').map(c=>c.trim()).join(' | '),cells:line.slice(1,-1).split('|').map(c=>c.trim())})):[{text}];
  });
  const matches = clauses.filter(({text})=>normalizePolicySearch(text).includes(term));
  if(!matches.length && normalizePolicySearch(section.title).includes(term)) matches.push(clauses[0] || {text:section.title});
  return matches.map(({text,cells})=>({id:section.id,number,title:section.title,cells,clause:text.match(/^(\d+\.\d+)/)?.[1] || '',text}));
 });
}
// Presentation only: extract document control without changing stored content.
export function policyOpening(body, document = {}) {
 let text=body,rows=[];
 if(text.startsWith('### بيانات الإصدار والاعتماد\n')){
  const end=text.indexOf('\n\n');
  if(end>0){rows=text.slice(0,end).split('\n').slice(1).map(line=>{const at=line.indexOf(':');return at>0?[line.slice(0,at).trim(),line.slice(at+1).trim()]:['بيان إضافي',line];});text=text.slice(end+2);}
 }else{
  const lines=text.split('\n'),cells=line=>line.trim().replace(/^\||\|$/g,'').split('|').map(c=>c.trim());
  if(lines[0]?.trim()==='| بيان الوثيقة | التفاصيل |'&&/^\|[\s:|\-]+\|$/.test(lines[1]||'')){
   let end=2;while(end<lines.length&&lines[end].startsWith('|')){const row=cells(lines[end]);if(row.length!==2)return {body,rows:[],extra:[]};rows.push(row);end++;}text=lines.slice(end).join('\n').trimStart();
  }
 }
 const take=(pattern,fallbackLabel,fallback)=>{const index=rows.findIndex(([label])=>pattern.test(label));return index<0?[fallbackLabel,fallback||'غير محدد']:rows.splice(index,1)[0];};
 const main=[take(/^رمز السياسة$/,'رمز السياسة',document.code),take(/^رقم الإصدار$/,'رقم الإصدار',document.version),take(/^(حالة الوثيقة|حالة السياسة)$/,'حالة السياسة',document.status),take(/^صاحب.*اعتماد.*$/,'صاحب صلاحية الاعتماد',document.authority)];
 const combined=rows.findIndex(([label])=>label==='تاريخ الإصدار والنفاذ');
 if(combined>=0)main.push(rows.splice(combined,1)[0]);
 else main.push(take(/^تاريخ الإصدار$/,'تاريخ الإصدار',document.issued),take(/^تاريخ (النفاذ|السريان)$/,'تاريخ النفاذ',document.effective));
 return {body:text,rows:main,extra:rows};
}
const metadataRows=rows=>rows.map(([label,value])=>`<div><dt>${esc(label)}</dt><dd>${esc(value)}</dd></div>`).join('');
export function renderTravelBody(body, renderBody, options = {}) {
 const opening=options.overview||body.startsWith('### بيانات الإصدار والاعتماد\n');
 let html;
 if(opening){
  const data=policyOpening(body,{code:options.code,...options.document});
  const purpose=/^### (الغرض|الغرض من السياسة)\n/.test(data.body)?data.body:'### الغرض من السياسة\n'+data.body;
  html=`<div class="travel-meta"><h3>بيانات الإصدار والاعتماد</h3><dl>${metadataRows(data.rows)}</dl>${data.extra.length?`<details class="policy-document-control"><summary>بيانات توثيق إضافية</summary><dl>${metadataRows(data.extra)}</dl></details>`:''}</div>`+renderBody(purpose);
 }else html=renderBody(body);
 html=html.replace(/<p>(\d+\.\d+)(\s+)([\s\S]*?)<\/p>/g,(_,n,space,text)=>`<p class="travel-clause"><span class="travel-clause-number" dir="ltr">${n}</span>${space}<span class="travel-clause-text">${text}</span></p>`);
 return options.code&&options.code!=='POL-TRAVEL'?html:html.replace('<table class="policy-data-table">','<table class="policy-data-table"><colgroup><col style="width:80px"><col><col style="width:120px"></colgroup>');
}
const readerTitle=(title,code)=>code==='POL-LEAVE'?String(title).replace(/^\d+\s+/, ''):title;
const groups = [ ['نظرة عامة',[1,2]], ['التعريفات والإجراءات',[3,4,5]], ['الانتداب ومستحقاته',[6,7]], ['النقل الوظيفي',[8,9]], ['أحكام التنفيذ',[10,11,12,13]], ['الحوكمة والتوثيق',[14,15,16]] ];
export function policyReaderGroups(sections, code='POL-TRAVEL') {
 const selected=code==='POL-LEAVE'?[['نظرة عامة',[1,2,3]],['الإجازة السنوية والطارئة',[4,5,6]],['الإجازات والحالات الخاصة',[7,8,9,10,11,12,13,14]],['الإجراءات والعودة للعمل',[15,16,17,18,19,20]],['التذاكر والاستحقاق',[21,22,23,24,25]],['الحوكمة والسريان',[26,27]],['الملاحق',[28,29,30]]]:code==='POL-COMPENSATION'?[['التعريف والهيكل الوظيفي',[1,2]],['السلم والمزايا',[3,4]],['إدارة الرواتب والاعتمادات',[5,6]],['المراجع',[8]]]:groups;
 return selected.filter(([,numbers])=>sections.some(s=>numbers.includes(s.number)));
}
export function renderTravelReader(sections, renderBody, notes, options = {}) {
 const indexGroups=policyReaderGroups(sections,options.code);

 return `<div class="travel-reader" data-policy-code="${esc(options.code||'POL-TRAVEL')}"><section class="travel-search" aria-label="البحث داخل السياسة"><label for="travelSearch">البحث في السياسة</label><div class="travel-search-field"><input id="travelSearch" type="search" placeholder="ابحث برقم البند أو كلمة في كامل السياسة…" autocomplete="off" aria-controls="travelResults"><button type="button" class="atwar-btn" id="travelClear">مسح البحث</button></div><p class="travel-search-status" id="travelSearchStatus" role="status" aria-live="polite"></p><div id="travelResults" class="travel-results" hidden></div></section><div class="travel-reader-grid"><aside class="travel-index" id="travelIndex" tabindex="-1"><h2>فهرس السياسة</h2><p>${sections.length} قسمًا · صفحة قراءة واحدة</p><nav aria-label="فهرس السياسة">${indexGroups.map(([title,numbers],groupIndex)=>`<details ${groupIndex===0?'open':''}><summary>${title}</summary>${sections.filter(s=>numbers.includes(s.number)).map(({section,number})=>`<button type="button" data-travel-target="${esc(section.id)}"><span>${String(number).padStart(2,'0')}</span>${esc(readerTitle(number===1?'الغرض من السياسة':section.title,options.code))}</button>`).join('')}</details>`).join('')}</nav></aside><div class="travel-reading"><div class="travel-controls"><button class="atwar-btn" type="button" id="travelExpand">فتح جميع الأقسام</button><button class="atwar-btn" type="button" id="travelCollapse">طيّ الجميع</button></div>${sections.map(({section,number},index)=>`<details class="travel-section" data-travel-panel="${esc(section.id)}" ${index===0?'open':''}><summary><span class="travel-section-number">${String(number).padStart(2,'0')}</span><h2>${esc(readerTitle(number===1?'الغرض من السياسة':section.title,options.code))}</h2></summary><div class="travel-section-content"><div class="policy-body">${renderTravelBody(section.body,renderBody,{...options,overview:number===1})}</div>${notes(section)}<button type="button" class="travel-back-index">العودة للفهرس ↑</button></div></details>`).join('')}</div></div></div>`;
}
export function wireTravelReader(host, sections) {
 const input=host.querySelector('#travelSearch'); if(!input)return;
 const code=host.querySelector('.travel-reader').dataset.policyCode;
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
 function revealSalaryMatch(panel,match,query){
  const term=normalizePolicySearch(query.trim());
  panel.querySelectorAll('.policy-registry-widget,.policy-progression-widget').forEach(widget=>{
   const search=widget.querySelector('input[type="search"]'),grade=widget.querySelector('.policy-salary-controls select'),nation=widget.querySelector('select[aria-label="شريحة الراتب"]');
   if(!search||!grade)return;
   const exactGrade=[...grade.options].find(option=>normalizePolicySearch(option.value)===term&&option.value);
   const rowGrade=match.cells&&[...grade.options].find(option=>option.value===match.cells[0]&&option.value);
   const card=[...widget.querySelectorAll('.policy-salary-print .policy-point-card')].find(el=>normalizePolicySearch(el.textContent).includes(term));
   const job=rowGrade?match.cells[1]:card?.querySelector('h4')?.textContent;
   if(!job&&!exactGrade)return;
   grade.value=rowGrade?.value||exactGrade?.value||'';search.value=job||'';if(nation)nation.value='all';
   search.dispatchEvent(new Event('input',{bubbles:true}));
  });
 }
 function openSection(id,match){
  const panel=panels.find(p=>p.dataset.travelPanel===id);if(!panel)return;
  const indexLink=nav.find(b=>b.dataset.travelTarget===id);const group=indexLink?.closest('details');if(group)group.open=true;
  panel.open=true;results.hidden=true;if(code==='POL-COMPENSATION'&&match)revealSalaryMatch(panel,match,input.value);nav.forEach(button=>{const current=button.dataset.travelTarget===id;button.classList.toggle('active',current);if(current)button.setAttribute('aria-current','location');else button.removeAttribute('aria-current');});
  clearHighlights();if(input.value.trim())highlight(panel,input.value);
  const clause=match?.clause;
  const target=clause?[...panel.querySelectorAll('.policy-body p')].find(p=>p.textContent.trim().startsWith(clause+' ')):null;
  const firstMark=panel.querySelector('mark.travel-match');if(firstMark){let parent=firstMark.parentElement;while(parent&&parent!==panel){if(parent.tagName==='DETAILS')parent.open=true;parent=parent.parentElement;}}
  const visibleMark=[...panel.querySelectorAll('mark.travel-match')].find(mark=>mark.getClientRects().length);
  const focus=target||visibleMark||panel.querySelector('summary');
  focus.setAttribute('tabindex','-1');focus.focus({preventScroll:true});scroll(focus);
 }
 function runSearch(){
  clearTimeout(timer);clearHighlights();const query=input.value.trim();matches=searchPolicy(sections,query,{code});
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
 host.querySelectorAll('.travel-index nav>details').forEach(group=>group.addEventListener('toggle',()=>{if(group.open)host.querySelectorAll('.travel-index nav>details').forEach(other=>{if(other!==group)other.open=false;});}));
 host.querySelector('#travelExpand').onclick=()=>panels.forEach(panel=>panel.open=true);
 host.querySelector('#travelCollapse').onclick=()=>{panels.forEach(panel=>panel.open=false);nav.forEach(button=>{button.classList.remove('active');button.removeAttribute('aria-current');});};
 host.querySelectorAll('.travel-back-index').forEach(button=>button.onclick=()=>{const index=host.querySelector('#travelIndex');index.focus({preventScroll:true});scroll(index);});
 const print=()=>{const items=[...panels,...host.querySelectorAll('.policy-document-control')],state=items.map(p=>p.open);items.forEach(p=>p.open=true);return()=>items.forEach((p,i)=>p.open=state[i]);};
 let restore;const before=()=>{if(!restore)restore=print();},after=()=>{restore?.();restore=null;};
 window.addEventListener('beforeprint',before);window.addEventListener('afterprint',after);
 host._disposeTravelReader=()=>{clearTimeout(timer);window.removeEventListener('beforeprint',before);window.removeEventListener('afterprint',after);};
}
