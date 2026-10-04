# Dithmarschen RSS feeds for n8n

dithmarschen.de has no RSS feeds. This n8n workflow reads four public list pages and gives you four RSS 2.0 feeds.
Each feed uses one webhook. All four webhooks use the same workflow.

## Feed URLs

| Feed | URL | Source page |
|---|---|---|
| Pressemitteilungen | `https://n8n.home.arpa/webhook/dithmarschen/pressemitteilungen` | `/aktuelles/pressemitteilungen` |
| Bekanntmachungen | `https://n8n.home.arpa/webhook/dithmarschen/bekanntmachungen` | `/aktuelles/bekanntmachungen` |
| Ausschreibungen | `https://n8n.home.arpa/webhook/dithmarschen/ausschreibungen` | `/aktuelles/ausschreibungen` |
| Terminkalender | `https://n8n.home.arpa/webhook/dithmarschen/terminkalender` | `/aktuelles/terminkalender` |

The terminkalender feed accepts a city filter: `.../terminkalender?ort=Heide`. The filter is not case-sensitive.
It matches part of the city name.

## Import

1. In n8n, select **Workflows**, then **Import from File**. Select `dithmarschen-feeds.n8n.json`.
2. Open the node **Config**. Check the three constants at the top (see "Settings").
3. Select **Active** (top right). The production webhooks work only when the workflow is active.
4. Open a feed URL in a browser or with `curl -i <url>`. The response must have `Content-Type: application/rss+xml`.
5. Add the feed URLs to your RSS reader.

The file has no credentials.

## The repo and n8n are two separate copies

Nothing syncs the code in this folder with the workflow in n8n. You must keep them the same by hand.

- The source is `src/*.js` in this repo. `node build.js` makes `dithmarschen-feeds.n8n.json` from it.
- n8n holds a copy of this code in two Code nodes (**Config** and **Build feed**).
  The workflow was created with the n8n MCP server (workflow ID `ihzCQ2vIU2Q5PE2J`).
  Later changes were also sent with the MCP server.
- No tool warns you when the two copies differ.

**Change the code in the repo:**

1. Edit the files in `src/`.
2. Run `node test.js <htmlDir> <outDir>` (see "Tests").
3. Run `node build.js`.
4. Put the new code in n8n. Choose one way:
   - Paste the code into the Code node in the n8n editor and save. Then make the workflow active again.
   - Import the new JSON file. An import makes a new workflow. Delete the old workflow first, or the two webhooks use the same paths.
   - Ask Claude Code to update the workflow with the n8n MCP server.

**If you change a Code node in the n8n editor,** copy the change into `src/` as well. If you do not, the next
`build.js` and import will remove your change.

**To find a difference:** open the Code node in n8n and compare it with `src/config.js` (for **Config**) and with
`src/lib.js` followed by `src/glue.js` (for **Build feed**).

## Settings

All settings are at the top of the **Config** node.

| Constant | Default | Use |
|---|---|---|
| `BASE_URL` | `https://n8n.home.arpa/webhook/dithmarschen` | Public URL of the webhooks. It goes into `atom:link rel="self"`. To change it, edit this line. |
| `USER_AGENT` | `dithmarschen-feed-bot (contact: services+bots@ture.dev)` | Sent with each request to dithmarschen.de. |
| `CACHE_MINUTES` | `45` | A feed is rebuilt at most once in this time. Within this time, n8n does not contact dithmarschen.de. |

The URLs in the table above must also match the host that n8n uses (`WEBHOOK_URL` in `terraform/n8n.tf`).

## How it works

```
Webhook <feed> -> Config -> Needs fetch? --yes-> Fetch source page -> Build feed -> Respond
                               |                                          |
                               +--no (cache hit or unknown feed)-> Respond  +-> Failed? -> Notify (wire up later)
```

- **Webhook**: one node for each feed. Path: `dithmarschen/<feed>`.
- **Config**: holds the settings and the table of feeds. It finds the feed and looks in the cache.
  A feed that is younger than `CACHE_MINUTES` goes straight to **Respond**.
- **Fetch source page**: one GET request, page 1 only.
- **Build feed**: reads the HTML, builds the RSS XML, saves it in the cache.
  If the source fails, it sends the old XML (even if it is old). If there is no old XML, it sends HTTP 502.
- **Respond**: sends status, `Content-Type` and body. All paths use this one node.
- **Notify (wire up later)**: does nothing now. Replace it with a mail, chat or push node.
  `{{ $json.reason }}` tells what failed.

To change the code, edit the files in `src/`, then run `node build.js`. This writes the JSON file again.
Do not edit the Code nodes in the JSON by hand.

## What the scripts read

| Feed | Item card | Link | Title | Date | Text |
|---|---|---|---|---|---|
| pressemitteilungen | `div.col.align-items-stretch` | `a[href*="/pressemitteilungen/details/news/"]` | `title` attribute of the link | `<time datetime>` | `[itemprop=description]` |
| bekanntmachungen | same | `a[href*="/fileadmin/download/aktuelles/bekanntmachungen/"]` (PDF) | `title` attribute | `<time datetime>` | none |
| ausschreibungen | `div.article` | `a[href*="/fileadmin/download/aktuelles/ausschreibungen/"]` (PDF) | `title` attribute | `<time datetime>` | none |
| terminkalender | `div.teaser-event` | `a[href*="/terminkalender/ansicht/"]` | `span[itemprop=headline]` | first-seen time (see below) | date line, city, organizer |

The script splits the page into cards with a plain text search. It does not use a HTML parser library.
Each card gives one item. The three links in a card (image, title, "mehr Infos") give one item.

## Limits

- **Page 1 only.** Each feed has about 10 items (9 to 12 in the test). The scripts never read other pages.
- **Ausschreibungen is not complete.** Many tenders are published only on the subreport portal.
- **Terminkalender dates.** The date of an item is the time when the workflow first saw the event.
  The event date and city are in the title: `[Heide] 04.10.2026 11:00 - Title`.
  The list is sorted by event date. An event appears in the feed when it enters the first 12 events.
  After the first run, all items on page 1 have the same date.
- **Cache and first-seen times are in n8n workflow static data.** n8n saves this data only for active workflows
  that run from a production webhook. Test runs in the editor do not keep the cache.
- **One cache entry for each `?ort=` value.** n8n keeps 30 entries and removes the oldest.
  A new `?ort=` value causes one new request to dithmarschen.de. Do not expose this webhook to the internet.
- **Layout changes.** If dithmarschen.de changes its HTML, the script finds no items. The feed then sends the old XML,
  and **Notify** gets the reason. Compare the table above with the new HTML.
- **Dates have no time.** Items use 12:00 UTC on the publication day.
- **Not tested inside n8n.** See `TEST-REPORT.md`.

## Tests

`test.js` runs the code from `src/lib.js` against saved HTML pages. It makes no network requests.

```
mkdir html
for f in pressemitteilungen bekanntmachungen ausschreibungen terminkalender; do
  curl -s -A "dithmarschen-feed-bot (contact: services+bots@ture.dev)" -o html/$f.html https://www.dithmarschen.de/aktuelles/$f
done
node test.js html out
for f in out/*.xml; do xmllint --noout $f; done
```
