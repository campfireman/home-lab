// Pure functions: parse the dithmarschen.de list pages and build RSS 2.0.
// No n8n globals are used here, so test.js can run this file in plain Node.
// build.js pastes this file into the "Build feed" Code node.

const SITE = 'https://www.dithmarschen.de';

const MONTHS = { Jan: 1, Feb: 2, 'Mär': 3, Apr: 4, Mai: 5, Jun: 6, Jul: 7, Aug: 8, Sep: 9, Okt: 10, Nov: 11, Dez: 12 };

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

// The n8n Code node sandbox has no URL global. All hrefs on these pages are absolute paths or full URLs.
function absUrl(href) {
  const h = decodeEntities(href);
  if (/^https?:\/\//.test(h)) return h;
  return h.startsWith('/') ? SITE + h : `${SITE}/${h}`;
}

function isoToDate(iso) {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d, 12, 0, 0)); // 12:00 UTC: the calendar day stays the same in Europe/Berlin
}

// Fallback only: the card shows "01" and "Okt" but no <time datetime>.
function dayMonthToDate(day, mon, year, now) {
  const month = MONTHS[mon];
  if (!month) return null;
  if (year) return new Date(Date.UTC(year, month - 1, Number(day), 12));
  let date = new Date(Date.UTC(now.getUTCFullYear(), month - 1, Number(day), 12));
  if (date > now) date = new Date(Date.UTC(now.getUTCFullYear() - 1, month - 1, Number(day), 12));
  return date;
}

// Where does each item (card) start in the page? One marker per layout.
const CARD_MARKERS = {
  news: '<div class="col align-items-stretch mb-4">',
  tender: '<div class="article articletype-',
  event: '<div class="teaser-event',
};

function splitCards(html, layout) {
  const marker = CARD_MARKERS[layout];
  const starts = [];
  for (let i = html.indexOf(marker); i !== -1; i = html.indexOf(marker, i + marker.length)) starts.push(i);
  return starts.map((start, n) => {
    let end = n + 1 < starts.length ? starts[n + 1] : html.length;
    const nav = html.indexOf('<div class="page-navigation', start);
    if (nav !== -1 && nav < end) end = nav;
    return html.slice(start, end);
  });
}

// Value of an attribute inside the first <a ...> tag that has the given href.
function anchorAttr(card, href, attr) {
  const tags = card.match(/<a\s[^>]*>/g) || [];
  for (const tag of tags) {
    if (tag.includes(`href="${href}"`)) {
      const m = tag.match(new RegExp(`\\s${attr}="([^"]*)"`));
      if (m) return decodeEntities(m[1]).trim();
    }
  }
  return null;
}

function firstMatch(card, regex) {
  const m = card.match(regex);
  return m ? m[1] : null;
}

// cfg: { layout, hrefPart, ... } from config.js. Returns items in page order.
function parseItems(html, cfg, now = new Date()) {
  const seen = new Set();
  const items = [];
  const warnings = [];

  for (const card of splitCards(html, cfg.layout)) {
    const rawHref = firstMatch(card, new RegExp(`href="([^"]*${cfg.hrefPart}[^"]*)"`));
    if (!rawHref) continue;
    const link = absUrl(rawHref);
    if (seen.has(link)) continue; // image, title and "mehr Infos" point to the same target
    seen.add(link);

    const headline = firstMatch(card, /<span itemprop="headline">([\s\S]*?)<\/span>/);
    const title = anchorAttr(card, rawHref, 'title') || (headline ? text(headline) : link);

    const item = { title, link, guid: link, guidIsLink: true, description: '', date: null, city: null };

    if (cfg.layout === 'event') {
      parseEventFields(card, item, rawHref);
    } else {
      const iso = firstMatch(card, /<time datetime="(\d{4}-\d{2}-\d{2})"/);
      if (iso) {
        item.date = isoToDate(iso);
      } else {
        const day = firstMatch(card, /card-date-day[^>]*>(\d{1,2})</);
        const mon = firstMatch(card, /card-date-month[^>]*>([^<]+)</);
        const pathYear = firstMatch(link, /\/(\d{4})\//);
        if (day && mon) item.date = dayMonthToDate(day, mon.trim(), cfg.layout === 'news' && cfg.yearFromPath ? Number(pathYear) : null, now);
        warnings.push(`no <time datetime> for ${link}, used fallback`);
      }
      const desc = firstMatch(card, /<div itemprop="description">([\s\S]*?)<\/div>/);
      if (desc) {
        let d = text(desc);
        if (d.startsWith(title)) d = d.slice(title.length).trim(); // some teasers repeat the title
        item.description = d;
      }
      if (item.date && item.date.getTime() > now.getTime() + 86400000) warnings.push(`date in the future: ${link}`);
      if (cfg.yearFromPath) {
        const pathYear = firstMatch(link, /\/(\d{4})\//);
        if (item.date && pathYear && item.date.getUTCFullYear() !== Number(pathYear)) {
          warnings.push(`year differs from URL year (${pathYear}): ${link}`);
        }
      }
    }
    items.push(item);
  }
  return { items, warnings };
}

function parseEventFields(card, item, rawHref) {
  const id = firstMatch(rawHref, /-(\d+)$/);
  if (id) {
    item.guid = id;
    item.guidIsLink = false;
  }
  const headline = firstMatch(card, /<span itemprop="headline">([\s\S]*?)<\/span>/);
  const name = headline ? text(headline) : item.title;
  item.city = text(firstMatch(card, /<span class="card-place[^>]*>([\s\S]*?)<\/span>/) || '');
  const organizer = text(firstMatch(card, /<p class="organizer[^>]*>([\s\S]*?)<\/p>/) || '');
  const when = text(firstMatch(card, /<div class="card-body">([\s\S]*?)<\/div>/) || ''); // "Sonntag, 04.10.2026 09:00 Uhr - 13:00 Uhr"
  const day = when.match(/(\d{2})\.(\d{2})\.(\d{4})/);
  const time = when.match(/(\d{2}:\d{2}) Uhr/);
  const dateText = day ? `${day[1]}.${day[2]}.${day[3]}` : '';
  item.title = [item.city ? `[${item.city}]` : '', dateText, time ? time[1] : '', ].filter(Boolean).join(' ') + ` - ${name}`;
  item.description = [`Wann: ${when || 'unbekannt'}`, item.city ? `Ort: ${item.city}` : '', organizer ? `Veranstalter: ${organizer}` : '']
    .filter(Boolean).join('. ');
}

function filterByCity(items, ort) {
  const wanted = (ort || '').trim().toLowerCase();
  if (!wanted) return items;
  return items.filter((i) => (i.city || '').toLowerCase().includes(wanted));
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
  module.exports = { parseItems, buildRss, filterByCity, escapeXml, cdata, text, dayMonthToDate };
}
