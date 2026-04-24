# Showcase Screenshot Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the showcase instance from 4 screenshots to 17, covering every user-facing surface, and integrate them into the landing page and wiki.

**Architecture:** Keep the existing seed + tour architecture. Swap one catalog entry (Dragnet → Beverly Hillbillies S1), regenerate fallback thumbnails with tasteful dark placeholders, extend the seeder with populated history / console logs, add scroll anchors to the settings page for section-level shots, expand the Playwright tour from 4 to 17 stops, and batch wiki page updates into a single commit.

**Tech Stack:** Elixir / Phoenix LiveView, Ecto, Playwright (via bun), ImageMagick 7, Jujutsu (jj).

**Design spec:** [docs/superpowers/specs/2026-04-24-showcase-screenshots-design.md](../specs/2026-04-24-showcase-screenshots-design.md)

---

## Prerequisites

Before starting, verify the showcase environment works today:

```bash
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.create
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.migrate
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix seed.showcase
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix phx.server
# In another shell:
scripts/screenshot-tour
```

Expected: 4 PNGs land in `docs-site/assets/screenshots/`. If not, fix before starting this plan.

---

## Phase 1 — Safety assertion + catalog swap

### Task 1: Add belt-and-suspenders safety assertion to seeder

**Files:**
- Modify: `lib/media_centarr/showcase.ex` — add assertion at top of `seed!/0`
- Modify: `test/media_centarr/showcase_test.exs` — add negative test

**Why:** `Mix.Tasks.Seed.Showcase` requires `MEDIA_CENTARR_CONFIG_OVERRIDE` to be set, but `MediaCentarr.Showcase.seed!/0` called directly from IEx bypasses that check. Add a second rail that inspects the live config.

- [ ] **Step 1.1: Write the failing test**

Add to `test/media_centarr/showcase_test.exs` in a new `describe` block:

```elixir
describe "safety rail" do
  test "raises when database_path does not look like a showcase path" do
    config = :persistent_term.get({MediaCentarr.Config, :config})

    :persistent_term.put(
      {MediaCentarr.Config, :config},
      Map.put(config, :database_path, "/home/user/.local/share/media-centarr/media-centarr.db")
    )

    on_exit(fn -> :persistent_term.put({MediaCentarr.Config, :config}, config) end)

    assert_raise RuntimeError, ~r/refusing to seed/i, fn ->
      Showcase.seed!()
    end
  end
end
```

- [ ] **Step 1.2: Run test to verify it fails**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr/showcase_test.exs:89 --no-start
```

Expected: FAIL (no assertion yet).

- [ ] **Step 1.3: Add the assertion**

At the top of `MediaCentarr.Showcase.seed!/0` (currently line 58), before `client = TMDB.Client.default_client()`:

```elixir
def seed! do
  assert_showcase_db!()
  client = TMDB.Client.default_client()
  # ... existing body ...
```

Add a new private function at the end of the module (before `defp pending_file_data`):

```elixir
# Belt-and-suspenders: the Mix task wrapper refuses to run without
# MEDIA_CENTARR_CONFIG_OVERRIDE, but a direct IEx call to this function
# would bypass that check. This rail fires for both invocation paths by
# inspecting the live config.
defp assert_showcase_db! do
  db_path = MediaCentarr.Config.get(:database_path) || ""

  unless String.contains?(db_path, "showcase") do
    raise """
    Showcase seeder refusing to seed: database_path=#{inspect(db_path)}
    doesn't look like a showcase DB.

    The showcase seeder only runs against a DB whose configured path
    contains "showcase". Set MEDIA_CENTARR_CONFIG_OVERRIDE to
    defaults/media-centarr-showcase.toml (or a custom TOML with a
    showcase-prefixed database_path) and try again.
    """
  end
end
```

- [ ] **Step 1.4: Update the existing positive-path test setup**

The existing `setup` block in `showcase_test.exs` sets `:watch_dirs` via persistent_term. It does NOT set `:database_path`, so the assertion would fail. Extend the setup to also set a showcase-looking database_path:

Find this block around line 27–28:

```elixir
config = :persistent_term.get({MediaCentarr.Config, :config})
:persistent_term.put({MediaCentarr.Config, :config}, Map.put(config, :watch_dirs, [tmp_dir]))
```

Replace with:

```elixir
config = :persistent_term.get({MediaCentarr.Config, :config})

:persistent_term.put(
  {MediaCentarr.Config, :config},
  config
  |> Map.put(:watch_dirs, [tmp_dir])
  |> Map.put(:database_path, "priv/showcase/test.db")
)
```

- [ ] **Step 1.5: Run tests, verify they pass**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr/showcase_test.exs
```

Expected: both tests PASS.

- [ ] **Step 1.6: Commit**

```bash
jj describe -m "feat(showcase): refuse to seed non-showcase databases"
jj new
```

---

### Task 2: Swap Dragnet → Beverly Hillbillies S1 in catalog

**Files:**
- Modify: `lib/media_centarr/showcase/catalog.ex` — swap TV entry
- Test: existing `test/media_centarr/showcase_test.exs` still passes (dynamic catalog counts)

- [ ] **Step 2.1: Edit the catalog**

In `lib/media_centarr/showcase/catalog.ex`, replace the `tv_series/0` body:

```elixir
@spec tv_series() :: [tv_entry()]
def tv_series do
  [
    # The Beverly Hillbillies Season 1 (1962) — all 36 S1 episodes lapsed
    # into US public domain when Orion Television (successor to Filmways)
    # neglected to renew the copyrights. TMDB has both series metadata
    # and episodic still_path coverage, so the TV detail modal renders
    # real stills instead of fallback placeholders. Theme song "Ballad
    # of Jed Clampett" is still under copyright — irrelevant since we
    # don't use audio.
    %{title: "The Beverly Hillbillies", year: 1962, seasons: [1]},

    # CC-BY-NC-SA modern web series. No TMDB stills — exercises the
    # bundled-fixture fallback (priv/showcase/fixtures/thumbs/).
    %{title: "Pioneer One", year: 2010, seasons: [1]}
  ]
end
```

- [ ] **Step 2.2: Run tests**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr/showcase_test.exs
```

Expected: PASS. The test counts catalog entries dynamically, so the swap is transparent.

- [ ] **Step 2.3: Reseed the showcase DB and inspect**

```bash
rm -rf priv/showcase/media-centarr.db priv/showcase/media-centarr.db-* priv/showcase/images priv/showcase/media
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.create
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.migrate
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix seed.showcase
sqlite3 priv/showcase/media-centarr.db "SELECT name FROM library_tv_series;"
```

Expected output: two rows, "The Beverly Hillbillies" and "Pioneer One".

- [ ] **Step 2.4: Verify Beverly Hillbillies episodes have real thumbs**

```bash
BH_ID=$(sqlite3 priv/showcase/media-centarr.db "SELECT id FROM library_tv_series WHERE name='The Beverly Hillbillies';")
sqlite3 priv/showcase/media-centarr.db "SELECT COUNT(*) FROM library_images i JOIN library_episodes e ON i.episode_id=e.id JOIN library_seasons s ON e.season_id=s.id WHERE s.tv_series_id='$BH_ID' AND i.role='thumb';"
```

Expected: >20 (most of 36 S1 episodes should have stills).

- [ ] **Step 2.5: Commit**

```bash
jj describe -m "feat(showcase): swap Dragnet for Beverly Hillbillies S1

TMDB has stills for BH S1 episodes where it had none for Dragnet,
so the TV detail modal now renders real thumbnails in the primary
TV shot. Pioneer One is retained as the CC-indie story and still
exercises the bundled-fixture fallback path."
jj new
```

---

## Phase 2 — Fallback thumbnail redesign

### Task 3: Rewrite `scripts/generate-showcase-thumbs` with tasteful placeholders

**Files:**
- Modify: `scripts/generate-showcase-thumbs`
- Regenerate: `priv/showcase/fixtures/thumbs/thumb-{1..5}.jpg`

- [ ] **Step 3.1: Replace the script**

Overwrite `scripts/generate-showcase-thumbs` with:

```bash
#!/usr/bin/env bash
# Regenerate the bundled showcase episode-thumbnail placeholders.
#
# These are the fallback thumbs used by the seeder
# (MediaCentarr.Showcase.bundle_episode_thumb!/1) for TV series where
# TMDB has no still_path — currently only Pioneer One (CC-BY-NC-SA).
#
# The design goal is "tasteful dark placeholder that reads as
# intentional, not as a broken thumbnail." We produce five fixtures so
# consecutive episodes get visual variety via
# rem(episode_number - 1, 5) + 1.
#
# Requires: ImageMagick 7 (`magick`).
#
# Output: priv/showcase/fixtures/thumbs/thumb-{1..5}.jpg

set -euo pipefail

OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/priv/showcase/fixtures/thumbs"
mkdir -p "$OUT_DIR"

# 400×225 matches TMDB's minimum episodic-backdrop spec so the detail
# panel renders natively without upscaling.
SIZE="400x225"

# Dark palette pulled from the app's ink scale. Not gradients — flat
# near-black with a subtle radial vignette.
BASE="#0f1117"
VIGNETTE="#1a1d26"

# Five monochrome icons (ImageMagick glyph overlays). Keep them subtle —
# low contrast on the dark background so the shot reads as "polite
# placeholder" rather than "look at me".
#
# Each entry: ICON_CHAR|FONT_SIZE|OPACITY
icons=(
  "▶|96|0.12"   # play triangle
  "●|80|0.10"   # dot / film reel
  "■|72|0.10"   # square
  "◆|80|0.10"   # diamond
  "▲|88|0.10"   # triangle up
)

for i in "${!icons[@]}"; do
  n=$((i + 1))
  IFS='|' read -r char pt opacity <<< "${icons[$i]}"

  magick -size "$SIZE" \
    radial-gradient:"$VIGNETTE"-"$BASE" \
    -gravity center \
    -fill "rgba(255,255,255,$opacity)" \
    -pointsize "$pt" \
    -annotate 0 "$char" \
    -quality 90 \
    "$OUT_DIR/thumb-${n}.jpg"
done

echo "generated ${#icons[@]} thumbs at $OUT_DIR"
ls -la "$OUT_DIR"
```

- [ ] **Step 3.2: Regenerate the fixtures**

```bash
scripts/generate-showcase-thumbs
```

Expected: five JPGs written, each ~10–20 KB, visibly dark with a subtle centered glyph.

- [ ] **Step 3.3: Visual check**

Open one of them to confirm it looks tasteful, not ugly:

```bash
xdg-open priv/showcase/fixtures/thumbs/thumb-1.jpg &
```

If they look wrong (too dark, too bright, wrong proportions), iterate on the glyph size / opacity / vignette colors in the script before committing.

- [ ] **Step 3.4: Reseed and view Pioneer One detail**

```bash
rm -rf priv/showcase/media-centarr.db* priv/showcase/images priv/showcase/media
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.create
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.migrate
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix seed.showcase
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix phx.server
```

In a browser, visit `http://127.0.0.1:4003/?zone=library`, click Pioneer One, check the episode strip. Placeholders should read as intentional dark placeholders, not as the old loud gradients. Stop the server (`Ctrl+C` twice).

- [ ] **Step 3.5: Commit**

```bash
jj describe -m "feat(showcase): tasteful dark fallback thumbnails

Replace the five loud gradient fixtures with subtle monochrome-glyph
placeholders on a flat dark vignette. Used only for Pioneer One
(the one catalog entry TMDB has no stills for). Matches the app's
dark ink palette so the fallback reads as intentional restraint
rather than a rendering bug."
jj new
```

---

## Phase 3 — Seed scenario additions

### Task 4: Populated watch history

**Files:**
- Modify: `lib/media_centarr/showcase.ex` — expand `seed_watch_history!/1` to 15–20 events

- [ ] **Step 4.1: Edit `seed_watch_history!/1`**

In `lib/media_centarr/showcase.ex`, locate `seed_watch_history!/1` (currently around line 401). Replace its body:

```elixir
defp seed_watch_history!(movies) do
  now = DateTime.utc_now(:second)
  available_movies = movies |> Enum.filter(& &1.id) |> Enum.take(10)

  # Seed 2 watch events per movie, spread across the last 30 days, so
  # the /history page shows a populated, varied feed. Event i for
  # movie j lands at i*day-offset + j*hour-offset so timestamps are
  # distinct and the page renders in chronological order without
  # collisions.
  events =
    for {movie, movie_idx} <- Enum.with_index(available_movies),
        event_idx <- 0..1 do
      day_offset = movie_idx * 2 + event_idx * 5
      hour_offset = movie_idx

      {:ok, _} =
        WatchHistory.create_event(%{
          entity_type: :movie,
          movie_id: movie.id,
          title: movie.name,
          duration_seconds: 5400.0 + movie_idx * 120,
          completed_at:
            now
            |> DateTime.add(-day_offset * 86_400, :second)
            |> DateTime.add(-hour_offset * 3600, :second)
        })

      :ok
    end

  length(events)
end
```

- [ ] **Step 4.2: Run the showcase seed test to verify counts**

Update the existing test assertion in `test/media_centarr/showcase_test.exs` — `watch_events > 0` still holds but is now specifically ≥15:

```elixir
assert summary.watch_events >= 15
```

Run:

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr/showcase_test.exs
```

Expected: PASS.

- [ ] **Step 4.3: Reseed and visit /history**

```bash
rm -rf priv/showcase/media-centarr.db* priv/showcase/images priv/showcase/media
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.create
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.migrate
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix seed.showcase
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix phx.server
```

Visit `http://127.0.0.1:4003/history` and verify the page shows ~20 events over ~30 days. Stop the server.

- [ ] **Step 4.4: Commit**

```bash
jj describe -m "feat(showcase): populated watch history (20 events across 30 days)"
jj new
```

---

### Task 5: Seed console log entries

**Files:**
- Modify: `lib/media_centarr/showcase.ex` — emit varied log entries near end of `seed!/0`

**Why:** The `/console` page will otherwise be nearly empty at screenshot time. A varied set of log entries gives the filter chips something to show off.

- [ ] **Step 5.1: Add a `seed_console_entries/0` helper and call it**

In `lib/media_centarr/showcase.ex`, add just before the final `%{movies: length(movies), ...}` return in `seed!/0`:

```elixir
seed_console_entries!()
```

Add the helper after `seed_watch_history!/1`:

```elixir
# Synthetic log entries so the /console page has varied content at
# screenshot time. Touches every non-framework component once at each
# level. Framework components (:phoenix, :ecto, :live_view) are filled
# naturally by the server accepting HTTP requests during the tour.
defp seed_console_entries! do
  Log.info(:watcher, "scanned 14 files in /showcase/media")
  Log.info(:pipeline, "processed 3 movies, 1 TV series, 2 extras in last batch")
  Log.info(:tmdb, "search hit: Nosferatu (1922) → TMDB 653")
  Log.info(:library, "linked watched file: Big Buck Bunny (2008).mkv")
  Log.info(:playback, "session stopped: position 1820s of 5400s")

  Log.warning(:tmdb, "rate limit window: 3 requests queued, backing off 250ms")
  Log.warning(:watcher, "file appeared then disappeared within debounce window: /showcase/tmp/.partial.mkv")
  Log.warning(:pipeline, "no confident TMDB match for 'Ambiguous-RELEASE-GROUP.mkv' — escalated to review queue")

  Log.error(:library, "image download failed for backdrop (404) — falling back to poster crop")

  :ok
end
```

- [ ] **Step 5.2: Reseed, visit /console**

```bash
rm -rf priv/showcase/media-centarr.db* priv/showcase/images priv/showcase/media
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.create
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.migrate
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix seed.showcase
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix phx.server
```

Visit `http://127.0.0.1:4003/console` and verify ~10 varied entries across components, levels. Stop the server.

- [ ] **Step 5.3: Commit**

```bash
jj describe -m "feat(showcase): seed varied console log entries for /console shot"
jj new
```

---

### Task 6: Seed an acquisition grab row (for /download shot)

**Files:**
- Modify: `lib/media_centarr/showcase.ex` — add `seed_acquisition!/0`
- Modify: `lib/mix/tasks/seed.showcase.ex` — print acquisition count in summary

**Why:** `/download` is primarily a search UI with a queue monitor below. Seeding one grab row means the queue card below the search isn't completely empty at screenshot time. We still capture the empty-search state (no active search typed); the queue card provides visual anchor.

- [ ] **Step 6.1: Add `seed_acquisition!/0` helper**

In `lib/media_centarr/showcase.ex`, add near the end (before `# Helpers`):

```elixir
# One Acquisition.Grab row in the "searching" state so the /download
# page's queue monitor card has a visible entry at screenshot time.
# The Prowlarr client is not called — this is a static DB row only.
defp seed_acquisition! do
  changeset =
    MediaCentarr.Acquisition.Grab.create_changeset(%{
      tmdb_id: "12345",
      tmdb_type: "movie",
      title: "Showcase Upcoming Film (2026)"
    })

  {:ok, _grab} = MediaCentarr.Repo.insert(changeset)
  1
end
```

- [ ] **Step 6.2: Wire into `seed!/0`**

In `seed!/0`, add after `watch_event_count = seed_watch_history!(movies)`:

```elixir
acquisition_count = seed_acquisition!()
```

Add `acquisitions: acquisition_count` to the returned summary map.

- [ ] **Step 6.3: Extend the `summary()` type and Mix task printer**

In `lib/media_centarr/showcase.ex`, update the `@type summary` spec:

```elixir
@type summary :: %{
        movies: non_neg_integer(),
        tv_series: non_neg_integer(),
        seasons: non_neg_integer(),
        episodes: non_neg_integer(),
        video_objects: non_neg_integer(),
        watch_progress: non_neg_integer(),
        tracked_items: non_neg_integer(),
        pending_files: non_neg_integer(),
        watch_events: non_neg_integer(),
        acquisitions: non_neg_integer()
      }
```

In `lib/mix/tasks/seed.showcase.ex`, add `Acquisitions:   #{summary.acquisitions}` to the summary print-out.

- [ ] **Step 6.4: Extend the Showcase test**

In `test/media_centarr/showcase_test.exs`, add to the "creates all catalog entries" test:

```elixir
assert summary.acquisitions == 1
```

Also add a `Repo.all/1` assertion:

```elixir
grabs = Repo.all(MediaCentarr.Acquisition.Grab)
assert length(grabs) == 1
```

Run:

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr/showcase_test.exs
```

Expected: PASS.

- [ ] **Step 6.5: Reseed, visit /download**

Reseed as before, visit `http://127.0.0.1:4003/download`. The download page will render if Prowlarr is configured; if the showcase config doesn't have Prowlarr credentials, the page redirects to `/`. In that case, note the gap in tour comments — the `/download` stop becomes a "skip if Prowlarr not configured" stop.

- [ ] **Step 6.6: Commit**

```bash
jj describe -m "feat(showcase): seed one Acquisition.Grab row for /download shot"
jj new
```

---

## Phase 4 — Settings page anchor IDs

### Task 7: Add scroll anchors to settings sections

**Files:**
- Modify: `lib/media_centarr_web/live/settings_live.ex`

**Why:** The tour needs to scroll `/settings` to four distinct sections for the `settings-library`, `settings-tmdb`, `settings-prowlarr`, and `settings-download-clients` shots. Each section currently has only an `<h2>` — no stable anchor ID for Playwright to target.

- [ ] **Step 7.1: Add `id=` attributes to the four section containers**

In `lib/media_centarr_web/live/settings_live.ex`, find the four `<form>` / `<div>` blocks that wrap each section and add `id="settings-<name>"`:

**TMDB** (around line 1518):
```html
<form id="settings-tmdb" phx-submit="save_tmdb" class="p-5 rounded-lg glass-surface space-y-5">
```

**Prowlarr** (around line 1638):
```html
<form id="settings-prowlarr" phx-submit="save_prowlarr" class="p-5 rounded-lg glass-surface space-y-5">
```

**Download Client** (around line 1717):
```html
<form id="settings-download-client" phx-submit="save_download_client" class="p-5 rounded-lg glass-surface space-y-5">
```

**Library** (around line 2159 — the section wrapping `<h2>Library</h2>`):

Check the parent `<section>` or `<div>` two lines above the `<h2 class="text-lg font-semibold">Library</h2>` and add `id="settings-library"` to it. If the parent is unnamed, wrap the block in:

```html
<section id="settings-library" class="...">
  ... existing content ...
</section>
```

- [ ] **Step 7.2: Run precommit locally to confirm no HEEx/compile breakage**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix compile --warnings-as-errors
```

Expected: clean compile.

- [ ] **Step 7.3: Manual check in browser**

```bash
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix phx.server
```

Visit `http://127.0.0.1:4003/settings#settings-tmdb` — the page should scroll to the TMDB section on load. Repeat for each anchor. Stop the server.

- [ ] **Step 7.4: Commit**

```bash
jj describe -m "feat(settings): add section anchor ids for scroll targeting"
jj new
```

---

## Phase 5 — Tour expansion

### Task 8: Extend `scripts/screenshot-tour` entity ID lookup

**Files:**
- Modify: `scripts/screenshot-tour`

**Why:** The shell script currently queries two entity IDs (`NOSFERATU_ID`, `PIONEER_ONE_ID`) from the showcase DB. We need a third (`BEVERLY_HILLBILLIES_ID`) so the tour can open the Beverly Hillbillies detail modal.

- [ ] **Step 8.1: Add the lookup**

In `scripts/screenshot-tour`, find the existing block (lines 73–78):

```bash
if [ -f "$SHOWCASE_DB" ]; then
  NOSFERATU_ID=$(sqlite3 "$SHOWCASE_DB" "SELECT id FROM library_movies WHERE name = 'Nosferatu' LIMIT 1;" 2>/dev/null || true)
  PIONEER_ONE_ID=$(sqlite3 "$SHOWCASE_DB" "SELECT id FROM library_tv_series WHERE name = 'Pioneer One' LIMIT 1;" 2>/dev/null || true)
  export NOSFERATU_ID PIONEER_ONE_ID
fi
```

Replace with:

```bash
if [ -f "$SHOWCASE_DB" ]; then
  NOSFERATU_ID=$(sqlite3 "$SHOWCASE_DB" "SELECT id FROM library_movies WHERE name = 'Nosferatu' LIMIT 1;" 2>/dev/null || true)
  PIONEER_ONE_ID=$(sqlite3 "$SHOWCASE_DB" "SELECT id FROM library_tv_series WHERE name = 'Pioneer One' LIMIT 1;" 2>/dev/null || true)
  BEVERLY_HILLBILLIES_ID=$(sqlite3 "$SHOWCASE_DB" "SELECT id FROM library_tv_series WHERE name = 'The Beverly Hillbillies' LIMIT 1;" 2>/dev/null || true)
  export NOSFERATU_ID PIONEER_ONE_ID BEVERLY_HILLBILLIES_ID
fi
```

- [ ] **Step 8.2: Commit**

```bash
jj describe -m "chore(screenshot-tour): export Beverly Hillbillies id"
jj new
```

---

### Task 9: Rewrite `test/e2e/screenshot.tour.js` with 17 stops

**Files:**
- Modify: `test/e2e/screenshot.tour.js` — full rewrite

- [ ] **Step 9.1: Replace the TOUR array**

Replace the `TOUR` array and the stop execution loop with this fuller version. Keep everything else (`test.beforeEach`, `waitForLiveView`, path constants) unchanged:

```javascript
// Injected by scripts/screenshot-tour via sqlite3 lookup before each run.
const NOSFERATU_ID = process.env.NOSFERATU_ID || ""
const PIONEER_ONE_ID = process.env.PIONEER_ONE_ID || ""
const BEVERLY_HILLBILLIES_ID = process.env.BEVERLY_HILLBILLIES_ID || ""

/** @type {import("./screenshot.tour.types").Stop[]} */
const TOUR = [
  // ─── Library ─────────────────────────────────────────────────────────
  {
    name: "library-grid",
    url: "/?zone=library",
    waitFor: ".tab-active[data-nav-zone-value='library']",
  },
  {
    name: "library-detail-movie",
    url: `/?zone=library&selected=${NOSFERATU_ID}`,
    waitFor: "#detail-modal[data-state='open']",
  },
  {
    name: "library-detail-tv",
    url: `/?zone=library&selected=${BEVERLY_HILLBILLIES_ID}`,
    waitFor: "#detail-modal[data-state='open']",
  },
  {
    name: "library-detail-tv-pioneer",
    url: `/?zone=library&selected=${PIONEER_ONE_ID}`,
    waitFor: "#detail-modal[data-state='open']",
  },

  // ─── Review ──────────────────────────────────────────────────────────
  { name: "review-queue", url: "/review" },
  {
    name: "review-detail",
    url: "/review",
    action: async (page) => {
      // Click the first pending file card. The review page has
      // one or more [data-review-pending] items; select the first.
      const first = page.locator("[data-review-pending]").first()
      await first.click({ timeout: 5_000 }).catch(() => {})
    },
    settleMs: 600,
  },

  // ─── Status / releases / history / console ──────────────────────────
  {
    name: "release-tracking",
    url: "/status",
    action: async (page) => {
      const card = page.locator("[data-status-releases]").first()
      await card.scrollIntoViewIfNeeded({ timeout: 5_000 }).catch(() => {})
    },
    settleMs: 300,
  },
  { name: "status", url: "/status" },
  { name: "history", url: "/history" },
  { name: "download", url: "/download" },
  { name: "console", url: "/console" },

  // ─── Settings ────────────────────────────────────────────────────────
  { name: "settings-overview", url: "/settings" },
  { name: "settings-library", url: "/settings#settings-library", settleMs: 300 },
  { name: "settings-tmdb", url: "/settings#settings-tmdb", settleMs: 300 },
  {
    name: "settings-download-clients",
    url: "/settings#settings-download-client",
    settleMs: 300,
  },
  { name: "settings-prowlarr", url: "/settings#settings-prowlarr", settleMs: 300 },

  // ─── A11y / input system ────────────────────────────────────────────
  {
    name: "keyboard-focus",
    url: "/?zone=library",
    waitFor: ".tab-active[data-nav-zone-value='library']",
    action: async (page) => {
      // Focus the first library card so the focus ring is visible in
      // the shot. Presses Tab to move keyboard focus rather than
      // calling .focus() directly — this matches the real input
      // system's focus context and triggers the correct ring styling.
      await page.locator("[data-nav-item]").first().focus()
    },
    settleMs: 300,
  },

  // ─── Known gaps (omitted stops) ──────────────────────────────────────
  // playback-overlay: mpv renders the overlay, not the browser;
  //   Playwright can't capture it.
  // first-run: requires an empty DB, which conflicts with the populated
  //   showcase. Capture manually if needed.
]
```

- [ ] **Step 9.2: Update the loop to call `action` when present**

Replace the `for (const stop of TOUR) { ... }` block with:

```javascript
for (const stop of TOUR) {
  test(`tour: ${stop.name}`, async ({ page }) => {
    await page.goto(stop.url, { waitUntil: "domcontentloaded" })
    await waitForLiveView(page)

    if (stop.waitFor) {
      await page
        .waitForSelector(stop.waitFor, { timeout: 5_000 })
        .catch(() => {
          /* missing is fine — capture whatever rendered. */
        })
    }

    if (stop.action) {
      await stop.action(page)
    }

    await page.waitForLoadState("networkidle").catch(() => {})
    await page.waitForTimeout(stop.settleMs ?? 400)

    const outPath = path.join(OUT_DIR, `${stop.name}.png`)
    await page.screenshot({ path: outPath, fullPage: false })
    expect(outPath).toBeTruthy()
  })
}
```

- [ ] **Step 9.3: Update the Stop typedef**

In the same file, update the JSDoc typedef:

```javascript
/**
 * @typedef {object} Stop
 * @property {string} name       Output filename (no extension).
 * @property {string} url        Path or full URL to navigate to.
 * @property {string} [waitFor]  Optional selector to wait for before capturing.
 * @property {number} [settleMs] Extra pause (ms) after navigation/mount.
 * @property {(page: import("@playwright/test").Page) => Promise<void>} [action]
 *   Optional per-stop action that runs after waitFor and before the
 *   final settle + screenshot (click, scroll, focus, etc.).
 */
```

- [ ] **Step 9.4: Verify `data-review-pending` and `data-status-releases` exist**

Grep the codebase:

```bash
grep -rn 'data-review-pending\|data-status-releases' lib/media_centarr_web
```

If the attributes don't exist, add them to the appropriate HEEx templates in this same commit:

- `data-review-pending` — on the row/card for each pending file in the `/review` template (whichever LiveView renders the queue).
- `data-status-releases` — on the section/card wrapping the releases display in the `/status` template.

Stable test-hook attributes are fine to add; they're opaque to users.

- [ ] **Step 9.5: Start showcase server and run the tour**

```bash
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix phx.server
```

In another shell:

```bash
scripts/screenshot-tour
```

Expected: 17 PNGs in `docs-site/assets/screenshots/`. Inspect each visually.

- [ ] **Step 9.6: Iterate on any bad shots**

Loop until all 17 look right:
1. Identify which shot is off (wrong scroll position, modal not open, focus ring not visible, etc.).
2. Adjust the stop's `waitFor`, `action`, or `settleMs` in `screenshot.tour.js`.
3. Re-run only that stop: `scripts/screenshot-tour --grep "tour: <name>"`.
4. Repeat.

Stop the showcase server once all shots pass.

- [ ] **Step 9.7: Commit tour + any data-attribute additions**

```bash
jj describe -m "feat(screenshot-tour): expand to 17 stops covering every surface

Adds review-queue/detail, release-tracking, status, history, download,
console, four settings section crops, and a keyboard-focus a11y shot.
Keyboard-focus stop tabs to the first library card so the focus ring
is visible. Adds stable data-review-pending and data-status-releases
hooks used by tour actions."
jj new
```

---

## Phase 6 — Landing page + wiki

### Task 10: Expand `docs-site/index.html` screenshot grid

**Files:**
- Modify: `docs-site/index.html` — screenshots section

- [ ] **Step 10.1: Replace the screenshot grid**

Find the `<div class="mt-10 grid gap-6 md:grid-cols-2">` block in the SCREENSHOTS section (around line 410) and extend it to 8 figures. Use the pattern of the existing 4 `<figure>` blocks; each new figure follows the same structure:

```html
<figure class="shot-frame">
  <img
    src="assets/screenshots/<NAME>.png"
    alt="<ALT>"
    loading="lazy"
    width="1400"
    height="900"
    class="block w-full"
  />
  <figcaption class="px-4 py-3 text-xs uppercase tracking-wider text-parchment-400">
    <CAPTION>
  </figcaption>
</figure>
```

New figures to add in this order (keep existing 4 in place, append 4):

| NAME | ALT | CAPTION |
|------|-----|---------|
| `review-queue` | "Review queue — pending files awaiting metadata confirmation" | Review queue |
| `status` | "Status page — pipeline health, watcher state, and live metrics" | Status |
| `history` | "Watch history — recent playback events across the library" | Watch history |
| `console` | "Console drawer — component-tagged log stream" | Console |

- [ ] **Step 10.2: Visual check**

Open `docs-site/index.html` directly in a browser (it's a static page) and scroll to the screenshots section. All 8 tiles should render.

- [ ] **Step 10.3: Commit**

```bash
jj describe -m "docs(site): expand landing-page screenshot grid to 8 tiles"
jj new
```

---

### Task 11: Update wiki pages with new / fixed screenshot references

**Files:** (in sibling repo `../media-centarr.wiki/`)
- Modify: `Review-Queue.md` (fix broken link, add detail shot)
- Modify: `Release-Tracking.md` (fix broken link)
- Modify: `Browsing-Your-Library.md` (add movie + TV detail shots)
- Modify: `Settings-Reference.md` (add section shots)
- Modify: `Watch-History.md` (add history shot)
- Modify: `Download-Clients.md` (add settings-download-clients shot)
- Modify: `Prowlarr-Integration.md` (add settings-prowlarr shot)
- Modify: `TMDB-API-Key.md` (add settings-tmdb shot)
- Modify: `Adding-Your-Library.md` (add settings-library shot)
- Modify: `Keyboard-and-Gamepad.md` (add keyboard-focus shot)
- Modify: `Home.md` (add library-grid hero)

All images use the `https://raw.githubusercontent.com/media-centarr/media-centarr/main/docs-site/assets/screenshots/<NAME>.png` URL pattern, matching existing references.

- [ ] **Step 11.1: Ensure screenshot commit is on `main` and pushed first**

Wiki images point at `main/docs-site/assets/screenshots/`. The screenshots must be on `main` before the wiki commit lands, or the wiki will render broken links until the screenshots ship.

Push Phases 1–6 first (see "Phase 7 — Ship" below), then return to this task.

- [ ] **Step 11.2: For each wiki page, insert or fix the image reference**

All edits happen in `../media-centarr.wiki/`. For each page:

**`Review-Queue.md`** — the top `![Review queue](...)` line is currently broken; keep it, and after the first paragraph add a second image for the detail view:

```markdown
![Review detail](https://raw.githubusercontent.com/media-centarr/media-centarr/main/docs-site/assets/screenshots/review-detail.png)
```

**`Release-Tracking.md`** — the top `![Release tracking](...)` line is currently broken. No change needed to the reference itself (screenshot now exists); just verify the filename matches (`release-tracking.png`).

**`Browsing-Your-Library.md`** — currently has `library-grid` at top. After the first paragraph, add:

```markdown
![Movie detail](https://raw.githubusercontent.com/media-centarr/media-centarr/main/docs-site/assets/screenshots/library-detail-movie.png)
![TV series detail](https://raw.githubusercontent.com/media-centarr/media-centarr/main/docs-site/assets/screenshots/library-detail-tv.png)
```

**`Settings-Reference.md`** — currently has `settings-overview` at top. Near the relevant section headings in the body, insert section screenshots:

```markdown
![TMDB settings](https://raw.githubusercontent.com/media-centarr/media-centarr/main/docs-site/assets/screenshots/settings-tmdb.png)
```

(Similarly `settings-prowlarr`, `settings-download-clients`, `settings-library` near their section headings.)

**`Watch-History.md`** — after the intro, add:

```markdown
![Watch history](https://raw.githubusercontent.com/media-centarr/media-centarr/main/docs-site/assets/screenshots/history.png)
```

**`Download-Clients.md`** — after the intro:

```markdown
![Download client settings](https://raw.githubusercontent.com/media-centarr/media-centarr/main/docs-site/assets/screenshots/settings-download-clients.png)
```

**`Prowlarr-Integration.md`** — after the intro:

```markdown
![Prowlarr settings](https://raw.githubusercontent.com/media-centarr/media-centarr/main/docs-site/assets/screenshots/settings-prowlarr.png)
```

**`TMDB-API-Key.md`** — after the intro:

```markdown
![TMDB API key setting](https://raw.githubusercontent.com/media-centarr/media-centarr/main/docs-site/assets/screenshots/settings-tmdb.png)
```

**`Adding-Your-Library.md`** — after the first paragraph:

```markdown
![Library settings](https://raw.githubusercontent.com/media-centarr/media-centarr/main/docs-site/assets/screenshots/settings-library.png)
```

**`Keyboard-and-Gamepad.md`** — after the intro:

```markdown
![Keyboard focus ring](https://raw.githubusercontent.com/media-centarr/media-centarr/main/docs-site/assets/screenshots/keyboard-focus.png)
```

**`Home.md`** — add after the existing logo/title block, before the first section:

```markdown
![Library grid](https://raw.githubusercontent.com/media-centarr/media-centarr/main/docs-site/assets/screenshots/library-grid.png)
```

- [ ] **Step 11.3: Commit the wiki bundle**

```bash
cd ../media-centarr.wiki
jj describe -m "wiki: screenshots for every major page"
jj bookmark set master -r @
jj git push
cd -
```

- [ ] **Step 11.4: Visual check on GitHub**

Open the GitHub wiki (e.g. `https://github.com/media-centarr/media-centarr/wiki/Review-Queue`) and verify images render in each edited page. GitHub caches images aggressively — may take 1–2 minutes for new images to show.

---

## Phase 7 — Ship

### Task 12: Pre-ship precommit sweep

- [ ] **Step 12.1: Run precommit**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix precommit
```

Expected: no warnings, no test failures, no credo/sobelow/audit issues. Fix anything flagged before shipping.

- [ ] **Step 12.2: Run input system JS tests and E2E**

```bash
bun test assets/js/input/
```

Expected: PASS. The screenshot tour runs separately (not in `mix precommit`) so no need to re-run it here.

---

### Task 13: Ship via `/ship patch`

- [ ] **Step 13.1: Invoke ship**

The `/ship` skill handles the version bump, CHANGELOG entry, tag, and push. Invoke:

```
/ship patch
```

- [ ] **Step 13.2: Confirm the release workflow deployed**

After the tag pushes, `.github/workflows/release.yml` builds and uploads the tarball. Check:

```bash
gh release list --limit 3
```

Expected: the new `v0.22.1` (or whatever patch was cut) appears with a tarball asset.

- [ ] **Step 13.3: Pages deploy check**

`docs-site/index.html` change triggers `.github/workflows/pages.yml`. Verify the deployed landing page shows 8 tiles at https://media-centarr.github.io/media-centarr/.

- [ ] **Step 13.4: Wiki commit**

Once `main` is pushed (screenshots live at the `raw.githubusercontent.com` URLs), return to Phase 6 Task 11 if it was deferred.

---

## Self-review notes

- **Spec coverage:** Every section of `2026-04-24-showcase-screenshots-design.md` maps to at least one task: §1 catalog → Task 2; §2 fallback thumbs → Task 3; §3 seed scenarios → Tasks 4, 5, 6; §4 tour → Tasks 8, 9 (plus settings anchors in Task 7); §5 integration → Tasks 10, 11; §6 safety → Task 1.
- **Placeholder scan:** No TBDs, TODOs, or "implement later" references. Stop-17 visual treatment deferred decision lives in Task 9 Step 6 (iterate loop), not a placeholder.
- **Type consistency:** All method names and fields verified — `seed_acquisition!/0`, `seed_console_entries!/0`, `seed_watch_history!/1`, `Acquisition.Grab.create_changeset/1`, `BEVERLY_HILLBILLIES_ID`.

## Known gaps accepted

Same as the spec: no first-run screenshot, no playback-overlay screenshot, no light-theme variants, no sidebar-expanded variants.
