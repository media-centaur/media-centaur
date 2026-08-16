---
status: accepted
date: 2026-08-16
---
# Release quality: gates bound, ladders order, a profile chooses — size is never a signal

## Context and Problem Statement

Within a resolution tier the release picker had no opinion: quality ranking
knew only 4K vs 1080p, and the seeder tiebreak is permanently `nil` on
indexers that don't report it, so within-tier auto-picks degraded to indexer
list order. Candidate fixes each had a flaw: file size as a quality proxy is
confounded (audio tracks, subtitle bundles bloat size without video quality);
a numeric size budget demands release-landscape expertise and a painful
tune-and-rerun loop; a per-dimension scoring language (the Radarr
custom-format model) is a configuration rabbit hole.

## Decision Outcome

Chosen option: "fixed source-fidelity ladders selected by one semantic
profile", because the release title's source tokens (remux / WEB-DL / encode)
are the only honest within-tier signal, and "do you want the best-looking
file or the smaller file?" is a question every user can answer without
knowing the corpus.

The invariant:

* **Gates express bounds and safety** — quality floor/ceiling, red flags.
  They may exclude.
* **Ladders express preference** — resolution first, then source, then
  seeders. They only order, never exclude.
* **The profile picks the ladder** — `fidelity` (remux > WEB-DL > BluRay
  encode > WEBRip/HDTV, the default) or `space` (BluRay encode > WEB-DL >
  WEBRip/HDTV > remux). Both ladders are hardcoded; the setting selects one
  and never composes them.
* **Size is never a ranking signal and never a gate.** It stays where it
  was: red-flag sanity checks only.

WEB-DL outranks BluRay encode on the fidelity ladder: an encode spans
everything from HQ to starved, and with size rejected as a signal the two
are indistinguishable — predictable-good beats variance.

### Consequences

* Good, because within-tier picks become deterministic and legible, on
  indexers with or without seeder data.
* Good, because nothing can go unfound due to preference — remux-only titles
  are still covered under `space`.
* Good, because storage-constrained users get one self-describing dropdown
  instead of a numeric footgun.
* Bad, because taste beyond the two ladders (codec, HDR, audio, release
  group) is not expressible — deliberately deferred until a real need
  appears.
* Bad, because source classification is title-token parsing and inherits its
  false-negative tail (bare `WEB` stays unclassified and ranks bottom).
