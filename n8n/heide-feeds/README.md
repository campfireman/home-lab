# Heide RSS feed for n8n

The RSS feed on heide.de does not work. This n8n workflow reads the public list page
`https://www.heide.de/alle-artikel.html` and gives you one RSS 2.0 feed.
It uses the same design as `../dithmarschen-feeds`.

## Feed URL

`https://n8n.home.arpa/webhook/heide/alle-artikel`

## Import

1. In n8n, select **Workflows**, then **Import from File**. Select `heide-feeds.n8n.json`.
2. Open the node **Config**. Check the constants at the top (see "Settings").
3. Select **Active** (top right). The production webhook works only when the workflow is active.
4. Run `curl -i <feed url>`. The response must have `Content-Type: application/rss+xml`.
5. Add the feed URL to your RSS reader.

The file has no credentials.

## The repo and n8n are two separate copies

Nothing syncs the code in this folder with the workflow in n8n. You must keep them the same by hand.

- The source is `src/*.js` in this repo. `node build.js` makes `heide-feeds.n8n.json` from it.
- n8n holds a copy of this code in two Code nodes (**Config** and **Build feed**).
- No tool warns you when the two copies differ.

**Change the code in the repo:**

1. Edit the files in `src/`.
2. Run `node test.js <alle-artikel.html> <outDir>` (see "Tests").
3. Run `node build.js`.
4. Put the new code in n8n. Paste it into the Code node and save, or delete the old workflow and import the new JSON file.
   An import makes a new workflow. If the old workflow stays, both use the same webhook path.

**If you change a Code node in the n8n editor,** copy the change into `src/` as well.
If you do not, the next `build.js` and import removes your change.

## Settings

All settings are at the top of the **Config** node.

| Constant | Default | Use |
|---|---|---|
| `BASE_URL` | `https://n8n.home.arpa/webhook/heide` | Public URL of the webhook. It goes into `atom:link rel="self"`. |
| `USER_AGENT` | `heide-feed-bot (contact: services+bots@ture.dev)` | Sent with each request to heide.de. |
| `CACHE_MINUTES` | `45` | The feed is rebuilt at most once in this time. Within this time, n8n does not contact heide.de. |

## How it works

```
Webhook -> Config -> Needs fetch? --yes-> Fetch source page -> Build feed -> Respond
                         |                                          |
                         +--no (cache hit)-> Respond                +-> Failed? -> Notify (wire up later)
```

- **Config**: holds the settings. A feed that is younger than `CACHE_MINUTES` goes straight to **Respond**.
- **Fetch source page**: one GET request, page 1 only.
- **Build feed**: reads the HTML, builds the RSS XML, saves it in the cache.
  If the source fails, it sends the old XML (even if it is old). If there is no old XML, it sends HTTP 502.
- **Notify (wire up later)**: does nothing now. Replace it with a mail, chat or push node.
  `{{ $json.reason }}` tells what failed.

## What the script reads

| Part | Where in the HTML |
|---|---|
| Item card | `<a itemprop="url" class="newsLink ...">` up to the next card |
| Link | `href="/artikelansicht/..."` of the card |
| Title | `<h2 class="newsTitle">` |
| Date | Three `<span class="text-small fw-bold">` tags: day, month name, year (for example `29.` `September` `2026`) |

The script cuts the page at `<ul class="f3-widget-paginator` so the last card does not include the page links.
It uses a plain text search and no HTML parser library.

## Limits

- **Page 1 only.** The page has 9 items. The script never reads other pages.
- **No item text.** The list page has no teaser text, so items have only a title, a link and a date.
- **Dates have no time.** Items use 12:00 UTC on the publication day.
- **Layout changes.** If heide.de changes its HTML, the script finds no items. The feed then sends the old XML,
  and **Notify** gets the reason. Compare the table above with the new HTML.
- **Cache is in n8n workflow static data.** n8n saves this data only for active workflows that run from a production webhook.
  Test runs in the editor do not keep the cache.
- **Not tested inside n8n.** The parser and the RSS output are tested with a saved page. The workflow JSON was not run in n8n.

## Tests

`test.js` runs the code from `src/lib.js` against a saved HTML page. It makes no network requests.

```
mkdir html
curl -s -A "heide-feed-bot (contact: services+bots@ture.dev)" -o html/alle-artikel.html https://www.heide.de/alle-artikel.html
node test.js html/alle-artikel.html out
xmllint --noout out/*.xml
```
