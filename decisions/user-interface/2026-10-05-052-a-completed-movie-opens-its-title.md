---
status: proposed
date: 2026-10-05
---
# A completed movie opens its title

## Context and Problem Statement

When a movie ends, the natural next acts are reviewing it or deleting it.
Both live on the title detail modal (UIDR-043). Three places could offer
them at that moment: an overlay inside mpv, a dedicated after-viewing
dialog in the app, or the detail modal itself. Play in place (plan 003)
promised that leaving playback returns the person to the page exactly as
they left it.

## Decision Outcome

Chosen option: "the detail modal opens on the finished movie with a finish
prompt (Review, Delete, Done) at its top", because Review and Delete are
the title's own actions and already have one owner, `TitleDetailHost`. An
mpv overlay cannot take review text and would need a new mpv → app
channel for Delete. A dedicated dialog would need a second copy of the
review opening, the delete arm and the delete protection.

It applies when a standalone movie completes during the session and mpv
closes, and only with the preference on (default on). If the modal is
already open on that movie, it keeps its view and gains the prompt. If
another title's modal is open, the finished movie takes it. The prompt is
transient modal state, not part of the URL.

### Consequences

* Good, because there is one surface for a title's actions, whichever way
  the person arrives at it.
* Good, because Delete keeps its single confirmation step and the guard
  against deleting a playing title.
* Bad, because play in place no longer always returns the page as it was:
  after a completed movie, with the preference on, the title's modal is
  open.
* Bad, because movies in a collection are excluded for now: they play
  under the collection's entity, where the primary delete removes the
  whole collection.
