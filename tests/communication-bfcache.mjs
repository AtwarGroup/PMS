import assert from 'node:assert/strict';

const windowEvents = new EventTarget();
const documentEvents = new EventTarget();
let channels = 0, removed = 0, unsubscribed = 0, reads = 0;
const sb = {
  auth: {
    getUser: async () => ({ data: { user: { id: 'employee' } }, error: null }),
    onAuthStateChange: () => ({ data: { subscription: { unsubscribe() { unsubscribed++; } } } }),
  },
  rpc: async () => ({ data: true, error: null }),
  functions: { invoke: async () => ({ data: {}, error: null }) },
  from: () => ({ select() { return this; }, eq() { return this; }, is() { return this; }, order() { return this; }, limit() { reads++; return Promise.resolve({ data: [], error: null }); } }),
  channel: () => { channels++; return { on() { return this; }, subscribe() { return this; } }; },
  removeChannel: async () => { removed++; },
};
globalThis.window = windowEvents;
window.atwarGetSupabase = async () => sb;
globalThis.document = documentEvents;
Object.assign(document, { readyState: 'complete', hidden: false, querySelectorAll: () => [], querySelector: () => null });
const { startCommunicationAlerts } = await import('../assets/js/communication-global.mjs');
const event = (name, persisted) => Object.assign(new Event(name), { persisted });
const settle = async () => { for (let i = 0; i < 10; i++) await new Promise(resolve => setImmediate(resolve)); };
await startCommunicationAlerts();
assert.equal(channels, 1);
window.dispatchEvent(event('pagehide', true));
assert.equal(removed, 1);
assert.equal(unsubscribed, 1);
window.dispatchEvent(event('pageshow', true));
await settle();
assert.equal(channels, 2, 'restoring a cached page reconnects alerts');
assert.equal(reads, 2, 'restoring a cached page refreshes unread notifications');
window.dispatchEvent(event('pageshow', true));
await settle();
assert.equal(channels, 2, 'restoration does not create duplicate subscriptions');
window.dispatchEvent(event('pagehide', false));
window.dispatchEvent(event('pageshow', false));
await settle();
assert.equal(channels, 2, 'normal navigation does not restart the old page');
console.log('communication bfcache restoration passed');
