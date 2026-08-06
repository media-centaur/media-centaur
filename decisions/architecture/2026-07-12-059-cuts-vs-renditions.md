---
status: accepted
date: 2026-07-12
---
# Versions split into cuts (PlayableItem) and renditions (WatchedFile)

## Context and Problem Statement

Users want multiple versions of one movie or episode in the library —
an HDR and an SDR copy of the same film, a theatrical and a director's
cut. Today a second file for a known entity is silently appended as
another `WatchedFile` and playback picks an arbitrary insertion-order
copy (`populate_leaf_content_url/1` takes the unordered preload head,
while `playable_file_path/1` orders by `inserted_at` — two code paths
that can disagree). Nothing surfaces the extra file; the
`duplicate-episode-copies` campaign treated this shape purely as
accidental waste. "Version" needs a model before any pick policy,
acquisition affordance, or UI can be designed coherently.

## Decision Outcome

Chosen option: **two distinct concepts mapped onto the schema shapes
ADR-047 already reified**, because the user-meaningful difference is
whether the *content* differs or only the *encoding*:

* **Cut** — different content (theatrical vs director's cut, two-part
  edit): a second `PlayableItem` on the same container, labeled via the
  existing `name` override field. Each cut carries its **own**
  `WatchProgress` — minute 40 of one cut is not minute 40 of another.
* **Rendition** — same content, different encoding (HDR vs SDR, 2160p
  vs 1080p, remux vs web): a second `WatchedFile` on the **same**
  `PlayableItem`. Renditions **share** watch progress — start a film in
  HDR, resume the SDR copy at the same minute.

Playback pick: the highest-quality rendition plays by default
(deterministic ranking over rendition metadata); the user may override
by selecting an **active** version per playable item in the entity's
Manage modal. A persisted override beats the default; clearing it
returns to highest-quality. An unwanted duplicate is simply a rendition
the user deletes from the same surface — "duplicate" is a user
judgement, not a data shape.

Rendition metadata (resolution, dynamic range, codec, source, size) is
recomputable derived data per ADR-057 — derived from filename parse +
file probe, never hand-maintained.

### Consequences

* Good, because the schema needs no structural change — ADR-047
  anticipated both shapes; this ADR assigns them semantics.
* Good, because shared-progress renditions and per-cut progress fall
  out of the model instead of needing special cases.
* Good, because one policy covers intentional versions and accidental
  duplicates — no second half-policy for the same data shape.
* Bad, because import must now *classify* an incoming second file
  (rendition vs cut) — edition-marker parsing carries ambiguity and
  needs a review path when uncertain.
* Bad, because every playback-adjacent read path must honor one pick
  function; the two existing divergent paths must collapse to one.

## Pointers

* [ADR-047](2026-05-17-047-playable-item-reification.md) — the leaf
  schema this builds on.
* [ADR-057](2026-06-14-057-derived-data-is-recomputable.md) — rendition
  metadata as a deriver.
* Campaign: `campaigns/playable-item-versions.md` (removed on completion — see git history).
