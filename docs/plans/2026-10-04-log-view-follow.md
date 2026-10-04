# Log view with follow — implementation plan

Date: 2026-10-04. Status: implemented 2026-10-04 with all three decisions as recommended.

## Glossary

- **Log view** — a scrolling, chronological list of log lines from one source, oldest at the top and newest at the bottom. The `/console` list and the System journal are log views.
- **Live edge** — the bottom of a log view, where new lines arrive.
- **Following** — the state in which the log view keeps the live edge in sight as lines arrive.
- **Held** — the state in which the log view stays where the reader scrolled while lines keep arriving below; nothing is dropped.
- **Jump to latest** — the control shown while held. It reads "N new lines", and pressing it scrolls to the live edge and resumes following.
- **Log preview** — the last 15 lines of a subsystem's log on its Status drill-in. It does not scroll and links to the console for anything more.
- **Console scope** — `/console?subsystem=<name>`: for this visit only, the console's filter is set to that subsystem's components.

## Core idea

A log view is a chronological window onto a filtered log source. It either follows the live edge or holds the reader's place. The browser owns which of the two it is in, because the decision is about the viewport alone. Status shows a preview and hands off to the console, which is the one surface built for reading logs.

## What exists, and what is wrong with it

1. **The console's order is mixed.** The first paint streams the history oldest-first (`stream(:entries, Enum.reverse(visible))`). Live lines are inserted at position 0, the top. A live probe of the dev server confirmed ascending ids on first paint. The list therefore reads oldest→newest, and then newer lines appear above it.
2. **Follow pins to the wrong end.** `LogTail` assumes newest-at-top and pins `scrollTop = 0`, which in the first-painted history is the oldest line.
3. **Pause drops lines.** `Logic.should_insert_entry?(_, true, _)` returns false, so lines that arrive while paused never reach the stream. Resuming leaves a gap.
4. **Follow is inferred from scroll position only.** It re-pins on child-list mutations and on `updated()`, but not when row heights change: text search hides rows, lines wrap, the window resizes. A follow that misses height changes drifts off the live edge.
5. **Status logs run newest-first** (both the ring panel and the journal), the opposite of the console's history and of `tail`.
6. **Status cannot reach the console.** `/console` is URL-only, and its filter is global and persisted (`Console.update_filter` broadcasts `:filter_changed` to every viewer).

## Design

### Order: chronological everywhere

Every log surface reads oldest at the top and newest at the bottom: the console, the journal and the preview. A new line is appended at the live edge, below what the reader is looking at. This is what makes holding possible without a server pause, because appending below the viewport does not move the lines in view.

### The follow behaviour (one hook, `LogFollow`, replacing `LogTail`)

DOM: a scroller element carries the hook. Inside it are the rows container (the stream container on the console) and the jump-to-latest button.

- **Starts following.** The first paint pins to the live edge.
- **Pins on every height change while following.** A `ResizeObserver` on the rows container is the single trigger. It catches inserts, removals at the stream limit, search hiding rows, wrapping and font load. A second `ResizeObserver` on the scroller catches window resizes. `updated()` and the child-list observer stop being pin triggers.
- **Leaves following only on the reader's own scroll.** On a `scroll` event, if the distance from the live edge is beyond a threshold (24px) and the scroll was not one the hook issued, the view is held. The hook records the `scrollTop` it set, so its own pins never count as reader intent.
- **Resumes following when the reader returns to the live edge**, by scrolling, by the End key (the browser's own End), or by pressing jump to latest.
- **While held, counts arrivals.** A child-list observer adds the number of rows added. The button reads "1 new line" or "N new lines" with a down-chevron, and it is hidden while following. A stream reset (a filter change) clears the count.
- **The held position survives trimming.** When the stream limit removes the oldest rows above the viewport, CSS scroll anchoring (`overflow-anchor`, Chromium's default) keeps the reader's lines in place. The rows container must not opt out.

Server-side pause is removed: the `paused` assign, the `toggle_pause` event, the footer button, `View.pause_button_label/1`, and the `paused` argument of `Logic.should_insert_entry?/3`, which becomes `Filter.matches?/2` at the call site. Holding replaces it and loses nothing.

### Component: `log_view/1` in `ConsoleComponents`

It renders the scroller (hook), the rows and the jump button. It takes either a stream (`stream`, the console) or a list (`lines`, the journal), plus `show_component` and `show_timestamp`, which pass through to `log_line/1`. A story covers the list form with a few entries, and the stream form is exercised by the console tests. `log_list/1` is removed and the console renders `log_view/1`.

### Console

- The stream inserts at -1 (the live edge) with `limit: -whole_store_limit` (keeps the newest). The history paint stays oldest-first, as today.
- **Console scope.** `handle_params` reads `subsystem`. When it names a board subsystem, the filter assign is `HealthBoard.log_filter(subsystem)`. It is held by this LiveView only: it is not persisted, `:filter_changed` broadcasts are ignored, and chip and level edits update the local filter and re-read the stream. Without the parameter, the console behaves as today and edits the saved filter. An unknown subsystem falls through to the unscoped console. Which owner applies is decided by a pure function in `ConsolePageLive.Logic`.
- While scoped, the header shows the scope ("Library logs") with a "Show all logs" link (patch to `/console`) and a "Status" link back to `/status?subsystem=<name>`.

### Status drill-in

- **Log preview** replaces the "Technical logs" scroll box. It shows the last 15 lines, chronological, with no inner scroll and no follow (it is always the latest 15). Below the lines, an "Open in console" link (`navigate`, `data-nav-item`) goes to `/console?subsystem=<name>`. It stays inside the collapsed "Technical logs" disclosure, in the full-width row under the body (already done).
- The live update appends matching lines and keeps the last 15. This is a pure helper: `StatusLive` currently does the reverse-and-take inline.
- **Journal** renders `log_view/1` (list form), chronological, last 200, bounded at 32rem and following. `journal_seed/1` loses its reverse.

## Decisions to confirm

1. **The console scope is per visit** and never overwrites the saved filter. The alternative is to write the subsystem filter as the saved filter: simpler, but arriving from Status would replace your own console setup.
2. **The console calls `StatusLive.HealthBoard.log_filter/1`**, a web-layer call from one LiveView into another's module. The subsystem→components mapping is the board's concept, so it stays there rather than moving into `Console`.
3. **The journal is not a console source.** It stays the System drill-in's follow-enabled log view. Folding `JournalSource` into the console's sources is a separate change, which this plan does not schedule.

## Test plan (test-first)

- **Bun (`log_follow.test.js`, replacing `log_tail.test.js`):** pins on growth while following; a reader scroll beyond the threshold holds; the hook's own pin does not hold; arrivals while held are counted and the button shows; scrolling to the edge resumes and clears the count; the button resumes; a height change from search while following re-pins.
- **`ConsolePageLive.Logic`:** scope resolution (known subsystem → scoped filter; unknown or absent → unscoped). Remove the pause cases from `should_insert_entry?`.
- **`console_page_live_test.exs`:** `?subsystem=library` shows only library lines; a chip toggle while scoped leaves `Console.get_filter/0` unchanged; a live line is appended after existing rows (order); the pause tests go.
- **Status:** the pure tail helper keeps the last N in order; `status_live_test` asserts the preview's "Open in console" link targets the scoped URL.
- **Smoke:** `/console?subsystem=library` in `page_smoke_test.exs`.
- **Real browser:** verify with `chromium-probe` that a scrolled-up console stays put while lines arrive, the button counts them, End and the button resume, and search keeps the edge pinned while following.

## Docs

- `CLAUDE.md` Observability: `/console` is now linked from each drill-in's preview.
- Wiki `Troubleshooting.md`: replace "Type the address; nothing links to it" and describe the preview, Open in console and following.
- `ConsoleComponents` and `LogFollow` moduledocs/headers carry the behaviour contract.

## Scope cost

About one session: a hook rewrite with tests, one new component with a story, `handle_params` scope plus header on the console, the preview and journal changes on Status, pause removal, docs. The full-width move already done is kept.
