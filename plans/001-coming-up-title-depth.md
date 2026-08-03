# Coming Up title depth — one modal idiom, stragglers as rows

## Problem Statement

Coming Up's per-title depth opens the app's only slide-over — a one-off physics that
clashes with the centered pursuit modal on the same page — and tracked titles with
nothing scheduled are inert text in a disclosure: the user can see them but cannot
open them, toggle automation, or stop tracking. The status vocabulary also leans on
an invented term ("Armed") users must learn for this app exclusively.

## Design Objectives

- One idiom for depth: clicking any object on Incoming zooms in the same way.
- Everything tracked is actionable: schedule state never gates access to a title's
  verbs.
- Calm stays calm: the agenda list keeps its density; bookkeeping never outshouts
  the schedule.
- Copy states what happens: no vocabulary the reader has to be taught.

## User-Facing Behavior

- The Coming up agenda list is unchanged in anatomy and order. After the dated rows
  and "Show all N", a quiet hairline toggle — "Not scheduled yet · N" — holds the
  tracked-but-unscheduled titles, collapsed by default. Expanding grows the list in
  place with normal rows: empty date slot, poster thumb, title, the media type in
  the subtitle position, neutral Tracked pill. Collapsing hides them again; every
  fresh visit starts collapsed.
- Selecting any row (dated or unscheduled) opens a centered title modal (ephemeral:
  backdrop click, Escape, and × all close; focus returns to the opening row). The
  modal carries: identity header with the title's backdrop art; a featured
  next-release line ("S03E07 'Landfall' — Tonight · Will grab") or, for unscheduled
  titles, a plain absence statement; the auto-grab toggle; the releases timeline
  with landed entries muted; recent activity; and "Stop tracking" — the only
  error-tinted control — in the footer.
- The right slide-over no longer exists anywhere in the app.
- The status label "Armed" is replaced by "Will grab" on every surface (row pills,
  torrent-row pills, event cards, wiki). "Grabs if still missing" remains for the
  fallback status.
- Without acquisition configured, the modal shows no automation section and no
  status implying grabbing is possible (existing degradation rule holds).

## Acceptance Criteria

- [ ] Clicking any Coming Up row opens a centered ephemeral modal through the house
  modal seam; no drawer/slide-over remains in the app.
- [ ] Tracked titles with nothing scheduled sit behind a "Not scheduled yet · N"
  toggle, collapsed by default; expanding renders them as rows in place; the
  text-only disclosure is gone.
- [ ] Straggler rows open the same modal with the same verbs (auto-grab toggle, stop
  tracking); their releases section states the absence plus the last landed entry
  rather than rendering empty.
- [ ] The modal leads with a featured next-release line, or an explicit "Nothing
  scheduled" statement for unscheduled titles.
- [ ] The word "Armed" appears on no user-facing surface; the status reads "Will
  grab" on row pills, torrent-row pills, and event cards, and the wiki reflects it.
- [ ] Keyboard/gamepad: every row is a discrete nav item; the modal is reachable and
  dismissible from the couch; focus returns to the opening row on close.
- [ ] Forecast-only installs: no automation section and no grab-implying status
  anywhere in the modal or list.
- [ ] Empty states: dated rows absent but stragglers present → divider and rows
  still render; nothing tracked at all → the section renders nothing.

## Anti-patterns

- **Second depth idiom**: no drawers, no accordions — the pursuit modal and the
  title modal must share physics; that split is the bug this work removes.
- **Watchlist wall**: no card grid for stragglers; presence scales as rows and never
  reads louder than the schedule.
- **Settings-page cosplay**: the modal carries one automation toggle, not a settings
  panel.
- **Decorative color**: per-title hue lives only in artwork; chrome stays
  achromatic; color communicates state only.
- **Glossary vocabulary**: no status label that requires a wiki definition to parse.

## Deferred

- Richer per-title management (quality/version preferences, artwork) — separate
  feature; if added later, the modal idiom is the surface with room to grow.
- Capping straggler rows behind their own "Show all" — only if real libraries prove
  the tail long; measure first.

## Decisions

See `decisions/user-interface/2026-08-03-017-coming-up-title-depth.md`.
Mockup exploration and per-direction reasoning: `mockups/coming-up-depth/`.
