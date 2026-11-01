import assert from 'node:assert/strict';
import {documentState,documentDateError,filterDocumentVehicles} from '../assets/js/fleet-document-model.mjs';
for(const [days,state] of [[46,'valid'],[45,'warning'],[16,'warning'],[15,'urgent'],[1,'urgent'],[0,'urgent'],[-1,'expired']])assert.equal(documentState({days_left:days}),state);
assert.equal(documentState(undefined),'missing');assert.equal(documentState({days_left:null}),'missing');
const data={vehicles:[{id:'a',plate:'ر ق ه 1960',driver_name:'السائق الأول'},{id:'b',plate:'XYZ 2',driver_name:null},{id:'c',plate:'ABC 3',driver_name:'السائق الأول'}],documents:[
 {vehicle_id:'a',kind:'insurance',expires_on:'2026-11-15',days_left:13},
 {vehicle_id:'a',kind:'registration',expires_on:'2027-02-01',days_left:91},
 {vehicle_id:'b',kind:'insurance',expires_on:'2026-10-31',days_left:-2},
 {vehicle_id:'b',kind:'inspection',expires_on:'2026-11-30',days_left:28},
]};
const ids=filters=>filterDocumentVehicles(data,filters).map(x=>x.vehicle.id);
assert.deepEqual(ids({}),['a','b','c']);
assert.deepEqual(ids({query:'١٩٦٠'}),['a']);assert.deepEqual(ids({query:'x y z'}),['b']);
assert.deepEqual(ids({vehicle:'a',driver:'السائق الأول'}),['a']);assert.deepEqual(ids({driver:'__unassigned__'}),['b']);
assert.deepEqual(ids({kind:'insurance',state:'expired'}),['b']);
assert.deepEqual(ids({kind:'insurance',state:'warning'}),[]);
assert.deepEqual(ids({state:'missing',kind:'insurance'}),['c']);
assert.deepEqual(ids({from:'2026-11-15',to:'2026-11-15'}),['a']);
assert.deepEqual(ids({kind:'insurance',from:'2026-11-30'}),[]);
assert.deepEqual(ids({kind:'insurance',to:'2026-10-31'}),['b']);
assert.deepEqual(ids({state:'urgent',from:'2027-01-01'}),[]);
assert.deepEqual(ids({kind:'insurance',state:'missing',from:'2026-01-01'}),[]);
assert.equal(filterDocumentVehicles(data,{})[1].state,'expired');
assert.equal(filterDocumentVehicles(data,{state:'warning'})[0].state,'warning');
assert.match(documentDateError({from:'2026-12-01',to:'2026-11-01'}),/«إلى»/);
assert.match(documentDateError({from:'2026-02-30'}),/صالح/);
assert.equal(documentDateError({from:'2028-02-29'}),'');
assert.deepEqual(ids({from:'2026-12-01',to:'2026-11-01'}),[]);
console.log('PASS document risk boundaries, inclusive/open date ranges, compound same-document filters, missing dates, plate search and vehicle/driver filters.');
