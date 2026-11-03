import {englishDigits} from './fleet-model.mjs?v=4';
const searchKey=value=>englishDigits(value??'').toLocaleLowerCase('ar').replace(/\s+/g,'');
export function filterFleetVehicles(vehicles,{query='',city='',type='',driver='',active='',operation=''}={}){
 const key=searchKey(query);
 return vehicles.filter(v=>(!city||v.city===city)&&(!type||v.vehicle_type===type)&&(!driver||(driver==='unassigned'?!v.driver_id:v.driver_id===driver))&&(!active||String(v.active)===active)&&(!operation||(v.operational_status||'available')===operation)&&(!key||[v.plate,v.vin,v.registration_number,v.owner_identity_number,v.vehicle_type,v.model,v.city,v.driver_name].some(value=>searchKey(value).includes(key))));
}
