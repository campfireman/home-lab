# Test report

Date: 2026-10-04. Each source page was fetched one time and saved. All tests ran on the saved HTML.

## Result for each feed

| Feed | Items | Independent count | First item | Last item |
|---|---|---|---|---|
| pressemitteilungen | 12 | 12 | 2026-10-01 „Schnupperzeit“ bei der Brücke Dithmarschen im Oktober | 2026-07-30 Sommerfestival der Kulturen in Heide: Vielfalt feiern |
| bekanntmachungen | 12 | 12 | 2026-10-02 Bekanntmachung 71/2026: Öffentlich-rechtlicher Vertrag … Amt KLG Eider | 2026-10-02 Bekanntmachung 60/2026: Öffentlich-rechtlicher Vertrag über die Bildung einer Verwaltungsgemeinschaft … |
| ausschreibungen | 9 | 9 | 2026-10-02 Lieferung von neun Rollcontainern mit Beladung - Los 1 … | 2026-05-13 Raumlufttechnische Anlagen (VE4030) - ZFB … |
| terminkalender | 12 | 12 | [Wesselburen] 04.10.2026 09:00 - Flohmarkt am Kohlosseum in Wesselburen (guid 9220808) | [Brunsbüttel] 04.10.2026 16:00 - Helmut Heyen - Lööpt sik allens wedder trecht |

"Independent count" is the number of different links in the raw HTML found with `grep`, not with the parser.

First link of each feed:

- `https://www.dithmarschen.de/aktuelles/pressemitteilungen/details/news/schnupperzeit-bei-der-bruecke-dithmarschen-im-oktober-1`
- `https://www.dithmarschen.de/fileadmin/download/aktuelles/bekanntmachungen/2026/2026-71_oeffentlich-rechtlicher_vertrag_…pdf`
- `https://www.dithmarschen.de/fileadmin/download/aktuelles/ausschreibungen/2026-10-02_lieferung_von_neun_rollcontainern_…pdf`
- `https://www.dithmarschen.de/aktuelles/terminkalender/ansicht/flohmarkt-am-kohlosseum-in-wesselburen-9220808`

## Checks

| Check | Result |
|---|---|
| No date in the future (all feeds) | Pass |
| Bekanntmachungen: year of date = year in URL path (12 of 12) | Pass |
| No duplicate guid in a feed | Pass (also with `feedparser`) |
| `xmllint --noout` on the 4 feeds and on a test feed with `& < > " ' ]]>` | Pass |
| `feedparser`: `bozo = False`, entry count = item count | Pass for all 4 feeds |
| Special characters in a test feed come back unchanged through `feedparser` | Pass |
| Terminkalender city filter (`?ort=`), not case-sensitive | Pass (`WESSELBUREN` gives 1 item; `heide` gives 1 item) |
| Warnings from the parser (no `<time>`, future date, year difference) | 0 |

## Code nodes, run with stubbed n8n values

The real code of the nodes **Config** and **Build feed** was taken from the JSON file and run in Node.
n8n values (`$`, `$input`, `$getWorkflowStaticData`) were stubs.

| Case | Result |
|---|---|
| Unknown feed | HTTP 404 body, no fetch |
| Cache miss | `needsFetch`, correct URL and `feedUrl` |
| Cache hit | Same XML, no fetch |
| Source answers 503, old cache exists | Old XML with status 200, `failed = true` |
| Source answers 500, no cache | Status 502 |
| Page without items (layout change) | Handled as failure |
| `?ort=heide` | Own cache key, 1 item, first-seen times saved for all 12 events |

The workflow JSON loads, has 11 nodes and no connection to a missing node.

## Live test in n8n

The workflow was created and published in n8n with the n8n MCP server (workflow ID `ihzCQ2vIU2Q5PE2J`).
The tests ran against `https://n8n.home.arpa/webhook/dithmarschen/<feed>`.

| Check | Result |
|---|---|
| HTTP status and `Content-Type: application/rss+xml; charset=utf-8` for the 4 feeds | Pass |
| Item counts: 12 / 12 / 9 / 12 | Same as the local test |
| `xmllint --noout` and `feedparser` (`bozo = False`, no duplicate guid, no future date) | Pass |
| `atom:link rel="self"` is the webhook URL | Pass |
| Second request is answered from the cache (0.08 s, first request 1.2 s) | Pass |
| `?ort=heide` | 1 item: `[Heide] 04.10.2026 11:00 - Gottesdienst` |

**Fault found in the first live run.** The Code node sandbox of n8n has no `URL` global. All four feeds answered with HTTP 502
(`parse error: URL is not defined`). This also showed that the error path works. `absUrl()` in `src/lib.js` now uses plain string handling.
`test.js` now removes `URL` before it runs, so the same fault shows up in the local test.

## Not tested

- The stale-cache fallback and the 502 path in the live workflow. Only the stubbed test covers them.
- The unknown-feed path (HTTP 404). With one Webhook node for each feed, n8n answers an unknown path with its own 404 (JSON).
  The 404 branch in **Config** does not run in practice.
- Pages other than page 1.
- Months with a different date format in the terminkalender (events over several days). The parser reads the first
  date and time it finds. It keeps the full text in the description.
