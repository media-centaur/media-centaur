# Plan Board Diagnosis

## Problem Statement

A plan for a show that exists only below the user's quality preference
(a pre-HD sitcom under a 1080p default) reported its episodes as
unfindable, narrated internal ladder arithmetic as its headline, hid
below-preference availability entirely for TV, and offered no honest
way to stop a running search. The user could not tell "the world has
nothing" from "the app declined what the world offered", and could not
act on either.

## Design Objectives

- The board narrates a **diagnosis** — what the world offers per
  episode against the user's terms — never the search procedure.
- Every terminal state answers "what would a reasonable person do
  next" with the action attached to its evidence.
- Every number shown is provable from stored evidence and reconciles.
- One model behind three renderings (verdict, grid, outcome rows) so
  the surfaces cannot contradict each other.
- Quality preferences stay bounds (ADR-061), resolved per title;
  accepting less for one show never touches the global setting.

## User-Facing Behavior

- **Searching**: the verdict slot narrates progress in one live
  sentence; grid cells fill in as results land; outcome rows show "so
  far" counts; no decision buttons yet. Footer offers **Stop
  searching** — one press, no confirmation, effective within one
  search, settling the board with what is known.
- **Finished**: a plain verdict sentence leads ("Murphy Brown exists
  almost entirely in SD. One episode was found in 1080p; the other 21
  are available only in SD."). The enlarged episode grid shows each
  episode's outcome; focus/hover captions its best release. Outcome
  rows total the grid; the below-preference row carries **Take SD for
  this show** with quiet *Show them* (best release per episode) and
  the scope note "This show only; your 1080p preference is unchanged."
  Kept releases list as today. A single receipts footnote (searches ·
  indexers · freshness · results, reconciling) ends the body, with a
  collapsed "How we searched" disclosure holding the rung narrative.
  Discard keeps its confirmation here.
- **After acceptance**: header meta gains "SD accepted for this show";
  the row flips to accepted with Undo; Approve covers all queued
  releases. The acceptance is the title's own quality preference —
  visible and resettable in Manage, honored by later seasons and
  re-plans without re-asking.
- Genuinely-nothing episodes read differently from below-preference
  episodes; a zero-count outcome renders no row.
- Final copy passes through the writing-copy house voice; "floor"
  never appears in user copy.

## Acceptance Criteria

- [ ] A finished plan whose gaps are below-preference states that
      above the fold — never "couldn't be found" while releases exist
- [ ] Verdict copy comes from a closed set of count-proven worlds;
      no inferred causes
- [ ] The receipts line reconciles: results in = kept + below
      preference + rejected + out of scope
- [ ] TV counts below-preference availability per episode (movie parity)
- [ ] One press of Take SD grabs best-available for the gap episodes
      and persists per title; global preference untouched; reversible
      in Manage
- [ ] Stop searching: one press mid-search, no further indexer
      requests after one in-flight search, board settles immediately —
      never a stuck spinner
- [ ] Discarding a ready plan keeps its confirmation
- [ ] Grid cells are keyboard/gamepad focusable within the modal's
      two-region nav (UIDR-019); searching state shows no premature
      actions
- [ ] Verdict, grid, and rows never disagree (single outcome model)

## Anti-patterns

- **Rung-arithmetic headlines** — "covered 1 — 21 still missing" is
  procedure, not diagnosis.
- **Banner stacking** — evidence scattered across appended rows.
- **Cancel-as-status-flip** — a stop control that changes a label
  while searches continue.
- **Era inference** — never auto-relax quality from air dates; the
  acceptance button is the user saying it.
- **Console look, chips, accent bars, duplicate CTAs** — house rules.

## Deferred

- Auto-upgrade when higher quality appears after acceptance (no
  upgrade machinery exists; acceptance promises none).
- Incoming-page row summary refresh.
- Per-episode rejected-candidate diagnosis for TV (aggregate stays;
  named convergence in ADR-063).

## Decisions

See `decisions/user-interface/2026-08-31-029-plan-board-diagnosis.md`
(board) and
`decisions/architecture/2026-08-31-063-plan-diagnosis-model.md`
(outcome model, per-title bounds, cancellation). Reference mockups:
`docs/plans/plan-board-diagnosis-mockups/` (direction 3 chassis +
direction 2 verdict).
