// Code node "Build feed": uses the functions from lib.js (pasted above this code by build.js).
// Input: the HTTP Request result. Output: { status, contentType, body, failed }.

const ctx = $('Config').first().json;
const store = $getWorkflowStaticData('global');
store.cache = store.cache || {};

const RSS_TYPE = 'application/rss+xml; charset=utf-8';

// Failure: send the old XML if we have one (even if stale), else 502.
function fail(reason) {
  console.log(`[heide] ${ctx.feed}: ${reason}`);
  const stale = store.cache[ctx.cacheKey];
  if (stale) return [{ json: { failed: true, reason, status: 200, contentType: RSS_TYPE, body: stale.xml } }];
  return [{ json: { failed: true, reason, status: 502, contentType: 'text/plain; charset=utf-8', body: `Could not read the source page: ${reason}\n` } }];
}

const res = $input.first().json;
if (res.statusCode !== 200) return fail(`source answered HTTP ${res.statusCode}`);

let items, warnings;
try {
  ({ items, warnings } = parseItems(String(res.body ?? res.data ?? '')));
} catch (e) {
  return fail(`parse error: ${e.message}`);
}
if (items.length === 0) return fail('no items found, page layout may have changed');
for (const w of warnings) console.log(`[heide] ${ctx.feed}: ${w}`);

const now = new Date();
for (const i of items) i.pubDate = i.date;

const xml = buildRss({
  feedUrl: ctx.feedUrl,
  channel: { title: ctx.cfg.title, link: ctx.cfg.url, description: ctx.cfg.description },
  items,
  now,
});

store.cache[ctx.cacheKey] = { timestamp: now.getTime(), xml };

return [{ json: { failed: false, status: 200, contentType: RSS_TYPE, body: xml } }];
