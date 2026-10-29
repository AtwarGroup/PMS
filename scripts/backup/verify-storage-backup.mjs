import {readFile,realpath,lstat} from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

export async function digestFile(file){
 const hash=createHash('sha256');let size=0;
 for await(const chunk of createReadStream(file)){hash.update(chunk);size+=chunk.length;}
 return {size,sha256:hash.digest('hex')};
}

export async function verifyStorageBackup(directory){
 const root=await realpath(directory);
 const manifest=JSON.parse(await readFile(path.join(root,'storage-manifest.json'),'utf8'));
 if(!Array.isArray(manifest.buckets)||![undefined,1,2].includes(manifest.version))throw Error('Invalid storage backup manifest');
 if(manifest.bucketCount!==undefined&&manifest.bucketCount!==manifest.buckets.length)throw Error('Backup bucket count mismatch');
 const buckets=new Set();let objects=0,checksummedObjects=0;
 for(const bucket of manifest.buckets){
  if(!/^[a-zA-Z0-9_-]+$/.test(bucket.id)||buckets.has(bucket.id)||!Array.isArray(bucket.objects))throw Error('Unsafe or duplicate backup bucket');
  buckets.add(bucket.id);
  if(bucket.objectCount!==undefined&&bucket.objectCount!==bucket.objects.length)throw Error('Backup object count mismatch');
  const names=new Set();
  for(const object of bucket.objects){
   const parts=typeof object.object==='string'?object.object.split('/'):[];
   if(!parts.length||parts.some(p=>!p||p==='.'||p==='..'||p.includes('\\'))||names.has(object.object))throw Error('Unsafe or duplicate backup object');
   names.add(object.object);
   if(object.bucket!==undefined&&object.bucket!==bucket.id)throw Error('Backup bucket ownership mismatch');
   const file=path.resolve(root,bucket.id,...parts),resolved=await realpath(file);
   if(!resolved.startsWith(root+path.sep)||!(await lstat(file)).isFile())throw Error('Unsafe backup file');
   const digest=await digestFile(file);
   // Legacy sizes came from HTTP headers and may describe compressed/unknown lengths.
   // Only manifests with actual-byte metadata can establish content integrity.
   if(manifest.version===2||object.sha256!==undefined){
    if(!Number.isSafeInteger(object.size)||object.size<0||object.size!==digest.size)throw Error('Backup file size mismatch');
   }
   if(object.sha256!==undefined||manifest.version===2){
    if(!/^[a-f0-9]{64}$/.test(object.sha256||'')||object.sha256!==digest.sha256)throw Error('Backup file checksum mismatch');
    checksummedObjects++;
   }
   objects++;
  }
 }
 return {buckets:buckets.size,objects,checksummedObjects,legacyObjects:objects-checksummedObjects};
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const result=await verifyStorageBackup(process.argv[2]);
 console.log('Storage backup integrity verified: '+JSON.stringify(result));
}
