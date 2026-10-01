#!/usr/bin/env python3
"""Extract local policy HTML into private JSON. Output must not be committed."""
import argparse,json,re
from pathlib import Path
from lxml import html
BLOCKS={'p','div','li','ul','ol','table','tr','h3','h4','br'}
def render(node):
    if node.tag in {'script','style','button','h2'}:return ''
    out=node.text or ''
    for child in node:
        out+=render(child)+(child.tail or '')
    if node.tag in {'td','th'}:return out.strip()+' | '
    if node.tag in BLOCKS:return '\n'+out+'\n'
    return out

def extract(path,code,title,selector):
    doc=html.fromstring(Path(path).read_text())
    sections=[]
    for i,node in enumerate(doc.xpath(selector),1):
        headings=node.xpath('.//h2')
        if not headings:continue
        heading=' '.join(headings[0].text_content().split())
        body=render(node)
        body='\n'.join(re.sub(r'[ \t]+',' ',line).strip(' |\t ') for line in body.splitlines())
        body=re.sub(r'\n{3,}','\n\n',body).strip()
        assert body and heading
        sections.append({'id':f's{i}','title':heading,'body':body})
    return {'code':code,'title':title,'label':'V2.0 — مسودة للمراجعة والاعتماد','content':sections}
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('leave');p.add_argument('travel');p.add_argument('--output',required=True);a=p.parse_args()
    result=[extract(a.leave,'POL-LEAVE','سياسة الإجازات والتذاكر',"//section[contains(concat(' ',normalize-space(@class),' '),' card ')]"),extract(a.travel,'POL-TRAVEL','سياسة الانتداب والنقل الوظيفي',"//section[starts-with(@id,'s')]")]
    assert len(result[0]['content'])==27 and len(result[1]['content'])==19,'Unexpected source structure'
    Path(a.output).write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print(json.dumps([{'code':x['code'],'sections':len(x['content']),'characters':sum(len(s['body']) for s in x['content'])} for x in result],ensure_ascii=False))
