---
status: design exploration
started: 2026-05-30
last_updated: 2026-05-30
---
# Marketing site overhaul (media-centaur.net)

## Goal

Rebuild the public landing site (`docs-site/index.html`, served at
media-centaur.net) so it (a) stops reading as obviously AI/Claude-Code
generated, (b) is true to the actual product's brand, and (c) properly
sells a deep app — lean home with summaries, secondary feature pages,
and a demo that shows the thing in motion. Triggered by the page leaning
on generic AI-landing tells (no real fonts, blue/purple glow blobs,
pill-with-dot badges, glassy 3-col feature grid, dead symmetry).

## Status

**Design exploration / direction chosen.** Five HTML mockups built under
`mockups/` (gitignored scratch, not shipped):
1. `1-cinematic-film-archival/` — editorial/Criterion. (reference)
2. `2-retro-terminal/` — CLI-tool aesthetic. (reference)
3. `3-heraldic-mythic/` — parchment + engraving. (reference)
4. `4-streaming-app-cinematic/` — streaming-interface v1 (amber; superseded).
5. `5-streaming-home-v2/` — **the chosen direction**, palette-corrected,
   copy-corrected, + one example feature page (`features/playback.html`).

Direction picked: **"the site is a media center"** — Netflix/Prime/Apple-TV
home-screen idiom (billboard hero, horizontal content rails, frosted-on-
scroll nav), using the app's own colors so the site and app feel like one
thing.

**Full multi-page site now built in `mockups/5-streaming-home-v2/` (flat files,
one shared design system, canonical nav + footer, all internal links verified):**
home (`index.html`), 6 feature pages (`feature-library-management`,
`feature-playback`, `feature-release-tracking`, `feature-acquisition`,
`feature-input`, `feature-real-time`), `how-it-works`, `compare`, `faq`,
`about`. The old `features/playback.html` subdir was removed (superseded by the
flat `feature-playback.html`). Whole site is navigable for review.

## Decisions made

* `2026-05-30` — **Direction: streaming-interface** ("the landing page is a
  media center"). Chosen over cinematic/terminal/heraldic mocks because it's
  true to the product, not borrowed.
* `2026-05-30` — **Use the app's real palette**, pulled from
  `assets/css/app.css` `:root`: azure primary `oklch(62% 0.16 250)`, cool-slate
  base (hue 264), the app's glass tokens. Earlier amber/gold accent rejected —
  it matched nothing in the app. The blue must be *earned* by killing the other
  slop tells (no glow blobs, no pill-dots, real fonts, broken symmetry).
* `2026-05-30` — **Type: one premium grotesque with heavy weight contrast**
  (device-UI feel), NOT an editorial serif. Hanken Grotesk in the current mock;
  family not finally locked.
* `2026-05-30` — **No maturity label at all.** Dropped "Alpha"; not "Beta"
  either. Must sweep README badge (`status-alpha-orange`), `installer/install.sh`
  header comment, and the docs-site status pill so nothing contradicts it.
* `2026-05-30` — **Framing: "desk to couch."** Desktop is first-class; scrub
  every couch/TV-only line ("distance between couch and TV"). Keyboard-fast at
  the desk, gamepad/remote on the couch — both first-class.
* `2026-05-30` — **IA: lean home → secondary feature pages.** Home carries
  one-line capability summaries with "Learn more →"; depth (more screenshots +
  copy) lives on per-feature pages. The app does a lot; equal heavy blocks
  flatten it.
* `2026-05-30` — **Non-goals trimmed to three:** not-a-streaming-server,
  no-transcoding, single-user. **Docker dropped** — it's a *how*, not a
  philosophy, and "no Docker" reads as a missing feature to part of the audience.
* `2026-05-30` — **macOS install corrected.** `installer/install.sh` has a
  `Darwin/arm64` branch (launchd) — the one-liner installs on Linux x86_64 AND
  Apple Silicon (experimental). Copy must not say "Linux only" or imply manual.
* `2026-05-30` — **Footer copyright: `© 2026 Shawn McCool`** (matches `LICENSE`).
  "Media Centaur" is not a company.
* `2026-05-30` — **Privacy/ownership is a pillar**, not a throwaway line
  ("Your library. Your machine. No cloud, no accounts, nothing phones home.").
* `2026-05-30` — **Hero designed to host a looping muted demo clip** (static
  screenshot poster placeholder for now); the `<video>` drops in later.
* `2026-05-30` — **Showcase catalog gains 2 TV series** (`catalog.ex`): Petticoat
  Junction (1963, PD via Filmways renewal lapse) + One Step Beyond (1959, PD
  anthology), bringing tracked TV series to 4. The home "Coming Up" marquee
  dedups by series (`home_live/logic.ex:128`), so 2 series only rendered 2 tiles;
  4 series → 4 tiles. **Real repo change, tested** (`showcase_test.exs` 15/0).
  Still needs `reseed-showcase` + `regenerate-screenshots` to capture the shot.
* `2026-05-30` — **Page messaging reframes** (mock): Input leads with "your
  universal TV remote already runs it" (keyboard-nav is the enabler, not the
  hook; mouse at the desk); Real-time leads with "Runs chromeless. Feels
  native." (best-of-both-worlds, "native application" wording); Release tracking
  leads with "Show a little interest. One morning it's just there." (framed as
  showing interest, not a deliberate one-time add; auto-arrival needs optional
  acquisition).
* `2026-05-30` — **Founder's note (about.html) is unsigned** — name/byline
  removed at owner's request (self-aggrandizing); footer legal `© Shawn McCool`
  stays (matches LICENSE).
* `2026-05-30` — **Responsive pass done** across all 11 pages: consistent mobile
  nav (hamburger → glass dropdown below 760px), ultra-wide cap (~1480px,
  ~70ch measure), tablet/mobile single-column collapse, no horizontal overflow
  (compare scorecard side-scrolls; kiosk mock + install boxes contained).
  Verified headless at 390/820/2560 on 9 of 11 pages.

## Status update — port DONE (2026-05-30)

The full 11-page site is **ported into `docs-site/`** (real, tracked) via a
deterministic Python script: logo paths rewritten to `assets/…`, screenshots
switched **CDN → local `assets/screenshots/…`**, per-page `<head>` meta injected
(canonical, theme-color, favicon, OpenGraph/Twitter). Verified: no stray `../../`
or jsDelivr-screenshot refs, every local screenshot resolves, all internal links
OK, OG on every page, **zero "alpha"** in docs-site. Tailwind CDN and the old
"Alpha" status strip are gone (replaced by the new design). README swept: alpha
status badge removed, `[!WARNING] Alpha` → `[!NOTE] Pre-1.0 and actively
developed`, couch-only line reframed to desk+couch. **Not committed/pushed yet —
awaiting local review (push to `main` auto-deploys to media-centaur.net).**

## Next steps

1. **Local review of `docs-site/`**, then commit + push (deploys). Keep the
   docs-site port commit separate from unrelated working-tree changes (app.css,
   test/e2e/*) and the `catalog.ex` showcase change.
2. **Follow-up bucket (remaining):**
   - Custom OG social card (currently reuses the logo); favicon set.
   - Roadmap / what's-new page (only planned surface not built).
3. Wiki sync for any user-visible copy/positioning changes.

## Shipped (2026-05-30, pushed to main)

* `c3ec971` docs-site rebuild (11 pages) + README alpha sweep — **live on
  media-centaur.net**.
* `9794083` + `ab8671f` showcase 4-tile Coming Up: needed BOTH the catalog
  addition (library presence) AND the `seed_release_tracking!` `upcoming` list
  (the marquee dedups by *tracked* series, not catalog — caught by verifying the
  captured screenshot before publishing).
* `95fcdd3` regenerated marketing screenshots (web → main, 4K → assets repo),
  verified the 4-tile Coming Up renders (hero One Step Beyond + Petticoat
  Junction / Pioneer One / Beverly Hillbillies).
* `de739e5` hero layout fix — `.hero` was a 2-col grid wrapping a 2-col inner,
  cramming content left with a dead right half.
* `c04b2eb` + `0f4d5ec` hero demo clip: a muted, looping ~15s walkthrough
  (home with nav → into Library where the sidebar collapses and artwork takes
  over → a title's episode-list detail), wired as autoplaying `<video>` with
  home.png poster + an autoplay-nudge / tap-to-play fallback for mobile.
  Reproducible via `scripts/record-demo` + `test/e2e/demo-record.mjs`.

## Shipped (2026-05-30, second session)

* **Shared CSS extraction** — pulled the design-system core duplicated across all
  11 pages into one `docs-site/assets/site.css` (25 `:root` vars unioned + 80
  shared selectors), linked before each page's inline `<style>`. **−1335 lines of
  duplicated HTML**, collapsed into a 248-line sheet. Dead `.play-affordance` rules
  dropped (the campaign's earlier note was wrong about `.stage-chip` — that one is
  still live as the "Live preview" chip on the hero video stage, so it stayed).
  * **Hard part = cascade order.** External sheet loads *before* inline, so any
    moved rule jumps ahead of inline rules. Three collision classes had to stay
    inline to preserve rendering: (1) `@media` blocks (never extracted — nesting a
    breakpoint override ahead of its base flips the cascade); (2) base/modifier
    families where the base is page-divergent (`.btn` + `.btn-ghost`); (3) selectors
    also targeted inside an `@media`. The transform self-computes these excludes
    from the `@media` contents + markup class co-occurrence.
  * **Verified zero visual change** three ways: a set-equality check (every page's
    applicable rule multiset preserved), a computed-style oracle diffing every body
    element before/after at 1280/760/390px (via `chromium-probe` + a width-forced
    CDP probe), and isolating the only residuals (`.live-dot` pulse, `.rail-tag`
    reveal) as keyframe-animation timing jitter (reproduce on self-vs-self loads).
    The one-shot migration script lives in `/tmp` (not a repo build step — re-running
    it against already-extracted files would mis-classify).

## Completion criteria

* media-centaur.net serves the streaming-direction site: lean home + feature
  pages, real app palette, corrected copy (no label, desk-to-couch, Docker
  dropped, macOS accurate, `© Shawn McCool`), a demo clip in the hero, proper
  OG card + favicons, and none of the original AI-slop tells.
* No "alpha" remaining in README badge, installer header, or docs-site.
* Wiki reflects any changed positioning/setup copy.
