---
status: accepted
date: 2026-09-07
---
# Home is the only page that carries artwork

Supersedes the Library and Incoming halves of
[UIDR-032](2026-09-06-032-page-hero-backdrops-paint-from-a-decoded-bitmap-cache.md).

## Context and Problem Statement

Home's backdrop is the artwork *of its hero* — the title the page is offering,
sitting behind that title's name, synopsis and Play button. The image is the
subject.

Library and Incoming had no hero. They rendered a band of some *other* title's
backdrop, picked by rotation, purely as decoration. Because the image referred
to nothing on the page, everything downstream of it had to compensate:

* a slot allocator (`select_page_hero/3`, `select_alt_hero/2`, `hero_pages/0`)
  existed only to keep three pages from showing the same random picture;
* two `Settings → Preferences` toggles, two `Settings` boolean keys, two
  `on_mount` modules and a seed migration existed only so a user could turn
  the decoration off;
* two extra scrim ramps (`.page-side-dim-high`) and a masked band
  (`.page-atmosphere`, `.page-atmosphere-deep`) existed only to keep text
  readable over an image nobody asked for;
* the prefetch warmup fetched and decoded three 4K masters at launch instead
  of one.

A setting whose honest description is "show a picture of something unrelated"
is a sign the feature is decoration, not design. UIDR-012's rendering budget is
spent on instant perception of content, not ambience.

## Decision Outcome

Chosen option: "Home carries page artwork; every other page carries the scrim
only", because a backdrop earns its cost when it depicts the page's subject,
and no other page has one.

* `.page-backdrop` (Home) is the app's one page-artwork surface. It keeps the
  UIDR-032 canvas + decoded-bitmap cache, now with a single cache slot.
* Every other page keeps `.page-side-dim` — the subject-free scrim that gives
  the shell its depth — in the standard ramp, or `.page-side-dim-calm` on
  pages sparse enough that the standard ramp reads as a band (Settings,
  Status, Incoming).
* `.page-atmosphere`, `.page-atmosphere-deep` and `.page-side-dim-high` are
  removed, as are both preferences and their toggles.
* Hero selection collapses to `HomeLive.Logic.select_hero/2`; `ArtworkWarmup`
  warms the single current pick.

### Consequences

* Good, because artwork on a page now always means "this is what the page is
  about" — there is one rule, not a per-page opt-out.
* Good, because it deletes a settings pair, a rotation allocator, two CSS
  systems and two thirds of the launch backdrop decode budget.
* Good, because Library and Incoming are dense working surfaces; without a
  band under them, posters and rows sit on flat dark and read at full contrast.
* Bad, because installs that had the bands on lose them with no way back. The
  orphaned settings rows are dropped by
  `20260907120000_drop_page_backdrop_settings`; re-introducing the feature
  would mean re-introducing the decision, which is the point.
