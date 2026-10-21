"""Offline mapping tests; deliberately contains only synthetic identities and cars."""
import importlib.util,pathlib
spec=importlib.util.spec_from_file_location('fleet_import',pathlib.Path(__file__).with_name('prepare-fleet-import.py'));module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
sheets={'Sheet1':[{}, {'A':'VIN0001','B':'QA 123','D':'Test','E':'Model','F':'2025'},{'A':'VIN0002','B':'QA 124','D':'Test'}], 'السائقين':[{}, {'A':'VIN0001','B':'999000001','C':'Full driver name','I':'QA 123','K':'QA'}], 'السيارت المباعة':[{}, {'A':'VIN0002','B':'QA 124','D':'Test'},{'A':'VIN0003','B':'QA 125','D':'Test'}]}
employees=[{'id':'synthetic-employee','employee_code':'QA01','residency_number':'999000001','full_name':'Short display name','vin':'VIN0001'}]
r=module.prepare(sheets,employees);assert r['summary']=={'vehicles':3,'active':1,'inactive':2,'linked':1,'unassigned':2,'issues':0};assert r['rows'][0]['driver_id']=='synthetic-employee';assert all('residency_number'not in row for row in r['rows'])
employees[0]['residency_number']='different';r=module.prepare(sheets,employees);assert r['summary']['linked']==0;assert r['issues'][0]['issue']=='driver_not_uniquely_matched_to_employee'
sheets['السائقين'].append(sheets['السائقين'][1]);r=module.prepare(sheets,employees);assert r['issues'][0]['issue']=='multiple_driver_rows';assert r['rows'][0]['driver_id']is None
print('PASS: exact identity matching, differing display names, sold-only records, no identity output, unmatched and duplicate-driver cases.')
