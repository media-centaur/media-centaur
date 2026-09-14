---
status: accepted
date: 2026-08-16
amended: 2026-09-13
---
# Release quality: gates bound, ladders order, a profile chooses — size is never a signal

## Context and Problem Statement

Within a resolution tier the release picker had no opinion: ranking knew only
4K versus 1080p, and the seeder tiebreak is permanently `nil` on indexers
that do not report it, so within-tier picks fell to indexer list order. File
size as a proxy is confounded by audio and subtitle bundles; a numeric size
budget demands release-landscape expertise; a per-dimension scoring language
is a configuration rabbit hole.

## Decision Outcome

Fixed source-fidelity ladders selected by one semantic profile. The title's
source tokens (remux, WEB-DL, encode) are the only honest within-tier signal.

1. **Gates express bounds and safety** — the quality floor and ceiling, red
   flags. They may exclude.
2. **Ladders express preference** — resolution, then source, then seeders.
   They only order, never exclude.
3. **The profile picks the ladder** (`auto_grab.size_preference`):
   `fidelity` (remux > WEB-DL > BluRay encode > WEBRip/HDTV, the default) or
   `space` (BluRay encode > WEB-DL > WEBRip/HDTV > remux). Both ladders are
   hardcoded in `Search.Quality`; the setting selects one and never composes
   them. WEB-DL outranks BluRay encode on the fidelity ladder because an
   encode spans HQ to starved and, with size rejected, the two are
   indistinguishable.
4. **Size is never a ranking signal and never a gate.** It remains a
   red-flag sanity check only.
5. **Bounds resolve per title** (amended 2026-08-31,
   [ADR-063](2026-08-31-063-plan-diagnosis-model.md) §2): a title's
   acceptance of releases below the floor lives in
   `Acquisition.TitleDownloadParams`.
6. **The floor is fixed at 1080p and there is no patience window** (amended
   2026-09-13, UIDR-041 §6). The automatic policy is two choices: highest
   resolution and within-resolution preference. Below the floor a release is
   taken only under the per-title acceptance of rule 5.

### Consequences

* Taste beyond the two ladders — codec, HDR, audio, release group — is not
  expressible.
* Source classification is title-token parsing and inherits its
  false-negative tail; a bare `WEB` ranks bottom.
* A tracked episode grabbed at 1080p stays at 1080p when 4K lands later;
  nothing upgrades.
