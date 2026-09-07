---
status: accepted
date: 2026-09-07
---
# An empty surface states the diagnosed reason it is empty, and the one action that changes it

## Context and Problem Statement

A first-run review against a genuinely empty instance — no config, no media,
no history — found the app repeatedly asserting a world it had not diagnosed.

* **Home** read "Nothing is here yet because no media directory has been
  scanned" whatever the truth was, and offered "Add a media directory" →
  Settings. With a directory already configured, both the cause and the action
  were wrong — and that is the state every user is in the instant the setup
  tour finishes.
* **Incoming** answered every search on a keyless install with "Nothing found
  on TMDB." That reads as *that title does not exist*, when the search never
  ran. It also contradicted the guide's own promise that features gate on
  capabilities so the reader "won't land on a dead end".
* **Status** showed all ten subsystems green with "No issues", because the
  board reads only `ErrorReports` rollups: nothing had errored because nothing
  had run. The Metadata drill-in managed to print "TMDB — not configured" in
  red and "● Healthy" inside one panel.
* **History** stacked three zeroed stat tiles, an empty 52-week heatmap and a
  filter for nothing above an empty state that already said the place was
  empty.

Underneath the copy sat a second problem: four unrelated empty-state dialects
(centered hero with a CTA; a bare sentence; a sentence in an inset band with no
action; a circled tick with no action), with Review's two tabs disagreeing with
each other. Nothing forced a page to decide *why* it was empty before writing a
sentence about it, so each page guessed, and each guessed differently.

This is the same failure [UIDR-022](2026-08-11-022-gap-banner-states-diagnosed-world.md)
named for the plan board's gap banner. That decision fixed one banner; the
stance was never generalised.

## Decision Outcome

Chosen option: **generalise UIDR-022 to every empty surface** — a page
diagnoses the reason in a pure function, then renders the matching copy and the
one action that changes it, through a single shared treatment.

Three parts:

1. **Diagnosis is a pure function, not a template conditional.** Each surface
   that can be empty for more than one reason answers *why* first —
   `HomeLive.Logic.empty_reason/1`, `LibraryHelpers.empty_grid_reason/2`,
   `WatchHistoryLive.empty_reason/1` — unit-tested with no DB and no render
   ([ADR-030](../architecture/2026-04-02-030-liveview-logic-extraction.md)). A
   surface may not state a cause it cannot compute.

2. **One treatment.** `CoreComponents.empty_state/1` — icon, headline naming
   what fills the place, body carrying the consequence, and an `action` slot
   (two buttons is the ceiling). It is to empty surfaces what `page_header/1`
   is to page titles. Copy never says "nothing here yet": the empty screen
   already shows that ([`writing-copy`](../../.claude/skills/writing-copy/SKILL.md)).

3. **Health has a third state.** `SubsystemView.state` gains `:dormant` for a
   subsystem whose prerequisite is unconfigured — neutral dot, "Not
   configured", and `HealthBoard.dormant_remedy/1` for the one action that
   starts it. Green becomes an assertion (configured and running), not a
   default. A real error still outranks dormancy: a subsystem that failed
   reports the failure, configured or not. `HealthBoard` stays pure — the
   caller supplies the capability flags.

The corollary is that a capability gap is a diagnosis like any other. A surface
whose whole content comes from an integration says so before the reader acts,
in the shape that page already uses for capability gaps.

### Consequences

* Good, because the four dialects collapse to one, and a new empty surface
  inherits the treatment rather than inventing a fifth.
* Good, because Status stops reassuring a reader whose install cannot do
  anything, which is the single most misleading thing a fresh instance did.
* Good, because the reason functions are unit-testable, so "which world is
  this" is covered without rendering.
* Good, because each empty state now carries the action that resolves it, so
  the reader is never told a place is empty and left to work out why.
* Bad, because a page with several reasons renders several `empty_state` calls
  guarded by the reason, which is more template than one unconditional block.
* Bad, because dormancy needs a per-subsystem prerequisite mapping that a new
  configurable subsystem has to be added to; forgetting it means the subsystem
  reads green while unconfigured — the exact bug this decision fixes.
