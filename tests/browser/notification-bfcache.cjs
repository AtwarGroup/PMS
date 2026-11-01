const { chromium } = require('@playwright/test');
const { readFileSync } = require('node:fs');
const assert = require('node:assert/strict');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  try {
    await page.route('**/*', route => route.fulfill({ status: 200, contentType: 'text/html', body: '<!doctype html><html><head></head><body></body></html>' }));
    await page.goto('http://127.0.0.1/communication/');
    await page.evaluate(() => {
      window.counts = { reads: 0, starts: 0, stops: 0 };
      const originalSetInterval = window.setInterval.bind(window);
      const originalClearInterval = window.clearInterval.bind(window);
      const timers = new Set();
      window.setInterval = (fn, ms) => { const id = originalSetInterval(fn, ms); if (ms === 30000) { timers.add(id); window.counts.starts++; } return id; };
      window.clearInterval = id => { if (timers.delete(id)) window.counts.stops++; originalClearInterval(id); };
      const sb = { auth: { getSession: async () => ({ data: { session: { user: { id: 'u1' } } } }) },
        from: () => ({ select() { return this; }, order() { return this; }, limit() { window.counts.reads++; return Promise.resolve({ data: [], error: null }); } }),
        rpc: async name => { if(name==='notification_overview'){window.counts.reads++;return {data:{total_unread:0,modules:{},items:[]}};}return {data:true}; } };
      window.atwarGetSupabase = async () => sb;
      document.body.innerHTML = '<div id="header"><button data-global-notification-button></button><div data-global-notification-panel><div data-global-notification-list></div></div><span data-global-notification-badge></span></div>';
    });
    await page.addScriptTag({ content: readFileSync('assets/js/shell-components.js', 'utf8') });
    await page.evaluate(async () => { await window.atwarInitGlobalNotifications(document.querySelector('#header')); });
    await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true })));
    await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true })));
    await page.waitForFunction(() => window.counts.reads === 2);
    let counts = await page.evaluate(() => window.counts);
    assert.equal(counts.starts, 2, 'notification refresh timer is restarted');
    assert.equal(counts.stops, 1, 'old timer is stopped before restart');
    await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true })));
    counts = await page.evaluate(() => window.counts);
    assert.equal(counts.starts, 2, 'repeated pageshow does not duplicate timers');
    await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide', { persisted: false })));
    counts = await page.evaluate(() => window.counts);
    assert.equal(counts.stops, 2, 'final navigation stops the restarted timer');
    console.log('notification bfcache lifecycle passed');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
