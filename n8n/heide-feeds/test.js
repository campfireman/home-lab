// Runs the parsing and RSS code from src/lib.js against a saved HTML page.
// Run: node test.js <alle-artikel.html> <output dir for XML files>
// It makes no network requests. Save the page first, for example with curl.

// The n8n Code node sandbox has no URL global. Remove it here so the test fails the same way.
delete globalThis.URL;

const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { parseItems, buildRss, germanDate } = require('./src/lib.js');

const [htmlFile, outDir] = process.argv.slice(2);
if (!htmlFile || !outDir) {
  console.error('usage: node test.js <alle-artikel.html> <outDir>');
  process.exit(2);
}
fs.mkdirSync(outDir, { recursive: true });

// Take the feed settings from config.js, so the test uses the same text as n8n.
const configSource = fs.readFileSync(path.join(__dirname, 'src', 'config.js'), 'utf8');
const feedSource = configSource.match(/const FEED = \{[\s\S]*?\n\};/)[0];
const FEED = new Function(`${feedSource}; return FEED;`)();

const now = new Date();
const fmt = (d) => (d ? d.toISOString().slice(0, 10) : 'none');
let failures = 0;

const { items, warnings } = parseItems(fs.readFileSync(htmlFile, 'utf8'), now);
for (const i of items) i.pubDate = i.date;

console.log(`=== ${items.length} items, ${warnings.length} warnings`);
for (const w of warnings) console.log(`  warning: ${w}`);
for (const i of items.slice(0, 3)) console.log(`  - [${fmt(i.date)}] ${i.title}\n    ${i.link}`);
const last = items[items.length - 1];
if (last) console.log(`  last: [${fmt(last.date)}] ${last.title}\n    ${last.link}`);

try {
  assert(items.length >= 5, 'fewer than 5 items');
  assert.strictEqual(new Set(items.map((i) => i.guid)).size, items.length, 'duplicate guid');
  assert(items.every((i) => i.title && i.link.startsWith('https://www.heide.de/artikelansicht/')), 'missing title or bad link');
  assert(items.every((i) => i.date && i.date <= now), 'missing or future date');
  assert(items.every((i, n) => n === 0 || i.date <= items[n - 1].date), 'items are not sorted newest first');
  assert.strictEqual(warnings.length, 0, 'warnings present');
} catch (e) {
  failures++;
  console.log(`  FAIL: ${e.message}`);
}

// Date parser: full names, "März" and a bad name.
try {
  assert.strictEqual(fmt(germanDate('29.', 'September', '2026')), '2026-09-29');
  assert.strictEqual(fmt(germanDate('1.', 'März', '2026')), '2026-03-01');
  assert.strictEqual(fmt(germanDate('1.', 'Mär', '2026')), '2026-03-01');
  assert.strictEqual(germanDate('1.', 'Foo', '2026'), null);
} catch (e) {
  failures++;
  console.log(`  FAIL: date parser: ${e.message}`);
}

const xml = buildRss({
  feedUrl: 'https://n8n.home.arpa/webhook/heide/alle-artikel',
  channel: { title: FEED.title, link: FEED.url, description: FEED.description },
  items,
  now,
});
fs.writeFileSync(path.join(outDir, 'alle-artikel.xml'), xml);

// Escaping check: special characters must not break the XML.
const tricky = buildRss({
  feedUrl: 'https://x/?a=1&b=2',
  channel: { title: 'A & B <c> "d"', link: 'https://x', description: "it's" },
  items: [{ title: 'T & <x>', link: 'https://x/?a=1&b=2', guid: 'g', guidIsLink: false, pubDate: now, description: 'a ]]> b & <i>' }],
  now,
});
fs.writeFileSync(path.join(outDir, 'tricky.xml'), tricky);

if (failures) {
  console.log(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log('\nall checks passed');
