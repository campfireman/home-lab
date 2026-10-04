// Pure functions: parse the heide.de article list and build RSS 2.0.
// No n8n globals are used here, so test.js can run this file in plain Node.
// build.js pastes this file into the "Build feed" Code node.
// The helper functions (decodeEntities, text, escapeXml, cdata, buildRss) are copies of
// ../../dithmarschen-feeds/src/lib.js. Code nodes cannot import files.

const SITE = 'https://www.heide.de';

const MONTHS = {
  januar: 1, jan: 1, februar: 2, feb: 2, 'märz': 3, 'mär': 3, maerz: 3, april: 4, apr: 4, mai: 5,
  juni: 6, jun: 6, juli: 7, jul: 7, august: 8, aug: 8, september: 9, sep: 9,
  oktober: 10, okt: 10, november: 11, nov: 11, dezember: 12, dez: 12,
};

const NAMED_ENTITIES = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', hellip: '…', ndash: '–', mdash: '—',
  auml: 'ä', ouml: 'ö', uuml: 'ü', Auml: 'Ä', Ouml: 'Ö', Uuml: 'Ü', szlig: 'ß',
  laquo: '«', raquo: '»', bdquo: '„', ldquo: '“', rdquo: '”', lsquo: '‘', rsquo: '’',
};

function decodeEntities(s) {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) => {
    if (e[0] === '#') {
      const code = e[1].toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return String.fromCodePoint(code);
    }
    return Object.prototype.hasOwnProperty.call(NAMED_ENTITIES, e) ? NAMED_ENTITIES[e] : m;
  });
}

// Remove tags, decode entities, collapse white space.
function text(html) {
  return decodeEntities(html.replace(/<br\s*\/?>/gi, ' ').replace(/<[^>]*>/g, ' ')).replace(/\s+/g, ' ').trim();
}

// The n8n Code node sandbox has no URL global. All hrefs on this page are absolute paths.
function absUrl(href) {
  const h = decodeEntities(href);
  if (/^https?:\/\//.test(h)) return h;
  return h.startsWith('/') ? SITE + h : `${SITE}/${h}`;
}

// "29." "September" "2026" -> 12:00 UTC on that day. Returns null if a part is wrong.
function germanDate(day, monthName, year) {
  const d = parseInt(day, 10);
  const m = MONTHS[String(monthName).toLowerCase().replace(/\.$/, '')];
  const y = parseInt(year, 10);
  if (!d || !m || !y) return null;
  return new Date(Date.UTC(y, m - 1, d, 12, 0, 0)); // 12:00 UTC: the calendar day stays the same in Europe/Berlin
}

const CARD_MARKER = '<a itemprop="url" class="newsLink';

function splitCards(html) {
  const pager = html.indexOf('<ul class="f3-widget-paginator'); // the last card must not include the pager
  const page = pager === -1 ? html : html.slice(0, pager);
  const starts = [];
  for (let i = page.indexOf(CARD_MARKER); i !== -1; i = page.indexOf(CARD_MARKER, i + CARD_MARKER.length)) starts.push(i);
  return starts.map((start, n) => page.slice(start, n + 1 < starts.length ? starts[n + 1] : page.length));
}

function firstMatch(card, regex) {
  const m = card.match(regex);
  return m ? m[1] : null;
}

// Returns items in page order (newest first).
function parseItems(html, now = new Date()) {
  const seen = new Set();
  const items = [];
  const warnings = [];

  for (const card of splitCards(html)) {
    const rawHref = firstMatch(card, /href="(\/artikelansicht\/[^"]*)"/);
    if (!rawHref) continue;
    const link = absUrl(rawHref);
    if (seen.has(link)) {
      warnings.push(`duplicate link: ${link}`);
      continue;
    }
    seen.add(link);

    const headline = firstMatch(card, /<h2 class="newsTitle[^>]*>([\s\S]*?)<\/h2>/);
    const attr = firstMatch(card, /\stitle="([^"]*)"/);
    const title = headline ? text(headline)
      : attr ? decodeEntities(attr).replace(/^Den Artikel '/, '').replace(/' lesen$/, '').trim()
      : link;

    // Date: three <span> tags with "29." / "September" / "2026".
    const spans = [...card.matchAll(/<span class="text-small fw-bold[^>]*>([\s\S]*?)<\/span>/g)].map((m) => text(m[1]));
    const date = spans.length >= 3 ? germanDate(spans[0], spans[1], spans[2]) : null;
    if (!date) warnings.push(`no date for ${link}`);
    else if (date.getTime() > now.getTime() + 86400000) warnings.push(`date in the future: ${link}`);

    items.push({ title, link, guid: link, guidIsLink: true, description: '', date });
  }
  return { items, warnings };
}

// ---- RSS 2.0 ----

function stripInvalidXmlChars(s) {
  return s.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '');
}

function escapeXml(s) {
  return stripInvalidXmlChars(String(s))
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
}

function cdata(s) {
  return `<![CDATA[${stripInvalidXmlChars(String(s)).replace(/]]>/g, ']]]]><![CDATA[>')}]]>`;
}

function buildRss({ feedUrl, channel, items, now = new Date() }) {
  const out = [];
  out.push('<?xml version="1.0" encoding="UTF-8"?>');
  out.push('<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">');
  out.push('<channel>');
  out.push(`<title>${escapeXml(channel.title)}</title>`);
  out.push(`<link>${escapeXml(channel.link)}</link>`);
  out.push(`<description>${escapeXml(channel.description)}</description>`);
  out.push('<language>de</language>');
  out.push(`<lastBuildDate>${now.toUTCString()}</lastBuildDate>`);
  out.push(`<atom:link href="${escapeXml(feedUrl)}" rel="self" type="application/rss+xml"/>`);
  for (const i of items) {
    out.push('<item>');
    out.push(`<title>${escapeXml(i.title)}</title>`);
    out.push(`<link>${escapeXml(i.link)}</link>`);
    out.push(`<guid isPermaLink="${i.guidIsLink}">${escapeXml(i.guid)}</guid>`);
    if (i.pubDate) out.push(`<pubDate>${i.pubDate.toUTCString()}</pubDate>`);
    if (i.description) out.push(`<description>${cdata(i.description)}</description>`);
    out.push('</item>');
  }
  out.push('</channel>');
  out.push('</rss>');
  return out.join('\n') + '\n';
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { parseItems, buildRss, escapeXml, cdata, text, germanDate };
}
