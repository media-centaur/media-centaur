---
status: accepted
date: 2026-09-07
---
# An empty surface states the diagnosed reason it is empty, and the one action that changes it

## Context and Problem Statement

On an empty instance the app asserted worlds it had not diagnosed: Home blamed a missing media directory whatever the truth, Incoming answered a keyless search with "Nothing found on TMDB", Status showed ten green subsystems because nothing had run. Four empty-state dialects existed because nothing forced a page to decide why it was empty before writing about it. UIDR-022 fixed one banner; this generalises it.

## Decision Outcome

1. **Diagnosis is a pure function.** A surface that can be empty for more than one reason answers why first (`HomeLive.Logic.empty_reason/1`, `LibraryHelpers.empty_grid_reason/2`, `WatchHistoryLive.empty_reason/1`), unit-tested without a DB or render (ADR-030). A surface may not state a cause it cannot compute.
2. **One treatment.** `CoreComponents.empty_state/1`: icon, headline naming what fills the place, body carrying the consequence, an `action` slot (two buttons is the ceiling). Copy never says "nothing here yet".
3. **Health has a third state.** `SubsystemView.state` gains `:dormant` for a subsystem whose prerequisite is unconfigured: neutral dot, "Not configured", and `HealthBoard.dormant_remedy/1` for the one action that starts it. Green is an assertion, not a default; a real error outranks dormancy.

A capability gap is a diagnosis like any other: a surface fed by an integration says so before the reader acts.

### Consequences

* A new configurable subsystem left out of the dormancy prerequisite mapping reads green while unconfigured, the bug this decision fixes.
