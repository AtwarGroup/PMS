import {readFileSync} from 'node:fs';
// Restore missing role identities only. Existing target service/login credentials stay target-owned.
const source=readFileSync(process.argv[2],'utf8');
const roles=[...source.matchAll(/^CREATE ROLE ("(?:[^"]|"")*"|[a-zA-Z_][a-zA-Z0-9_]*);$/gm)].map(m=>m[1]);
if(!roles.length)throw Error('Backup role inventory is missing');
for(const quoted of roles){
 const name=quoted.startsWith('"')?quoted.slice(1,-1).replaceAll('""','"'):quoted;
 if(name==='postgres'||name.startsWith('pg_'))continue;
 console.log(`DO $roles$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='${name.replaceAll("'","''")}') THEN CREATE ROLE ${quoted} NOLOGIN; END IF; END $roles$;`);
}
// Membership grants are independent of database ACLs and are part of pg_dumpall roles.
for(const line of source.split('\n').filter(line=>line.startsWith('GRANT '))){
 if(!/^GRANT [^;]+ TO [^;]+;$/.test(line))throw Error('Unrecognized role membership statement');
 console.log(line);
}
