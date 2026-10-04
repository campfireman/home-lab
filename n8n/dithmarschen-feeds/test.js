// Runs the parsing and RSS code from src/lib.js against saved HTML pages.
// Run: node test.js <dir with <feed>.html files> <output dir for XML files>
// It makes no network requests. Save the pages first, for example with curl.

// The n8n Code node sandbox has no URL global. Remove it here so the test fails the same way.
delete globalThis.URL;

const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { parseItems, buildRss, filterByCity } = require('./src/lib.js');

const [htmlDir, outDir] = process.argv.slice(2);
if (!htmlDir || !outDir) {
  console.error('usage: node test.js <htmlDir> <outDir>');
  process.exit(2);
}
fs.mkdirSync(outDir, { recursive: true });

// Take the feed settings from config.js, so the test uses the same selectors as n8n.
const configSource = fs.readFileSync(path.join(__dirname, 'src', 'config.js'), 'utf8');
const feedsSource = configSource.match(/const FEEDS = \{[\s\S]*?\n\};/)[0];
const FEEDS = new Function(`${feedsSource}; return FEEDS;`)();

const now = new Date();
const fmt = (d) => (d ? d.toISOString().slice(0, 10) : 'none');
let failures = 0;

for (const [feed, cfg] of Object.entries(FEEDS)) {
  const html = fs.readFileSync(path.join(htmlDir, `${feed}.html`), 'utf8');
  const { items, warnings } = parseItems(html, cfg, now);

  // Same step as glue.js for events: the first-seen time is "now".
  if (cfg.layout === 'event') for (const i of items) i.date = now;
  for (const i of items) i.pubDate = i.date;

  console.log(`\n=== ${feed}: ${items.length} items, ${warnings.length} warnings`);
  for (const w of warnings) console.log(`  warning: ${w}`);
  for (const i of items.slice(0, 3)) {
    console.log(`  - [${fmt(i.date)}] ${i.title}\n    ${i.link}\n    guid=${i.guid} desc=${JSON.stringify(i.description.slice(0, 80))}`);
  }
  const last = items[items.length - 1];
  console.log(`  last: [${fmt(last.date)}] ${last.title}\n    ${last.link}`);

  try {
    assert(items.length >= 5, 'fewer than 5 items');
    assert.strictEqual(new Set(items.map((i) => i.guid)).size, items.length, 'duplicate guid');
    assert(items.every((i) => i.title && i.link.startsWith('https://www.dithmarschen.de/')), 'missing title or bad link');
    assert(items.every((i) => i.date && i.date <= now), 'missing or future date');
    assert.strictEqual(warnings.length, 0, 'warnings present');
    if (cfg.yearFromPath) {
      assert(items.every((i) => String(i.date.getUTCFullYear()) === i.link.match(/\/(\d{4})\//)[1]), 'year differs from URL year');
    }
  } catch (e) {
    failures++;
    console.log(`  FAIL: ${e.message}`);
  }

  const xml = buildRss({
    feedUrl: `https://n8n.home.arpa/webhook/dithmarschen/${feed}`,
    channel: { title: cfg.title, link: cfg.url, description: cfg.description },
    items,
    now,
  });
  fs.writeFileSync(path.join(outDir, `${feed}.xml`), xml);

  if (cfg.layout === 'event') {
    const cities = [...new Set(items.map((i) => i.city))];
    const first = items[0].city;
    const filtered = filterByCity(items, first.toUpperCase());
    console.log(`  cities on page: ${cities.join(', ')}; filter "${first.toUpperCase()}" keeps ${filtered.length}`);
    assert(filtered.length >= 1 && filtered.every((i) => i.city === first), 'city filter');
  }
}

// Escaping check: special characters must not break the XML.
const tricky = buildRss({
  feedUrl: 'https://x/?a=1&b=2',
  channel: { title: 'A & B <c> "d"', link: 'https://x', description: "it's" },
  items: [{ title: 'T & <x>', link: 'https://x/?a=1&b=2', guid: 'g', guidIsLink: false, pubDate: now, description: 'a ]]> b & <i>' }],
  now,
});
fs.writeFileSync(path.join(outDir, 'tricky.xml'), tricky);

if (failures) {
  console.log(`\n${failures} feed(s) failed`);
  process.exit(1);
}
console.log('\nall checks passed');
