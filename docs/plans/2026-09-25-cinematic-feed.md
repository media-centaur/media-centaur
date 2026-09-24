# The cinematic feed — implementation plan (draft)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Draft, written the night of 2026-09-24/25 before the owner's decision**; the first section lists what it assumes.

**Goal:** The Feed becomes a full-width column of bands, one per action, each on its title's backdrop under the house scrim, the newest action as the lead; own rows are marked by the identity tile; the Friends tab draws people with the same tile.

**Architecture:** One component at two sizes (`Discovery.FeedBand`, `size: :lead | :band`) renders every author; the identity tile is its own component (`Discovery.IdentityTile`) composed by the band and the person card. The host resolves a row's poster *and* backdrop down one artwork ladder (`DiscoveryLive.ActivityArtwork` over `Library.Artwork` and `TmdbArtwork`); the projection (`FeedEntries`) carries the backdrop and derives the crop offset from adjacency; the page takes the layout's `full_width` and drops its own column. The scrim, mask and crop are CSS classes in `app.css`; the derivative widths are two public builders on the band so the URL is one definition.

**Tech Stack:** Phoenix LiveView, Tailwind v4 + daisyUI, Phoenix Storybook, ExUnit + LazyHTML. Spec: `docs/superpowers/specs/2026-09-24-feed-appearance-design.md`; the chosen page: `…-mockups/F-cinematic-feed/REASONING.md` (every size); the decisions: `…-mockups/CRITIQUE-5.md`. Record to write: UIDR-046.

**Ground rules for this repo (read before Phase 1):**

- Never run `mix` directly in an agent shell. Every command below uses `~/scripts/agents/agent-mix`, which builds outside the checkout so the dev daily driver is never disturbed.
- Test-first: write the failing test, run it, see it fail for the right reason, then implement. The storybook-first rule applies to the two components that already have stories (`feed_entry_row`, `person_card`): the story variation is edited before the component.
- Zero warnings. `mix precommit` runs `--warnings-as-errors`, Credo `--strict` (MC0008 typed attrs, MC0009 story per component and every `values:` literal in the story, MC0016 eager images, MC0028 declared artwork width, MC0034 text ≥ /55, MC0024 no markup `=~`, MC0023 factory-only setup), Boundary, and the storybook compile/render tests.
- No real show titles anywhere (`Sample Movie`, `Sample Friend`); fixture artwork is PD/CC from `priv/showcase/images`.
- Commit after each phase. End every commit message with the line `Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L`. Never add a `Co-Authored-By` trailer. Commit straight to `main`; do not push.
- The dev server on :2160 hot-reloads from the checkout. The `assets/` watchers are off: after a CSS change, or a template change that adds Tailwind utilities, run `~/scripts/agents/agent-mix assets.build`. For a visual check use `~/scripts/agents/page-shot --url http://127.0.0.1:2160/discovery --viewport 1920x1080 --wait-ms 3000` and Read the PNG; also 1280x800 and 2560x1440 on the last phase.
- A new module named in a context's `exports:` needs `~/scripts/agents/agent-mix compile --force` once, or Boundary reports a stale manifest.

---

## Glossary

Terms from `docs/GLOSSARY.md` are used as defined there: *Feed*, *feed row*, *Scope*, *Author*, *Action*, *Review*, *Listing*, *Rung*, *Ladder* (artwork tiers: library, referenced, browsing). This plan adds, in the order the code meets them:

| Term | Meaning |
|---|---|
| **Band** | The Feed's unit: one action rendered as a 152px, full-width strip on its title's backdrop, with the identity tile, the poster, the sentence, the title and the review in a dark text zone on the left and the picture on the right. `Discovery.FeedBand` at `size: :band`. |
| **Lead** | The same unit at 340px for the newest action in the window — index 0 under the current scope. `size: :lead`. Larger in every dimension; the picture begins at the text zone's edge instead of a capped box. An empty Feed has no lead. |
| **Identity tile** | The app's one drawing of a person: a circle carrying the name's first letter (the *monogram*), or a photo when one exists; filled with the button primary for the reader's own rows. `Discovery.IdentityTile`, on the band and the Friends card. The Friends card's inline monogram moves into it. |
| **Row artwork** | The artwork a row is about — the title's poster and backdrop — resolved by the host down the ladder, never by the component. `FeedEntry.poster_url` and `FeedEntry.backdrop_url`. |
| **Text zone** | The left 576px of every unit, inside which no image box begins; the review's measure ends there and the band's time is right-aligned to its edge. |
| **Image box** | Where the backdrop is painted: from `max(576, width − cap)` to the unit's right edge. The band's cap is 900px; the lead has none. Its left edge dissolves over 360px under a mask. |
| **Crop rule** | `object-fit: cover; object-position: 50% 30%` on every backdrop, measured on real stills (`MEASUREMENT.md`); the second of two adjacent units of one title carries the **offset crop**, `50% 38%`, derived from adjacency in the scoped window (`FeedEntry.offset_crop?`). No per-title position exists. |
| **Scrim** | The gradient of the theme's ink (`oklch(13% 0.02 264)`, the identity-banner family's literal — *not* `--color-base-100`, which is 27%) laid over the image box: heavy under the text zone, dissolving across the box's first 540px, clear at the right. One recipe for both sizes; the lead adds a faint left-running layer under its time. Hover multiplies every alpha by `--s: .8`. |
| **Seat** | The toolbar's fixed 20px slot at the poster's foot, empty at rest, shown on hover; unchanged from UIDR-045 except Ignore's position (10px after Download, not at the far edge). |
| **Derivative** | A width-constrained copy of a local artwork master served by `ImageServer` for `?w=<px>`, snapped up the ladder `160 · 240 · 320 · 480 · 640 · 960 · 1280 · 1920`; wider requests get the master. `?w=` constrains the **width** (a 16:9 still at `?w=1280` is 1280×720). |

---

## Owner decisions this plan assumes

Each is a fork the critique left to the morning. The plan takes the first branch; every alternative is one line of change and is named so the owner can flip it before Phase 1.

1. **Ship F as assembled**: C's band (900px capped box, the time at the text zone's edge) with A2's uncapped lead. The capped lead (mockup state 14) is not built.
2. **Full width for Discovery, all three tabs** (`Layouts.app full_width` is one attribute for the whole LiveView). Consequence the critique did not render: the Friends cards (`glass-surface`, no max width) and the Watchlist rows stretch to 1820px at 1920, and the Friends card's six-column poster strip gets ~290px cells until its own phase. Alternative: keep a `max-w-4xl` wrapper on the Watchlist and Friends tab bodies until their bands land — one class on each tab's root `div`.
3. **The Watchlist stays as it is** in this campaign; bands there are the next campaign (§ Out of scope).
4. **No hover ease.** The only transition is the seat's 120ms opacity fade; the scrim step (`--s`) and the ground lift are instant, as REASONING states. A 400ms `scale(1.03)` would be a two-line CSS addition later.
5. **Derivative widths per the critique: `?w=1280` on a band, `?w=1920` on the lead.** MC0028's arithmetic (rendered box × 2 for a 4K panel) says 1920 for the band (900 CSS px → 1800) and the master for the lead (1244 → 2488, past the ladder) — a 1280 derivative in a 900px box is upscaled ~1.4× on a 4K panel; on the owner's 1920 monitor it is downscaled and sharp. Sixteen bands at 1920 are ~16 × 300 KB; the lead at the master is the 4K `<img>` problem UIDR-032 solved for Home with a canvas. The plan keeps 1280/1920 behind two builders so the number is one line each.
6. **Identity tile sizes 40 and 48 only.** The critique lists 32/40/48; nothing in this plan renders 32 (the Watchlist band might). It is added with its first tenant, not before.
7. **No `photo_url` on `Person` or `FeedEntry` yet.** The tile takes a `photo_url` attr and its story pins the two photo states (the space the design asks for); the view-models gain the field when the social protocol carries a photo event, which it does not today (`docs/social-protocol.md`: review, watched, listing). Mockup state 8 is pinned in the tile's story only.
8. **The band keeps the row's DOM contract** — `id="feed-row-<activity id>"`, `data-component="feed-row"`, `data-kind`, `data-own`, `data-list-slot`, `data-download-slot`, `data-role` (`who`, `title`, `text`, `time`, `toolbar`), the `-list`/`-download`/`-ignore` control ids, `phx-click="open_title"` on the root — so the feed-tab tests in `discovery_live_test.exs` stay green without edits. The component and its module are renamed; the DOM names the thing (a feed row), the class names the look (a band).
9. **`Library.Posters` becomes `Library.Artwork`** with `urls_by_refs(refs, role)`, rather than a copy of it named `Backdrops`; the one other caller (`WatchHistory.Views.PlaybackActivity`) changes one line.

---

## What the code says that the critique did not know

Read before estimating; each changes a step below.

1. **Backdrops are already warmed.** `TmdbArtwork.ensure/2` → `fetch_missing/2` downloads the poster, the backdrop *and* the logo from the stored title's payload, and `TmdbArtwork.urls/2` already returns `backdrop_url`. Critique item 2's "`TmdbArtwork` warms backdrops for activity identities" is true today. What is missing is on the reading side: `LiveHelpers.title_poster_url/1` calls `urls/2` and discards the backdrop; `ActivityPosters.missing/1` warms only rows whose *poster* is nil, so an identity that found a poster and no backdrop is never warmed; and the library tier, `Library.Posters.urls_by_refs/1`, queries `role == "poster"` only.
2. **The wire snapshot carries no artwork paths in practice.** `Activities.Publisher` leaves poster and backdrop to the receiving install (its moduledoc, line 28); `Translation` sends name, year, date and overview. `poster_path`/`backdrop_path` are optional on the wire, so the "TMDB hotlink" rung of the ladder is effectively dead for backdrops and nearly so for posters — the referenced tier (`TmdbArtwork`) is the source for every title the library does not own. Keep the hotlink rung (a foreign client may send the paths) but do not design around it. The poster hotlink is `:w92`, too soft for the band's 72×108 poster on a 2× panel; the resolver asks `:w185` for a poster and `:w1280` for a backdrop.
3. **`?w=` constrains the width, snapping up a fixed ladder, never upscaling** (`ImageFiles.derivative/2`; the `"<w>x<h>"` thumbnail form fixed the older longest-side behaviour). `?w=1280` → 1280×720 from a 16:9 master; `?w=1920` → 1920×1080; anything above 1920 → the master. Derivatives are cached per master per tier and regenerated when the master's mtime changes.
4. **`full_width` is one attribute on `Layouts.app`** (`layouts.ex:263`): it removes `max-w-7xl` from the content wrapper for the whole LiveView, so it applies to all three tabs at once. The layout keeps `px-6` on `<main>`; with the 52px rail the content is 1920 − 52 − 48 = **1820px**, exactly REASONING's unit width. Discovery's own `mx-auto w-full max-w-4xl` wrapper is the 896px column and must go with it.
5. **Discovery carries no `.page-side-dim`.** Every other page renders one (UIDR-033 rule 2); Discovery never did. The bands sit on the body's radial gradient (`body.media-centaur`, base-100 at 27% with the two glass gradients). The mockups' ground (`base.css`: a radial from 28% to 17%) is close. Not changed by this plan; noted for the owner.
6. **The mockup's ink is not the theme's base.** `oklch(13% 0.02 264)` is the literal the identity-banner family already uses (`.scrim-surface`, `.identity-row`, `.identity-banner-strip`); `--color-base-100` is `oklch(27% 0.019 264)`, and `.image-scrim-t/-r` derive from it. The band's scrim must use the 13% literal — defined once as `--feed-ink` beside those rules — or the words wash out fourteen points lighter. Likewise the own tile's fill is `--color-primary` (`oklch(62% 0.16 250)`, hue 250) and `--color-primary-content`, not the mockup's hue-264 literal: the theme's own token is the button primary the critique names.
7. **MC0016 and MC0028 on the band's two images.** Both `<img>`s carry `loading="eager" decoding="sync"`; the lead's backdrop alone adds `fetchpriority="high"` (the surface's one hero image; the ceiling is two). Every `/media-images` `src` passes through `sized_image_url/2` or a `*_src(` builder; a remote TMDB URL is exempt.
8. **The storybook's sample images do not exist.** `/images/sample-nosferatu-poster.jpg` (five stories, including `feed_entry_row` and `person_card`) and `/storybook/fixtures/poster.jpg` (`poster_card`) are both 404s — `Plug.Static` serves `priv/static/images`, `storybook_assets()` serves PhoenixStorybook's own priv, and neither holds these files. The render test only checks the page's status, so it never noticed. `priv/showcase/images/<uuid>/{poster,backdrop}.jpg` are PD/CC and in git; Phase 1 copies one pair to `priv/static/images/storybook/` and repoints the six references (the campaign's inherited follow-up, closed early because the band's story needs a real still).
9. **`Tab.count` is already hidden at zero** (`tab_strip.ex:44`); the mockup's "Feed omitted at zero" needs nothing.
10. **The `Downloading` hairline has no progress source.** The mockup's `--pct` is a fixed 45%; `FeedEntry.acquisition_state` is an atom. The band keeps the row's static hairline. Not a regression.
11. **Nothing in the Feed is a nav item today** (the toolbar and the pill are mouse-only per the campaign), and `config.js` names no feed zone. Phase 6 adds them; Phases 1–5 add no `data-nav-*`.

---

## File structure

**Create**
- `lib/media_centaur_web/components/discovery/identity_tile.ex` — `identity_tile/1`.
- `storybook/discovery/identity_tile.story.exs`
- `test/media_centaur_web/components/discovery/identity_tile_test.exs`
- `priv/static/images/storybook/sample-poster.jpg`, `sample-backdrop.jpg` — PD/CC fixtures from `priv/showcase/images`.
- `decisions/user-interface/2026-09-25-046-the-cinematic-feed.md`

**Rename** (`git mv`)
- `lib/media_centaur/library/posters.ex` → `artwork.ex` (`Library.Artwork`); `test/media_centaur/library/posters_test.exs` → `artwork_test.exs`.
- `lib/media_centaur_web/live/discovery_live/activity_posters.ex` → `activity_artwork.ex` (`DiscoveryLive.ActivityArtwork`); its test likewise.
- `lib/media_centaur_web/components/discovery/feed_entry_row.ex` → `feed_band.ex` (`Discovery.FeedBand.feed_band/1`); `storybook/discovery/feed_entry_row.story.exs` → `feed_band.story.exs` (MC0009 pins the story filename to the function name).

**Modify**
- `lib/media_centaur/library.ex` — `exports:` and the moduledoc's artwork row.
- `lib/media_centaur/watch_history/views/playback_activity.ex` — one call site.
- `lib/media_centaur_web/components/discovery/feed_entry.ex` — `backdrop_url`, `offset_crop?`.
- `lib/media_centaur_web/components/discovery/person_card.ex` — composes the tile.
- `lib/media_centaur_web/live/discovery_live/feed_entries.ex` — carries the backdrop, stamps the crop, `size/1`.
- `lib/media_centaur_web/live/discovery_live.ex` — `full_width`, the column, the lead, the artwork read, the warm rule.
- `assets/css/app.css` — the feed band block.
- `test/support/discovery_rows.ex` — `backdrop_url` override.
- `storybook/discovery/_discovery.index.exs`, `storybook/discovery/person_card.story.exs`, `storybook/library_cards/poster_card.story.exs`, `storybook/detail/lockup.story.exs` (fixture paths).
- `test/media_centaur_web/live/discovery_live_test.exs`, `test/media_centaur_web/live/discovery_live/feed_entries_test.exs`, `test/media_centaur_web/page_smoke_test.exs`.
- Records and docs (Phase 5): UIDR-045, UIDR-038, UIDR-033, `decisions/README.md` (generated), `docs/social.md`, `docs/GLOSSARY.md`, `docs/storybook.md`, `.claude/skills/user-interface/SKILL.md`, the design spec, `campaigns/feed-appearance.md`, `../media-centaur.wiki/Social.md`.

---

### Phase 1: `Discovery.IdentityTile`, and the Friends card composes it

The person card already has a story, so its variation is edited first (the You card's tile becomes the own fill); the tile is a new component, so component then story.

**Files:**
- Create: `lib/media_centaur_web/components/discovery/identity_tile.ex`, `test/media_centaur_web/components/discovery/identity_tile_test.exs`, `storybook/discovery/identity_tile.story.exs`
- Modify: `lib/media_centaur_web/components/discovery/person_card.ex:60-66`, `storybook/discovery/person_card.story.exs` (`:you` description; fixture path), `storybook/discovery/_discovery.index.exs`
- Create: `priv/static/images/storybook/sample-poster.jpg`, `sample-backdrop.jpg`; modify the six fixture references (`storybook/discovery/feed_entry_row.story.exs`, `person_card.story.exs`, `storybook/library_cards/poster_card.story.exs:299`, `storybook/detail/lockup.story.exs:48`, and the two others `grep -rn 'sample-nosferatu' storybook` finds)

- [ ] **Step 1: The fixtures.** Pick one showcase title with both files (`find priv/showcase/images -name backdrop.jpg | head`; open two or three and keep a still whose subject sits in the upper third — the crop rule's case). Copy to `priv/static/images/storybook/sample-poster.jpg` and `sample-backdrop.jpg`; confirm `git check-ignore` reports neither. Repoint every `/images/sample-nosferatu-poster.jpg` and `/storybook/fixtures/poster.jpg` to `/images/storybook/sample-poster.jpg`. (`priv/static/images` is in `static_paths/0`; the plain path serves in dev, the digested one in prod.)

- [ ] **Step 2: Write the failing component test**

```elixir
defmodule MediaCentaurWeb.Components.Discovery.IdentityTileTest do
  use MediaCentaur.Case, async: true

  import Phoenix.LiveViewTest

  alias MediaCentaurWeb.Components.Discovery.IdentityTile

  defp render(attrs),
    do: &IdentityTile.identity_tile/1 |> render_component(attrs) |> LazyHTML.from_fragment()

  test "a monogram carries the name's first letter, hidden from assistive tech" do
    tile = render(name: "Cleo") |> LazyHTML.query("[data-component='identity-tile']")

    assert LazyHTML.text(tile) |> String.trim() == "C"
    assert LazyHTML.attribute(tile, "aria-hidden") == ["true"]
    assert LazyHTML.attribute(tile, "data-own") == []
  end

  test "an own tile says so; the letter stays" do
    tile = render(name: "You", own?: true) |> LazyHTML.query("[data-component='identity-tile'][data-own]")
    assert LazyHTML.text(tile) |> String.trim() == "Y"
  end

  test "a photo replaces the letter and paints eagerly" do
    html = render(name: "Ada", photo_url: "/images/storybook/sample-poster.jpg")
    img = LazyHTML.query(html, "[data-component='identity-tile'] img")

    assert LazyHTML.attribute(img, "src") == ["/images/storybook/sample-poster.jpg"]
    assert LazyHTML.attribute(img, "loading") == ["eager"]
    assert html |> LazyHTML.query("[data-component='identity-tile']") |> LazyHTML.text() |> String.trim() == ""
  end

  test "the size is one of the two the surfaces render" do
    assert_raise ArgumentError, fn -> render(name: "Cleo", size: 32) end
  end
end
```

(`render_component` here asserts the tile's *contract* — the letter, `data-own`, the photo's `src`, `aria-hidden` — the way `segmented_control_test.exs` does, never its classes.)

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
  2px primary ring says the same. On the Feed's bands (40px, 48px on
  the lead) and the Friends card (40px). `aria-hidden`: the name is
  read from the row's text, the tile is its redundant channel.

  No photo exists today — the social protocol carries no profile
  event — so every host passes `nil`; the attr is the space the
  design leaves for one.
  """

  use Phoenix.Component

  attr :name, :string, required: true, doc: "the display name; its first grapheme is the monogram"
  attr :own?, :boolean, default: false
  attr :photo_url, :string, default: nil
  attr :size, :integer, values: [40, 48], default: 40

  def identity_tile(assigns) do
    ~H"""
    <span
      class={[
        "relative grid shrink-0 place-items-center overflow-hidden rounded-full leading-none",
        @size == 40 && "size-10 text-base",
        @size == 48 && "size-12 text-[19px]",
        !@photo_url && !@own? &&
          "bg-primary/20 font-semibold text-primary ring-1 ring-inset ring-primary/25 shadow-[0_2px_8px_oklch(0%_0_0/0.35)]",
        !@photo_url && @own? &&
          "bg-primary font-bold text-primary-content shadow-[0_2px_8px_oklch(0%_0_0/0.4)]",
        @photo_url && !@own? && "ring-1 ring-inset ring-base-content/20",
        @photo_url && @own? && "ring-2 ring-primary"
      ]}
      data-component="identity-tile"
      data-own={@own?}
      aria-hidden="true"
    >
      <img
        :if={@photo_url}
        src={@photo_url}
        alt=""
        class="size-full object-cover"
        loading="eager"
        decoding="sync"
      />
      {if !@photo_url, do: String.first(@name)}
    </span>
    """
  end
end
```

Class precedence is stylesheet order (the `phoenix-thinking` gotcha), which is why the states are disjoint branches rather than a base plus overrides.

- [ ] **Step 5: The story** — `storybook/discovery/identity_tile.story.exs`, `MediaCentaurWeb.Storybook.Discovery.IdentityTile`, `render_source :function`. Two `VariationGroup`s, one per size, each with four variations: `:monogram` (`name: "Cleo"`), `:photo` (`name: "Ada", photo_url: "/images/storybook/sample-poster.jpg"`), `:own` (`name: "You", own?: true`), `:own_photo` (`name: "You", own?: true, photo_url: …`). Both `40` and `48` must appear as literals (MC0009's `values:` scan). Index entry: `def entry("identity_tile"), do: [icon: {:fa, "circle-user", :thin}, name: "Identity tile"]`.

- [ ] **Step 6: The Friends card** — story first: change the `:you` variation's description to "The You card: the own tile, \"How friends see you\", no footer." Then in `person_card.ex` replace the header's inline `<span class="grid size-10 …">{String.first(@person.name)}</span>` with `<IdentityTile.identity_tile name={@person.name} own?={@person.own?} />` (alias it). The You card's `border-primary/30` stays — the Friends card beyond the tile is a follow-up. The moduledoc's first sentence names the tile.

- [ ] **Step 7: Green, precommit, look**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/discovery test/media_centaur_web/storybook_render_test.exs test/media_centaur_web/live/discovery_live_test.exs`
Then `~/scripts/agents/agent-mix precommit` (foreground, timeout 600000). Open `/storybook/discovery/identity_tile` and `/storybook/discovery/person_card` on :2160 and Read a `page-shot` of each.

**Acceptance:** eight tile states render; the You card's tile is filled; the six stories that pointed at a missing image now show one; Credo MC0009 finds `identity_tile.story.exs`; the Friends-tab tests are untouched and green.

```bash
git add -A
git commit -m "feat: the identity tile — one drawing of a person on the Feed and the Friends card

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Phase 2: Row artwork — the backdrop down the same ladder

Data only; nothing renders a backdrop until Phase 3. Three seams, each test-first: the library tier by role, the resolver for both roles, the projection field.

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

Run: `~/scripts/agents/agent-mix test test/media_centaur/library/artwork_test.exs` → FAIL, `Artwork.urls_by_refs/2 is undefined`.

- [ ] **Step 2: `Library.Artwork`** — the module keeps its shape; `@type role :: String.t()` with `@roles ~w(poster backdrop)`, `urls_by_refs(refs, role) when role in @roles`, and `image.role == ^role` in `poster_urls_by_owner/1` (rename it `urls_by_owner/2`). Moduledoc: "Batch artwork-URL resolution by entity reference and role — the poster or the backdrop — for surfaces outside the Library views…"; keep the episode→series sentence (an episode's own image is its `thumb`; both roles resolve to the series). `library.ex`: `Artwork` in `exports:`, the moduledoc row `| Artwork | \`Library.Images\`, \`Library.Artwork\`, \`Library.ImageHealth\` |`. `playback_activity.ex`: `Artwork.urls_by_refs(refs, "poster")`. Run `~/scripts/agents/agent-mix compile --force` once (the exports manifest), then the test → green; then `~/scripts/agents/agent-mix test test/media_centaur/watch_history` → green.

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

(`activity/4` grows a `backdrop_path` argument; `library_refs/1` tests stay.) The referenced tier is filesystem-backed (`TmdbArtwork.urls/2` checks `File.exists?`); the pure test covers the library and hotlink rungs, and the page test in Step 7 covers the referenced one through the real cache.

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

Import `tmdb_cdn_url: 2` from `LiveHelpers` instead of `title_poster_url: 1` — one `TmdbArtwork.urls/2` call per row now serves both roles (it was three `File.exists?` per row for the poster alone; it stays three). Moduledoc: the ladder is stated per role; the hotlink rung's widths are named with the reason (finding 2). `DiscoveryLive.load_activities/1`:

```elixir
    refs = ActivityArtwork.library_refs(owners)
    library_artwork = Map.new(["poster", "backdrop"], &{&1, Artwork.urls_by_refs(refs, &1)})
    …
        activity
        |> ActivityArtwork.urls(owners, library_artwork)
        |> Map.merge(%{library_owner_id: Map.get(owners, ref), rung: Map.get(rungs, ref)})
        |> then(&Map.merge(row, &1))
```

`warm_activity_artwork/1` reads `ActivityArtwork.missing/1` unchanged in shape; its comment gains the sentence "or a backdrop — the band paints one". `People.build/3` keeps reading `row.poster_url`.

- [ ] **Step 5: `FeedEntry.backdrop_url` — failing projection test**

In `feed_entries_test.exs`, the test "an entry carries what the row shows…" adds `backdrop_url: "/b.jpg"` to the first row's overrides and `backdrop_url: "/b.jpg"` to the `%FeedEntry{…} = review` match, and `backdrop_url: nil` to the listing's. `test/support/discovery_rows.ex` gains `backdrop_url: Map.get(overrides, :backdrop_url)`. Run → FAIL (`backdrop_url` is not a key of `FeedEntry`).

- [ ] **Step 6: The field** — `FeedEntry` gains `:backdrop_url` after `:poster_url` (struct, `@type`, moduledoc: "`poster_url` and `backdrop_url` are the row artwork, resolved by the host down the ladder; nil paints the quiet fallback"); `FeedEntries.entry/2` copies `row.backdrop_url`. Green.

- [ ] **Step 7: No page test yet.** The page-level proof — an owned title's band paints the library entity's backdrop, an unowned one's the artwork cache's — needs the `<img>` that Phase 3 renders; a LiveView test may not read the assign (MC0004), and a test may not be skipped. Phase 2 ends with the pure tests green and the Feed rendering exactly as before; Phase 3 Step 7 writes that page test.

- [ ] **Step 8: Green, precommit**

Run: `~/scripts/agents/agent-mix test test/media_centaur/library test/media_centaur_web/live/discovery_live test/media_centaur_web/live/discovery_live_test.exs test/media_centaur/watch_history`, then precommit.

**Acceptance:** `Library.Artwork.urls_by_refs/2` resolves both roles; `ActivityArtwork.urls/3` returns both and `missing/1` names either-role gaps; every `FeedEntry` carries `backdrop_url`; `Posters` and `ActivityPosters` no longer exist (`grep -rn 'Posters' lib test` is empty); the Feed renders exactly as before.

```bash
git commit -am "feat: row artwork — the backdrop resolves down the same ladder as the poster

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Phase 3: The band — one unit at two sizes

Storybook-first: the story is rewritten before the component. The DOM contract is kept (decision 8), so the page tests are the regression net while the look changes underneath them.

**Files:**
- Rename: `storybook/discovery/feed_entry_row.story.exs` → `feed_band.story.exs`; `lib/media_centaur_web/components/discovery/feed_entry_row.ex` → `feed_band.ex`
- Modify: `storybook/discovery/_discovery.index.exs`, `lib/media_centaur_web/components/discovery/feed_entry.ex` (`offset_crop?`), `lib/media_centaur_web/live/discovery_live/feed_entries.ex` (the crop stamp), `test/media_centaur_web/live/discovery_live/feed_entries_test.exs`, `assets/css/app.css`, `lib/media_centaur_web/live/discovery_live.ex` (the alias and the call; the column and the lead are Phase 4 — for this phase every entry renders at `size: :band` inside the old list surface, which is ugly for one commit and correct), `lib/media_centaur_web/components/title/row.ex:9-10` (names the band), `test/media_centaur_web/live/discovery_live_test.exs` (the artwork test from Phase 2 Step 7)

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

    test "size/1: index 0 is the lead, the rest are bands" do
      assert FeedEntries.size(0) == :lead
      assert FeedEntries.size(1) == :band
      assert FeedEntries.size(49) == :band
    end
```

Run → FAIL.

- [ ] **Step 2: The projection** — `FeedEntry` gains `offset_crop?: false` (default in `defstruct`, `boolean()` in the type; moduledoc: "the second of two adjacent rows of one title, so two stills of one frame never repeat exactly — UIDR-046's crop rule"). In `FeedEntries.build/2`:

```elixir
    %{
      entries: entries |> Enum.take(window) |> Enum.map(&entry(&1, now)) |> stamp_crops(),
      has_older?: length(entries) > window
    }

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

  @doc "The unit's size by its index in the window: the newest action is the lead."
  @spec size(non_neg_integer()) :: :lead | :band
  def size(0), do: :lead
  def size(_index), do: :band
```

Green.

- [ ] **Step 3: The story, rewritten** — `git mv` both files. `storybook/discovery/feed_band.story.exs`, module `MediaCentaurWeb.Storybook.Discovery.FeedBand`, `function: &…FeedBand.feed_band/1`, `layout :one_column`, template `<div class="feed-column"><.psb-variation/></div>`. The fixture `entry/2` gains `backdrop_url: "/images/storybook/sample-backdrop.jpg"` and `offset_crop?: false`. The mockup's fourteen states map onto the story as follows — every state a component can hold is a variation; page states are named with where they are pinned instead:

| Mockup state | Story variation (`size`) | Notes |
|---|---|---|
| 1 · Everyone, the lead | `:lead_listing` (`:lead`) | a friend wants to watch; `fetchpriority` is the page's, not visible here |
| 1 · a band, own review, Listed · In library | `:own_review` (`:band`) | own tile, the heart, two lines of review, no Ignore |
| 1 · a band, a friend's listing | `:listing` (`:band`) | the resting friend's band |
| 2 · Friends | page state | pinned by the scope test in `discovery_live_test.exs` |
| 3 · You, the lead as an own review | `:lead_own_review` (`:lead`) | the 48px own tile; the review at 16px, three lines |
| 4 · You, empty — no lead | page state | `empty_state/1` has its story; the page test refutes a lead |
| 5 · a friend's band hovered | `:hovered` (`:band`, template `<div class="feed-column feed-hover-pin"><.psb-variation/></div>`) | List · Download · Ignore in the seat; the scrim × .8 |
| 5b · the seat's plain states | `VariationGroup :seat_states` — `:tracking`, `:in_library`, `:listed`, `:downloading` (all `:band`, hover-pinned) | the four slot states, seat shown |
| 6 · an own band hovered | `:own_hovered` (`:band`, hover-pinned) | Listed · In library; no Ignore |
| 7 · the keyboard cursor | Phase 6 | no nav item yet; the `::after` ring lands with the zone |
| 8 · a friend with a photo; You with a photo | the tile's story | `FeedEntry` has no `photo_url` (decision 7) |
| 9 · no artwork, a band | `:no_artwork` (`:band`, `poster_url: nil, backdrop_url: nil`) | the inset tone, the empty poster slot |
| 10 · the lead as a review with words | `:lead_review` (`:lead`, a friend's `:love` review with three lines of text) | |
| 11 · the lead with no artwork | `:lead_no_artwork` (`:lead`) | 340px of the inset tone; the 160×240 slot empty |
| 12 · two adjacent bands of one title | `VariationGroup :adjacent_pair` — `:first` (`offset_crop?: false`), `:second` (`offset_crop?: true`), group template `<div class="feed-column"><.psb-variation-group/></div>` | the same still twice, 30% then 38% |
| 13 · at rest, then hovered | `:listing` and `:hovered` side by side | already covered |
| 14 · the capped lead | not built | the alternative the owner did not choose |
| — | `VariationGroup :sentiments` — `:like`, `:dislike`, `:text_only`, `:bare` (`:band`) | the existing glyph matrix, kept |

Both `:lead` and `:band` appear as literals (MC0009). Index: `def entry("feed_band"), do: [icon: {:fa, "stream", :thin}, name: "Feed band"]`.

- [ ] **Step 4: The CSS** — append to `assets/css/app.css` after the `.identity-row` block (the family it joins):

```css
/* ── Feed bands (UIDR-046) ──
   One unit at two sizes: a still in a right-hand image box under the
   ink scrim, the words in a dark text zone on the left. Every position
   is a custom property of the size class; the text is Tailwind on top.
   --feed-ink is the identity-banner family's literal, not base-100
   (27%): the scrim must sit under the words at 13%. */
:root {
  --feed-ink: oklch(13% 0.02 264);
  --feed-text-zone: 576px;   /* no image box begins left of it */
  --feed-dissolve: 360px;    /* the box's left edge fades in over this */
}

.feed-column { display: flex; flex-direction: column; gap: 6px; }

.feed-band {
  --s: 1;
  --h: 152px; --rad: 10px; --box: 900px;
  --tile: 40px; --x-tile: 18px; --tile-top: calc(50% - var(--tile) / 2);
  --pw: 72px; --ph: 108px; --x-poster: 74px; --pad-y: 22px;
  --pshadow: 0 3px 12px oklch(0% 0 0 / 0.55);
  --x-body: 164px; --body-right: calc(100% - var(--feed-text-zone)); --body-pt: 0px;
  --when-right: calc(100% - var(--feed-text-zone));
  --bx: max(var(--feed-text-zone), calc(100% - var(--box)));
  position: relative; height: var(--h); border-radius: var(--rad); overflow: hidden;
  background: var(--feed-ink); isolation: isolate; cursor: pointer;
}
.feed-band-lead {
  --h: 340px; --rad: 14px; --box: 100%;
  --tile: 48px; --x-tile: 32px;
  --tile-top: calc(var(--pad-y) + var(--body-pt) + 13px - var(--tile) / 2);
  --pw: 160px; --ph: 240px; --x-poster: 100px; --pad-y: 50px;
  --pshadow: 0 10px 28px oklch(0% 0 0 / 0.55);
  --x-body: 280px; --body-right: calc(100% - 800px); --body-pt: 11px;
  --when-right: var(--x-tile);
}
.feed-band-backdrop {
  position: absolute; top: 0; left: var(--bx); width: calc(100% - var(--bx)); height: 100%;
  object-fit: cover; object-position: 50% 30%; display: block;
  mask-image: linear-gradient(to right, transparent, #000 var(--feed-dissolve));
}
.feed-band-offset .feed-band-backdrop { object-position: 50% 38%; }
.feed-band-scrim {
  position: absolute; inset: 0; pointer-events: none;
  background: linear-gradient(to right,
    oklch(from var(--feed-ink) l c h / calc(0.97 * var(--s))) 0,
    oklch(from var(--feed-ink) l c h / calc(0.93 * var(--s))) var(--bx),
    oklch(from var(--feed-ink) l c h / calc(0.55 * var(--s))) calc(var(--bx) + 180px),
    oklch(from var(--feed-ink) l c h / calc(0.16 * var(--s))) calc(var(--bx) + 360px),
    oklch(from var(--feed-ink) l c h / calc(0.04 * var(--s))) calc(var(--bx) + 540px),
    oklch(from var(--feed-ink) l c h / 0) 100%);
}
/* the lead's time sits top right on the picture: a second layer holds it */
.feed-band-lead .feed-band-scrim {
  background:
    linear-gradient(to right, /* the same five stops */ …),
    linear-gradient(to left, oklch(from var(--feed-ink) l c h / calc(0.30 * var(--s))), oklch(from var(--feed-ink) l c h / 0) 220px);
}
.feed-band-bare { background: var(--glass-inset-bg); }
.feed-band-bare .feed-band-scrim {
  background: linear-gradient(to right, oklch(from var(--feed-ink) l c h / 0.35), oklch(from var(--feed-ink) l c h / 0) 800px);
}
.feed-band-tile   { position: absolute; left: var(--x-tile); top: var(--tile-top); z-index: 2; }
.feed-band-poster { position: absolute; left: var(--x-poster); top: var(--pad-y); width: var(--pw); height: var(--ph); z-index: 2; box-shadow: var(--pshadow); }
.feed-band-body   { position: absolute; left: var(--x-body); right: var(--body-right); top: var(--pad-y); height: var(--ph); padding-top: var(--body-pt); z-index: 2; }
.feed-band-time   { position: absolute; right: var(--when-right); top: calc(var(--pad-y) + var(--body-pt)); z-index: 2; }
/* hover: every scrim alpha × .8 and the ground lifts; nothing moves. The
   catalog pins it with .feed-hover-pin, since a story cannot hover. */
.feed-band:hover, .feed-band:focus-within, .feed-hover-pin > .feed-band { --s: 0.8; background: oklch(16% 0.02 264); }
.feed-band-bare:hover, .feed-band-bare:focus-within, .feed-hover-pin > .feed-band-bare { background: oklch(20% 0.017 264 / 0.5); }
```

Write the lead's five stops out in full (the `…` above is the plan's elision). The lead's tile-top constant `13px` is half of line 1's 26px height; the band centres its tile on the unit. The seat's opacity stays Tailwind (`group-hover:opacity-100`, 120ms). Then `~/scripts/agents/agent-mix assets.build`.

- [ ] **Step 5: The component** — `lib/media_centaur_web/components/discovery/feed_band.ex`, `Discovery.FeedBand`, `feed_band/1`. Attrs: `attr :entry, FeedEntry, required: true`; `attr :size, :atom, values: [:lead, :band], default: :band`. Two public builders (MC0028 sees `*_src(`; a later `ArtworkWarmup` entry calls them):

```elixir
  @backdrop_width %{band: 1280, lead: 1920}
  @poster_width %{band: 160, lead: 320}

  @doc "The `src` a unit's still paints at its size — one definition per size, so a prefetch can match it."
  @spec band_backdrop_src(String.t() | nil, :lead | :band) :: String.t() | nil
  def band_backdrop_src(url, size), do: sized_image_url(url, @backdrop_width[size])

  @spec band_poster_src(String.t() | nil, :lead | :band) :: String.t() | nil
  def band_poster_src(url, size), do: sized_image_url(url, @poster_width[size])
```

The template, from the mockup's DOM, keeping the row's contract:

```heex
<div
  id={@entry.id}
  role="button"
  class={[
    "group feed-band text-left",
    @size == :lead && "feed-band-lead",
    @entry.offset_crop? && "feed-band-offset",
    !@entry.backdrop_url && "feed-band-bare"
  ]}
  data-component="feed-row"
  data-size={@size}
  data-kind={@entry.kind}
  data-own={@entry.own?}
  data-list-slot={@entry.list_slot}
  data-download-slot={slot_name(@entry.download_slot)}
  phx-click="open_title"
  phx-value-ref={TitleRef.param(@entry.ref)}
  phx-value-activity={@entry.activity_id}
  data-entity-id={TitleRef.param(@entry.ref)}
>
  <img
    :if={@entry.backdrop_url}
    src={band_backdrop_src(@entry.backdrop_url, @size)}
    alt=""
    class="feed-band-backdrop"
    data-role="backdrop"
    loading="eager"
    decoding="sync"
    fetchpriority={if @size == :lead, do: "high"}
  />
  <div class="feed-band-scrim" aria-hidden="true"></div>
  <span class="feed-band-tile">
    <IdentityTile.identity_tile name={@entry.author} own?={@entry.own?} size={tile_size(@size)} />
  </span>
  <img :if={@entry.poster_url} src={band_poster_src(@entry.poster_url, @size)} alt="" class="feed-band-poster rounded-md object-cover" data-role="poster" loading="eager" decoding="sync" />
  <div :if={!@entry.poster_url} class="feed-band-poster rounded-md ring-1 ring-inset ring-base-content/10" data-role="poster-empty"></div>
  <div class="feed-band-body text-on-image flex flex-col">
    <p class="truncate text-base-content/80 …" data-role="who">…name at font-medium text-base-content/95, the verb, the glyph…</p>
    <p class="flex items-baseline gap-2 …" data-role="title">…title at font-semibold, the year at text-base-content/60…</p>
    <p :if={@entry.text} class="line-clamp-2 text-base-content/80 …" data-role="text">{@entry.text}</p>
    <div class="-mx-1.5 mt-auto flex h-5 items-center gap-0.5 text-[13px] text-base-content/80 opacity-0 transition-opacity duration-120 group-hover:opacity-100 group-focus-within:opacity-100" data-role="toolbar">
      …the four slots as today; Ignore gets `ml-2.5` instead of `ml-auto`…
    </div>
  </div>
  <span class="feed-band-time text-on-image text-[13px] tabular-nums text-base-content/80" data-role="time">{@entry.ago}</span>
</div>
```

Sizes per REASONING's table, by `@size`: line 1 `text-[15px] leading-[22px]` / `text-lg leading-[26px]`; line 2 `text-lg leading-6` / `text-[32px] leading-[38px] text-on-image-lg`; the year `text-[13px]` / `text-[15px]`; line 3 `text-sm leading-5 line-clamp-2 mt-[5px]` / `text-base leading-6 line-clamp-3 mt-2.5`; the glyph `size-[13px]` / `size-4`; the lead's `data-role="who"` drops the 64px right padding. The tile's position is the band's (`span.feed-band-tile`), its look the tile's. Text alphas: 80% body, 95% name, 60% year, 66% plain states (`text-base-content/65` — MC0034 wants an integer ≥ 55), 80% seat. `tile_size(:lead) = 48; tile_size(:band) = 40`. Moduledoc rewritten from the glossary's *Band* and *Lead* rows plus the contract paragraph; `title/row.ex:9-10` now says `Discovery.FeedBand`.

- [ ] **Step 6: Wire the page minimally** — in `discovery_live.ex`, alias `FeedBand`, and `<FeedBand.feed_band :for={entry <- @feed} entry={entry} />` inside the old `#feed-list` (the column and the lead are Phase 4). Run the page tests: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs` — all green without edits proves decision 8 held. Then the storybook render test.

- [ ] **Step 7: The artwork page test.** In `discovery_live_test.exs` § feed tab, after "an activity for a title in the library paints the entity's poster" (the Friends-tab precedent at line 339):

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

Every row is a band until Phase 4, when the newest becomes the lead and this test's first assertion changes to `?w=1920`. `data_dir` comes from a `setup` that points the config's `data_dir` at a temp directory the way `test/media_centaur/tmdb_artwork_test.exs:7-17` does (a `:persistent_term` write, legal in this `async: false` module and restored by the checkout); `seed_referenced_artwork/4` is that test's `seed_entry/4` — move it into `test/support` so both files share it (an empty `backdrop.jpg` is enough: the page checks `File.exists?`, never decodes). The warm path (`warm_activity_artwork/1`) behaves as in every existing feed test: gated by `Capabilities.tmdb_ready?/0`, awaited by `await_supervised_tasks/0`.

- [ ] **Step 8: Precommit and look.** `~/scripts/agents/agent-mix precommit`. `page-shot` `/storybook/discovery/feed_band` and Read it; check the still's crop on the adjacent pair and that the seat appears on the hover-pinned variations.

**Acceptance:** every variation renders; the band reads at 152px and the lead at 340px in the catalog; the crop offset alternates in the projection; the page tests pass untouched; MC0009 finds `feed_band.story.exs` with both `:lead` and `:band`; no `loading="lazy"`; every `/media-images` src is width-declared.

```bash
git add -A
git commit -m "feat: the feed band — one unit at two sizes, on the title's still under the ink scrim

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Phase 4: The page — full width, the column, the lead

**Files:**
- Modify: `lib/media_centaur_web/live/discovery_live.ex` (`render/1`, the moduledoc's Feed paragraph)
- Modify: `test/media_centaur_web/live/discovery_live_test.exs` § feed tab, `test/media_centaur_web/page_smoke_test.exs`

- [ ] **Step 1: Failing page tests**

```elixir
    test "the newest action in the window is the lead; the rest are bands; a scope change re-projects the lead", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, theirs} = Activities.ingest(friend_listing_event(777, System.os_time(:second) - 60))
      title = Title.new!(%{tmdb_id: 999, media_type: :movie, name: "Sample Movie 999"})
      {:ok, mine} = Activities.listing(title)

      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, "#feed-list > " <> entry(mine) <> "[data-size='lead']:first-child")
      assert has_element?(view, entry(theirs) <> "[data-size='band']")
      assert ids(view, "[data-size='lead']") == ["feed-row-#{mine.id}"]

      view |> element("#feed-scope [phx-value-choice='friends']") |> render_click()
      assert ids(view, "[data-size='lead']") == ["feed-row-#{theirs.id}"]

      await_supervised_tasks()
    end

    test "an empty Feed has no lead", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery?scope=you")
      assert has_element?(view, "#feed-empty")
      refute has_element?(view, "[data-size='lead']")
    end
```

Update Phase 3's artwork test: the owned title (newest) is now the lead and asserts `?w=1920`; the cached one stays a band at `?w=1280`. Add to it: the lead's backdrop carries the priority hint and no band's does —

```elixir
      assert has_element?(view, entry(owned) <> " img[data-role='backdrop'][fetchpriority='high']")
      refute has_element?(view, entry(cached) <> " img[data-role='backdrop'][fetchpriority='high']")
```

Run → FAIL (`data-size='lead'` never renders; everything is a band).

- [ ] **Step 2: The template**

- `<Layouts.app … full_width …>` (decision 2).
- The page root's inner wrapper `mx-auto w-full max-w-4xl space-y-4 pt-10` → `w-full space-y-4 pt-10`. (Under decision 2's alternative, the Watchlist and Friends tab roots each get `mx-auto w-full max-w-4xl` instead.)
- The Feed's list: `<div :if={@feed != []} id="feed-list" class="feed-column">` with

```heex
<FeedBand.feed_band
  :for={{entry, index} <- Enum.with_index(@feed)}
  entry={entry}
  size={FeedEntries.size(index)}
/>
```

- *Show older*: `class="pl-2 pt-2.5"` on its wrapper (left, at the tile's edge) instead of `flex justify-center pt-3`.
- The empty state is unchanged; with `@feed == []` no band renders, so no lead — the test pins the fact.
- The moduledoc's Feed paragraph: "…one row per action, newest first, flat (`FeedEntries`), as a full-width column of bands on the page ground, the newest as the lead (`FeedBand`, UIDR-046)…" replacing "in one list surface".

- [ ] **Step 3: The smoke** — in `page_smoke_test.exs`, the `/discovery` fixture (the block around line 58) seeds one friend listing on a title the library owns with poster and backdrop images (`create_image role: "backdrop"`), so the smoke renders the lead's artwork branch and a band's; keep it in the smoke file, not the feature test.

- [ ] **Step 4: Green, precommit, the three widths**

`~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/page_smoke_test.exs`, then precommit, then on :2160 (the dev DB has the real roster) `page-shot` `/discovery` at `1920x1080`, `1280x800`, `2560x1440`, and `/discovery?scope=you`, `/discovery/friends`, `/discovery/watchlist` at 1920. Read each. What to look for, from REASONING: the lead's still begins at x≈576 and the bands' at ≈920 (the picture edge steps right after the first unit — the designer's one doubt; if it reads as two rules, state 14 is the fallback); the band's box at 1280 starts at 576 with no ink gap; at 2560 the ink between words and box is ~984px (the known limit — the app's UI scale renders 2560 near 1920 anyway); the seat appears on hover and the height does not change; the Friends cards at full width (decision 2's consequence).

**Acceptance:** index 0 is the lead under every scope; the empty You scope has no lead; `?w=1920`/`?w=1280` as declared; the three widths render as REASONING describes; the tab count still follows the scope; the modal opens from a band and closes to the same scope (existing tests).

```bash
git commit -am "feat: the Feed at full width — a column of bands, the newest as the lead

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Phase 5: Records and docs

**Files:**
- Create: `decisions/user-interface/2026-09-25-046-the-cinematic-feed.md`
- Modify: `decisions/user-interface/2026-09-24-045-…md`, `2026-09-11-038-…md`, `2026-09-07-033-…md`; run `scripts/gen-decisions-index`
- Modify: `docs/superpowers/specs/2026-09-24-feed-appearance-design.md`, `docs/social.md` (§ Web layer, the Feed bullet), `docs/GLOSSARY.md`, `docs/storybook.md` (§ Component triage), `.claude/skills/user-interface/SKILL.md`, `campaigns/feed-appearance.md`, `../media-centaur.wiki/Social.md`

- [ ] **Step 1: UIDR-046 — *The cinematic feed*.** MADR 4.0 from `template.md`, `status: accepted`, `date: 2026-09-25`. Opening line: "Amends UIDR-045 (rules 3 and 5), UIDR-038 (the *wall of watching*, *title-first row* and *social-network chrome* anti-patterns) and UIDR-033 (the artwork rule). Design: the spec; the chosen page: `F-cinematic-feed/REASONING.md`." Decision Outcome, numbered:
  1. One unit at two sizes — the band (152px) and the lead (340px, index 0 in the scoped window); same markup, same scrim, same crop; 6px apart on the page ground; no border, glass, shadow or hairline; the Discovery page at full width.
  2. The identity tile is the app's person device on the Feed and the Friends tab: a monogram, a photo when one exists, the own tile filled with the button primary and a white letter (a 2px primary ring over a photo); "You" is set like any name.
  3. Row artwork is the row's subject: the title's backdrop in an image box from `max(576, width − cap)`, the band's cap 900px, the lead uncapped, the box's left edge dissolved over 360px, under the ink scrim (the five stops); the lead adds a .30 left layer under its time.
  4. The crop rule: `50% 30%` on every still; the second of two adjacent rows of one title at `50% 38%`, derived, never set; no smart crop (MEASUREMENT).
  5. The time seat: right-aligned at the body's edge — the text zone's edge on a band, the padding on the lead.
  6. Hover: the scrim × .8 and the ground lifted, instant; the seat's 120ms fade is the only transition; heights constant.
  7. Every size named (paste REASONING's "What the user sees" table).
  Consequences: good — the author is found without reading at any roster size; the page composes at 1920 and holds at 1280 and 2560; bad — sixteen stills per screen (one derivative each, cached); the Watchlist and Friends tabs share the width before they share the language. Anti-patterns: a per-title crop position; a hairline between two pictures; a different still for a repeated title; parallax or drift; a vignette on the band's right edge; an avatar with handles, counts or reactions.

- [ ] **Step 2: The amendments** (front matter `amended: 2026-09-25` plus one line under the title, the house pattern in UIDR-038):
  - UIDR-045: "Amended by UIDR-046 (2026-09-25): rule 3 — the own mark is the identity tile, the word You set like any name; rule 5 — the list surface is gone, bands 6px apart on the page ground, the Discovery page at full width."
  - UIDR-038: "Amended by UIDR-046 (2026-09-25): *social-network chrome* admits the identity tile (the Friends tab's monogram, a photo when one exists) as the app's person device on both tabs — handles, counts and reactions stay banned; *wall of watching* — a captioned still per action is not a wall of titles, the sentence leads in a fixed text zone; *title-first row* is bent on the lead only, where the title is the largest type under the sentence."
  - UIDR-033: "Amended by UIDR-046 (2026-09-25): a row's own title artwork is that row's subject — the Feed's bands carry their title's backdrop; a band of an unrelated title stays banned; the page-level rule (rule 2) is unchanged."
  - `scripts/gen-decisions-index`.

- [ ] **Step 3: The spec** — in `2026-09-24-feed-appearance-design.md`: status → `implemented 2026-09-25 (UIDR-046); plan in \`../../plans/2026-09-25-cinematic-feed.md\``; "What the user sees" ← REASONING's table verbatim, with its lead paragraph; "The model" — the identity tile paragraph becomes present tense (the attr exists; the view-model field waits on the protocol), the row artwork paragraph names `ActivityArtwork`, `Library.Artwork`, `TmdbArtwork` and the two builders; "Acceptance criteria" ← this plan's phase acceptances; "Anti-patterns" ← UIDR-046's; "Records" ← the four.

- [ ] **Step 4: Contributor docs** — `docs/social.md` Feed bullet: "…`FeedBand` renders one unit at two sizes — the newest action as the lead — on the page ground at full width, each on its title's backdrop (`ActivityArtwork` resolves poster and backdrop down the ladder; `Library.Artwork` is the library tier by role), with its hover toolbar…". `docs/GLOSSARY.md`: the **Feed** (tab) row loses "in one inset list surface" and gains "as a column of bands, the newest the lead (UIDR-046)"; the **Author** row: "an own row's tile is filled"; new rows **Band**, **Lead**, **Identity tile** from this plan's glossary (the app's words, not the plan's). `docs/storybook.md` § Component triage: rows for `discovery.identity_tile/1`, `discovery.feed_band/1`, `discovery.person_card/1` (✅ covered; the table has no Discovery rows today). `.claude/skills/user-interface/SKILL.md`: UIDR table row `| 046 | The cinematic feed — one unit at two sizes on the title's still; the identity tile; the crop rule |`; Component Inventory rows for `identity_tile/1` and `feed_band/1` under the Discovery family; in § Rendering Defaults the sentence "Every other page carries the scrim only" gains "— a row's own artwork is different: the Feed's bands carry their title's backdrop (UIDR-046)"; § Layout gains one line on `.feed-column` / `.feed-band` as the band's classes.

- [ ] **Step 5: The wiki** (`../media-centaur.wiki/Social.md`): § Feed's first paragraph adds "Each row is a wide band on the title's own artwork, and the newest action is shown larger at the top; the page uses the whole width of the window. Your own rows carry a filled circle with your initial; a friend's carries the first letter of their name — the same circle the Friends tab draws." The "A row shows" table's first line gains the circle; § Friends: "Each card starts with the person's circle — their initial…". Commit the wiki separately (`wiki: the Feed's bands and the identity tile`); do not push.

- [ ] **Step 6: The campaign** — `campaigns/feed-appearance.md`: `status: implementing` (or `complete` if the owner closes it here), a Status paragraph naming the five phases shipped and the sixth pending, a Decisions entry for the owner's morning decisions with their dates, and every inherited follow-up bucketed (ship / verify / defer-to-X, the closure rule): the storybook fixture image → closed in Phase 1; "a listing row's two lines sit at the top" and "row type sizes grew" → absorbed by UIDR-046's table; "Friends card's Recently watched tiles at the wider column" → re-opened by decision 2 (verify at 1920 or the alternative); the rest unchanged.

```bash
git add -A
git commit -m "docs: UIDR-046 the cinematic feed; amendments to 045, 038 and 033; the spec, glossary, skill and campaign

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Phase 6: The hardening pass (later; not planned here)

Once the layout has stopped moving: a `feed` nav zone (a vertical list, `Context.TREE` like `title_rows`) with each band a nav item and the seat's verbs reachable inside it; the scope pill's zone; `config.js` edges from `zone_tabs` down into `feed` and from the sidebar right into it; the 2px primary `::after` ring on the focused band (mockup state 7 — the UIDR-020 default, no collision to name); Enter opens the title; verification with `~/scripts/agents/mc-nav-trace`; the wiki's Keyboard-and-Gamepad page. Also `Discovery.PersonCard`'s items already are nav items. This is the campaign's step 6 and the *Feed rows and the scope pill are mouse-only* follow-up; it is its own plan.

---

## Out of scope — follow-ups, each its own phase or campaign

- **The Watchlist in bands** (P): title first, the ladder and acquisition words in the seat, the pennant mast at the text zone's edge (not the far right — the time-seat problem again), a no-artwork title as an ink band; the identity tile's 32px size arrives with it if it needs one. Owner decision 3.
- **The Friends card beyond the tile**: whether `border-primary/30` on the You card survives now that the tile marks it; the six-column strip at full width (decision 2's consequence); the card's own max width.
- **Incoming's activity** in the band language (state words are the seat's vocabulary).
- **Hover or cursor ease** (400ms, scale 1.03) — owner decision 4; two lines of CSS if wanted.
- **A profile photo**: the social protocol's event, `Person.photo_url` and `FeedEntry.photo_url`, the hosts passing them; the tile already renders it.
- **`ArtworkWarmup` for the Feed**: the two builders are public for it; whether Discovery is "first screen" is the judgment that module asks for. Not now.
- **`.page-side-dim` on Discovery** — finding 5; the owner's call whether the Feed's ground gets the scrim every other page has.
- **The `Downloading` hairline's progress** — finding 10; needs a progress fact on the row.
- **Motion**: none (parallax and drift rejected by X).
