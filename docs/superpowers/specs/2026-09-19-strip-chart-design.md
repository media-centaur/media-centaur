# Strip charts for outbound requests — design

**Date:** 2026-09-19
**Status:** Design approved section by section with the owner on
2026-09-19 (decisions listed under *Decisions*). Implementation plan: to be
written after the owner has reviewed this document.

## Problem

The Connections drill-in on Status shows outbound traffic as a table of the
last fifteen minutes: one row per upstream with requests, errors, median
latency, cache hits and last success, session totals in grey, and a
collapsed list of the twenty most recent requests. It answers "what happened
just now" and nothing else. There is no way to see a scrape ramp up and
fall off, a download client drop out for five minutes at 03:00, or what a
normal week of TMDB traffic looks like. The figures behind the table live in
one process's memory, pruned at fifteen minutes, lost on restart, and the
page re-reads them every five minutes.

The owner's requirements, in their words: a low-performance-cost histogram
per upstream, one selectable window from five minutes to a month shared by
every chart, updating every ten seconds while the page is open and not at
all when it is not, data kept in a round-robin store dedicated to this use,
no added contention on the main SQLite database, an off-the-shelf renderer
if one fits, a look that belongs to the app, and a component that other
sections can adopt later.

## Glossary

Terms defined before first use. Existing project words keep their meaning;
new ones are the plain words a programmer would use.

- **Upstream** — one server the app sends requests to, as enumerated by
  `MediaCentaur.HttpClient.Upstream`: TMDB, TMDB images, Prowlarr,
  qBittorrent, SABnzbd, GitHub, Steam. Not an *integration* (see
  `docs/GLOSSARY.md` § Outbound integrations); GitHub and the image CDN are
  upstreams without being integrations.
- **Request** — one HTTP attempt that reached an upstream. A **cache hit**
  was answered from the local response cache and never went out; it is not
  a request. A request **failed** when it errored at the transport or
  answered 400 or above. Unchanged from `HttpClient.Stats`.
- **Time series** — counts of an event per upstream (or, for a future
  tenant, per some other key) laid out along time. The new context
  `MediaCentaur.TimeSeries` owns the mechanism.
- **Time bucket** — one span of time the store counts into; the span of one
  bar. Qualified as *time* bucket because `ErrorReports.Bucket` already
  names an incident group. In `MediaCentaur.TimeSeries` code, `bucket`
  alone means the time bucket.
- **Resolution** — one of the four stored bucket widths (10 s, 1 min,
  10 min, 1 h), each with its own retention. The word "tier" is not used;
  it already has two meanings in the glossary.
- **Window** — the span the viewer selects: 5m, 1h, 5h, 1d, 1w, 1mo. One
  window drives every strip on a surface.
- **Round-robin store** — the fixed-ceiling store the time series live in:
  rows older than their resolution's retention are swept, so the row count
  is bounded by construction. `MediaCentaur.TimeSeries.Store`.
- **Snapshot** — the store's on-disk copy, one file written whole,
  atomically, once a minute when anything changed. Unrelated to the
  `Cache.Worker` "snapshot" of a projection.
- **Strip** — one row of the chart surface: a name column with figures on
  the left, a short wide chart on the right, for one key (one upstream).
- **Strip chart** — the reusable surface: N strips sharing one window, one
  time axis and one synced cursor. An established term for a time-series
  recorder trace. `MediaCentaurWeb.Components.StripChart` and the `StripChart`
  JS hook.
- **Frame** — one push of data from the LiveView to the hook: the window,
  the schema, and per strip its figures and columns. The whole contract
  between server and browser.
- **Feed** — the LiveView-side lifecycle around frames: the window in the
  URL, the 10-second timer while the surface is open and the tab visible,
  the visibility pause. `MediaCentaurWeb.Components.StripChart.Feed`.
- **Tenant** — a surface that renders a strip chart from its own time
  series. The first tenant is the Connections drill-in, fed by
  **Traffic**, `MediaCentaur.HttpClient.Traffic`, the HTTP layer's record of
  requests per upstream over time. "Traffic" is the word the outbound
  integrations glossary already uses for these requests.

## Core idea

Every outbound request is one event at one seam, and the app keeps one
bounded, multi-resolution count of those events per upstream. The strip
charts, the figures beside them, and the incident assessor are all folds
over that one record. The record is durable in its own file because it is
observational data of fixed size, and the main database is not the place
for another periodic writer.

## Decisions

Taken with the owner in this order. Rejected alternatives are named so they
are not re-litigated.

1. **One chart per upstream, all live at once, one window control for all.**
   Not one chart filtered by upstream, not a window per chart.
2. **Each strip carries everything: stacked bars (failed / went out / from
   cache) on a count axis and mean latency as a thin line on a right axis.**
   Rejected: counts-only strips with latency as a header figure (fallback if
   the right axis proves noisy; the stored data is identical); two charts per
   upstream (doubles page height).
3. **Window → bucket table** below, with 30 to 84 bars per window.
   Alternatives named and declined for now: 5 s buckets for a 60-bar 5m
   view; 1-day buckets for a 30-bar 1mo view.
4. **Storage is an ETS round-robin store with a periodic snapshot file, not
   SQLite.** Rejected: a table in the main database (another writer on a
   database that already reports busy errors); a second SQLite database
   (solves contention but threads a second Repo through config, release
   migration, the test sandbox and every override TOML, for transactional
   durability and SQL this data does not need).
5. **uPlot, vendored, inside one LiveView hook.** Rejected: server-rendered
   SVG (a diff of hundreds of rects every ten seconds and no synced cursor
   or live readout); a hand-written canvas renderer (the owner would rather
   not, and nothing here needs it).
6. **Drill-in only.** The Connections tile in the grid is unchanged. A
   sparkline on the tile would make the feed run whenever Status is open and
   is out of scope.
7. **Layout: name and figures stacked in a fixed left column, chart beside
   it.** Rejected: name and figures on one line above a full-width chart.
8. **Hover swaps figures; no floating tooltips.** Hovering any strip moves a
   cursor on all of them and every strip's figures show that bucket
   (time, requests, failed, cached, mean, worst). Leaving restores the
   window totals.
9. **The table goes away.** Its figures move into each strip and follow the
   selected window. Session totals are retired; median latency is retired
   in favour of mean and worst.
10. **Names:** `Traffic` for the HTTP record, 60-second snapshot cadence,
    `TimeSeries` for the mechanism, `StripChart` for the surface.
11. **The strip chart is a reusable component with a declared frame
    contract**, and Connections is its first tenant.

## Scope

In: everything under *Design*, the retention entry, the datastore figure,
ADR-070, the wiki update, and the retirement of `HttpClient.Stats`.

Out, decided rather than forgotten:

- **Nostr relay traffic.** WebSocket messages over a persistent socket are
  not requests and bypass the HTTP seam. No strip.
- **Steam.** Counted, never listed, as today (`panel?: false`).
- **A second tenant.** The contract is designed and documented; no other
  section is wired in this work.
- **Per-chart windows, zoom, brushing, export.** None.
- **The root cause of the existing SQLite busy errors.** Separate work.
- **Keyboard and gamepad wiring for the window control.** Ships mouse-first
  like other surfaces still settling; the hardening pass adds it.

## Design

Outside in: what the viewer sees, the component that draws it, the feed
that drives it, the store underneath, and the HTTP tenant that fills it.

### 1. The Connections drill-in

The card sits where the "Outbound requests" widget sits today, the wide
column of the drill-in. It keeps the house card shell (`glass-inset`, section
header in the muted uppercase style).

**Header.** Title "Requests". Lede: "Requests are what went out; cache is
what was answered here instead. Hover a bar to read that bucket." Right of
the title, the window control: the house pick-one segmented pill with
`5m · 1h · 5h · 1d · 1w · 1mo`, the current one `aria-pressed`. Clicking
pushes a patch to `?subsystem=http&window=<w>`.

**Strips.** One per upstream that has a strip, in this fixed order: TMDB,
TMDB images, Prowlarr, qBittorrent, SABnzbd, GitHub. TMDB, TMDB images and
GitHub always have a strip. Prowlarr and each download client have one when
configured (`Capabilities`). A strip never disappears because it was quiet.

Each strip is a two-column row, `11.5rem minmax(0, 1fr)`, hairline
separators between strips:

- **Left column.** Line 1: a 6 px dot and the upstream label. The dot is the
  outcome of the upstream's most recent request in the store: success
  green, failure red, neutral when there is none. One rule for every strip
  from one record; it replaces the mix of availability and connectivity
  values the table used. Lines 2 to 4, muted, tabular numerals: the window
  totals, "189 requests · 5 failed" (failed in error red when above zero),
  "577 cached · 279 ms mean" (cached omitted for upstreams without a cache;
  a dash when there were no requests), and "ok 12 s ago". When the
  integration is down per `IntegrationAvailability`, the last line reads
  "Down since 13:02" in warning amber instead. The TMDB strip adds the
  rate-limiter budget, "28 of 30 slots free", as a fifth line while the
  limiter is running.
- **Chart.** 72 CSS px tall. Bars are counts per bucket, stacked bottom to
  top: failed (error red), went out (base-content at 0.42), from cache
  (base-content at 0.14). A thin line in primary blue is the bucket's mean
  latency on a right axis; it breaks where a bucket had no requests, and an
  isolated single-bucket value draws as a dot. Left axis: whole-number
  ticks only, two labels. Right axis: two labels in ms, switching to s at
  1000. Faint horizontal and vertical grid. The rightmost bar is the bucket
  in progress.
- **Time labels** appear once, under the bottom strip, in local time. Every
  strip reserves identical left and right gutters so all plots align to the
  pixel. Labels read clock times up to 1d and day names for 1w and 1mo.

**Hover.** A dashed vertical cursor appears on every strip at the same
bucket. Each strip's lines 2 to 4 are replaced by the bucket's time and its
figures: "13:26", "15 requests · 3 failed", "38 cached · 310 ms · 1.2 s
worst". Leaving the charts restores the totals. Nothing floats over the
chart.

**Footer.** Left: the legend, four swatches with labels (failed, went out,
from cache, mean latency). Right: the collapsed "Recent requests"
disclosure, the existing 20-line list, unchanged.

**A strip with no requests in the window** draws its axes and baseline with
no bars and its figures read "No requests in this window". It is not an
`empty_state`; the card is not empty.

### 2. The strip chart component

`MediaCentaurWeb.Components.StripChart`, function component `strip_chart/1`,
with story `storybook/composites/strip_chart.story.exs`. It is generic: it knows
nothing about upstreams.

**Attributes**

- `id` — the hook element id and the feed's key.
- `title`, `lede` — the card header.
- `window` — the current window atom; `windows` — the allowed list, default
  the six. The pills push the fixed event `strip_chart:window` with
  `phx-value-id` and `phx-value-window`; the feed handles it.
- `legend` — a list of `%{label, tone}`; drawn in the footer.
- Slot `:footer` — tenant content beside the legend (Connections puts the
  "Recent requests" disclosure here).

**Markup ownership.** The component renders the card shell, header, pills,
legend and footer slot. Inside it, one element carries `phx-hook="StripChart"`
and `phx-update="ignore"`. The hook owns everything inside that element:
the strip rows, the name columns, the figures and the canvases. LiveView
never patches them; the server changes them only by sending a frame. The
story therefore pins the shell, the pills' `aria-pressed`, the legend and
the hook wiring, and says in its doc that strips render from frames under a
live socket, the same arrangement the flash toast's auto-dismiss story has.

**The frame.** One JSON object per push, event name `strip_chart:frame`,
addressed by `id`. Columnar, fixed-length per strip, zero-filled.

```json
{
  "id": "traffic",
  "window": "1h",
  "bucket_seconds": 60,
  "from": 1789800000,
  "schema": {
    "bars": [
      {"key": "failed",   "label": "failed",     "tone": "error"},
      {"key": "went_out", "label": "went out",   "tone": "solid"},
      {"key": "cached",   "label": "from cache", "tone": "muted"}
    ],
    "bars_total_label": "requests",
    "line": {"key": "mean_ms", "worst_key": "worst_ms", "label": "mean latency", "unit": "ms"}
  },
  "strips": [
    {
      "id": "tmdb",
      "label": "TMDB",
      "dot": "ok",
      "figures": [
        [{"text": "189 requests"}, {"text": "5 failed", "tone": "error"}],
        [{"text": "577 cached"}, {"text": "279 ms mean"}],
        [{"text": "ok 12 s ago"}],
        [{"text": "28 of 30 slots free"}]
      ],
      "t": [1789800000, 1789800060],
      "failed": [0, 2], "went_out": [3, 12], "cached": [9, 31],
      "mean_ms": [180, 310], "worst_ms": [240, 1200]
    }
  ]
}
```

Rules the hook applies:

- Bars are drawn back to front as three overlapping full-height series from
  the same baseline, so the stack needs two additions per bucket and no
  cumulative bookkeeping on the server.
- Hover figures are formatted by the hook from the columns and the schema:
  the bucket's time, `bars_total_label` with the sum of the bar series,
  each bar series with its tone, then the line's mean and worst with its
  unit. Window totals are strings the server computed, because they include
  things only it knows (ok 12 s ago, Down since, slots).
- `figures` is a list of lines, each a list of segments `{text, tone}`; the
  hook joins segments with " · " and writes them as text nodes, applying the
  tone (`error`, `warning`) as a class. No HTML crosses the wire.
- A frame whose `strips` ids or order differ from the current rows rebuilds
  the rows; otherwise it updates in place.
- `line` may be absent from the schema; a tenant without a second series
  gets no right axis.

**Rendering facts.**

- One uPlot instance per strip: `width` from the container's layout width
  (`offsetWidth`, never a bounding rect, because the root runs under
  `zoom`), `height` 72, `pxRatio: devicePixelRatio × --ui-scale`, updated
  through `setPxRatio` on the `phx:ui-scale` event and on a device pixel
  ratio change. Cursor `sync.key` is the component `id`. Legend off. Bars
  via `uPlot.paths.bars` at 0.62 of the slot. Count axis `incrs` restricted
  to whole numbers. Time axis shown only on the last strip; every strip
  sets identical axis sizes so plot areas line up. Series `points.show`
  returns true only for isolated line values.
- Colors are read once at mount from registered CSS custom properties
  (`@property … { syntax: "<color>" }`, the mechanism `--ui-scale` already
  uses), so `getComputedStyle` yields resolved colors the canvas accepts:
  `--strip-chart-bar-error`, `--strip-chart-bar-solid`,
  `--strip-chart-bar-muted`, `--strip-chart-line`, `--strip-chart-grid`,
  `--strip-chart-axis-text`, `--strip-chart-cursor`. Defined in `app.css`
  from the theme tokens. No hex in JavaScript.
- A `ResizeObserver` on the hook element coalesces to one `setSize` per
  strip per animation frame. `destroyed()` disconnects it, removes the
  visibility listener and calls `destroy()` on every instance.
- The hook exposes pure helpers for bun tests: stacking, hover-figure
  formatting, the ms/s formatter, axis label selection per window, and
  the "hovered index changed" check. DOM writes stay thin.
- uPlot's base CSS (wrapper, over/under layers, cursor line) is vendored
  into `app.css` under the component's class prefix and restyled; its legend
  and tooltip CSS are not used.

**Vendoring.** `assets/vendor/uplot.js`, uPlot 1.6.32, MIT, no
dependencies, pinned with the version in a header comment as the other
vendored files are. It is reachable from `app.js` through the hook, which
satisfies the `no-unreachable-from-app` rule.

### 3. The feed

`MediaCentaurWeb.Components.StripChart.Feed` is the LiveView-side lifecycle,
written once so a tenant does not hand-write timer and visibility clauses.
It uses `attach_hook/4` for `handle_params`, `handle_info` and
`handle_event`, keyed by the component `id`.

A tenant calls, in `mount`:

```elixir
socket =
  StripChart.Feed.attach(socket,
    id: "traffic",
    frame: &TrafficFrame.build/1,
    active?: &(&1.assigns.selected_subsystem == :http)
  )
```

and the feed does the rest:

- **Window from the URL.** `handle_params` reads `window`, validates it
  against the allowed list, defaults to `1h`, and assigns
  `strip_chart_window` under the id. The tenant's pill event pushes a patch
  with the new window; the feed handles that event too.
- **Active or not.** After every `handle_params` the feed evaluates
  `active?`. Becoming active pushes one frame at once and arms a
  10-second timer; becoming inactive cancels it. The Status page is active
  for this feed only while the Connections drill-in is selected, so the
  tile grid alone costs nothing.
- **Tick.** On the timer, if still active and visible: build the frame by
  calling `frame.(window)`, `push_event` it, re-arm. The build is a pure fold
  over ETS in the page's process, low milliseconds. No assign changes, so
  LiveView renders nothing and morphdom does nothing.
- **Visibility.** The hook pushes `strip_chart:visibility` with
  `visible: true | false` on `visibilitychange` and once at mount when the
  document is hidden. Hidden cancels the timer; visible pushes a frame and
  re-arms. A reconnect after Chromium froze the tab remounts the page, which
  re-runs `handle_params` and re-enters cleanly.
- **Leaving.** Navigating away ends the process and its timer. Deselecting
  the drill-in goes through `handle_params` and cancels it.

The Status page's existing 5-minute vitals tick is unchanged and no longer
reads request figures.

### 4. The round-robin store

`MediaCentaur.TimeSeries`, a new top-level context with `deps: []`, exporting
`Store`, `Resolution`, `Window`, `Fold`, `Snapshot`.

**Row.** `{ {resolution, key, bucket_start}, counters... }` in a named ETS
`:set` with `write_concurrency: true` and `read_concurrency: true`. `key` is
an opaque term the tenant chooses (an upstream atom). `bucket_start` is
epoch seconds aligned down to the resolution width in UTC. Counters are the
integer fields the tenant declared at start; each is either summed or kept
as a maximum.

**Resolutions and retention.**

| Resolution | Kept | Rows per key at most |
|---|---|---|
| 10 s | 1 h | 360 |
| 1 min | 6 h | 360 |
| 10 min | 2 d | 288 |
| 1 h | 31 d | 744 |

**Windows.**

| Window | Bar | Bars | From resolution |
|---|---|---|---|
| 5m | 10 s | 30 | 10 s |
| 1h | 1 min | 60 | 1 min |
| 5h | 5 min | 60 | 1 min × 5 |
| 1d | 20 min | 72 | 10 min × 2 |
| 1w | 2 h | 84 | 1 h × 2 |
| 1mo | 12 h | 60 | 1 h × 12 |

**Write path.** `Store.add(table, key, counters, at)` runs in the caller:
for each of the four resolutions, one `:ets.update_counter` with a default
row for the summed fields, then one `:ets.select_replace` with a bound key
for each max field (an atomic compare-and-set on one object). About eight
ETS operations per event, each microseconds. Rows exist only for buckets
that saw an event, so an idle key costs nothing anywhere. The handler
around it never raises: a failure is logged once per boot and dropped,
because telemetry detaches a handler that raises.

**Sweep.** The owning process runs once a minute: per resolution, one
`select_delete` of rows older than the retention. The row ceiling is the
table above times the number of keys, about 12,000 for seven upstreams.
The sweep reports its pruned count to `Retention.record_run/2` under the
tenant's policy key.

**Snapshot.** Once a minute, if the store's write counter moved since the
last snapshot, the owner writes `{:media_centaur_time_series, 1, fields,
rows}` with `term_to_binary(…, compressed: 6)` to a temp file beside the
target and renames it into place. On clean shutdown it writes once more.
On boot it reads the file, checks the tag, version and field list, and
loads the rows; on mismatch or corruption it logs one line and starts
empty. Observational data is never migrated. The loss window on a hard
crash is one minute.

**Path.** `Path.dirname(database_path)/<tenant>.snapshot`, passed in by
the application supervisor as a child argument so the context needs no
dependency on Settings. Override TOMLs get their own file for free because
their database path differs.

**Fold.** `Fold.columns(table, key, window, now, local_day_start)` selects
the window's rows from the right resolution and returns zero-filled columns
per declared field, a mean per bucket for any field the tenant marks as
`sum_of: field / count_of: field`, and the window totals. Wide buckets
(20 min, 2 h, 12 h) are aligned to local midnight using the same local
conversion Console uses (`DateTime.shift_zone(dt, "localtime")`), so a 12 h
bar runs midnight to noon where the machine is. Half-hour offset zones
align to the nearest UTC hour; a bar across a DST change is an hour longer
or shorter. Both are stated in the moduledoc.

**Process.** `Store` is a GenServer that creates the table in `init`,
schedules the sweep and snapshot, and otherwise handles no traffic. Tests
start their own instances with a unique `name` and `table`, no snapshot
path, and drive `add/4` directly. Its public functions all take the table.

### 5. Traffic, the HTTP tenant

`MediaCentaur.HttpClient.Traffic` replaces `HttpClient.Stats`.

- **Recording.** A GenServer that attaches to
  `[:media_centaur, :http, :request, :stop]` (handler id from its name, as
  `Stats` does) and, in the handler, calls `Store.add` with fields
  `requests`, `failed`, `cached`, `latency_sum_ms` (summed) and
  `latency_max_ms` (max). A cache hit adds `cached: 1` and nothing else. It
  also owns the recent-requests ring: a 20-slot ETS ring keyed by
  `rem(seq, 20)` with `seq` from an ETS counter, two operations per request,
  no sweep, and the per-upstream last outcome and last success time as
  single ETS rows. `attach: false` keeps test instances off the global
  telemetry bus.
- **Reads.** `series/2` returns, for one upstream and a window, the
  columns and window totals from `Fold` plus the last outcome and last
  success time. `totals/2` returns one upstream's totals over an arbitrary
  span, which is how the incident assessor asks for fifteen minutes.
  `recent/0` returns the ring newest first. `Traffic` builds no frame: the
  frame carries strings and facts from TMDB's rate limiter, which sits
  above `HttpClient` in the Boundary graph.
- **The frame builder** is `MediaCentaurWeb.StatusLive.TrafficFrame.build/1`,
  a pure web-side module: strip membership from `Upstream.panel_ids/0` and
  `Capabilities`, series from `Traffic.series/2`, the dot from the last
  outcome, "Down since" from `IntegrationAvailability.down_since/1`, the
  slots line from `TMDB.RateLimiter.status/0`, and the figure strings. It is
  the only place that knows how a Traffic series becomes strip chart
  figures.
- **Retention entry.** `HttpClient.RetentionPolicies` declares
  `%Policy{key: :request_history, subsystem: :http, label: "Request
  history", description: "Ten-second buckets for an hour, up to hourly
  buckets for 31 days; swept continuously.", mode: :external}`. The panel
  then appears on the Connections drill-in for the first time.
- **Datastore figure.** `Runtime.Vitals` gains `db.time_series_bytes`, the
  size of every `*.snapshot` beside the database, and the System tile's
  Database figure names it.

**What changes for existing readers.**

- `HttpClient.IncidentContext`: the `:tmdb_images` share rule reads
  `Traffic.totals(:tmdb_images, minutes: 15)`; `vitals/0` reports window
  requests, failed, mean and worst latency per upstream; session figures and
  median go.
- `StatusLive`: the `http_stats` and `rate_limiter` assigns and their
  5-minute refresh go; the activity bundle for `:http` carries only what the
  shell needs (the window and the configured strip list for the story).
- `StatusWidgets.Http`: rewritten as a thin tenant of `strip_chart/1` with
  the "Recent requests" disclosure in the footer slot. Its story is rewritten
  to pin the shell.
- `HealthBoard`'s note that `:http` is a lens, not a subsystem, stands
  unchanged; this work does not resolve it.

### 6. Boundaries and supervision

- `MediaCentaur.TimeSeries`: `top_level?: true, deps: [MediaCentaur.Retention]`.
- `MediaCentaur.HttpClient`: adds `MediaCentaur.TimeSeries` to `deps`;
  exports gain `Traffic`, lose `Stats`. It does not learn about TMDB or
  Capabilities; the web-side frame builder reads those.
- `MediaCentaurWeb`: already depends on `HttpClient`; gains nothing.
- `MediaCentaur.Application`: adds `TimeSeries` to its deps list.
- `HttpClient.Supervisor` children become `Cache.Coordinator`,
  `{TimeSeries.Store, name: Traffic.Store, table: :http_traffic, fields: …,
  snapshot_path: …}`, `Traffic`. Still not started under `:test`; the sandbox
  disposition text is updated to name the store.

## Sizing and performance

Always on, page open or not:

| Path | Trigger | Cost |
|---|---|---|
| Count a request | each request, in the caller | 8 atomic ETS ops, about 10 µs; strictly cheaper than today's message per request and re-prune of an unbounded list |
| Sweep | once a minute | one bounded scan per resolution, low milliseconds |
| Snapshot | once a minute, only if a request happened | serialise about 12k rows compressed, tens of KB, one atomic write; a polling download client keeps it dirty most minutes, which is why it is compressed |
| Boot | once | read one file, insert rows, milliseconds |

Only while the Connections drill-in is selected and the tab visible:

| Path | Trigger | Cost |
|---|---|---|
| Build a frame | every 10 s | fold at most about 750 rows per upstream, 1 to 2 ms |
| Send a frame | every 10 s | one WebSocket message of 8 to 12 KB; no LiveView diff |
| Redraw | once per frame per strip | six synchronous canvas draws of a few hundred primitives, under 1 ms in total |
| Hover | mouse moves | cursor lines are DOM transforms; figures rewrite only when the hovered bucket changes |
| Resize | rare | one redraw per strip, coalesced to a frame |
| Hidden tab | `visibilitychange` | timer cancelled; nothing runs |
| Drill-in closed or page left | patch or exit | timer cancelled, six instances destroyed |

Texture memory about 1 MB at 1× pixel ratio, about 4 MB at 2×. Bundle
growth about 17 KB gzipped.

Deliberately not done, each with the number that would change it:

- **Delta frames** (send only the changed buckets): cuts wire cost from about
  1 KB/s to about 30 B/s while open. Adopt if a frame ever exceeds 50 KB.
- **Roll-up batching** (count only the 10 s resolution per request, fold
  coarser ones once a minute): saves six of the eight ETS ops per request at
  the cost of a roll-up pass and read-time patching of the current bucket.
  Adopt if request counting ever shows in a profile, which at 10 µs it will
  not.
- **Lazy-loading uPlot as a separate chunk**: needs ESM code splitting in
  the esbuild config. Adopt if the app bundle's size becomes a measured
  problem.

## Diff against the code that exists

Each incoherence and its disposition, per the unify-design rule.

- **Two folds of one event.** `Stats` (15-minute list) and the new store
  would be two representations of "requests per upstream". Disposition:
  fix now. `Stats` is deleted; every reader moves to `Traffic`.
- **Session totals.** "Since boot" is not a window a viewer can select and
  is not derivable exactly from a bounded ring. Disposition: retired, with
  the owner's approval.
- **Median latency.** Needs per-request samples, which the ring does not
  keep. Disposition: mean and worst per bucket, with the owner's approval.
- **Per-strip health from three sources.** The table mixed availability
  (TMDB, Prowlarr), nothing (images, GitHub) and a download-connectivity
  grade elsewhere. Disposition: the dot is the last outcome from the one
  record; "Down since" from availability stays as a figure because it says
  something the record cannot (held work produces no requests).
- **ADR-041, "no ETS state is authoritative for a persistent fact".** The
  store is authoritative for request history and lives outside the
  database. Disposition: ADR-070 records the exception, its reason (writer
  contention on the main database), its bounds (observational, fixed
  ceiling, one file, one-minute loss window) and the rule for future
  instances (a time series a tenant would graph goes in a `TimeSeries.Store`,
  not a table).
- **`:http` as a lens.** Unchanged; the existing scheduled convergence in
  `HealthBoard` stands.
- **First hook to handle pixel ratio and root zoom.** Contained in the
  `StripChart` hook; the rule (layout pixels in, `pxRatio` = device ratio ×
  UI scale) is written in the hook's header comment and the moduledoc.
- **Storybook cannot render a canvas.** The component's contract is its
  shell and its frame; the story pins the shell, the frame is pinned by
  ExUnit on `Traffic.frame/1` and by bun on the hook's helpers.

## Testing

- **ExUnit, `MediaCentaur.TimeSeries`.** `Store.add` lands in all four
  resolutions with the right bucket starts; sums and maxima; sweep removes
  exactly the expired rows and reports the count; snapshot round trip;
  version and field mismatch start empty; `Fold` zero-fills, sums wide
  buckets from the right resolution, aligns wide buckets to a given local
  day start, and computes means and totals. Each test starts its own store
  with a unique table.
- **ExUnit, `HttpClient.Traffic`.** A telemetry stop event with a cache
  hit counts only `cached`; a failed request counts `requests` and `failed`;
  the recent ring holds twenty newest first; `series/2` returns columns,
  totals, last outcome and last success; `totals/2` over fifteen minutes
  feeds the assessor. Driven with `attach: false`.
- **ExUnit, `StatusLive.TrafficFrame`.** Pure: the schema, the configured
  strips in order, the dot per last outcome, the "Down since" figure, the
  slots line, the "No requests in this window" figure, segment tones.
- **ExUnit, `HttpClient.IncidentContext`.** The images share rule over the
  new totals; `vitals/0` shape.
- **ExUnit, `StatusLive`.** `?subsystem=http&window=5h` sets the window
  and pushes a frame (`assert_push_event`); an invalid window falls back to
  1h; the pill event patches the URL; the timer is armed only while the
  Connections drill-in is selected; the visibility event pauses and resumes;
  the vitals tick no longer touches request figures.
- **Storybook.** `strip_chart.story.exs` (shell, pills, legend, footer
  slot) and the rewritten `http_widget.story.exs`. Both compile and render
  under the existing storybook tests; MC0009 is satisfied.
- **bun.** The hook's pure helpers: stacking, hover figure text, ms/s
  formatting, axis label choice per window, hovered-index change detection.
- **Real browser, on the dev server.** Six canvases present after opening
  the drill-in; canvas backing size equals layout size × UI scale × device
  pixel ratio at two UI scales; a frame arrives every 10 s and only while
  the drill-in is open; hover swaps figures on all six; nothing is pushed
  while the tab is hidden; leaving the drill-in destroys the instances.
  Verified with `chromium-probe` and `page-shot`, recorded in the plan.

## Documentation

- Moduledocs on `TimeSeries`, `Store`, `Fold`, `Snapshot`, `Traffic`,
  `StripChart`, `StripChart.Feed`, each carrying its contract: row shape,
  resolutions, the frame JSON, the feed lifecycle.
- ADR-070 in `decisions/architecture/`, index regenerated with
  `scripts/gen-decisions-index`.
- `docs/GLOSSARY.md`: the terms above under a new "Time series" heading,
  and "time bucket" cross-referenced from the existing *Bucket* entry.
- `docs/architecture.md`: `TimeSeries` added to the bounded contexts.
- Wiki, *Using Media Centaur → Status* page: the Connections drill-in, the
  window control, what the bars and the line mean, the snapshot file and
  its loss window under Troubleshooting.
- `docs/storybook.md` inventory: the two stories.

## Deferred by name

- Second tenant of the strip chart. Candidates the owner may name later:
  pipeline imports per bucket, image downloads, playback sessions.
- Nostr relay message counts, which would need their own recorder at the
  socket, not the HTTP seam.
- Keyboard and gamepad wiring for the window control (hardening pass).
- The three performance options above, each with its trigger.
- The SQLite busy-error root cause.
