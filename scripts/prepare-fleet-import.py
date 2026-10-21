"""Prepare an auditable fleet import from the supplied workbook, without network or writes to a database.
Usage: python scripts/prepare-fleet-import.py workbook.xlsx employees.json output.json
Employee input is a read-only export of id, employee_code, full_name, vin, plate from the current HR master.
National IDs can be supplied for exact employee matching only; they are not retained in output. Birth dates and phone numbers are ignored. Output must stay outside the public repository.
"""
import sys,json,zipfile,xml.etree.ElementTree as ET,re,hashlib,collections,posixpath,datetime
N={'m':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
def workbook(file):
 with zipfile.ZipFile(file) as z:
  strings=[]
  if 'xl/sharedStrings.xml' in z.namelist():
   strings=[''.join(x.itertext()) for x in ET.fromstring(z.read('xl/sharedStrings.xml')).findall('m:si',N)]
  rels={x.attrib['Id']:x.attrib['Target'] for x in ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))}
  sheets={}
  for s in ET.fromstring(z.read('xl/workbook.xml')).findall('m:sheets/m:sheet',N):
   target=rels[s.attrib['{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id']]
   target=target.lstrip('/') if target.startswith('/') else posixpath.normpath('xl/'+target)
   rows=[]
   for row in ET.fromstring(z.read(target)).findall('m:sheetData/m:row',N):
    cells={}
    for c in row.findall('m:c',N):
     col=re.sub('[0-9]','',c.attrib['r']);v=c.find('m:v',N);value=v.text if v is not None else ''
     if c.attrib.get('t')=='s':value=strings[int(value)]
     elif c.attrib.get('t')=='inlineStr':value=''.join(c.find('m:is',N).itertext())
     cells[col]=value or ''
    rows.append(cells)
   sheets[s.attrib['name']]=rows
  return sheets

def identity(v):return re.sub(r'\s+','',str(v or '')).upper()
def name(v):return re.sub(r'[\s\u064b-\u065f\u0640]+','',str(v or ''))
def expiry(value):
 if not value:return None
 if re.fullmatch(r'20[0-9]{2}-[0-9]{2}-[0-9]{2}',str(value)):return str(value)
 try:
  number=float(value)
  if 36526<=number<=109574:return (datetime.date(1899,12,30)+datetime.timedelta(days=int(number))).isoformat()
 except (ValueError,TypeError,OverflowError):pass
 return None

def prepare(sheets,employees):
 drivers=collections.defaultdict(list);issues=[]
 for row in sheets.get('السائقين',[])[1:]:
  if row.get('A'):drivers[identity(row['A'])].append(row)
 sold={identity(r.get('A')) for r in sheets.get('السيارت المباعة',[])[1:] if r.get('A')}
 byname=collections.defaultdict(list);byvin=collections.defaultdict(list);byid=collections.defaultdict(list)
 for e in employees:
  byname[name(e['full_name'])].append(e)
  if e.get('residency_number'):byid[identity(e['residency_number'])].append(e)
  if e.get('vin'):byvin[identity(e['vin'])].append(e)
 rows=[];seen=set();plates=set()
 for i,row in enumerate(sheets['Sheet1'][1:],2):
  vin=identity(row.get('A'));plate=re.sub(r'\s+',' ',row.get('B','')).strip()
  if not vin and not plate:continue
  if not vin or not plate or vin in seen or identity(plate)in plates:
   issues.append({'row':i,'vin':vin,'plate':plate,'issue':'missing_or_duplicate_identity'});continue
  seen.add(vin);plates.add(identity(plate));d=drivers.get(vin,[]);assigned=None
  if len(d)>1:issues.append({'row':i,'vin':vin,'issue':'multiple_driver_rows'})
  elif d:
   if identity(d[0].get('I'))!=identity(plate):issues.append({'row':i,'vin':vin,'issue':'driver_plate_mismatch'})
   else:
    matches=byid[identity(d[0].get('B'))] if d[0].get('B') else byname[name(d[0].get('C'))]
    if len(matches)==1:assigned=matches[0]
    elif d[0].get('C') not in ['لا يوجد سائق','عند معرض الصناعية']:issues.append({'row':i,'vin':vin,'driver_name':d[0].get('C'),'issue':'driver_not_uniquely_matched_to_employee'})
  elif len(byvin[vin])==1:assigned=byvin[vin][0]
  if assigned and byvin[vin] and not any(e['id']==assigned['id'] for e in byvin[vin]):
   issues.append({'row':i,'vin':vin,'issue':'workbook_vs_current_hr_assignment_conflict'});assigned=None
  rows.append({'plate':plate,'vin':vin,'vehicle_type':row.get('D')or'غير محدد','model':' '.join(filter(None,[row.get('E'),row.get('F')])),'city':d[0].get('K','')if len(d)==1 else '', 'driver_id':assigned['id']if assigned and vin not in sold else None,'active':vin not in sold,'odometer':0})
 for vehicle in rows:
  source=next((r for r in sheets['Sheet1'][1:]if identity(r.get('A'))==vehicle['vin']),{})
  docs={'registration':expiry(source.get('J')or source.get('I')),'inspection':expiry(source.get('M')or source.get('L')),'insurance':expiry(source.get('O'))}
  driver_rows=drivers.get(vehicle['vin'],[])
  if vehicle['driver_id']and len(driver_rows)==1:docs['authorization']=expiry(driver_rows[0].get('G'))
  vehicle['documents']={key:value for key,value in docs.items()if value}
 for r in sheets.get('السيارت المباعة',[])[1:]:
  vin=identity(r.get('A'))
  if vin and vin not in seen:
   rows.append({'vin':vin,'plate':r.get('B',''),'vehicle_type':r.get('D')or'غير محدد','model':' '.join(filter(None,[r.get('E'),r.get('F')])),'city':'','driver_id':None,'active':False,'odometer':0});seen.add(vin)
 return{'rows':rows,'issues':issues,'summary':{'vehicles':len(rows),'active':sum(r['active'] for r in rows),'inactive':sum(not r['active']for r in rows),'linked':sum(bool(r['driver_id'])for r in rows),'unassigned':sum(not r['driver_id']for r in rows),'issues':len(issues)}}
if __name__=='__main__':
 source,employee_file,out=sys.argv[1:];result=prepare(workbook(source),json.load(open(employee_file)));result['source_sha256']=hashlib.sha256(open(source,'rb').read()).hexdigest();json.dump(result,open(out,'w'),ensure_ascii=False,indent=2);print(json.dumps(result['summary'],ensure_ascii=False))
