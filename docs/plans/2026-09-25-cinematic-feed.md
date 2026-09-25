# The cinematic feed — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Rewritten 2026-09-25 for the settled design (`G-couch-feed` + `J-friends-page` with the corner disc); the first draft (the night of 2026-09-24/25, F's lead-and-band page) is superseded in full.

**Goal:** The Feed becomes two full-height columns at the layout's full width: bands, one per action, each on its title's still under the ink scrim, beside a rail of person cards; the Friends tab becomes a grid of the same card at its page width, each card a strip of the person's latest acts as posters with act discs; own rows are marked by the filled identity tile; paging is a window with a cap and a queued head; every size meets the couch floors.

**Architecture:** One band component (`Discovery.FeedBand`, no size axis) renders every author and keeps the row's DOM contract; one person-card component (`Discovery.PersonCard`, `width: :rail | :page`) is composed on the Feed's rail and the Friends page; the identity tile (`Discovery.IdentityTile`) is composed by both. The host resolves a row's poster *and* backdrop down one artwork ladder (`DiscoveryLive.ActivityArtwork` over `Library.Artwork` and `TmdbArtwork`); the Feed projection (`FeedEntries`) carries the backdrop, stamps the offset crop from adjacency, and pages by window, cap and head; the people projection (`People`) builds each person's acts and the rail's roster. The flag vocabulary the pennant and the strip share is `Title.Flag`. The scrim, mask, crop, disc and the two-column fold are CSS in `app.css` (the fold a container query); a small `FeedHead` hook reports the column's top leaving and returning to the viewport.

**Tech Stack:** Phoenix LiveView, Tailwind v4 + daisyUI, Phoenix Storybook, ExUnit + LazyHTML, bun for the hook. Spec: `docs/superpowers/specs/2026-09-24-feed-appearance-design.md` (every size; read its "What the user sees" before any phase). The pages: `…-mockups/G-couch-feed/REASONING.md`, `…/J-friends-page/REASONING.md`; the disc: the owner's call in `…/CRITIQUE-9.md`; the crop: `…/MEASUREMENT.md`. Record to write: UIDR-046.

**Ground rules for this repo (read before Phase 1):**

- Never run `mix` directly in an agent shell. Every command below uses `~/scripts/agents/agent-mix`, which builds outside the checkout so the dev daily driver is never disturbed.
- Test-first: write the failing test, run it, see it fail for the right reason, then implement. The storybook-first rule applies to the two components that already have stories (`feed_entry_row`, `person_card`): the story variation is edited before the component.
- Zero warnings. `mix precommit` runs `--warnings-as-errors`, Credo `--strict` (MC0008 typed attrs, MC0009 a story per component and every `values:` literal in the story, MC0016 eager images, MC0028 declared artwork width, MC0034 text ≥ /55, MC0024 no markup `=~`, MC0023 factory-only setup, MC0035/36 the test-case template), Boundary, and the storybook compile/render tests.
- No real show titles anywhere (`Sample Movie`, `Sample Show`, `Sample Friend`); fixture artwork is PD/CC from `priv/showcase/images`.
- Commit after each phase. End every commit message with the line `Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L`. Never add a `Co-Authored-By` trailer. Commit straight to `main`; do not push.
- The dev server on :2160 hot-reloads from the checkout. The `assets/` watchers are off: after a CSS change, a hook change, or a template change that adds Tailwind utilities, run `~/scripts/agents/agent-mix assets.build`. For a visual check use `~/scripts/agents/page-shot --url http://127.0.0.1:2160/discovery --viewport 1920x1080 --wait-ms 3000` and Read the PNG; the half-size check is `vips resize <png> <half.png> 0.5` and a Read of the result.
- A new module named in a context's `exports:` needs `~/scripts/agents/agent-mix compile --force` once, or Boundary reports a stale manifest.
- Nothing in Phases 1–6 adds `data-nav-*`: the Feed and the rail ship mouse-only until Phase 7 (the campaign's step 6). The Friends page keeps the nav items it has where the element survives.

---

## Glossary

Terms from `docs/GLOSSARY.md` are used as defined there: *Feed*, *feed row*, *Scope*, *Author*, *Action*, *Review*, *Listing*, *Rung*, *Ladder* (artwork tiers: library, referenced, browsing). The spec's glossary defines the design's words (band, rail, person card, acts strip, act glyph, act disc, opened card, window, queued arrivals, couch floors, fold width). This plan adds, in the order the code meets them:

| Term | Meaning |
|---|---|
| **Identity tile** | `Discovery.IdentityTile`: monogram · own · photo, at `size` 48 (rail), 56 (band), 64 (page). |
| **Row artwork** | `FeedEntry.poster_url` and `FeedEntry.backdrop_url`, resolved by `ActivityArtwork` down the ladder per role. |
| **Flag** | `Title.Flag`: the activity → flag map (`flag/1`), the flag → heroicon map (`glyph/1`) and the mast order (`mast_order/0`), extracted from `Pennant` so the pennant and the acts strip compose one vocabulary. |
| **Act** | `Person.Act`: one title the person acted on — its ref, title, poster, the newest activity's id and time, the flags flown in mast order, and every activity behind it (`Person.Entry`, the opened card's rows). |
| **Rail roster** | `People.rail/1`: the first eight of `People.build/3`'s order, and how many the cap hid. |
| **Head** | `feed_head`: nil while the reader is at the column's top (arrivals prepend live); else the `activity_id` of the newest band shown, which freezes the window there and counts newer actions as queued. |
| **Derivative** | A width-constrained copy of a local artwork master served by `ImageServer` for `?w=<px>`, snapped up the ladder `160 · 240 · 320 · 480 · 640 · 960 · 1280 · 1920`; wider requests get the master. `?w=` constrains the **width**. |
| **Fold** | `@container discovery (min-width: …)`: 1600px shows the rail beside the column; 1700px sets the Friends grid to two columns. A CSS fact; no assign knows the width. |

---

## Owner decisions this plan assumes

Few, all mechanics; each is one line to flip.

1. **The band keeps the row's DOM contract** — `id="feed-row-<activity id>"`, `data-component="feed-row"`, `data-kind`, `data-own`, `data-list-slot`, `data-download-slot`, `data-role` (`who`, `title`, `text`, `time`, `toolbar`), the `-list`/`-download`/`-ignore` control ids, `phx-click="open_title"` on the root — so every feed-tab test in `discovery_live_test.exs` stays green without edits through Phase 4. The module is renamed; the DOM names the thing, the class names the look.
2. **`Library.Posters` becomes `Library.Artwork`** with `urls_by_refs(refs, role)`, rather than a sibling `Backdrops`; the one other caller (`WatchHistory.Views.PlaybackActivity`) changes one line.
3. **Derivative widths by the rendered box × 2**: the band's still `?w=1280` (536 CSS px → 1072 → 1280), the band's poster `?w=240` (100 → 200), the rail's poster `?w=240` (96 → 192), the page's poster `?w=320` (130 → 260). Each is a public `*_src` builder on its component so MC0028 sees it and a later warmup can match it.
4. **No `photo_url` on `Person` or `FeedEntry` yet.** The tile takes `photo_url` and its story pins the photo states; the view-models gain the field when the social protocol carries a profile event (`docs/social-protocol.md`: review, watched, listing).
5. **The fold is CSS.** The rail is rendered whenever the tab has one (Feed, Watchlist) and hidden by the container query below 1600; it is not rendered on the Friends tab. The LiveView never learns the width.
6. **The head is a hook.** `FeedHead` observes a sentinel at the column's top and pushes `feed_scrolled` / `feed_at_top` on the crossing; "N new" is `feed_show_new`, which also scrolls to the top. No polling, no scroll position on the server.
7. **A rail card navigates.** `open_person` → `push_navigate` to `/discovery/friends?person=<card id>`; the Friends page reads `?person=` into its opened set and the named card takes focus on mount (which scrolls it into view). The tab strip keeps navigating to fresh mounts (the standing scope-reset follow-up is unchanged).
8. **The Watchlist rows stay as they are**, in the left column beside the rail. Bands there are the next campaign.
9. **`Person`'s shelves go.** `presence`, `watched`, `listed` and `reviewed` leave the struct with the card that read them; the Friends-tab tests that assert them are rewritten to the acts contract in Phase 3 and Phase 5, not kept on a compatibility shim.

---

## What the code says

Verified 2026-09-25 against the checkout; each changes a step below.

1. **Backdrops are already warmed.** `TmdbArtwork.ensure/2` → `fetch_missing/2` downloads the poster, the backdrop *and* the logo from the stored title's payload (`tmdb_artwork.ex:334`), and `TmdbArtwork.urls/2` returns `backdrop_url`. What is missing is on the reading side: `LiveHelpers.title_poster_url/1` discards the backdrop; `ActivityPosters.missing/1` warms only rows whose *poster* is nil; the library tier, `Library.Posters.urls_by_refs/1`, queries `role == "poster"` only.
2. **The wire snapshot carries no artwork paths.** `Activities.Publisher`'s moduledoc: poster and backdrop are left for the receiving install; `Activities.Translation` never writes `poster_path` or `backdrop_path` (grep is empty). The "TMDB hotlink" rung is dead in practice for both roles — the referenced tier is the source for every title the library does not own. Keep the rung (the `Title` struct has the fields and a foreign client may fill them) but do not design around it; the resolver asks `:w185` for a poster and `:w1280` for a backdrop, never `:w92`.
3. **`?w=` constrains the width, snapping up a fixed ladder, never upscaling** (`ImageFiles.derivative/2`, `@derivative_widths [160, 240, 320, 480, 640, 960, 1280, 1920]`). `?w=1280` → 1280×720 from a 16:9 master; above 1920 → the master. Derivatives are cached per master per tier.
4. **`full_width` is one attribute on `Layouts.app`** (`layouts.ex:263`): it drops `max-w-7xl` for the whole LiveView, so it applies to all three tabs at once. `<main>` keeps `px-6`; with the 52px sidebar the content is 1920 − 52 − 48 = **1820px**, the spec's width. Discovery's own `mx-auto w-full max-w-4xl` wrapper is the 896px column and goes. Library, Home, Incoming and Settings already pass `full_width`.
5. **Discovery carries no `.page-side-dim`** (grep: 0). The bands and cards sit on the body's radial gradient. Not changed by this plan; noted for the owner.
6. **The mockup's ink is not the theme's base.** `oklch(13% 0.02 264)` is the literal the identity-banner family uses (`.scrim-surface`, `.identity-row`, `.identity-banner-strip`); `--color-base-100` is `oklch(27% 0.019 264)`. The band and the card must use the 13% literal — defined once as `--ink` beside those rules — or the words wash out fourteen points lighter. The own tile's fill is `--color-primary` (`oklch(62% 0.16 250)`) and `--color-primary-content`, the theme's own button primary, not the mockup's hue-264 literal.
7. **MC0016 and MC0028 on every image.** Every `<img>` carries `loading="eager" decoding="sync"`; no `fetchpriority="high"` anywhere on the Feed now that there is no lead (the priority signal is reserved for a surface's one or two hero images). Every `/media-images` `src` passes through `sized_image_url/2` or a `*_src(` builder; a remote TMDB URL is exempt.
8. **The storybook's sample images do not exist.** `/images/sample-nosferatu-poster.jpg` (five stories: `feed_entry_row`, `person_card`, `title/title_row`, `incoming/shelf_row`, `tmdb/title_summary`) and `/storybook/fixtures/poster.jpg` (`library_cards/poster_card`) are 404s — `priv/static/images/` holds only the app's icons and logos. The render test checks the page's status only. `priv/showcase/images/<uuid>/{poster,backdrop}.jpg` are PD/CC and in git; Phase 1 copies one pair to `priv/static/images/storybook/` and repoints the six references (the campaign's inherited follow-up).
9. **`Tab.count` is already hidden at zero** (`tab_strip.ex:44`).
10. **The `Downloading` hairline has no progress source**; `FeedEntry.acquisition_state` is an atom. The band keeps the row's static hairline.
11. **Nothing on the Feed is a nav item**; `config.js` declares `title_rows` "for Discovery's Feed and watchlist rows", but only the Watchlist renders that zone. The person card's posters, names and Remove friend *are* nav items in the `people` zone (`Context.SHELF`, geometry). Phases 1–6 keep the card's surviving items as nav items and add none; Phase 7 wires the rest.
12. **`Pennant.glyph/1` is private and `Pennant.flag/1` is public**; `Sentiment.glyph/1` is public. The strip needs the flag → glyph map for all six flags and the mast order (`@flags`), so the vocabulary is extracted (glossary: *Flag*) rather than a second map written.
13. **The `hero-*` icons are CSS masks of Heroicons' 24-unit outline set** (stroke 1.5): at 28px the stroke draws about 1.75px, at 32px 2px. The spec's "2px stroke" is met at 32 and approximated at 28; the half-size check on the rail card's story is where that is judged, and a heavier set is the fallback, not a per-icon stroke.
14. **`People.build/3` already orders You first, then by latest act, quiet friends last by name** (`sort_key/1`); the rail's order is the same list, cut at eight. `People` builds `presence` and three shelves the new card does not read.
15. **`FeedEntries.page_size/0` is 50** and `discovery_live_test.exs:931` ("the window holds a page; Show older widens it") and `feed_entries_test.exs` pin it; both change in Phase 5 with the window.
16. **The share toggles exist and default to off** (`Settings.Preferences.ShareWatched`, `ShareWatchlist`); the card reads neither — a person's card is what arrived.
17. **`share_watched` off means the You card has no watched acts** unless the reader turned it on; the You card renders whatever `Activities.list_activities/0` holds as `own?: true`. Nothing to add.
18. **The Friends-tab tests assert the shelf card's contract** (`discovery_live_test.exs:251–402`: `[data-role='presence']`, "How friends see you", "once sharing is on under Settings → Social", `-watched-<id>`, `-watched-all`, `[data-role='watched-strip']`, `footer`). They are rewritten in Phase 3 (the card) and Phase 5 (the page).
19. **Hooks live in `assets/js/hooks/<name>.js` with a colocated `<name>.test.js`** (bun) and are registered in `app.js`; `detail_body_scroll.js` is the nearest precedent for an observer-driven hook.
20. **`expand_person` is the card's only host event** and grows the shelves; it becomes `toggle_person` (the opened card) and `open_person` (the rail's navigation).

---

## File structure

**Create**
- `lib/media_centaur_web/components/discovery/identity_tile.ex` — `identity_tile/1`.
- `lib/media_centaur_web/components/title/flag.ex` — `Title.Flag` (`@storybook_status :skip`, pure).
- `lib/media_centaur_web/components/discovery/feed_band.ex` — `feed_band/1` (renamed from `feed_entry_row.ex`, see Rename).
- `assets/js/hooks/feed_head.js`, `assets/js/hooks/feed_head.test.js`.
- `storybook/discovery/identity_tile.story.exs`; `storybook/discovery/feed_band.story.exs` (renamed).
- `test/media_centaur_web/components/discovery/identity_tile_test.exs`, `person_card_test.exs`, `feed_band_test.exs`; `test/media_centaur_web/components/title/flag_test.exs`.
- `test/support/referenced_artwork.ex` — `seed_referenced_artwork/4`, moved from `tmdb_artwork_test.exs`.
- `priv/static/images/storybook/sample-poster.jpg`, `sample-backdrop.jpg` — PD/CC fixtures from `priv/showcase/images`.
- `decisions/user-interface/2026-09-25-046-the-cinematic-feed.md`.

**Rename** (`git mv`)
- `lib/media_centaur/library/posters.ex` → `artwork.ex` (`Library.Artwork`); `test/media_centaur/library/posters_test.exs` → `artwork_test.exs`.
- `lib/media_centaur_web/live/discovery_live/activity_posters.ex` → `activity_artwork.ex` (`DiscoveryLive.ActivityArtwork`); its test likewise.
- `lib/media_centaur_web/components/discovery/feed_entry_row.ex` → `feed_band.ex`; `storybook/discovery/feed_entry_row.story.exs` → `feed_band.story.exs` (MC0009 pins the story filename to the function name).

**Modify**
- `lib/media_centaur/library.ex` — `exports:` and the moduledoc's artwork row.
- `lib/media_centaur/watch_history/views/playback_activity.ex` — one call site.
- `lib/media_centaur_web/components/title/pennant.ex` — composes `Title.Flag`.
- `lib/media_centaur_web/components/discovery/feed_entry.ex` — `backdrop_url`, `offset_crop?`.
- `lib/media_centaur_web/components/discovery/person.ex` — `Act`; `Entry` gains `kind` and `flag`; the shelves and `presence` go.
- `lib/media_centaur_web/components/discovery/person_card.ex` — rebuilt at two widths.
- `lib/media_centaur_web/live/discovery_live/people.ex` — acts, `rail/1`.
- `lib/media_centaur_web/live/discovery_live/feed_entries.ex` — the backdrop, the crop stamp, the window/cap/head.
- `lib/media_centaur_web/live/discovery_live.ex` — `full_width`, the columns, the rail, the paging events, the Friends grid, `?person=`.
- `lib/media_centaur_web/components/title/row.ex:9-10` — names the band.
- `assets/css/app.css` — `--ink`, the band block, the person card block, the Discovery columns and the fold.
- `assets/js/app.js` — registers `FeedHead`.
- `test/support/discovery_rows.ex` — `backdrop_url` override.
- `storybook/discovery/_discovery.index.exs`, `storybook/discovery/person_card.story.exs`, `storybook/title/pennants.story.exs` (unchanged contract, re-run), the five fixture-path stories.
- `test/media_centaur_web/live/discovery_live_test.exs`, `test/media_centaur_web/live/discovery_live/feed_entries_test.exs`, `people_test.exs`, `test/media_centaur_web/page_smoke_test.exs`, `test/media_centaur/tmdb_artwork_test.exs` (the moved helper).
- Records and docs (Phase 6): UIDR-045, UIDR-038, UIDR-037, UIDR-033, `decisions/README.md` (generated), `docs/social.md`, `docs/GLOSSARY.md`, `docs/storybook.md`, `.claude/skills/user-interface/SKILL.md`, the design spec, `campaigns/feed-appearance.md`, `../media-centaur.wiki/Social.md`.

---

### Phase 1: `Discovery.IdentityTile`, and the storybook fixture images

The tile is a new component (component then story); the person card is rebuilt in Phase 3, so this phase does not touch it. The fixtures come first because every later story needs a real still.

**Files:**
- Create: `lib/media_centaur_web/components/discovery/identity_tile.ex`, `test/media_centaur_web/components/discovery/identity_tile_test.exs`, `storybook/discovery/identity_tile.story.exs`
- Create: `priv/static/images/storybook/sample-poster.jpg`, `sample-backdrop.jpg`; modify the six fixture references (`grep -rn 'sample-nosferatu\|storybook/fixtures' storybook`)
- Modify: `storybook/discovery/_discovery.index.exs`

- [ ] **Step 1: The fixtures.** `find priv/showcase/images -name backdrop.jpg | head`; open two or three with Read and keep a still whose subject sits in the upper third (the crop rule's case). Copy the pair to `priv/static/images/storybook/sample-poster.jpg` and `sample-backdrop.jpg`; confirm `git check-ignore` reports neither. Repoint every `/images/sample-nosferatu-poster.jpg` and `/storybook/fixtures/poster.jpg` to `/images/storybook/sample-poster.jpg`. (`priv/static/images` is in `static_paths/0`; the plain path serves in dev, the digested one in prod.)

- [ ] **Step 2: Write the failing component test**

```elixir
defmodule MediaCentaurWeb.Components.Discovery.IdentityTileTest do
  use MediaCentaur.Case, async: true

  import Phoenix.LiveViewTest

  alias MediaCentaurWeb.Components.Discovery.IdentityTile

  defp render(attrs),
    do: &IdentityTile.identity_tile/1 |> render_component(attrs) |> LazyHTML.from_fragment()

  test "a monogram carries the name's first letter, hidden from assistive tech" do
    tile = render(name: "Cleo", size: 56) |> LazyHTML.query("[data-component='identity-tile']")

    assert tile |> LazyHTML.text() |> String.trim() == "C"
    assert LazyHTML.attribute(tile, "aria-hidden") == ["true"]
    assert LazyHTML.attribute(tile, "data-own") == []
    assert LazyHTML.attribute(tile, "data-size") == ["56"]
  end

  test "an own tile says so; the letter stays" do
    tile =
      render(name: "You", own?: true, size: 48)
      |> LazyHTML.query("[data-component='identity-tile'][data-own]")

    assert tile |> LazyHTML.text() |> String.trim() == "Y"
  end

  test "a photo replaces the letter and paints eagerly" do
    html = render(name: "Ada", size: 64, photo_url: "/images/storybook/sample-poster.jpg")
    img = LazyHTML.query(html, "[data-component='identity-tile'] img")

    assert LazyHTML.attribute(img, "src") == ["/images/storybook/sample-poster.jpg"]
    assert LazyHTML.attribute(img, "loading") == ["eager"]
    assert html |> LazyHTML.query("[data-component='identity-tile']") |> LazyHTML.text() |> String.trim() == ""
  end

  test "the size is one of the three the surfaces render" do
    assert_raise ArgumentError, fn -> render(name: "Cleo", size: 40) end
  end
end
```

(`render_component` asserts the tile's *contract* — the letter, `data-own`, `data-size`, the photo's `src`, `aria-hidden` — the way `segmented_control_test.exs` does, never its classes.)

- [ ] **Step 3: Run it to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/discovery/identity_tile_test.exs`
Expected: FAIL — `IdentityTile.identity_tile/1 is undefined`.

- [ ] **Step 4: The component**

```elixir
defmodule MediaCentaurWeb.Components.Discovery.IdentityTile do
  @moduledoc """
  The app's one drawing of a person (UIDR-046): a circle carrying the
  name's first letter — the monogram — or a photo when one exists. The
  reader's own tile is filled with the button primary and a white
  letter, so an own row is found without reading; a photo inside a
  2px primary ring says the same. Three sizes, one per surface: 48 in
  the Feed's rail, 56 on a band, 64 on the Friends page. `aria-hidden`:
  the name is read from the surface's text, the tile is its redundant
  channel.

  No photo exists today — the social protocol carries no profile
  event — so every host passes `nil`; the attr is the space the design
  leaves for one.
  """

  use Phoenix.Component

  attr :name, :string, required: true, doc: "the display name; its first grapheme is the monogram"
  attr :size, :integer, required: true, values: [48, 56, 64]
  attr :own?, :boolean, default: false
  attr :photo_url, :string, default: nil

  def identity_tile(assigns) do
    ~H"""
    <span
      class={[
        "relative grid shrink-0 place-items-center overflow-hidden rounded-full leading-none",
        @size == 48 && "size-12 text-[19px]",
        @size == 56 && "size-14 text-[22px]",
        @size == 64 && "size-16 text-[26px]",
        !@photo_url && !@own? &&
          "bg-primary/20 font-semibold text-primary ring-1 ring-inset ring-primary/25 shadow-[0_2px_8px_oklch(0%_0_0/0.35)]",
        !@photo_url && @own? &&
          "bg-primary font-bold text-primary-content shadow-[0_2px_8px_oklch(0%_0_0/0.4)]",
        @photo_url && !@own? && "ring-1 ring-inset ring-base-content/20",
        @photo_url && @own? && "ring-2 ring-primary"
      ]}
      data-component="identity-tile"
      data-size={@size}
      data-own={@own?}
      aria-hidden="true"
    >
      <img :if={@photo_url} src={@photo_url} alt="" class="size-full object-cover" loading="eager" decoding="sync" />
      {if !@photo_url, do: String.first(@name)}
    </span>
    """
  end
end
```

Class precedence is stylesheet order (the `phoenix-thinking` gotcha), which is why the states are disjoint branches rather than a base plus overrides. A photo `src` is not local artwork (no `/media-images`), so MC0028 does not apply; when the protocol brings one it will be, and the tile gets a `tile_photo_src/1` builder then.

- [ ] **Step 5: The story** — `storybook/discovery/identity_tile.story.exs`, `MediaCentaurWeb.Storybook.Discovery.IdentityTile`, `render_source :function`. Three `VariationGroup`s, one per size (`:rail_48`, `:band_56`, `:page_64`), each with four variations: `:monogram` (`name: "Cleo"`), `:photo` (`name: "Ada", photo_url: "/images/storybook/sample-poster.jpg"`), `:own` (`name: "You", own?: true`), `:own_photo`. All of `48`, `56` and `64` must appear as literals (MC0009's `values:` scan). Index entry: `def entry("identity_tile"), do: [icon: {:fa, "circle-user", :thin}, name: "Identity tile"]`.

- [ ] **Step 6: Green, precommit, look**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/discovery test/media_centaur_web/storybook_render_test.exs`, then `~/scripts/agents/agent-mix precommit` (foreground, timeout 600000). Open `/storybook/discovery/identity_tile` on :2160 and Read a `page-shot`; also the six stories that pointed at a missing image.

**Acceptance:** twelve tile states render; the six stories that pointed at a missing image now show one; MC0009 finds `identity_tile.story.exs` with `48`, `56` and `64`; nothing in the app renders the tile yet and every existing test is green.

```bash
git add -A
git commit -m "feat: the identity tile — one drawing of a person at three sizes; real storybook fixtures

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Phase 2: Row artwork — the backdrop down the same ladder

Data only; nothing renders a backdrop until Phase 4. Three seams, each test-first: the library tier by role, the resolver for both roles, the projection field.

**Files:**
- Rename + modify: `lib/media_centaur/library/posters.ex` → `artwork.ex`; `test/media_centaur/library/posters_test.exs` → `artwork_test.exs`
- Modify: `lib/media_centaur/library.ex` (`exports:` line 45 `Posters` → `Artwork`; moduledoc line 96), `lib/media_centaur/watch_history/views/playback_activity.ex:24,38`
- Rename + modify: `lib/media_centaur_web/live/discovery_live/activity_posters.ex` → `activity_artwork.ex`; its test
- Modify: `lib/media_centaur_web/components/discovery/feed_entry.ex`, `lib/media_centaur_web/live/discovery_live/feed_entries.ex`, `test/media_centaur_web/live/discovery_live/feed_entries_test.exs`, `test/support/discovery_rows.ex`, `lib/media_centaur_web/live/discovery_live.ex` (`load_activities/1`, `warm_activity_artwork/1`)

- [ ] **Step 1: `Library.Artwork` — failing tests**

`git mv` the module and its test; rename the module to `MediaCentaur.Library.Artwork`, every `Posters.urls_by_refs(refs)` in the test to `Artwork.urls_by_refs(refs, "poster")`, and append:

```elixir
  describe "urls_by_refs/2 with the backdrop role" do
    test "resolves a movie's backdrop, and an episode to its series' backdrop" do
      movie = create_movie(%{name: "Movie A"})
      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 3})

      create_image(%{owner_type: :movie, owner_id: movie.id, role: "backdrop", content_url: "a/backdrop.jpg"})
      create_image(%{owner_type: :movie, owner_id: movie.id, role: "poster", content_url: "a/poster.jpg"})
      create_image(%{owner_type: :tv_series, owner_id: series.id, role: "backdrop", content_url: "s/backdrop.jpg"})

      assert Artwork.urls_by_refs([{:movie, movie.id}, {:episode, episode.id}], "backdrop") == %{
               {:movie, movie.id} => "/media-images/a/backdrop.jpg",
               {:episode, episode.id} => "/media-images/s/backdrop.jpg"
             }
    end

    test "a role the entity lacks is simply absent" do
      movie = create_movie(%{name: "Movie A"})
      create_image(%{owner_type: :movie, owner_id: movie.id, role: "poster", content_url: "a/poster.jpg"})

      assert Artwork.urls_by_refs([{:movie, movie.id}], "backdrop") == %{}
    end
  end
```

(Grep `TestFactory` for the image builder's exact name and keys before writing; the existing `posters_test.exs` shows the shape it uses.) Run: `~/scripts/agents/agent-mix test test/media_centaur/library/artwork_test.exs` → FAIL, `Artwork.urls_by_refs/2 is undefined`.

- [ ] **Step 2: `Library.Artwork`** — the module keeps its shape; `@type role :: String.t()` with `@roles ~w(poster backdrop)`, `urls_by_refs(refs, role) when role in @roles`, and `image.role == ^role` in `poster_urls_by_owner/1` (renamed `urls_by_owner/2`). Moduledoc: "Batch artwork-URL resolution by entity reference and role — the poster or the backdrop — for surfaces outside the Library views…"; keep the episode → series sentence (both roles resolve to the series). `library.ex`: `Artwork` in `exports:`, the moduledoc row `| Artwork | \`Library.Images\`, \`Library.Artwork\`, \`Library.ImageHealth\` |`. `playback_activity.ex`: `Artwork.urls_by_refs(refs, "poster")` and its moduledoc sentence. Run `~/scripts/agents/agent-mix compile --force` once (the exports manifest), then the test → green; then `~/scripts/agents/agent-mix test test/media_centaur/watch_history` → green.

- [ ] **Step 3: `ActivityArtwork` — failing tests**

`git mv` the resolver and its test. Rewrite the test module against the new contract:

```elixir
  @library %{
    "poster" => %{{:tv_series, "series-id"} => "/media-images/series-id/poster.jpg"},
    "backdrop" => %{{:tv_series, "series-id"} => "/media-images/series-id/backdrop.jpg"}
  }

  describe "urls/3" do
    test "the library tier serves both roles for an owned title" do
      owners = %{{3219, :tv_series} => "series-id"}

      assert ActivityArtwork.urls(activity(3219, :tv_series), owners, @library) == %{
               poster_url: "/media-images/series-id/poster.jpg",
               backdrop_url: "/media-images/series-id/backdrop.jpg"
             }
    end

    test "each role falls independently: an owned entity without a backdrop falls to the next tier" do
      owners = %{{3219, :tv_series} => "series-id"}
      library = %{"poster" => @library["poster"], "backdrop" => %{}}

      assert %{poster_url: "/media-images/series-id/poster.jpg", backdrop_url: nil} =
               ActivityArtwork.urls(activity(3219, :tv_series), owners, library)
    end

    test "the hotlink asks TMDB for a poster the band can paint and a backdrop the box can" do
      assert ActivityArtwork.urls(activity(550, :movie, "/p.jpg", "/b.jpg"), %{}, %{"poster" => %{}, "backdrop" => %{}}) ==
               %{
                 poster_url: "https://image.tmdb.org/t/p/w185/p.jpg",
                 backdrop_url: "https://image.tmdb.org/t/p/w1280/b.jpg"
               }
    end

    test "nothing on any tier is nil for both — the snapshot carries no paths" do
      assert ActivityArtwork.urls(activity(550, :movie), %{}, %{"poster" => %{}, "backdrop" => %{}}) ==
               %{poster_url: nil, backdrop_url: nil}
    end
  end

  describe "missing/1" do
    test "names each identity whose row painted nothing for either role, once" do
      rows = [
        %{activity: activity(550, :movie), poster_url: nil, backdrop_url: nil},
        %{activity: activity(550, :movie), poster_url: "/media-images/x/poster.jpg", backdrop_url: nil},
        %{activity: activity(3219, :tv_series), poster_url: nil, backdrop_url: "/media-images/y/backdrop.jpg"},
        %{activity: activity(615, :tv_series), poster_url: "/p.jpg", backdrop_url: "/b.jpg"}
      ]

      assert Enum.sort(ActivityArtwork.missing(rows)) == Enum.sort([{550, :movie}, {3219, :tv_series}])
    end
  end
```

(`activity/4` grows a `backdrop_path` argument; the `library_refs/1` tests stay.) The referenced tier is filesystem-backed (`TmdbArtwork.urls/2` checks `File.exists?`); the pure test covers the library and hotlink rungs, and the page test in Phase 4 covers the referenced one through the real cache.

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live/activity_artwork_test.exs` → FAIL.

- [ ] **Step 4: `ActivityArtwork`**

```elixir
  @typedoc "The library tier's URLs per role, from `Library.Artwork.urls_by_refs/2`."
  @type library_artwork :: %{String.t() => %{Artwork.ref() => String.t()}}

  @spec urls(Activity.t(), owners(), library_artwork()) ::
          %{poster_url: String.t() | nil, backdrop_url: String.t() | nil}
  def urls(%Activity{} = activity, owners, library) do
    referenced = TmdbArtwork.urls(activity.media_type, activity.tmdb_id)

    %{
      poster_url:
        library_url(activity, owners, library["poster"]) || referenced.poster_url ||
          tmdb_cdn_url(activity.title.poster_path, :w185),
      backdrop_url:
        library_url(activity, owners, library["backdrop"]) || referenced.backdrop_url ||
          tmdb_cdn_url(activity.title.backdrop_path, :w1280)
    }
  end

  @spec missing([map()]) :: [ref()]
  def missing(rows) do
    for %{activity: %Activity{} = activity} = row <- rows,
        is_nil(row.poster_url) or is_nil(row.backdrop_url),
        uniq: true,
        do: {activity.tmdb_id, activity.media_type}
  end
```

Import `tmdb_cdn_url: 2` from `LiveHelpers` instead of `title_poster_url: 1` — one `TmdbArtwork.urls/2` call per row serves both roles. Moduledoc: the ladder stated per role; the hotlink rung's widths named with the reason (code fact 2). `DiscoveryLive.load_activities/1`:

```elixir
    refs = ActivityArtwork.library_refs(owners)
    library_artwork = Map.new(["poster", "backdrop"], &{&1, Artwork.urls_by_refs(refs, &1)})
    …
        activity
        |> ActivityArtwork.urls(owners, library_artwork)
        |> Map.merge(%{library_owner_id: Map.get(owners, ref), rung: Map.get(rungs, ref)})
        |> then(&Map.merge(row, &1))
```

`warm_activity_artwork/1` reads `ActivityArtwork.missing/1` unchanged in shape; its comment gains "or a backdrop — the band paints one". `People.build/3` keeps reading `row.poster_url`.

- [ ] **Step 5: `FeedEntry.backdrop_url` — failing projection test**

In `feed_entries_test.exs`, the test "an entry carries what the row shows…" adds `backdrop_url: "/b.jpg"` to the first row's overrides and to the `%FeedEntry{…} = review` match, and `backdrop_url: nil` to the listing's. `test/support/discovery_rows.ex` gains `backdrop_url: Map.get(overrides, :backdrop_url)`. Run → FAIL (`backdrop_url` is not a key of `FeedEntry`).

- [ ] **Step 6: The field** — `FeedEntry` gains `:backdrop_url` after `:poster_url` (struct, `@type`, moduledoc: "`poster_url` and `backdrop_url` are the row artwork, resolved by the host down the ladder; nil paints the inset tone"); `FeedEntries.entry/2` copies `row.backdrop_url`. Green.

- [ ] **Step 7: Green, precommit**

Run: `~/scripts/agents/agent-mix test test/media_centaur/library test/media_centaur_web/live/discovery_live test/media_centaur_web/live/discovery_live_test.exs test/media_centaur/watch_history`, then precommit.

**Acceptance:** `Library.Artwork.urls_by_refs/2` resolves both roles; `ActivityArtwork.urls/3` returns both and `missing/1` names either-role gaps; every `FeedEntry` carries `backdrop_url`; `Posters` and `ActivityPosters` no longer exist (`grep -rn 'Posters' lib test` is empty); the Feed renders exactly as before.

```bash
git commit -am "feat: row artwork — the backdrop resolves down the same ladder as the poster

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Phase 3: The acts strip and the person card at two widths

Storybook-first for the card (it has a story): the story is rewritten before the component. Four seams, test-first: the flag vocabulary, the acts projection, the rail's roster, the card. The Friends page still renders the card at the end of this phase — at `width: :page`, in today's single column — so the tab's tests are rewritten here to the card's new contract; the grid, `?person=` and the rail are Phase 5.

**Files:**
- Create: `lib/media_centaur_web/components/title/flag.ex`, `test/media_centaur_web/components/title/flag_test.exs`, `test/media_centaur_web/components/discovery/person_card_test.exs`
- Modify: `lib/media_centaur_web/components/title/pennant.ex`, `lib/media_centaur_web/components/discovery/person.ex`, `person_card.ex`, `lib/media_centaur_web/live/discovery_live/people.ex`, `test/media_centaur_web/live/discovery_live/people_test.exs`, `storybook/discovery/person_card.story.exs`, `assets/css/app.css`, `lib/media_centaur_web/live/discovery_live.ex` (the card's attrs and the two events), `test/media_centaur_web/live/discovery_live_test.exs` § friends tab

- [ ] **Step 1: `Title.Flag` — failing test**

```elixir
defmodule MediaCentaurWeb.Components.Title.FlagTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Activities.Activity
  alias MediaCentaurWeb.Components.Title.Flag

  test "a review flies its sentiment, or reviewed when it gives none; the other kinds fly themselves" do
    assert Flag.flag(%Activity{kind: :review, sentiment: :love}) == :love
    assert Flag.flag(%Activity{kind: :review, sentiment: nil}) == :review
    assert Flag.flag(%Activity{kind: :watched}) == :watched
    assert Flag.flag(%Activity{kind: :listing}) == :listing
  end

  test "mast order is love, like, dislike, reviewed, watched, listing, and every flag has a glyph" do
    assert Flag.mast_order() == [:love, :like, :dislike, :review, :watched, :listing]
    assert Enum.all?(Flag.mast_order(), &String.starts_with?(Flag.glyph(&1), "hero-"))
    assert Flag.glyph(:love) == "hero-heart-solid"
  end

  test "sort_by_mast/1 orders flags and drops repeats" do
    assert Flag.sort_by_mast([:watched, :love, :watched, :review]) == [:love, :review, :watched]
  end
end
```

Run → FAIL. Then the module: `flag/1`, `glyph/1` (sentiments through `Sentiment.glyph/1`; `:review`, `:watched`, `:listing` the pennant's three), `mast_order/0`, `sort_by_mast/1`; `@moduledoc` "The flag vocabulary shared by the pennant (UIDR-037) and a person card's acts strip (UIDR-046): which flag an activity flies, the glyph for a flag, and the mast order…"; `Module.register_attribute` + `@storybook_status :skip` / `@storybook_reason "Pure vocabulary, not a function component"`. `Pennant` drops its `@flags`, `glyph/1` and `flag/1` in favour of `Flag`'s (keep `Pennant.flag/1` delegating for one commit if a caller outside needs it — grep first; `mast/1` iterates `Flag.mast_order()`). `pennants_test` and the pennant story still pass.

- [ ] **Step 2: `Person.Act` and the acts projection — failing tests**

`person.ex`: `Entry` gains `kind` and `flag`; new nested `Act`:

```elixir
  defmodule Act do
    @moduledoc "One title the person acted on: what the strip shows for it and every act behind it."
    defstruct [:ref, :title, :poster_url, :activity_id, :acted_at, :episode, flags: [], entries: []]
    @type t :: %__MODULE__{…, flags: [Flag.flag()], entries: [Entry.t()]}
  end
```

`Person` becomes `[:id, :name, :own?, :pubkey, :short_npub, :added_on, :latest_at, :latest_ago, acts: []]` (`latest_ago` the relative time `People` anchors with `now`, so the card takes no clock) (`presence`, `watched`, `listed`, `reviewed` removed). In `people_test.exs` replace "a person's shelves are their activities by kind…" with:

```elixir
  test "a person's acts are one per title, newest first, flying every act on it in mast order" do
    episode = %Episode{season_number: 1, episode_number: 3}

    [bob | _rest] =
      People.build(
        [
          activity("Bob", @bob, %{tmdb_id: 7, kind: :watched, id: "w7", acted_at: ~U[2026-09-03 10:00:00Z]}),
          activity("Bob", @bob, %{tmdb_id: 7, kind: :review, sentiment: :love, id: "r7", acted_at: ~U[2026-09-03 09:00:00Z]}),
          activity("Bob", @bob, %{tmdb_id: 9, kind: :watched, episode: episode, id: "w9a", acted_at: ~U[2026-09-02 10:00:00Z], media_type: :tv_series}),
          activity("Bob", @bob, %{tmdb_id: 9, kind: :watched, episode: %Episode{season_number: 1, episode_number: 2}, id: "w9b", acted_at: ~U[2026-09-02 09:00:00Z], media_type: :tv_series}),
          activity("Bob", @bob, %{tmdb_id: 11, kind: :listing, id: "l11", acted_at: ~U[2026-09-01 10:00:00Z]})
        ],
        friends(),
        me: false,
        now: @now
      )

    assert Enum.map(bob.acts, &{&1.ref, &1.flags, &1.activity_id}) == [
             {{7, :movie}, [:love, :watched], "w7"},
             {{9, :tv_series}, [:watched], "w9a"},
             {{11, :movie}, [:listing], "l11"}
           ]

    # A binge is one poster with one eye; the episodes are the opened card's rows.
    assert Enum.map(Enum.at(bob.acts, 1).entries, & &1.activity_id) == ["w9a", "w9b"]
    assert Enum.at(bob.acts, 1).episode == episode
    assert bob.latest_at == ~U[2026-09-03 10:00:00Z]
  end

  test "rail/1 takes You and the seven most recent, and counts who the cap hid" do
    people = for index <- 1..12, do: %Person{id: "p#{index}", name: "Friend #{index}", own?: false}
    you = %Person{id: "person-you", name: "You", own?: true}

    assert %{people: shown, hidden: 5} = People.rail([you | people])
    assert length(shown) == 8
    assert hd(shown).own?

    assert %{people: [^you], hidden: 0} = People.rail([you])
  end
```

Keep the order test ("You first, then friends by latest activity, the quiet ones last by name") — `sort_key/1` reads `latest_at` now. Run → FAIL.

- [ ] **Step 3: `People`** — `person/5` groups the sorted rows by ref into `Act`s (`Enum.group_by` keeps first-seen order when built from the sorted list with `Enum.uniq_by` for the order and `group_by` for the members): `flags: rows |> Enum.map(&Flag.flag(&1.activity)) |> Flag.sort_by_mast()`, `activity_id`/`acted_at`/`episode` from the newest row, `entries` every row as an `Entry` with `kind` and `flag`; `latest_at` from the first sorted row. `rail/1`: `@rail_cap 8`, `Enum.split(people, @rail_cap)` → `%{people: shown, hidden: length(rest)}`. Moduledoc rewritten: the card's acts, the rail's roster. Green.

- [ ] **Step 4: The story, rewritten** — `storybook/discovery/person_card.story.exs`. Fixture `act/3` builds a `Person.Act` (`poster_url: "/images/storybook/sample-poster.jpg"` by default, a nil-poster variant), `person/1` a `Person`. `width` takes `:rail` and `:page` as literals (MC0009). Variations:

| Variation | `width` | State |
|---|---|---|
| `:rail_friend` | `:rail` | three acts, the second flying love and watched (two discs) |
| `:rail_photo` | `:rail` | a friend with `photo_url` on the tile — pinned on the tile's story until `Person` carries one; here the monogram |
| `:rail_no_artwork` | `:rail` | an act whose poster is nil: the 6% slot naming its title |
| `:rail_you` | `:rail` | the own tile, own acts (a love review, a listing) |
| `:rail_quiet` | `:rail` | no acts: tile and name, 72px |
| `VariationGroup :rail_flags` | `:rail` | six cards, one act each, one flag each — the six discs at 44/28 |
| `:page_friend` | `:page` | five acts, two carrying two discs |
| `:page_opened` | `:page`, `opened?: true` | seven acts wrapping 5+2, one row per poster, the foot with key, date, Remove friend |
| `:page_you` | `:page` | own acts |
| `:page_you_opened` | `:page`, `opened?: true` | the rows, no foot |
| `:page_quiet` | `:page` | no acts, 124px |
| `VariationGroup :page_flags` | `:page` | the six discs at 52/32 |

Template: `<div class="w-[560px]"><.psb-variation/></div>` for the rail (`def template` cannot vary per variation without `:template` on each; set `template:` on the rail variations and the page ones to a 900px wrapper). `layout :one_column`.

- [ ] **Step 5: The card's contract test** — `test/media_centaur_web/components/discovery/person_card_test.exs` (`render_component`, LazyHTML):

```elixir
  test "the strip is one button per act, newest first, carrying its flags and opening the newest activity" do
    html = render(person: friend_with_acts(), width: :rail)
    posters = LazyHTML.query(html, "[data-role='acts'] > button")

    assert LazyHTML.attribute(posters, "data-flags") == ["love watched", "watched", "listing"]
    assert LazyHTML.attribute(posters, "phx-value-activity") == ["r7", "w9a", "l11"]
    assert posters |> LazyHTML.query("[data-flag='love']") |> Enum.count() == 1
  end

  test "the rail shows three acts and navigates; the page shows five and opens in place" do
    rail = render(person: friend_with_acts(7), width: :rail)
    page = render(person: friend_with_acts(7), width: :page)

    assert rail |> LazyHTML.query("[data-role='acts'] > button") |> Enum.count() == 3
    assert page |> LazyHTML.query("[data-role='acts'] > button") |> Enum.count() == 5
    assert LazyHTML.attribute(LazyHTML.query(rail, "[data-component='person-card']"), "phx-click") == ["open_person"]
    assert LazyHTML.attribute(LazyHTML.query(page, "[data-component='person-card']"), "phx-click") == ["toggle_person"]
  end

  test "an opened page card shows every act, one row per poster, and the foot; the You card has no foot" do
    opened = render(person: friend_with_acts(7), width: :page, opened?: true)
    assert opened |> LazyHTML.query("[data-role='acts'] > button") |> Enum.count() == 7
    assert opened |> LazyHTML.query("[data-role='act-row']") |> Enum.count() == 7
    assert LazyHTML.query(opened, "footer button[phx-click='remove_friend']") != []

    you = render(person: you_with_acts(), width: :page, opened?: true)
    assert LazyHTML.query(you, "footer") == []
  end

  test "a person with no acts is a tile and a name: no strip, no ago, no note of any kind" do
    html = render(person: quiet_friend(), width: :rail)
    assert LazyHTML.query(html, "[data-role='acts']") == []
    assert LazyHTML.query(html, "[data-role='ago']") == []
    refute html |> LazyHTML.text() =~ "shared"
  end

  test "the tile is the identity tile at the width's size" do
    assert render(person: quiet_friend(), width: :rail) |> LazyHTML.query("[data-component='identity-tile'][data-size='48']") != []
    assert render(person: quiet_friend(), width: :page) |> LazyHTML.query("[data-component='identity-tile'][data-size='64']") != []
  end
```

Run → FAIL (`width` unknown, `acts` unknown).

- [ ] **Step 6: The CSS** — append to `assets/css/app.css` after the `.identity-row` block:

```css
/* ── Ink — the dark ground the Feed's bands and the person card share
   (UIDR-046). The identity-banner family's literal, not base-100 (27%). */
:root { --ink: oklch(13% 0.02 264); }

/* ── Person card (UIDR-046) ── one component at two widths: the rail's
   (560) and the Friends page's (900). Every size is a custom property of
   the width class; the text is Tailwind on top. */
.person-card {
  --pad: 12px 14px; --tile: 48px; --pw: 96px; --ph: 144px; --gap: 16px;
  --disc: 44px; --glyph: 28px; --ring: 3px;
  --pshadow: 0 3px 12px oklch(0% 0 0 / 0.5);
  position: relative; border-radius: 12px; background: var(--ink); padding: var(--pad);
  cursor: pointer;
}
.person-card-page {
  --pad: 30px; --tile: 64px; --pw: 130px; --ph: 195px;
  --disc: 52px; --glyph: 32px; --ring: 4px;
  --pshadow: 0 4px 16px oklch(0% 0 0 / 0.55);
}
.person-card:hover, .person-card:focus-within, .person-card-opened { background: oklch(16% 0.02 264); }
.acts-strip { display: flex; flex-wrap: wrap; gap: var(--gap); }
.act { position: relative; width: var(--pw); height: var(--ph); flex: none; border-radius: 6px;
  overflow: visible; box-shadow: var(--pshadow); cursor: pointer; }
.act > img { width: 100%; height: 100%; object-fit: cover; border-radius: 6px;
  outline: 1px solid oklch(100% 0 0 / 0.08); outline-offset: -1px; display: block; }
.act-empty { display: flex; align-items: flex-end; border-radius: 6px;
  background: oklch(from var(--color-base-content) l c h / 0.06); }
/* The act disc: ink at .85 with a 1px ring at the poster's top right,
   inset 8px; two acts stack downward 6px apart in mast order. */
.act-discs { position: absolute; top: 8px; right: 8px; display: flex; flex-direction: column;
  gap: 6px; z-index: 2; pointer-events: none; }
.act-disc { display: grid; place-items: center; width: var(--disc); height: var(--disc); border-radius: 9999px;
  background: oklch(from var(--ink) l c h / 0.85);
  box-shadow: inset 0 0 0 1px oklch(100% 0 0 / 0.18);
  color: oklch(from var(--color-base-content) l c h / 0.8); }
.act-disc > .icon, .act-disc > span { width: var(--glyph); height: var(--glyph); }
.act-disc-love { color: var(--color-love); } /* the same ink disc as every other glyph; only the heart is rose */
```

(The `.icon` selector must match what `<.icon>` emits — check `core_components.ex` and use the class it renders, or size the glyph with the `class` attr instead.) Then `~/scripts/agents/agent-mix assets.build`.

- [ ] **Step 7: The component** — `person_card.ex` rebuilt. Attrs: `attr :person, Person, required: true`; `attr :width, :atom, required: true, values: [:rail, :page]`; `attr :opened?, :boolean, default: false, doc: "the page card grown in place; the host keeps the set"`; `attr :landed?, :boolean, default: false, doc: "the card named by the address takes focus on mount"`. One public builder: `act_poster_src(url, :rail) → sized_image_url(url, 240)`, `(:page) → 320`. Structure:

```heex
<section
  id={@person.id}
  role="button"
  tabindex="-1"
  class={["person-card", @width == :page && "person-card-page", @opened? && "person-card-opened"]}
  data-component="person-card"
  data-width={@width}
  data-own={@person.own?}
  data-opened={@opened?}
  phx-click={if @width == :rail, do: "open_person", else: "toggle_person"}
  phx-value-id={@person.id}
  phx-mounted={@landed? && JS.focus()}
>
  <header class="flex items-start gap-3">  <%!-- the page card centres the name: items-center --%>
    <IdentityTile.identity_tile name={@person.name} own?={@person.own?} size={tile_size(@width)} />
    <h2 class="min-w-0 flex-1 truncate font-semibold …" data-role="name">{@person.name}</h2>
    <span :if={@person.acts != []} class="shrink-0 text-lg tabular-nums text-base-content/65" data-role="ago">{@ago}</span>
  </header>
  <div :if={@person.acts != []} class="acts-strip …" data-role="acts">
    <button :for={act <- @shown} id={"#{@person.id}-act-#{TitleRef.param(act.ref)}"} type="button" class="act"
      title={act_title(@person, act)} phx-click="open_title" phx-value-ref={TitleRef.param(act.ref)}
      phx-value-activity={act.activity_id} data-entity-id={TitleRef.param(act.ref)}
      data-flags={Enum.join(act.flags, " ")} data-nav-item tabindex="0">
      <img :if={act.poster_url} src={act_poster_src(act.poster_url, @width)} alt={act.title.name} loading="eager" decoding="sync" />
      <span :if={!act.poster_url} class="act-empty …">{act.title.name}</span>
      <span class="act-discs" aria-hidden="true">
        <span :for={flag <- act.flags} class={["act-disc", flag == :love && "act-disc-love"]} data-flag={flag}>
          <.icon name={Flag.glyph(flag)} class="…" />
        </span>
      </span>
    </button>
  </div>
  <div :if={@opened?} class="mt-5 space-y-2" data-role="act-rows"> … one row per act (`data-role="act-row"`), each a button opening that activity … </div>
  <footer :if={@opened? and not @person.own?} …> the key, the date, Remove friend (a nav item) </footer>
</section>
```

`@shown` is `Enum.take(acts, cap(@width))` — 3 / 5 — or every act when opened; `@ago` is `person.latest_ago` (the card is pure and takes no clock; `People` anchors it with `now`, as the old `presence.ago` was). The name line's sizes by width (`text-[22px] leading-7` / `text-2xl leading-8`); the row's sentence through `ActivityWords.verb/3` and the title, the glyph after it (`Flag.glyph`), the ago right. The strip's poster press is the whole `button`; the card's press is the root; LiveView dispatches the closest `phx-click`, so nesting is fine (the feed row already relies on it). Nav items: the posters, the rows and Remove friend keep `data-nav-item` (they exist today); the root gets none until Phase 7. Moduledoc rewritten from the spec's person-card paragraphs.

- [ ] **Step 8: The host, minimally** — `discovery_live.ex`: `expanded_people` → `opened_people`; `handle_event("toggle_person", %{"id" => id})` toggles membership; `handle_event("open_person", %{"id" => id})` → `push_navigate(to: ~p"/discovery/friends?person=#{id}")` (the page reads it in Phase 5; until then it opens the tab); the Friends tab renders `<PersonCard.person_card :for={person <- @people} person={person} width={:page} opened?={MapSet.member?(@opened_people, person.id)} />`. The `data-nav-zone="people"` wrapper stays.

- [ ] **Step 9: The Friends-tab tests, rewritten** (`discovery_live_test.exs:251–402`):
  - "a friend's card carries their shelves and presence; a poster opens that act" → "a friend's card is their acts as posters with their discs; a poster opens the newest act; an opened row opens a specific act": assert `friend_card() <> "-act-tv_series-1399[data-flags='watched listing']"` (a listing and a watch on one show are two discs on one poster); click it → `assert_patch` with the newest activity; open the card (`element(friend_card()) |> render_click()`), click `friend_card() <> "-#{listed.id}"` → the listing's modal; the review's row shows `.text-love` no longer — the glyph is `[data-flag='love']` in the row.
  - "the You card shows what you broadcast and deletes it by kind" → the rows are behind the press: open `#person-you`, then the existing assertions on `#person-you-#{rec.id}`; drop the presence and "How friends see you" assertions.
  - "an activity for a title in the library paints the entity's poster" → the selector becomes `#person-you-act-movie-424242 img[src^='/media-images/#{movie.id}/poster.jpg']`.
  - "a You card with nothing shared says where sharing starts" → "a You card with nothing shared is a tile and a name": `refute render(view) =~ "sharing is on"`, `refute has_element?(view, "#person-you [data-role='acts']")`, `has_element?(view, "#person-you [data-component='identity-tile'][data-own]")`.
  - "all N grows the strip in place" → "a press opens the card: every act, one row each, the foot; the same press closes it": seven acts → five posters; `render_click` the card → seven posters and seven `[data-role='act-row']`, `footer` with Remove friend; click again → five, no footer.
  - "adds a friend by npub + name, shows their card, and removes" → open the card before asserting the footer's npub and clicking Remove friend.

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/components test/media_centaur_web/live/discovery_live` → green.

- [ ] **Step 10: Precommit and look.** `~/scripts/agents/agent-mix precommit`. `page-shot` `/storybook/discovery/person_card` and `/discovery/friends` on :2160 (the real roster); Read each and the half-size copy: the six discs' glyphs at 28 — thumbs up from down, eye from bubble, the bookmark's notch — and two discs read as two. If the 28px glyph merges the thumbs, note it for the owner (the fallback is 32/36, CRITIQUE-9's owner's call) rather than changing the size silently.

**Acceptance:** `Title.Flag` is the one flag vocabulary and the pennant composes it; `Person.acts` is one per title newest first with flags in mast order; `People.rail/1` caps at eight; the card renders at both widths from one function with every state in its story; no card carries a presence line or a sharing note; the Friends tab renders the page card in today's column with its rewritten tests green; MC0009 finds `:rail` and `:page`.

```bash
git add -A
git commit -m "feat: the person card at two widths — the acts strip with act discs, the opened card

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Phase 4: The band

Storybook-first: the story is rewritten before the component. The DOM contract is kept (decision 1), so the page tests are the regression net while the look changes underneath them. For this phase every entry renders as a band inside the old list surface — ugly for one commit and correct; the columns are Phase 5.

**Files:**
- Rename: `storybook/discovery/feed_entry_row.story.exs` → `feed_band.story.exs`; `lib/media_centaur_web/components/discovery/feed_entry_row.ex` → `feed_band.ex`
- Create: `test/media_centaur_web/components/discovery/feed_band_test.exs`, `test/support/referenced_artwork.ex`
- Modify: `storybook/discovery/_discovery.index.exs`, `feed_entry.ex` (`offset_crop?`), `feed_entries.ex` (the crop stamp), `feed_entries_test.exs`, `assets/css/app.css`, `discovery_live.ex` (the alias and the call), `title/row.ex:9-10`, `discovery_live_test.exs` (the artwork page test), `test/media_centaur/tmdb_artwork_test.exs` (the moved helper)

- [ ] **Step 1: The crop offset — failing projection test**

```elixir
    test "the second of two adjacent entries of one title carries the offset crop; a run alternates" do
      at = fn minutes -> DateTime.add(~U[2026-09-01 12:00:00Z], -minutes, :minute) end

      %{entries: entries} =
        build([
          row("Cleo", %{tmdb_id: 7, kind: :listing, id: "a", acted_at: at.(0)}),
          row("Nick", %{tmdb_id: 7, kind: :review, id: "b", acted_at: at.(1)}),
          row("Sam", %{tmdb_id: 7, kind: :review, id: "c", acted_at: at.(2)}),
          row("Sam", %{tmdb_id: 8, kind: :listing, id: "d", acted_at: at.(3)}),
          row("Ada", %{tmdb_id: 7, kind: :listing, id: "e", acted_at: at.(4)})
        ])

      assert Enum.map(entries, &{&1.activity_id, &1.offset_crop?}) ==
               [{"a", false}, {"b", true}, {"c", false}, {"d", false}, {"e", false}]
    end

    test "adjacency is judged inside the scope and the window, not the whole list" do
      rows = [
        row("Cleo", %{tmdb_id: 7, kind: :listing, id: "cleo", acted_at: ~U[2026-09-01 12:00:00Z]}),
        row(nil, %{tmdb_id: 8, kind: :review, id: "mine", acted_at: ~U[2026-09-01 11:59:00Z]}, %{own?: true}),
        row("Nick", %{tmdb_id: 7, kind: :review, id: "nick", acted_at: ~U[2026-09-01 11:58:00Z]})
      ]

      assert Enum.map(build(rows, scope: :everyone).entries, & &1.offset_crop?) == [false, false, false]
      assert Enum.map(build(rows, scope: :friends).entries, & &1.offset_crop?) == [false, true]
    end
```

Run → FAIL.

- [ ] **Step 2: The projection** — `FeedEntry` gains `offset_crop?: false` (default in `defstruct`, `boolean()` in the type; moduledoc: "the second of two adjacent rows of one title, so two stills of one frame never repeat exactly — UIDR-046's crop rule"). In `FeedEntries.build/2` the windowed entries pass through `stamp_crops/1`:

```elixir
  # The crop rule's one variable: a row directly under a row of the same
  # title takes the offset, unless that row already did — a run alternates.
  defp stamp_crops(entries) do
    entries
    |> Enum.map_reduce(nil, fn entry, above ->
      offset? = above != nil and above.ref == entry.ref and not above.offset_crop?
      entry = %{entry | offset_crop?: offset?}
      {entry, entry}
    end)
    |> elem(0)
  end
```

Green.

- [ ] **Step 3: The story, rewritten** — `git mv` both files. `storybook/discovery/feed_band.story.exs`, module `MediaCentaurWeb.Storybook.Discovery.FeedBand`, `function: &…FeedBand.feed_band/1`, `layout :one_column`, template `<div class="feed-column w-[1236px]"><.psb-variation/></div>`. The fixture `entry/2` gains `backdrop_url: "/images/storybook/sample-backdrop.jpg"` and `offset_crop?: false`. Variations (every state a component can hold; page states are named with where they are pinned):

| Variation | State |
|---|---|
| `:listing` | a friend wants to watch: two lines, the time at the text zone's edge, the still in its box |
| `:review_like_with_text`, `:review_love`, `:review_dislike`, `:review_text_only`, `:review_bare` | the sentiment matrix, kept; the review at two lines |
| `:own_listing` | the own tile, "You want to watch", Listed filled, no Ignore |
| `:own_review` | the own tile, a love review |
| `:listed_title`, `:following_title`, `:in_library`, `:downloading` | the two slots' plain states |
| `:no_artwork` | `poster_url: nil, backdrop_url: nil`: the inset tone, the empty poster slot |
| `:no_backdrop` | a poster and no still |
| `VariationGroup :adjacent_pair` | `:first` (`offset_crop?: false`), `:second` (`offset_crop?: true`) — the same still twice, 30% then 38%; group template `<div class="feed-column w-[1236px]"><.psb-variation-group/></div>` |
| `:hovered` | template `<div class="feed-column w-[1236px] feed-hover-pin"><.psb-variation/></div>`: the seat shown, the scrim × .8 — List · Download · Ignore |
| `:own_hovered` | hover-pinned own band: List · Download |
| the cursor ring | Phase 7 (no nav item yet) |
| a photo on the tile | the tile's story (decision 4) |
| Everyone / Friends / You, the empty Feed, "N new", the cap | page states, pinned in `discovery_live_test.exs` |

Index: `def entry("feed_band"), do: [icon: {:fa, "stream", :thin}, name: "Feed band"]`.

- [ ] **Step 4: The CSS** — append after the person-card block:

```css
/* ── Feed bands (UIDR-046) ── one unit, one size: the title's still in a
   right-hand image box under the ink scrim, the words in the text zone on
   the left. Every position is a custom property; the text is Tailwind on top. */
:root {
  --feed-text-zone: 700px;   /* no image box begins left of it */
  --feed-dissolve: 360px;    /* the scrim's dissolve across the box's left */
}
.feed-column { display: flex; flex-direction: column; gap: 6px; }
.feed-band {
  --s: 1;
  --h: 224px; --box: 900px;
  --tile: 56px; --x-tile: 20px;
  --pw: 100px; --ph: 150px; --x-poster: 92px; --pad-y: 24px;
  --x-body: 210px;
  --bx: max(var(--feed-text-zone), calc(100% - var(--box)));
  position: relative; height: var(--h); border-radius: 12px; overflow: hidden;
  background: var(--ink); isolation: isolate; cursor: pointer;
}
.feed-band-backdrop {
  position: absolute; top: 0; left: var(--bx); width: calc(100% - var(--bx)); height: 100%;
  object-fit: cover; object-position: 50% 30%; display: block;
  mask-image: linear-gradient(to right, transparent, #000 240px);
}
.feed-band-offset .feed-band-backdrop { object-position: 50% 38%; }
.feed-band-scrim {
  position: absolute; inset: 0; pointer-events: none;
  background: linear-gradient(to right,
    oklch(from var(--ink) l c h / calc(0.97 * var(--s))) 0,
    oklch(from var(--ink) l c h / calc(0.93 * var(--s))) var(--bx),
    oklch(from var(--ink) l c h / calc(0.55 * var(--s))) calc(var(--bx) + 120px),
    oklch(from var(--ink) l c h / calc(0.16 * var(--s))) calc(var(--bx) + 240px),
    oklch(from var(--ink) l c h / calc(0.04 * var(--s))) calc(var(--bx) + var(--feed-dissolve)),
    oklch(from var(--ink) l c h / 0) 100%);
}
.feed-band-bare { background: var(--glass-inset-bg); }
.feed-band-bare .feed-band-scrim {
  background: linear-gradient(to right, oklch(from var(--ink) l c h / 0.35), oklch(from var(--ink) l c h / 0) 800px);
}
.feed-band-tile   { position: absolute; left: var(--x-tile); top: calc(50% - var(--tile) / 2); z-index: 2; }
.feed-band-poster { position: absolute; left: var(--x-poster); top: var(--pad-y); width: var(--pw); height: var(--ph); z-index: 2;
  border-radius: 6px; box-shadow: 0 3px 12px oklch(0% 0 0 / 0.55); }
.feed-band-body   { position: absolute; left: var(--x-body); right: calc(100% - var(--feed-text-zone)); top: var(--pad-y); bottom: var(--pad-y); z-index: 2; }
.feed-band-time   { position: absolute; right: calc(100% - var(--feed-text-zone)); top: var(--pad-y); z-index: 2; }
/* hover: every scrim alpha × .8 and the ground lifts; nothing moves. The
   catalog pins it with .feed-hover-pin, since a story cannot hover. */
.feed-band:hover, .feed-band:focus-within, .feed-hover-pin > .feed-band { --s: 0.8; background: oklch(16% 0.02 264); }
.feed-band-bare:hover, .feed-band-bare:focus-within, .feed-hover-pin > .feed-band-bare { background: oklch(20% 0.017 264 / 0.5); }
```

The scrim's stops are G's (.93 at the box's edge, .55 at +120, .16 at +240, .04 at +360) — G names them at 700/820/940/1060 in the 1236 column, i.e. relative to the box's left edge, which `--bx` is. Then `~/scripts/agents/agent-mix assets.build`.

- [ ] **Step 5: The component** — `lib/media_centaur_web/components/discovery/feed_band.ex`, `Discovery.FeedBand`, `feed_band/1`, `attr :entry, FeedEntry, required: true`. Two public builders (MC0028 sees `*_src(`):

```elixir
  @doc "The `src` a band's still paints — one definition, so a prefetch can match it."
  @spec band_backdrop_src(String.t() | nil) :: String.t() | nil
  def band_backdrop_src(url), do: sized_image_url(url, 1280)

  @spec band_poster_src(String.t() | nil) :: String.t() | nil
  def band_poster_src(url), do: sized_image_url(url, 240)
```

The template, from G's DOM, keeping the row's contract:

```heex
<div
  id={@entry.id}
  role="button"
  class={["group feed-band text-left", @entry.offset_crop? && "feed-band-offset", !@entry.backdrop_url && "feed-band-bare"]}
  data-component="feed-row"
  data-kind={@entry.kind}
  data-own={@entry.own?}
  data-offset-crop={@entry.offset_crop?}
  data-list-slot={@entry.list_slot}
  data-download-slot={slot_name(@entry.download_slot)}
  phx-click="open_title"
  phx-value-ref={TitleRef.param(@entry.ref)}
  phx-value-activity={@entry.activity_id}
  data-entity-id={TitleRef.param(@entry.ref)}
>
  <img :if={@entry.backdrop_url} src={band_backdrop_src(@entry.backdrop_url)} alt="" class="feed-band-backdrop" data-role="backdrop" loading="eager" decoding="sync" />
  <div class="feed-band-scrim" aria-hidden="true"></div>
  <span class="feed-band-tile"><IdentityTile.identity_tile name={@entry.author} own?={@entry.own?} size={56} /></span>
  <img :if={@entry.poster_url} src={band_poster_src(@entry.poster_url)} alt="" class="feed-band-poster object-cover" data-role="poster" loading="eager" decoding="sync" />
  <div :if={!@entry.poster_url} class="feed-band-poster bg-base-content/6 ring-1 ring-inset ring-base-content/10" data-role="poster-empty"></div>
  <div class="feed-band-body text-on-image flex flex-col">
    <p class="truncate text-[22px] leading-[30px] text-base-content/80" data-role="who">
      <span class="font-medium text-base-content/95">{@entry.author}</span>
      {ActivityWords.verb(@entry.kind, nil, subject(@entry))}
      <Sentiment.sentiment_glyph :if={@entry.sentiment} sentiment={@entry.sentiment} class="size-5" />
    </p>
    <p class="flex items-baseline gap-2.5 text-[28px] leading-9 font-semibold" data-role="title">
      <span class="truncate">{@entry.title.name}</span>
      <span :if={@entry.title.year} class="shrink-0 text-lg font-normal text-base-content/65">{@entry.title.year}</span>
    </p>
    <p :if={@entry.text} class="mt-1 line-clamp-2 text-[22px] leading-[30px] text-base-content/78" data-role="text">{@entry.text}</p>
    <div class="-mx-1.5 mt-auto flex h-8 items-center gap-0.5 text-lg text-base-content/80 opacity-0 transition-opacity duration-120 group-hover:opacity-100 group-focus-within:opacity-100" data-role="toolbar">
      …the four slots as today at 18px with 20px icons; Ignore gets `ml-2.5` instead of `ml-auto`…
    </div>
  </div>
  <span class="feed-band-time text-on-image text-lg tabular-nums text-base-content/78" data-role="time">{@entry.ago}</span>
</div>
```

Alphas: 80% body, 95% name, 65% year (MC0034 wants an integer ≥ 55; G's 66% rounds to `/65`), 78% review and time, 80% seat. The tile's position is the band's (`span.feed-band-tile`), its look the tile's. Moduledoc rewritten from the spec's *Band* row plus the contract paragraph; `title/row.ex:9-10` now says `Discovery.FeedBand`. A small `feed_band_test.exs` pins the contract the page tests do not: `data-offset-crop`, `img[data-role='backdrop'][src$='?w=1280']`, `[data-role='poster-empty']` when the poster is nil, the tile at `data-size='56'` with `data-own` on an own entry.

- [ ] **Step 6: Wire the page minimally** — in `discovery_live.ex`, alias `FeedBand`, and `<FeedBand.feed_band :for={entry <- @feed} entry={entry} />` inside the old `#feed-list` (the column is Phase 5). Run the page tests: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs` — all green without edits proves decision 1 held. Then the storybook render test.

- [ ] **Step 7: The artwork page test.** Move `seed_entry/4` from `tmdb_artwork_test.exs` into `test/support/referenced_artwork.ex` as `seed_referenced_artwork/4` (both files use it). In `discovery_live_test.exs` § feed tab, with a `setup` that points the config's `data_dir` at a temp directory the way `tmdb_artwork_test.exs:7-17` does (a `:persistent_term` write, legal in this `async: false` module and restored by the checkout):

```elixir
    test "a band paints the library entity's backdrop for an owned title, the artwork cache's for an unowned one, nothing for a bare one",
         %{conn: conn, data_dir: data_dir} do
      movie = create_standalone_movie(%{name: "Sample Movie 424242"})
      create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "424242"})
      create_linked_file(%{movie_id: movie.id})
      create_image(%{movie_id: movie.id, role: "backdrop", content_url: "#{movie.id}/backdrop.jpg", extension: "jpg"})
      seed_referenced_artwork(data_dir, :movie, 777, [:backdrop])

      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      now = System.os_time(:second)
      {:ok, owned} = Activities.ingest(friend_listing_event(424_242, now))
      {:ok, cached} = Activities.ingest(friend_listing_event(777, now - 60))
      {:ok, bare} = Activities.ingest(friend_listing_event(778, now - 120))

      {:ok, view, _html} = live(conn, "/discovery")

      assert has_element?(view, entry(owned) <> " img[data-role='backdrop'][src='/media-images/#{movie.id}/backdrop.jpg?w=1280']")
      assert has_element?(view, entry(cached) <> " img[data-role='backdrop'][src='/media-images/images/tmdb/movie-777/backdrop.jpg?w=1280']")
      refute has_element?(view, entry(bare) <> " img[data-role='backdrop']")
      assert has_element?(view, entry(bare) <> " [data-role='poster-empty']")

      await_supervised_tasks()
    end
```

(An empty `backdrop.jpg` is enough: the page checks `File.exists?`, never decodes. The warm path behaves as in every existing feed test: gated by `Capabilities.tmdb_ready?/0`, awaited by `await_supervised_tasks/0`.)

- [ ] **Step 8: Precommit and look.** `~/scripts/agents/agent-mix precommit`. `page-shot` `/storybook/discovery/feed_band` at 1920 and Read it and its half-size copy: the still's crop on the adjacent pair; the seat on the hover-pinned variations; every text readable at half.

**Acceptance:** every variation renders at 224px; the crop offset alternates in the projection; the page tests pass untouched; MC0009 finds `feed_band.story.exs`; no `loading="lazy"`; every `/media-images` src is width-declared; the half-size check passes on the story.

```bash
git add -A
git commit -m "feat: the feed band — one unit on the title's still under the ink scrim, at couch scale

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Phase 5: The page — full width, two columns, the rail, paging, the Friends grid

Four seams: the window/cap/head in the projection (pure), the `FeedHead` hook (bun), the template, the page tests.

**Files:**
- Create: `assets/js/hooks/feed_head.js`, `assets/js/hooks/feed_head.test.js`
- Modify: `assets/js/app.js`, `lib/media_centaur_web/live/discovery_live/feed_entries.ex`, `test/media_centaur_web/live/discovery_live/feed_entries_test.exs`, `lib/media_centaur_web/live/discovery_live.ex` (`mount`, `handle_params`, the events, `render/1`, the moduledoc), `assets/css/app.css` (the columns and the fold), `test/media_centaur_web/live/discovery_live_test.exs` § feed tab and § friends tab, `test/media_centaur_web/page_smoke_test.exs`

- [ ] **Step 1: The window, the cap and the head — failing projection tests**

In `feed_entries_test.exs`, the window test becomes the paging test:

```elixir
    test "the window is twenty, Show older adds twenty, sixty is the cap" do
      rows = for id <- 1..70, do: row("Nick", %{tmdb_id: id, kind: :listing, id: "act-#{id}", acted_at: DateTime.add(@now, -id, :minute)})

      assert FeedEntries.page_size() == 20
      assert FeedEntries.cap() == 60
      assert %{entries: entries, has_older?: true, at_cap?: false} = build(rows, window: 20)
      assert length(entries) == 20
      assert %{has_older?: true, at_cap?: false} = build(rows, window: 40)
      assert %{entries: entries, has_older?: false, at_cap?: true} = build(rows, window: 60)
      assert length(entries) == 60
      assert %{has_older?: false, at_cap?: false} = build(Enum.take(rows, 45), window: 60)
    end

    test "a head freezes the window at the newest band shown and counts what arrived above it as queued" do
      rows = for id <- 1..5, do: row("Nick", %{tmdb_id: id, kind: :listing, id: "act-#{id}", acted_at: DateTime.add(@now, -id, :minute)})

      assert %{entries: entries, queued: 0} = build(rows, head: nil)
      assert Enum.map(entries, & &1.activity_id) == ~w(act-1 act-2 act-3 act-4 act-5)

      assert %{entries: entries, queued: 2} = build(rows, head: "act-3")
      assert Enum.map(entries, & &1.activity_id) == ~w(act-3 act-4 act-5)

      # A head the list no longer holds (withdrawn) is live again.
      assert %{queued: 0, entries: [_, _, _, _, _]} = build(rows, head: "gone")
    end

    test "the queue is counted in the scope" do
      rows = [
        row("Cleo", %{tmdb_id: 1, kind: :listing, id: "cleo", acted_at: ~U[2026-09-01 13:00:00Z]}),
        row(nil, %{tmdb_id: 2, kind: :review, id: "mine", acted_at: ~U[2026-09-01 12:30:00Z]}, %{own?: true}),
        row("Nick", %{tmdb_id: 3, kind: :listing, id: "nick", acted_at: ~U[2026-09-01 12:00:00Z]})
      ]

      assert build(rows, scope: :everyone, head: "nick").queued == 2
      assert build(rows, scope: :friends, head: "nick").queued == 1
    end
```

`build/2`'s default opts in the test gain `head: nil`. Run → FAIL.

- [ ] **Step 2: The projection** — `@page_size 20`, `@cap 60`, `cap/0`; `build/2` takes `head: activity_id | nil`:

```elixir
    sorted = rows |> Enum.filter(&(entry?(&1) and in_scope?(&1, scope))) |> Enum.sort_by(& &1.activity.acted_at, {:desc, DateTime})
    {queued, visible} = split_at_head(sorted, Keyword.get(opts, :head))
    window = min(Keyword.fetch!(opts, :window), @cap)

    %{
      entries: visible |> Enum.take(window) |> Enum.map(&entry(&1, now)) |> stamp_crops(),
      has_older?: length(visible) > window and window < @cap,
      at_cap?: window == @cap and length(visible) > @cap,
      queued: length(queued)
    }

  # The head is the newest band the reader was shown; what sorts above it
  # arrived since and waits behind "N new". No head, or a head that was
  # withdrawn, is live.
  defp split_at_head(sorted, nil), do: {[], sorted}

  defp split_at_head(sorted, head) do
    case Enum.split_while(sorted, &(&1.activity.id != head)) do
      {_all, []} -> {[], sorted}
      {above, from_head} -> {above, from_head}
    end
  end
```

Moduledoc: the window, the cap, the head. The existing `feed_entries_test` line `assert FeedEntries.page_size() == 50` goes with the old window test. Green.

- [ ] **Step 3: The `FeedHead` hook — failing bun test**

`assets/js/hooks/feed_head.test.js`: construct the hook with a fake element and a fake `IntersectionObserver` (capture the callback), call it with `isIntersecting: false` → `pushEvent("feed_scrolled")` once; `true` → `pushEvent("feed_at_top")`; a repeated `false` pushes nothing (the crossing, not the state); `destroyed()` disconnects. Run `bun test assets/js/hooks/feed_head.test.js` → FAIL. Then:

```js
// The column's head leaving and returning to the viewport, reported once per
// crossing, so the LiveView knows whether an arrival may move the column.
export const FeedHead = {
  mounted() {
    this.atTop = true
    this.observer = new IntersectionObserver(([entry]) => {
      const atTop = entry.isIntersecting
      if (atTop === this.atTop) return
      this.atTop = atTop
      this.pushEvent(atTop ? "feed_at_top" : "feed_scrolled", {})
    }, { rootMargin: "0px 0px -100% 0px" })  // check the margin that means "the sentinel is at or above the fold's top"; state the choice in a comment
    this.observer.observe(this.el)
    this.handleEvent("feed:scroll_top", () => window.scrollTo({ top: 0 }))
  },
  destroyed() { this.observer?.disconnect() },
}
```

Register in `app.js` beside `StripChart`. The dependency-cruiser boundaries (`mix boundaries`) see a hook importing nothing; fine.

- [ ] **Step 4: Failing page tests** (§ feed tab; the helpers `entry/1`, `entries/1`, `feed_badge/0` exist):

```elixir
    test "the window is twenty; Show older widens it by twenty to sixty, then the foot says so", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      now = System.os_time(:second)
      for offset <- 1..65, do: {:ok, _} = Activities.ingest(friend_listing_event(1000 + offset, now - offset))

      {:ok, view, _html} = live(conn, "/discovery")
      assert length(entries(view)) == 20
      assert has_element?(view, feed_badge(), "20")
      view |> element("#feed-show-older") |> render_click()
      assert length(entries(view)) == 40
      view |> element("#feed-show-older") |> render_click()
      assert length(entries(view)) == 60
      refute has_element?(view, "#feed-show-older")
      assert has_element?(view, "#feed-cap", "That's the last sixty.")

      await_supervised_tasks()
    end

    test "at the top an arrival prepends live; scrolled, it queues behind N new until pressed", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      now = System.os_time(:second)
      {:ok, first} = Activities.ingest(friend_listing_event(701, now - 60))
      {:ok, view, _html} = live(conn, "/discovery")

      {:ok, live_one} = Activities.ingest(friend_listing_event(702, now - 30))
      assert entries(view) == ["feed-row-#{live_one.id}", "feed-row-#{first.id}"]
      refute has_element?(view, "#feed-new")

      render_hook(view, "feed_scrolled", %{})
      {:ok, queued} = Activities.ingest(friend_listing_event(703, now))
      refute has_element?(view, entry(queued))
      assert has_element?(view, "#feed-new", "1 new")
      assert has_element?(view, feed_badge(), "2")

      view |> element("#feed-new") |> render_click()
      assert hd(entries(view)) == "feed-row-#{queued.id}"
      refute has_element?(view, "#feed-new")

      render_hook(view, "feed_scrolled", %{})
      {:ok, _later} = Activities.ingest(friend_listing_event(704, now + 1))
      render_hook(view, "feed_at_top", %{})
      refute has_element?(view, "#feed-new")
      assert length(entries(view)) == 4

      await_supervised_tasks()
    end

    test "the rail lists You first then friends by latest act, capped at eight with All N friends; a card opens the Friends tab at the person", %{conn: conn} do
      for index <- 1..10, do: {:ok, _} = Social.add_friend(friend_pubkey(index), "Friend #{index}")
      … ingest one listing per friend at descending times …
      {:ok, view, _html} = live(conn, "/discovery")

      assert hd(ids(view, "#feed-rail [data-component='person-card']")) == "person-you"
      assert length(ids(view, "#feed-rail [data-component='person-card']")) == 8
      assert has_element?(view, "#feed-rail-all", "All 10 friends")
      assert has_element?(view, "#feed-rail [data-component='person-card'][data-width='rail']")

      view |> element("#feed-rail #person-" <> String.slice(friend_pubkey(1), 0, 8)) |> render_click()
      assert_redirect(view, "/discovery/friends?person=person-" <> String.slice(friend_pubkey(1), 0, 8))

      await_supervised_tasks()
    end

    test "the rail is on the Feed and Watchlist tabs, not the Friends tab; the scope and Show older leave it alone", %{conn: conn} do
      …
    end
```

(Generating ten friend keypairs: `Secret.wrap` a distinct 64-hex secret per index and derive the pubkey with `Keys`; the existing helpers show the two-key pattern.) § friends tab:

```elixir
    test "?person= opens that card and lands on it; the grid holds every person", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, view, _html} = live(conn, "/discovery/friends?person=person-" <> String.slice(@friend_pubkey, 0, 8))
      assert has_element?(view, friend_card() <> "[data-opened='true']")
      assert has_element?(view, "#friends-grid " <> friend_card())
    end
```

Run → FAIL.

- [ ] **Step 5: The CSS** — the columns and the fold, after the band block:

```css
/* ── Discovery's columns (UIDR-046) ── the feed column beside the rail
   above 1600px of content; one column below. The width is the
   container's, never an assign's. The Friends grid folds at 1700. */
.discovery-page { container: discovery / inline-size; }
.discovery-columns { display: grid; grid-template-columns: minmax(0, 1fr); column-gap: 24px; align-items: start; }
.discovery-rail { display: none; }
@container discovery (min-width: 1600px) {
  .discovery-columns { grid-template-columns: minmax(0, 1fr) 560px; }
  .discovery-rail { display: flex; flex-direction: column; gap: 6px; }
}
.friends-grid { display: grid; grid-template-columns: minmax(0, 1fr); gap: 20px; align-items: start; }
@container discovery (min-width: 1700px) {
  .friends-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}
```

`assets.build`.

- [ ] **Step 6: The template and the events** (`discovery_live.ex`):

- `<Layouts.app … full_width …>`; the inner wrapper `mx-auto w-full max-w-4xl space-y-4 pt-10` → `discovery-page w-full space-y-4 pt-10`.
- `mount` assigns `feed_head: nil`, `feed_queued: 0`, `feed_at_cap?: false`, `opened_people: MapSet.new()`, `landed_person: nil`; `feed_window: FeedEntries.page_size()` stays (now 20).
- `handle_params`: the scope as today, `feed_head` reset to nil on a scope change, `landed_person` from `params["person"]` added to `opened_people` on the Friends tab.
- Events: `feed_scrolled` → `feed_head = hd(@feed).activity_id` (nil when empty); `feed_at_top` → nil and `project`; `feed_show_new` → nil, `project`, `push_event(socket, "feed:scroll_top", %{})`; `feed_show_older` → `min(window + page_size, cap)`.
- `project/1` passes `head:` and assigns `feed_queued`, `feed_at_cap?`; `people` as today plus `rail: People.rail(people)`.
- The Feed tab's body:

```heex
<div class="discovery-columns">
  <div class="min-w-0">
    <div id="feed-head" phx-hook="FeedHead" phx-update="ignore" class="h-0"></div>
    <button :if={@feed_queued > 0} id="feed-new" type="button" class="… sticky top-3 z-10 …" phx-click="feed_show_new">
      <.icon name="hero-arrow-up" class="size-5" /> {@feed_queued} new
    </button>
    <.empty_state :if={@feed == []} … as today … />
    <div :if={@feed != []} id="feed-list" class="feed-column">
      <FeedBand.feed_band :for={entry <- @feed} entry={entry} />
    </div>
    <div :if={@feed_has_older?} class="pl-5 pt-2.5">
      <.button id="feed-show-older" variant="dismiss" size="sm" phx-click="feed_show_older">Show older</.button>
    </div>
    <p :if={@feed_at_cap?} id="feed-cap" class="pl-5 pt-2.5 text-xl text-base-content/65">That's the last sixty.</p>
  </div>
  <.rail :if={@live_action != :friends} rail={@rail} />
</div>
```

`rail/1` a private component in the LiveView (it is page composition, not a reusable component — no story; `data-nav-zone` none until Phase 7): `<aside id="feed-rail" class="discovery-rail">` with `<PersonCard.person_card :for={person <- @rail.people} person={person} width={:rail} />` and `<.link :if={@rail.hidden > 0} id="feed-rail-all" navigate={~p"/discovery/friends"} class="…">All {length(@friends)} friends</.link>`. The Watchlist tab's body goes into the same `discovery-columns` with the rail; the Friends tab renders `<div id="friends-grid" class="friends-grid" data-nav-zone="people">` with `width={:page}`, `opened?`, `landed?={person.id == @landed_person}`, then `AddFriendBlock` and the Settings pointer.
- The moduledoc's Feed and Friends paragraphs rewritten from the spec (the columns, the rail, the window/cap/head, the grid, `?person=`).

- [ ] **Step 7: The smoke** — `page_smoke_test.exs`: the `/discovery` fixture seeds one friend with a listing on a title the library owns (poster and backdrop images) and one own review, so the smoke renders a band's artwork branch, the rail with You and a friend, and the Friends grid; add `{"/discovery/friends?person=person-you", "discovery friends, a card opened"}`.

- [ ] **Step 8: Green, precommit, the three widths**

`~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/live/discovery_live test/media_centaur_web/page_smoke_test.exs`, `bun test assets/js/hooks`, then precommit. On :2160 (the real roster) `page-shot` `/discovery` at `1920x1080`, `1280x800`, `2560x1440`, and `/discovery?scope=you`, `/discovery/friends`, `/discovery/watchlist` at 1920; the half-size copy of each 1920 shot. Read each. What to look for, from G and J: the feed column at 1236 beside the rail at 560 with the 24 gutter; four bands and about five rail cards in the 1080 fold; the still's box beginning at x≈700; at 1280 no rail and the box from 700 (a 480 box at 1180); at 2560 the 900 cap; the Friends grid two across with the heads on one line; every name, ago, sentence, title and glyph readable at half.

**Acceptance:** the page is two columns above the fold and one below, with no assign for the width; the rail is You first, seven by latest act, *All N friends* when the cap hides anyone, absent on the Friends tab; the window is 20/40/60 with the cap's foot line; an arrival prepends live at the top and queues behind "N new" when scrolled; a rail card opens the Friends tab at its person; the grid folds at 1700; the tab count follows the scope; the modal opens from a band and closes to the same scope (existing tests); the three widths and the half-size check read as the spec describes.

```bash
git commit -am "feat: the Feed at full width — bands beside the rail, a windowed feed with a queued head, the Friends grid

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Phase 6: Records and docs

**Files:**
- Create: `decisions/user-interface/2026-09-25-046-the-cinematic-feed.md`
- Modify: `decisions/user-interface/2026-09-24-045-…md`, `2026-09-11-038-…md`, `2026-09-08-037-…md`, `2026-09-07-033-…md`; run `scripts/gen-decisions-index`
- Modify: the design spec (status line), `docs/social.md` (§ Web layer, the Feed and Friends bullets), `docs/GLOSSARY.md`, `docs/storybook.md` (§ Component triage), `.claude/skills/user-interface/SKILL.md`, `campaigns/feed-appearance.md`, `../media-centaur.wiki/Social.md`

- [ ] **Step 1: UIDR-046 — *The cinematic feed*.** MADR 4.0 from `template.md`, `status: accepted`, `date: 2026-09-25`. Opening line: "Amends UIDR-045 (rules 3 and 5), UIDR-038 (rules 7–10, *wall of watching*, *social-network chrome*), UIDR-037 (the pennant as a form) and UIDR-033 (the artwork rule). Design: the spec; the pages: `G-couch-feed`, `J-friends-page`." Context: the diagnosis's six points in three sentences and the owner's couch rule. Decision Outcome, numbered:
  1. **One band, one size**: 224px on ink, the still in a box from the text zone's edge under the ink scrim, 6px apart on the page ground; no lead; Discovery at the layout's full width.
  2. **The identity tile** is the app's person device on every Discovery surface: a monogram, a photo when one exists, the own tile filled with the button primary; "You" set like any name; 48 / 56 / 64.
  3. **Row artwork is the row's subject**: the title's backdrop on a band, the acts' posters on a person card; the crop rule `50% 30%`, the offset `50% 38%` on the second adjacent band of one title, derived, never set; no smart crop.
  4. **The rail**: person cards beside the Feed and Watchlist above 1600px of content — You first, then by latest act, eight at most, *All N friends*; a summary of the Friends tab, never a timeline; hidden on the Friends tab.
  5. **The person card at two widths**, one component: the head and the acts strip — one poster per title, newest first, every act a disc in mast order; no presence sentence, no sharing notes; the page card opens in place to its rows and its foot.
  6. **The act disc** is the person card's form for the pennant's flags: 44/28 in the rail, 52/32 on the page, ink at .85 with a 1px ring, love on `--color-love`; the pennant stays the title surfaces' form.
  7. **Paging**: a window of twenty, *Show older* to a cap of sixty (a count, "That's the last sixty."), arrivals live at the top and queued behind "N new" when scrolled.
  8. **The couch floors** — read text ≥ 22px, secondary ≥ 18px, titles ≥ 28px, tiles 48–64, 32px targets, a 3–4px ring, 4.5:1 over imagery, the half-size check — are a house rule for every surface; the Feed is the first designed under them.
  9. **Every size named**: the spec's tables, pasted.
  Consequences: good — the author is found without reading at any roster size; the page composes at 1920 and reads from the couch; a person's card carries a picture whatever they share; bad — twenty stills per window (one derivative each, cached); the Watchlist shares the width before it shares the language; the flag vocabulary is learned, not read. Anti-patterns: the spec's list.

- [ ] **Step 2: The amendments** (front matter `amended: 2026-09-25` plus one line under the title, the house pattern in UIDR-038):
  - UIDR-045: "Amended by UIDR-046 (2026-09-25): rule 3 — the own mark is the identity tile filled with the button primary, the word You set like any name, the second person kept; rule 5 — the list surface is gone, bands 6px apart on the page ground, Discovery at the layout's full width with the rail beside the column."
  - UIDR-038: "Amended by UIDR-046 (2026-09-25): rules 7–10 are the person card's at both widths — one card per person, You first, the name as the head, the key in the opened card's foot; no presence line, the acts strip is the presence; the body is the strip of posters with act discs, the text rows in the opened card; the You card is own acts like anyone's, the modal the place to withdraw. *Social-network chrome* admits the identity tile as the app's person device — handles, counts and reactions stay banned. *Wall of watching* is bent in the rail and the card only: watching as a person's presence, replaced on the next act, never a timeline."
  - UIDR-037: "Note (UIDR-046, 2026-09-25): the pennant is a form for the title surfaces — named flags flying inward from a hero's edge, with a tooltip. The person card takes the act disc with the same glyphs, order and tints (`Title.Flag`), because its job differs: one glyph on a 96px poster. A person card's strip flies flags on posters because there the poster is the act; the Library grid and Home's rails carry none."
  - UIDR-033: "Note (UIDR-046, 2026-09-25): a row's own title artwork is that row's subject — the Feed's bands carry their title's backdrop, a person card its acts' posters; a band or a card of an unrelated title stays banned; the page-level rule (rule 2) is unchanged."
  - `scripts/gen-decisions-index`.

- [ ] **Step 3: The spec** — status → `implemented 2026-09-25 (UIDR-046)`; the acceptance boxes ticked as verified; nothing else changes (its tables are the record's source).

- [ ] **Step 4: Contributor docs** — `docs/social.md` § Web layer: the Feed bullet ("…`FeedBand` renders one band per action on its title's backdrop at full width, beside the rail of person cards; `ActivityArtwork` resolves poster and backdrop down the ladder, `Library.Artwork` is the library tier by role; the window, the cap and the queued head are `FeedEntries`'…") and the Friends bullet ("…`PersonCard` at two widths from `Person.acts`, one poster per title with act discs from `Title.Flag`; `People.rail/1` is the rail's roster…"). `docs/GLOSSARY.md`: the **Feed** (tab) row loses "in one inset list surface … window of 50" and gains "as a column of bands beside the Friends rail, a window of twenty to a cap of sixty with a queued head (UIDR-046)"; the **Author** row: "an own row's tile is filled"; new rows **Band**, **Rail**, **Person card**, **Acts strip**, **Act disc**, **Identity tile**, **Couch floors** from the spec's glossary (the app's words, not the plan's); the **Pennant** row gains "the person card's form is the act disc". `docs/storybook.md` § Component triage: rows for `discovery.identity_tile/1`, `discovery.feed_band/1`, `discovery.person_card/1` (✅ covered), `title.flag` (⚠️ skip, pure vocabulary). `.claude/skills/user-interface/SKILL.md`: a **Couch floors** subsection under Design Values (the numbers and the half-size check as a house rule, "the Feed is the first surface designed under them; Home, Library, Incoming and Settings have not been"); the UIDR table row `| 046 | The cinematic feed — bands on the title's still beside a rail of person cards; the identity tile; the act disc; the couch floors |`; Component Inventory rows for `identity_tile/1`, `feed_band/1`, `person_card/1` under the Discovery family; in § Rendering Defaults the sentence "Every other page carries the scrim only" gains "— a row's own artwork is different: the Feed's bands carry their title's backdrop, a person card its acts' posters (UIDR-046)"; the Pennant paragraph's last sentences already name the person card's strip — add "in the act-disc form".

- [ ] **Step 5: The wiki** (`../media-centaur.wiki/Social.md`): § Feed's first paragraph adds "Each row is a wide band on the title's own artwork; the page uses the whole width of the window, with your friends in a column on the right. Your own rows carry a filled circle with your initial; a friend's carries the first letter of their name — the same circle the Friends tab draws." The "A row shows" table's first line gains the circle; "Past the newest fifty rows, **Show older** shows the next fifty" → "The Feed shows the newest twenty; **Show older** adds twenty more, up to sixty. New rows arriving while you are scrolled down wait behind **N new** at the top until you press it." § Friends rewritten: one card per person, You first; the card is the person's latest titles as posters, each marked with what they did — a heart, thumbs, a speech bubble, an eye, a bookmark — and nothing about what they have not shared; press a card for every title, one line each, the key and Remove friend; the column on the right of the Feed shows the eight most recent, "All N friends" opens this page. Commit the wiki separately (`wiki: the Feed's bands, the Friends rail and the person card`); do not push.

- [ ] **Step 6: The campaign** — `campaigns/feed-appearance.md`: `status: implementing` (or `complete` if the owner closes it here), a Status paragraph naming the six phases shipped and the seventh pending, and every inherited follow-up bucketed (ship / verify / defer-to-X): the storybook fixture image → closed in Phase 1; "a listing row's two lines sit at the top" and "row type sizes grew" → absorbed by UIDR-046's table; "Friends card's Recently watched tiles at the wider column" → closed by the acts strip (fixed poster sizes, declared widths); "Feed rows and the scope pill are mouse-only" → Phase 7; the rest unchanged.

```bash
git add -A
git commit -m "docs: UIDR-046 the cinematic feed; amendments to 045, 038, 037 and 033; the spec, glossary, skill, wiki and campaign

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Phase 7: The hardening pass (planned in outline; its own plan when the layout has stopped moving)

The campaign's step 6 and the *Feed rows and the scope pill are mouse-only* follow-up. In `assets/js/input/config.js` and the templates:

- **Zones.** `feed` — a vertical `Context.TREE` (like `title_rows`): each band a nav item (`data-nav-item tabindex="0"` on the root), the seat's verbs reachable with RIGHT inside it, Enter opens the title; "N new" and *Show older* are items in the same zone at its head and foot. `rail` — a vertical `Context.MENU` of the rail's cards plus *All N friends*. `people` — the Friends grid: keep `Context.SHELF` (geometry answers row-major adjacency, as the plan grid and cast grid do) with `data-nav-grid` on `#friends-grid`; the card root becomes the item (`tabindex="0"`), and an opened card's posters, rows and Remove friend are items inside it. The scope pill's buttons are already `data-nav-item`s; give the strip's line a zone (`discovery_toolbar`, `Context.TOOLBAR`) holding the tabs and the pill, or fold the pill into `zone_tabs` — decide by trace.
- **Layout.** `discovery: { zone_tabs: { down: ["feed", "title_rows", "people"] }, feed: { up: ["zone_tabs"], right: ["rail"] }, title_rows: { up: ["zone_tabs"], right: ["rail"] }, rail: { up: ["zone_tabs"], left: ["feed", "title_rows"] }, people: { up: ["zone_tabs"] }, sidebar: { right: ["feed", "title_rows", "people", "zone_tabs"] } }`; `cursorStartPriority.discovery: ["feed", "title_rows", "people", "zone_tabs", "sidebar"]`. Below the fold the rail's items fail visibility and the candidate lists skip it — one config, both graphs.
- **Cursor.** The UIDR-020 default ring: 3px primary on a band and a rail card, 4px on a page card (`[data-input=keyboard] .feed-band:focus-visible`, `.person-card:focus-visible`), the scrim step and the seat on `:focus-within` as hover; no collision to name.
- **Verification** with `~/scripts/agents/mc-nav-trace` on `/discovery` (down the bands, right into a seat, right into the rail, back), `/discovery/friends` (row-major across the grid, into an opened card); the wiki's Keyboard-and-Gamepad page gains a Discovery section.

---

## Out of scope — follow-ups, each its own phase or campaign

- **The Watchlist in bands** (P): title first, the ladder and acquisition words in the seat, the pennant mast at the text zone's edge, a no-artwork title as an ink band. The rows sit beside the rail until then (decision 8).
- **Photo events**: the social protocol's profile event, `Person.photo_url` and `FeedEntry.photo_url`, the hosts passing them; the tile already renders it (decision 4).
- **Hover or cursor ease** (400ms, scale 1.03): the one motion candidate; two lines of CSS if the owner wants it.
- **Incoming's activity** in the band language.
- **`.page-side-dim` on Discovery** — code fact 5; the owner's call.
- **The `Downloading` hairline's progress** — code fact 10; needs a progress fact on the row.
- **`ArtworkWarmup` for the Feed**: the builders are public for it; whether Discovery is "first screen" is the judgment that module asks for. Not now.
- **A heavier icon set for the 28px glyph** if the half-size check in Phase 3 finds the thumbs merging (code fact 13).
- **The tab strip's scope reset** (Feed → Watchlist → Feed): unchanged by this plan; still a follow-up.
- **Motion**: none (parallax and drift rejected by X).
