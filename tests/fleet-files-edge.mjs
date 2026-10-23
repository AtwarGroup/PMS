import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
const require=createRequire(import.meta.url),oldFetch=globalThis.fetch,oldDeno=globalThis.Deno;
let handler,allowed=true,stored=false,completed=0,object,corrupt=false;
const id='00000000-0000-4000-8000-000000000001',bytes=Buffer.from('%PDF-1.4 storage test'),hash=createHash('sha256').update(bytes).digest('hex');
globalThis.Deno={env:{get:key=>({SUPABASE_URL:'https://edge.example.invalid',SUPABASE_ANON_KEY:'anon-key',SUPABASE_SERVICE_ROLE_KEY:'service-key'})[key]},serve:fn=>{handler=fn}};
globalThis.fetch=async(input,options={})=>{
 const url=String(input),json=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json'}});
 if(url.includes('/auth/v1/user'))return allowed?json({id:'authorized-user'}):json({message:'denied'},401);
 if(url.includes('/rpc/fleet_download'))return allowed?json({name:'invoice.pdf',mime:'application/pdf',stored,size:bytes.length,hash,base64:stored?null:bytes.toString('base64')}):json({message:'denied'},403);
 if(url.includes('/rpc/fleet_file_archive_complete')){completed++;stored=true;return json(null);}
 if(url.includes('/object/sign/'))return json({signedURL:'/object/sign/fleet-files/request/'+id+'?token=test'});
 if(options.method==='POST'&&url.includes('/object/')){object=Buffer.from(options.body);return json({Key:'saved'});}
 if(url.includes('/object/'))return new Response(corrupt?'corrupt':object);
 throw Error('Unexpected network '+url);
};
try{
 const result=await build({entryPoints:['supabase/functions/fleet-files/index.ts'],bundle:true,write:false,format:'esm',platform:'browser',plugins:[{name:'local-client',setup(build){build.onResolve({filter:/^https:\/\/esm.sh\/@supabase\/supabase-js/},()=>({path:require.resolve('@supabase/supabase-js')}));}}]});
 await import('data:text/javascript;base64,'+Buffer.from(result.outputFiles[0].text).toString('base64'));
 const call=(action,extra={})=>handler(new Request('https://edge.example.invalid/functions/v1/fleet-files',{method:'POST',headers:{Authorization:'Bearer synthetic', 'Content-Type':'application/json'},body:JSON.stringify({action,kind:'request',id,...extra})}));
 allowed=false;assert.equal((await call('archive')).status,401);assert.equal(completed,0);
 allowed=true;assert.equal((await call('archive',{kind:'other'})).status,400);
 corrupt=true;assert.equal((await call('archive')).status,503);assert.equal(completed,0,'Never clear source bytes when downloaded object differs');
 corrupt=false;assert.equal((await call('archive',{base64:'untrusted-client-content',path:'another-file'})).status,200);assert.equal(completed,1);assert.deepEqual(object,bytes);
 const download=await call('download');assert.equal(download.headers.get('Cache-Control'),'no-store');assert.deepEqual(Buffer.from(await download.arrayBuffer()),bytes);assert.equal(completed,1);
 allowed=false;assert.equal((await call('download')).status,401,'Stored files require a fresh authorized request after revocation');allowed=true;
 assert.equal((await call('archive')).status,200);assert.equal(completed,1,'A retry must not rearchive an already stored file');
 console.log('PASS: real SDK Edge archive/download, unauthorized/invalid rejection, checksum failure retention, server-owned bytes/path, authenticated streaming and idempotent retry');
}finally{globalThis.fetch=oldFetch;globalThis.Deno=oldDeno;}
