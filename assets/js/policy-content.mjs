const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
// Deliberately supports text, subheadings and tables only; never interprets HTML or links.
const cellText=value=>/^[\d,–+ /%.]+$/.test(value)&&/\d/.test(value)?`<bdi dir="ltr" class="policy-number">${esc(value)}</bdi>`:esc(value);
export function renderPolicyBody(body){
 const lines=String(body??'').split('\n'),out=[];let i=0;
 while(i<lines.length){const line=lines[i];if(!line.trim()){i++;continue;}
 if(line.startsWith('|')&&lines[i+1]?.match(/^\|[\s:|\-]+\|$/)){
  const cells=l=>l.slice(1,-1).split('|').map(c=>c.trim());const head=cells(line);i+=2;const rows=[];while(lines[i]?.startsWith('|'))rows.push(cells(lines[i++]));
  out.push(`<div class="policy-table-wrap" tabindex="0" role="region" aria-label="جدول السياسة"><table class="policy-data-table"><thead><tr>${head.map(h=>`<th scope="col">${esc(h)}</th>`).join('')}</tr></thead><tbody>${rows.map(r=>`<tr>${head.map((h,j)=>`<td data-label="${esc(h)}">${cellText(r[j]||'')}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`);continue;
 }
 if(line.startsWith('### ')){out.push(`<h3>${esc(line.slice(4))}</h3>`);i++;continue;}
 const paragraph=[line];i++;while(i<lines.length&&lines[i].trim()&&!lines[i].startsWith('|')&&!lines[i].startsWith('### '))paragraph.push(lines[i++]);out.push(`<p>${esc(paragraph.join('\n')).replaceAll('\n','<br>')}</p>`);
 }return out.join('');
}
