# Downloads Command-Center Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `/download` into a main column (search, drafts, active pursuits) + ledger rail (history, other downloads) at `2xl`+, collapsing to today's single column below — per the approved spec `docs/superpowers/specs/2026-06-10-downloads-command-center-design.md`.

**Architecture:** One DOM, CSS-only breakpoints. A `2xl:grid` two-column wrapper with main/rail child divs; History's disclosure becomes width-dependent via responsive classes; the stale `download` nav-graph entry in the input system is rewritten to the real zones. No new assigns, events, or queries.

**Tech Stack:** Phoenix LiveView HEEx templates, Tailwind v4 (`2xl:`, `min-[2200px]:` variants), input-system config (`assets/js/input/config.js`).

**Precondition:** The working tree already contains uncommitted baseline edits (this session) to `acquisition_live.ex`, `history.ex`, `orphan_queue.ex` — `full_width`, width caps, multi-col grids. Task 1's commit deliberately includes them; do not try to separate.

**Repo policies that apply:** work directly on `main`; no Co-Authored-By lines; zero warnings; `mix precommit` before declaring done. No new unit tests — there is no new extracted logic; the `/download` smoke + `acquisition_live_test.exs` are the harness (per spec §Testing).

---

### Task 1: Two-region template restructure

**Files:**
- Modify: `lib/media_centaur_web/live/acquisition_live.ex` (render/1 template only, the region between `</header>` and `</Layouts.app>`)
- Test (existing, no edits): `test/media_centaur_web/page_smoke_test.exs`, `test/media_centaur_web/live/acquisition_live_test.exs`

- [x] **Step 1: Read the current render**

Read `acquisition_live.ex` render/1 (~lines 436–640). A formatter hook runs after edits — match `old_string`s against the file as it is on disk, not from memory.

- [x] **Step 2: Restructure the template**

Target shape for the content wrapper (keep the existing `header` element and all component attrs exactly as they are; only the wrappers/classes change):

```heex
<div class="relative z-[1] space-y-6">
  <header>
    … (unchanged)
  </header>

  <div class="space-y-6 2xl:grid 2xl:grid-cols-[minmax(0,1fr)_minmax(360px,460px)] 2xl:items-start 2xl:gap-x-8 2xl:space-y-0">
    <div class="min-w-0 space-y-6">
      <div class="max-w-4xl">
        <MediaOmnibox.media_omnibox … (unchanged) />
      </div>

      <div :if={@omnibox_mode == :release} class="max-w-4xl">
        <Search.search_zone … (unchanged) />
      </div>

      <section :if={@plan_drafts != []} data-nav-zone="drafts" class="max-w-4xl space-y-3 2xl:max-w-none">
        … heading unchanged …
        <div class="grid grid-cols-1 items-start gap-2 min-[2200px]:grid-cols-2">
          … draft rows unchanged …
        </div>
      </section>

      <p :if={!@download_client_ready} class="max-w-4xl scrim-surface …"> (unchanged) </p>

      <section :if={@paired_rows != []} data-nav-zone="pursuits" class="max-w-4xl space-y-3 2xl:max-w-none">
        … heading row unchanged …
        <div class="grid grid-cols-1 items-start gap-2 min-[2200px]:grid-cols-2">
          <PursuitRow.pursuit_row … (unchanged) />
          <.grouped_compact_rows entries={@active_compact} />
        </div>
      </section>

      <section :if={@paired_rows == [] && @loaded? && @download_client_ready} class="max-w-4xl scrim-surface …">
        (unchanged)
      </section>
    </div>

    <div class="min-w-0 space-y-6">
      <History.history_zone … (unchanged attrs)>
        <.grouped_compact_rows entries={@history_compact} />
      </History.history_zone>

      <OrphanQueue.orphan_zone items={@orphan_queue} />
    </div>
  </div>
</div>
```

Concrete deltas from what's in the tree:
1. Insert the `2xl:grid` wrapper div and the two `min-w-0 space-y-6` child divs (main: omnibox → empty-state; rail: history + orphans).
2. Search-zone wrapper: `max-w-4xl 2xl:max-w-6xl` → `max-w-4xl`.
3. Drafts grid and pursuits grid: `2xl:grid-cols-2 min-[2200px]:grid-cols-3` → `min-[2200px]:grid-cols-2`.

- [x] **Step 3: Run the page tests**

Run: `mix test test/media_centaur_web/page_smoke_test.exs test/media_centaur_web/live/acquisition_live_test.exs`
Expected: all pass, zero warnings.

- [x] **Step 4: Commit (includes the baseline edits already in tree)**

```bash
git add lib/media_centaur_web/live/acquisition_live.ex lib/media_centaur_web/live/acquisition_live/history.ex lib/media_centaur_web/live/acquisition_live/orphan_queue.ex
git commit -m "feat(downloads): full-bleed command-center layout — main column + ledger rail at 2xl+"
```

---

### Task 2: History rail semantics + orphan cap

**Files:**
- Modify: `lib/media_centaur_web/live/acquisition_live/history.ex`
- Modify: `lib/media_centaur_web/live/acquisition_live/orphan_queue.ex`
- Test (existing, no edits): same two test files as Task 1

- [x] **Step 1: Make History always-open at rail widths, disclosure below**

Replace `history_zone/1`'s template with:

```heex
<section data-nav-zone="history" class="max-w-4xl space-y-3 2xl:max-w-none">
  <%!-- Below 2xl: disclosure toggle (today's behavior). At 2xl+ the zone
        lives in the ledger rail where History IS the content — the
        toggle hides and a static heading shows instead. --%>
  <button
    type="button"
    phx-click="toggle_history"
    class="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wider text-base-content/50 hover:text-base-content/80 transition-colors 2xl:hidden"
    data-nav-item
    tabindex="0"
  >
    <.icon
      name={if @open?, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
      class="size-3.5"
    /> History
  </button>
  <h2 class="hidden text-xs font-medium uppercase tracking-wider text-base-content/50 2xl:block">
    History
  </h2>

  <div class={["flex flex-wrap items-center gap-2", !@open? && "hidden 2xl:flex"]}>
    … filter buttons and search form unchanged …
  </div>

  <section
    :if={@empty?}
    class={[
      "scrim-surface rounded-xl px-4 py-6 text-center text-sm text-base-content/40",
      !@open? && "hidden 2xl:block"
    ]}
  >
    {HistoryLogic.empty_state(@filter)}
  </section>
  <div :if={!@empty?} class={["grid grid-cols-1 gap-2", !@open? && "hidden 2xl:grid"]}>
    {render_slot(@inner_block)}
  </div>
</section>
```

Notes: the rows grid loses the multi-col variants (single column inside the narrow rail). Update the `@open?` attr doc to say it only affects sub-`2xl` widths. Update the moduledoc's zone description accordingly.

- [x] **Step 2: Drop the orphan zone's wide cap**

In `orphan_queue.ex`, section class `max-w-4xl scrim-surface rounded-xl overflow-hidden 2xl:max-w-6xl` → `max-w-4xl scrim-surface rounded-xl overflow-hidden 2xl:max-w-none`.

- [x] **Step 3: Run the page tests**

Run: `mix test test/media_centaur_web/page_smoke_test.exs test/media_centaur_web/live/acquisition_live_test.exs`
Expected: all pass. (Smoke seeds history rows, so the new always-rendered-while-closed branch is exercised.)

- [x] **Step 4: Commit**

```bash
git add lib/media_centaur_web/live/acquisition_live/history.ex lib/media_centaur_web/live/acquisition_live/orphan_queue.ex
git commit -m "feat(downloads): history is always open in the ledger rail, collapsible below 2xl"
```

---

### Task 3: Rewrite the stale download nav graph

**Files:**
- Modify: `assets/js/input/config.js` (the `navGraph.download` entry and `cursorStartPriority.download`)
- Test (existing, no edits): `bun test assets/js/input/`

- [x] **Step 1: Replace the `download` nav graph entry**

The current entry references zones that don't exist on the page (`sections`, `grid` as a generic content zone). Real zones: `omnibox`, `grid` (release-search results, conditional), `drafts` (conditional), `pursuits`, `history`, `other_downloads` (conditional). Candidate lists skip unrendered zones (same convention as `home`). Replace with:

```js
download: {
  omnibox:         { down: ["grid", "drafts", "pursuits", "history"], left: ["sidebar"], right: ["history", "other_downloads"] },
  grid:            { up: ["omnibox"], down: ["drafts", "pursuits", "history"], left: ["sidebar"], right: ["history", "other_downloads"] },
  drafts:          { up: ["grid", "omnibox"], down: ["pursuits", "history"], left: ["sidebar"], right: ["history", "other_downloads"] },
  pursuits:        { up: ["drafts", "grid", "omnibox"], down: ["history", "other_downloads"], left: ["sidebar"], right: ["history", "other_downloads"] },
  history:         { up: ["pursuits", "drafts", "grid", "omnibox"], down: ["other_downloads"], left: ["pursuits", "sidebar"] },
  other_downloads: { up: ["history"], left: ["pursuits", "sidebar"] },
  sidebar:         { right: ["pursuits", "omnibox", "history"] },
},
```

(The `right:` edges from main zones target the rail; below `2xl` they still resolve to History further down the stack — acceptable on a page that keeps the nav-WIP notice.)

- [x] **Step 2: Update cursor start priority**

```js
download:  ["pursuits", "omnibox", "sidebar"],
```

- [x] **Step 3: Run the JS suite**

Run: `bun test assets/js/input/`
Expected: all pass (config shape is consumed by `nav_graph.js`; tests catch malformed entries).

- [x] **Step 4: Commit**

```bash
git add assets/js/input/config.js
git commit -m "fix(input): rewrite stale download nav graph to the page's real zones"
```

---

### Task 4: Full verification + ship hygiene

**Files:** none new.

- [x] **Step 1: Precommit**

Run: `mix precommit`
Expected: compile (zero warnings), format, credo --strict, boundaries, deps.audit, sobelow, full test suite — all green. Known caveat: the full suite has pre-existing concurrency flakes (SQLite "Database busy"); if an unrelated file flakes, re-run that file in isolation before suspecting these changes.

- [x] **Step 2: Amend/fix anything precommit reports, re-run until green**

- [x] **Step 3: Hand verification to Shawn**

Final visual check is Shawn's, on his 4K display + a smaller window (his iex session needs `recompile`). Do NOT boot showcase/dev instances for screenshots without asking.

- [x] **Step 4: Wiki note**

The Downloads page layout changed user-visibly. Flag at ship time whether the wiki's *Using Media Centaur* downloads page needs a refreshed description/screenshot — don't mark the feature done without deciding this.
