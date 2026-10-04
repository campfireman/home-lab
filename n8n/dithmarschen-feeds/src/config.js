// Code node "Config": settings, feed lookup and cache lookup.
// Change the three constants below to match your setup.

const BASE_URL = 'https://n8n.home.arpa/webhook/dithmarschen'; // public URL of this workflow's webhook, no trailing slash
const USER_AGENT = 'dithmarschen-feed-bot (contact: services+bots@ture.dev)';
const CACHE_MINUTES = 45;
const MAX_CACHE_ENTRIES = 30; // the ?ort= value creates one cache entry per value

const FEEDS = {
  pressemitteilungen: {
    url: 'https://www.dithmarschen.de/aktuelles/pressemitteilungen',
    layout: 'news',
    hrefPart: '/pressemitteilungen/details/news/',
    title: 'Kreis Dithmarschen: Pressemitteilungen (inoffiziell)',
    description: 'Inoffizieller Feed. Erzeugt aus der ersten Seite der Pressemitteilungen auf dithmarschen.de.',
  },
  bekanntmachungen: {
    url: 'https://www.dithmarschen.de/aktuelles/bekanntmachungen',
    layout: 'news',
    hrefPart: '/fileadmin/download/aktuelles/bekanntmachungen/',
    yearFromPath: true,
    title: 'Kreis Dithmarschen: Bekanntmachungen (inoffiziell)',
    description: 'Inoffizieller Feed. Erzeugt aus der ersten Seite der Bekanntmachungen auf dithmarschen.de. Die Links führen direkt zu PDF-Dateien.',
  },
  ausschreibungen: {
    url: 'https://www.dithmarschen.de/aktuelles/ausschreibungen',
    layout: 'tender',
    hrefPart: '/fileadmin/download/aktuelles/ausschreibungen/',
    title: 'Kreis Dithmarschen: Ausschreibungen (inoffiziell)',
    description: 'Inoffizieller Feed. Hinweis: Viele Ausschreibungen erscheinen nur auf dem Vergabeportal subreport. Dieser Feed ist deshalb unvollständig.',
  },
  terminkalender: {
    url: 'https://www.dithmarschen.de/aktuelles/terminkalender',
    layout: 'event',
    hrefPart: '/terminkalender/ansicht/',
    title: 'Kreis Dithmarschen: Terminkalender (inoffiziell)',
    description: 'Inoffizieller Feed. Zeigt die ersten Termine der Liste auf dithmarschen.de. Das Datum der Meldung ist der Zeitpunkt, an dem der Termin zuerst in der Liste stand. Der Termin selbst steht im Titel.',
  },
};

// Each feed has its own Webhook node (path dithmarschen/<feed>). Find the one that ran.
const feed = Object.keys(FEEDS).find((key) => $(`Webhook ${key}`).isExecuted);
const ort = (($input.first().json.query || {}).ort || '').trim().slice(0, 40);
const cfg = FEEDS[feed];

if (!cfg) {
  return [{ json: { needsFetch: false, status: 404, contentType: 'text/plain; charset=utf-8', body: `Unknown feed. Use one of: ${Object.keys(FEEDS).join(', ')}\n` } }];
}

const cacheKey = feed + (ort ? `?ort=${ort.toLowerCase()}` : '');
const cache = $getWorkflowStaticData('global').cache || {};
const hit = cache[cacheKey];

if (hit && Date.now() - hit.timestamp < CACHE_MINUTES * 60000) {
  return [{ json: { needsFetch: false, status: 200, contentType: 'application/rss+xml; charset=utf-8', body: hit.xml } }];
}

return [{
  json: {
    needsFetch: true,
    feed, ort, cacheKey, cfg,
    url: cfg.url,
    userAgent: USER_AGENT,
    feedUrl: `${BASE_URL}/${feed}${ort ? `?ort=${encodeURIComponent(ort)}` : ''}`,
    maxCacheEntries: MAX_CACHE_ENTRIES,
  },
}];
