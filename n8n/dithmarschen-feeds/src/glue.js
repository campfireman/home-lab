// Code node "Build feed": uses the functions from lib.js (pasted above this code by build.js).
// Input: the HTTP Request result. Output: { status, contentType, body, failed }.

const ctx = $('Config').first().json;
const store = $getWorkflowStaticData('global');
store.cache = store.cache || {};
store.seen = store.seen || {};

const RSS_TYPE = 'application/rss+xml; charset=utf-8';

// Failure: send the old XML if we have one (even if stale), else 502.
function fail(reason) {
  console.log(`[dithmarschen] ${ctx.feed}: ${reason}`);
  const stale = store.cache[ctx.cacheKey];
  if (stale) return [{ json: { failed: true, reason, status: 200, contentType: RSS_TYPE, body: stale.xml } }];
  return [{ json: { failed: true, reason, status: 502, contentType: 'text/plain; charset=utf-8', body: `Could not read the source page: ${reason}\n` } }];
}

const res = $input.first().json;
if (res.statusCode !== 200) return fail(`source answered HTTP ${res.statusCode}`);

let items, warnings;
try {
  ({ items, warnings } = parseItems(String(res.body ?? res.data ?? ''), ctx.cfg));
} catch (e) {
  return fail(`parse error: ${e.message}`);
}
if (items.length === 0) return fail('no items found, page layout may have changed');
for (const w of warnings) console.log(`[dithmarschen] ${ctx.feed}: ${w}`);

const now = new Date();

if (ctx.cfg.layout === 'event') {
  // Event date is not the publication date. Use the time we first saw the event.
  for (const i of items) {
    if (!store.seen[i.guid]) store.seen[i.guid] = now.toISOString();
    i.date = new Date(store.seen[i.guid]);
  }
  // Forget events that were not on page 1 for 60 days, so the map stays small.
  const onPage = new Set(items.map((i) => i.guid));
  for (const [guid, ts] of Object.entries(store.seen)) {
    if (!onPage.has(guid) && now - new Date(ts) > 60 * 86400000) delete store.seen[guid];
  }
  items = filterByCity(items, ctx.ort);
}

for (const i of items) i.pubDate = i.date;

const xml = buildRss({
  feedUrl: ctx.feedUrl,
  channel: { title: ctx.cfg.title, link: ctx.cfg.url, description: ctx.cfg.description },
  items,
  now,
});

store.cache[ctx.cacheKey] = { timestamp: now.getTime(), xml };
// Keep the cache small: drop the oldest entries.
const keys = Object.keys(store.cache).sort((a, b) => store.cache[a].timestamp - store.cache[b].timestamp);
for (const k of keys.slice(0, Math.max(0, keys.length - ctx.maxCacheEntries))) delete store.cache[k];

return [{ json: { failed: false, status: 200, contentType: RSS_TYPE, body: xml } }];
