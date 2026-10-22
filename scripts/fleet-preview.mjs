// Local QA transport only. It uses synthetic fixtures and real PostgreSQL functions.
// It never reads production credentials or opens network connections to Supabase.
import http from "node:http";
import path from "node:path";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { createTestDB, ids } from "./fleet-test-db.mjs";
const root = path.resolve(fileURLToPath(new URL("../", import.meta.url)));
export async function startPreview() {
  const { db, rpc } = await createTestDB();
  let queue = Promise.resolve();
  const call = (u, n, a) => {
    const job = queue.then(() => rpc(u, n, a));
    queue = job.catch(() => {});
    return job;
  };
  await call("fleet", "fleet_vehicle_save", {
    p_id: null,
    p_revision: null,
    p_data: {
      plate: "QA 1234",
      vin: "QA-DEMO-001",
      vehicle_type: "تويوتا",
      model: "هايلكس 2025",
      city: "جدة",
      driver_id: ids.driver,
      odometer: 12500,
      active: true,
    },
    p_reason: "بيانات تجريبية معزولة",
  });
  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, "http://localhost");
      if (url.pathname === "/__qa/rpc" && req.method === "POST") {
        let body = "";
        for await (const chunk of req) {
          body += chunk;
          if (body.length > 45000000) throw Error("Payload too large");
        }
        const { actor, name, args } = JSON.parse(body);
        if (!ids[actor]) throw Error("Unknown QA actor");
        try {
          const data = await call(actor, name, args);
          res.setHeader("Content-Type", "application/json");
          res.end(JSON.stringify({ data, error: null }));
        } catch (e) {
          res.setHeader("Content-Type", "application/json");
          res.end(
            JSON.stringify({ data: null, error: { message: e.message } }),
          );
        }
        return;
      }
      if (req.method !== "GET") {
        res.writeHead(405);
        res.end();
        return;
      }
      let route = url.pathname === "/" ? "/fleet/index.html" : url.pathname;
      const runtime = `const qa=localStorage.getItem('fleetQAActor')||'driver';const uid=${JSON.stringify(ids)}[qa];const profile={id:uid,full_name:'حساب '+qa+' التجريبي',role:qa==='admin'?'admin':qa==='manager'?'manager':'employee',active:true,status:'active'};localStorage.setItem('atwarSession',JSON.stringify({...profile,name:profile.full_name,uid}));window.atwarGetCurrentProfile=async()=>({authUser:{id:uid},profile});window.ATWAR_SUPABASE_CONFIG={url:location.origin,publishableKey:"qa-public"};window.atwarGetSupabase=async()=>({auth:{getSession:async()=>({data:{session:{access_token:"qa-session",user:{id:uid}}}})},rpc:async(name,args={})=>{const r=await fetch('/__qa/rpc',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({actor:qa,name,args})});return r.json();}});`;
      if (route === "/assets/js/supabase-runtime.js") {
        res.setHeader("Content-Type", "text/javascript");
        res.end(runtime);
        return;
      }
      if (
        route === "/assets/js/supabase-config.js" ||
        route === "/assets/js/session-service.js"
      ) {
        res.setHeader("Content-Type", "text/javascript");
        res.end("// QA: no production services");
        return;
      }
      if (route === "/assets/js/communication-global.mjs") {
        res.setHeader("Content-Type", "text/javascript");
        res.end("export function startCommunicationAlerts(){}");
        return;
      }
      if (
        !route.startsWith("/assets/") &&
        !route.startsWith("/fleet/") &&
        !route.startsWith("/admin/") &&
        route !== "/favicon.svg"
      ) {
        res.writeHead(404);
        res.end();
        return;
      }
      const file = path.resolve(root, "." + decodeURIComponent(route));
      if (!file.startsWith(root + path.sep)) {
        res.writeHead(403);
        res.end();
        return;
      }
      let content = await readFile(file);
      const ext = path.extname(file);
      res.setHeader(
        "Content-Type",
        {
          ".html": "text/html; charset=utf-8",
          ".js": "text/javascript",
          ".mjs": "text/javascript",
          ".css": "text/css",
          ".svg": "image/svg+xml",
        }[ext] || "application/octet-stream",
      );
      if (ext === ".html") {
        content = content
          .toString()
          .replace(
            "<head>",
            '<head><script>const actor=new URLSearchParams(location.search).get("qa");if(actor)localStorage.setItem("fleetQAActor",actor);</script>',
          );
      }
      res.end(content);
    } catch (e) {
      res.writeHead(500);
      res.end(e.message);
    }
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  return {
    url: `http://127.0.0.1:${server.address().port}`,
    rpc: call,
    db,
    close: async () => {
      await new Promise((resolve) => server.close(resolve));
      await db.close();
    },
  };
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const app = await startPreview();
  console.log(
    "Synthetic fleet preview: " + app.url + "/fleet/index.html?qa=driver",
  );
  console.log(
    "QA roles: driver, manager, fleet, accountant, admin, outsider. Local only.",
  );
}
