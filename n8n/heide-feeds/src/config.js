// Code node "Config": settings and cache lookup.
// Change the constants below to match your setup.

const BASE_URL = 'https://n8n.home.arpa/webhook/heide'; // public URL of this workflow's webhook, no trailing slash
const USER_AGENT = 'heide-feed-bot (contact: services+bots@ture.dev)';
const CACHE_MINUTES = 45;

const FEED = {
  name: 'alle-artikel',
  url: 'https://www.heide.de/alle-artikel.html',
  title: 'Stadt Heide: Alle Artikel (inoffiziell)',
  description: 'Inoffizieller Feed. Erzeugt aus der ersten Seite der Artikelliste auf heide.de.',
};

const cacheKey = FEED.name;
const cache = $getWorkflowStaticData('global').cache || {};
const hit = cache[cacheKey];

if (hit && Date.now() - hit.timestamp < CACHE_MINUTES * 60000) {
  return [{ json: { needsFetch: false, status: 200, contentType: 'application/rss+xml; charset=utf-8', body: hit.xml } }];
}

return [{
  json: {
    needsFetch: true,
    feed: FEED.name,
    cacheKey,
    cfg: FEED,
    url: FEED.url,
    userAgent: USER_AGENT,
    feedUrl: `${BASE_URL}/${FEED.name}`,
  },
}];
