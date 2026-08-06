---
status: planning
started: 2026-07-10
last_updated: 2026-07-10
---
# Documentation catch-up pass

## Goal

A massive wiki / guide / documentation pass to catch everything up to date
with what the product actually is now — probably including an updated
showcase and webpage updates. (Owner's framing, 2026-07-10, prompted by the
usenet work: the wiki/settings docs were updated piecemeal per feature, but
whole surfaces have drifted as the product moved under them.)

## Status

Planned only — no inventory taken yet. First session should build the
surface inventory before editing anything.

## Scope surfaces (from the owner's framing)

* **Wiki** (`../media-centaur.wiki/`) — the fleshed-out user docs, page by
  page against current behavior. Note: `Download-Clients.md` /
  `Settings-Reference.md` already have local-only commits (usenet) waiting
  to be pushed with the next app release.
* **Guides** — setup / how-to content wherever it lives (wiki pages,
  `docs/` pointer stubs, First-Run, README).
* **Repo documentation** — README, `docs/` contributor docs accuracy.
* **Showcase** — the demo instance / marketing screenshots
  (`screenshot-showcase` skill covers the regeneration chain). This surface
  inherited the screenshot debt of every retired campaign: the sections
  overhauled since the last regeneration are **Upcoming** (a timeline rail
  now, not a calendar — the `upcoming-calendar` shot is of a UI that no
  longer exists), **Incoming**, and **media search**. Treat "which shots are
  of dead UI" as part of the inventory rather than assuming the list is
  those three.
* **Webpage** — `docs-site/index.html` (media-centaur.net) content updates.

## Decisions made

Append-only log.

* `2026-07-10` — Campaign created at the owner's direction as the follow-up
  to the usenet/multi-client work. Not started; planned as its own
  initiative rather than folded into feature ships.
* `2026-08-06` — Inherited the marketing-screenshot regeneration from the
  campaigns retired that day (`upcoming-overhaul` shipped v0.94.x and left
  its shot of the old calendar behind). Screenshot regen is a documentation
  surface, not a tail on each feature campaign — this is where it lives now.

## Next steps

1. Inventory pass: list every wiki page / doc / site section with a
   fresh-or-stale verdict against the current product (the `docs-audit`
   skill exists for the repo-docs slice).
2. Agree the order (likely: wiki accuracy → guides → showcase/screenshots →
   webpage) and whether anything is droppable rather than updatable.
3. Execute per surface; push the held usenet wiki commits with the first
   app release that ships the feature.

## Completion criteria

* Every wiki page describes current behavior (or is deleted).
* Guides reflect the current setup flow end to end (incl. usenet).
* Showcase screenshots and the webpage match the current UI and feature
  set.
* No held local-only wiki commits remain.
