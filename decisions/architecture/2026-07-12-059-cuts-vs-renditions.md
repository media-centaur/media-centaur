---
status: accepted
date: 2026-07-12
---
# Versions split into cuts (PlayableItem) and renditions (WatchedFile)

## Context and Problem Statement

Users want more than one version of a movie or episode — an HDR and an SDR
copy, a theatrical and a director's cut. A second file for a known entity is
silently appended as another `WatchedFile`, nothing surfaces it, and two
playback read paths pick a copy by different orderings. "Version" needs a
model before any pick policy, acquisition affordance or UI can be designed.

## Decision Outcome

Two concepts, mapped onto the shapes
[ADR-047](2026-05-17-047-playable-item-reification.md) already reified. The
user-meaningful difference is whether the content differs or only the
encoding.

1. **Cut** — different content (theatrical vs director's cut, a two-part
   edit): a second `PlayableItem` on the same container, labelled through the
   existing `name` override. Each cut has its own `WatchProgress`.
2. **Rendition** — same content, different encoding (HDR vs SDR, 2160p vs
   1080p, remux vs web): a second `WatchedFile` on the same `PlayableItem`.
   Renditions share watch progress.
3. **Pick policy.** The highest-quality rendition plays by default, by a
   deterministic ranking over rendition metadata. The user may select an
   active version per playable item in the entity's Manage view; a persisted
   override beats the default, and clearing it returns to highest quality. An
   unwanted duplicate is a rendition the user deletes from the same surface.
4. **Rendition metadata** (resolution, dynamic range, codec, source, size) is
   derived data per [ADR-057](2026-06-14-057-derived-data-is-recomputable.md):
   from filename parse plus file probe, never hand-maintained.

Implementation state: none of this is built. `lib/` contains no rendition
model, ranking or Manage control; the schema needs no change, and the
decision stands as the design for that work.

### Consequences

* Import must classify an incoming second file as rendition or cut;
  edition-marker parsing is ambiguous and needs a review path.
* Every playback-adjacent read path must honour one pick function; the two
  divergent paths collapse to it.
