// Explicit isolated-project allowlist. Never accepts production as a target.
import { readFile } from 'node:fs/promises';
export async function createLiveClient() {
 const url='https://ydfefhuymtdjpzodcjfi.supabase.co';
 const key=process.env.FLEET_REVIEW_PUBLISHABLE_KEY;
 if(!key||!process.env.FLEET_REVIEW_ACCOUNTS||!process.env.FLEET_REVIEW_IDENTITIES)throw Error('Review key, private account file and identity file are required');
 const accounts=JSON.parse(await readFile(process.env.FLEET_REVIEW_ACCOUNTS,'utf8'));
 const employees=JSON.parse(await readFile(process.env.FLEET_REVIEW_IDENTITIES,'utf8'));
 const ids={},employeeIds={},tokens={};
 for(const u of accounts){const actor=u.email.split('@')[0];if(!u.email.endsWith('@fleet.atwargroup.test'))throw Error('Synthetic accounts only');
 const r=await fetch(url+'/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey:key,'Content-Type':'application/json'},body:JSON.stringify({email:u.email,password:u.password}),signal:AbortSignal.timeout(30000)});const data=await r.json();if(!r.ok)throw Error('Review sign-in failed: '+actor+' '+data.msg);tokens[actor]=data.access_token;ids[actor]=u.id;employeeIds[actor]=employees.find(e=>e.profile_id===u.id).employee_id;
 }
 const rpc=async(actor,name,args={})=>{const r=await fetch(url+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:key,Authorization:'Bearer '+tokens[actor],'Content-Type':'application/json'},body:JSON.stringify(args),signal:AbortSignal.timeout(30000)});const data=await r.json();if(!r.ok)throw Error(data.message||'RPC failed');return data;};
 return{rpc,ids,employeeIds,url,key,tokens};
}
