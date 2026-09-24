# Strip charts and the time-series store

> Contributor guide for the request charts on Status → Connections and
> the mechanism behind them. Present-tense truth lives in the moduledocs
> named below; this page is the map. Design rationale:
> `docs/superpowers/specs/2026-09-19-strip-chart-design.md` (decisions,
> rejected alternatives, cost ledger). Decision record: ADR-070.
> Vocabulary: `docs/GLOSSARY.md` § Time series.

## What it is

A **strip chart** is N strips sharing one window, one time axis and one
synced cursor. Each strip is a name column with figures beside a short
canvas. The first tenant is the Connections drill-in: one strip per
upstream, stacked bars (failed / went out / from cache) on a count axis
and mean latency as a line on a right axis, over a window of 5m, 1h, 5h,
1d, 1w or 1mo. Frames go to the browser every ten seconds only while the
drill-in is selected and the tab is visible.

## The pieces

| Layer | Module | Owns |
|---|---|---|
| Store | `MediaCentaur.TimeSeries.Store` | Named public ETS `:set`; `add/5` counts an event into all four resolutions from the caller (atomic `update_counter` + `select_replace`); the process only sweeps (once a minute) and snapshots |
| Schema | `TimeSeries.Schema` | A tenant's counter fields, each `:sum` or `:max`, at most 8; tuple positions |
| Resolutions | `TimeSeries.Resolution` | 10 s kept 1 h · 1 min kept 6 h · 10 min kept 2 d · 1 h kept 31 d |
| Windows | `TimeSeries.Window` | The six windows: bar width, bar count, source resolution; `local_aligned?/1` for bars ≥ 20 min |
| Fold | `TimeSeries.Fold` | Rows → zero-filled columns and totals for a window; anchors wide bars on local midnight |
| Local day | `TimeSeries.LocalDay` | OS UTC offset (`:calendar.local_time/0`); the app has **no** time-zone database |
| Snapshot | `TimeSeries.Snapshot` | `{:media_centaur_time_series, 1, fields, rows}` in compressed ETF, atomic write, version/field check on read |
| Tenant | `MediaCentaur.HttpClient.Traffic` | Telemetry handler → `Store.add`; 20-slot recent ring keyed by `seq`; last outcome / last success per upstream; `series/3`, `totals/2`, `recent/1` |
| Frame | `MediaCentaurWeb.StatusLive.TrafficFrame` | Traffic series → the frame the hook draws; strip membership from `Capabilities`; figure strings; "Down since"; the TMDB slots line |
| Feed | `MediaCentaurWeb.Components.StripChart.Feed` | `attach_hook`s for `handle_params` / `handle_event` / `handle_info`: window from the URL, tick, visibility pause; **the frame contract is in this moduledoc** |
| Shell | `MediaCentaurWeb.Components.StripChart` | Card, window control, legend, footer slot, the `phx-update="ignore"` hook element; story `storybook/composites/strip_chart` |
| Hook | `assets/js/hooks/strip_chart.js` | Rows, figures and one uPlot instance per strip from frames; hover sync; sizing under the root zoom; pure helpers bun-tested in `strip_chart.test.js` |
| Renderer | `assets/vendor/uplot.js` | uPlot 1.6.32, MIT, ESM, unmodified |

Supervision: `HttpClient.Supervisor` starts `{TimeSeries.Store, name:
Traffic.Store, table: :http_traffic, …, snapshot_path: <db dir>/traffic.snapshot,
retention_policy: :request_history}` and then `Traffic`, in dev and prod
only. Under `:test` nothing is started and every read returns an empty
value; tests start their own store and tenant with unique table names and
`attach: false`.

## Adding a second tenant

1. **Declare a schema** as a module attribute: `Schema.new(started: :sum,
   failed: :sum, duration_max_ms: :max)`.
2. **Start a store** under the owning context's supervisor with a unique
   `name`, `table`, the schema, `snapshot_path: Path.join(dir,
   "<tenant>.snapshot")` (the application passes the database directory
   in as `snapshot_dir:`), and a `retention_policy:` key you declare in a
   `RetentionPolicies` provider (`mode: :external`) so the Status panel
   shows it.
3. **Count events** where they happen: `Store.add(table, @schema, key,
   System.os_time(:second), %{started: 1, …})`. Never from a GenServer
   that would serialise the hot path.
4. **Read** with `Fold.series(table, @schema, key, window, now)` and shape
   the tenant's own `series/3` from its columns.
5. **Build frames** in a pure web module (like `TrafficFrame`): `schema`
   (bar series in draw order, `bars_total_label`, optional `line`),
   `strips` with `id`, `label`, `dot`, `figures` (lines of `%{text, tone}`
   segments) and one column per key, all the same length as `t`.
6. **Attach the feed** in `mount/3`: `Feed.attach(socket, id: "…", frame:
   &MyFrame.build/1, active?: &(&1["subsystem"] == "…"))`, and render
   `<.strip_chart id="…" title="…" window={Feed.window(assigns, "…")}
   legend={…}>`.
7. **Tests**: store/fold behaviour through `Store.add` and `Fold.series`;
   the frame builder pure with injected functions; the LiveView with
   `assert_push_event(view, "strip_chart:frame", …)` (the test config
   ticks every 50 ms: `:strip_chart_tick_ms`); the widget's story for
   MC0009.

Windows and resolutions are shared by every tenant. Changing them means
editing the two tables and keeping `window_test.exs`'s invariants true:
every bar is a whole multiple of its source resolution and no window's
span exceeds its source resolution's retention.

## The browser side, and its one trap

The root element runs under CSS `zoom: var(--ui-scale)`. uPlot 1.6.32 has
no pixel-ratio option and mixes visual and layout pixels under zoom, so
the hook does three things (all in its header comment):

- reads widths from `offsetWidth`, never a bounding rect;
- `.strip-chart-plot { zoom: calc(1 / var(--ui-scale)) }` cancels the root
  zoom inside the plot cell, and `lengthsFor(scale)` multiplies every
  length handed to uPlot (heights, axis sizes, fonts) by the UI scale;
- rebuilds on `phx:ui-scale` and through a `ResizeObserver` coalesced to
  one `setSize` per frame.

Result: backing store = device pixel ratio × visual pixels, exact cursor
mapping at any scale. If a later uPlot ships `pxRatio` /
`setPxRatio`, the zoom cancel and `lengthsFor` can go and
`pxRatio: devicePixelRatio × uiScale` replaces them.

Other hook rules worth knowing before editing: zero bars are `null`
(uPlot draws a 0-height bar as an anti-aliased dash); the hover readout
rewrites figures only when `cursor.idx` changes; the figures block
reserves its rest-state height so hover never reflows the page; colors
come from the registered `--strip-chart-*` custom properties in
`assets/css/app.css`, never from JS.

## Verifying in a real browser

Dev server on `:2160`; the drill-in is `/status?subsystem=http`. Wait ~4 s
for the socket. Wrap multi-statement probes in an async IIFE.

Strips, canvases, plot alignment, hover sync, unique recent rows:

```bash
~/scripts/agents/chromium-probe 'http://localhost:2160/status?subsystem=http' '(async () => {
  await new Promise(r => setTimeout(r, 4000));
  const overs = [...document.querySelectorAll("#traffic .u-over")];
  const rows = () => [...document.querySelectorAll("#traffic .strip-chart-strip")].map(s => s.offsetHeight);
  const rest = rows();
  const o = overs[0], r = o.getBoundingClientRect();
  o.dispatchEvent(new MouseEvent("mousemove", {clientX: r.left + r.width / 2, clientY: r.top + r.height / 2, bubbles: true}));
  await new Promise(x => setTimeout(x, 80));
  const times = [...document.querySelectorAll("#traffic .strip-chart-time")].map(e => e.textContent);
  const hover = rows();
  o.dispatchEvent(new MouseEvent("mouseleave", {bubbles: true}));
  const ids = [...document.querySelectorAll("[id^=http-recent-]")].map(e => e.id);
  return JSON.stringify({canvases: document.querySelectorAll("#traffic canvas").length,
    plotHeights: overs.map(x => x.offsetHeight), times,
    rowsStable: rest.every((h, i) => h === hover[i]),
    recentUnique: new Set(ids).size === ids.length});
})()' | grep -o '{.*}'
```

Frames on the tick (a polling download client makes figures move):

```bash
~/scripts/agents/chromium-probe 'http://localhost:2160/status?subsystem=http' '(async () => {
  await new Promise(r => setTimeout(r, 4000));
  const fig = () => [...document.querySelectorAll("#traffic .strip-chart-figures")].map(e => e.textContent);
  const a = fig(); await new Promise(r => setTimeout(r, 21000)); const b = fig();
  return JSON.stringify({changed: a.some((x, i) => x !== b[i])});
})()' | grep -o '{.*}'
```

Look at it: `~/scripts/agents/page-shot --url 'http://localhost:2160/status?subsystem=http' --viewport 1920x1080 --wait-ms 4500`.
Headless has no visibility events; the hidden-tab pause and the window
control are covered by `test/media_centaur_web/live/status_live_test.exs`
("connections drill-in"). Console errors from the hook are the first
thing to check after any change: add `--with-console` to the probe.

## Operating notes

- The snapshot file is `traffic.snapshot` beside the database (every
  override TOML gets its own). It is written once a minute when a request
  happened and on clean shutdown; a crash loses at most one minute.
  Deleting it while the app is stopped empties the charts and nothing
  else. Its size shows on Status → System as **Request history**.
- Changing a tenant's schema, the snapshot tag or its version makes old
  files unreadable; the store logs one line and starts empty. That is the
  policy: observational data is never migrated (ADR-070).
- Wide bars (1d, 1w, 1mo) align to local midnight using the OS offset in
  force *now*. Across a daylight-saving change, bars before the change sit
  an hour off until the window rolls past it.
- Steam is counted but has no strip (`Upstream.panel?`). Nostr relay
  traffic is WebSocket messages, outside the HTTP seam, and has no strip.

## Cost, and what was left undone on purpose

Always on: about eight atomic ETS operations per request in the caller,
one bounded sweep and one compressed snapshot per minute. While the
drill-in is open and visible: one fold (1–2 ms) and one 8–12 KB frame per
ten seconds, six synchronous canvas redraws, nothing between frames.

Deferred with the number that would revisit each: delta frames (if a frame
exceeds ~50 KB); counting only the 10 s resolution per request with a
minute roll-up (if counting ever shows in a profile); a lazily loaded
uPlot chunk (if the app bundle's size becomes a measured problem).
The window control's options are nav items (the shared
`segmented_control/1`); in the Status drill-in, a vertical menu context,
they are walked with Down, and entering the drill-in from the tile board
lands on the chosen window rather than Close, because a segmented
control's pressed option is an active marker for focus restoration
(`docs/input-system.md`). Traced with `mc-nav-trace` on 2026-09-24; a
Right-walk would need the drill-in's context type changed in
`assets/js/input/config.js`, never an opt-out on the component.
