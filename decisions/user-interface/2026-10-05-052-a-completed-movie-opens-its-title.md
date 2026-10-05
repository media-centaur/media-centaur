---
status: proposed
date: 2026-10-05
amended: 2026-10-05
---
# A completed movie opens its title

> **Amendment 2026-10-05 (plan 006).** The prompt extends past standalone
> movies. A **collection movie** is finished as a movie: the collection's
> detail opens on that member, Review targets the movie, and Delete removes
> only that movie's files, never the collection. A **series** prompts when
> the session completed TMDB's latest aired episode (`last_episode_to_air`),
> not the last episode the library holds, because the library holds only
> seasons with files. A settled series (Ended or Canceled, nothing ahead)
> reads "You finished" with Review, Delete, Done; a series still airing reads
> "You're caught up" with Review, Track release dates, Done. The rule is
> judged in the web layer, where Playback's completed items and the TMDB
> record are both readable. The preference becomes *Ask after finishing a
> title* (`finish_prompt`). The consequence below excluding collections no
> longer holds.

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
