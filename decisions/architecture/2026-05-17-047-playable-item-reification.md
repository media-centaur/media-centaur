---
status: accepted
date: 2026-05-17
---
# PlayableItem is the canonical leaf of the Library schema

## Context and Problem Statement

Before Schema v2 the supporting tables (`WatchedFile`, `WatchProgress`, `Image`, `Extra`, `ExternalId`, subtitle metadata) each carried one nullable foreign key per container type, with "exactly one is set" enforced only in ad-hoc helpers. The same fact lived in several places (`tmdb_id` on every container and on `ExternalId`; durations as ISO 8601 strings parsed on read), two cuts of one movie had no row to live on, and every projection had to know all container shapes.

## Decision Outcome

1. **`Library.PlayableItem` (table `library_playable_items`) is the unit Play is pressed on**: `container_type` (`:movie | :episode | :video_object`), `container_id`, `position`, `duration_seconds`, an optional `name` override; `has_many :watched_files`, `has_one :watch_progress`.
2. **Supporting tables key on the leaf.** `WatchedFile` and `WatchProgress` carry a single `playable_item_id`; subtitle tracks are their own table under the watched file.
3. **Polymorphic owners use one discriminator.** `Image` and `Extra` reference `(owner_type, owner_id)`; the `(owner_type, owner_id, role)` tuple is unique for images.
4. **One home per fact.** External ids live only in `ExternalId`, the content path only on `WatchedFile`, duration only as `duration_seconds`. Containers hold metadata only.
5. **Fields are typed end to end**: dates as `:date`, durations as integers, cast and crew as embedded `Library.Person` schemas.

[ADR-059](2026-07-12-059-cuts-vs-renditions.md) assigns semantics to the two shapes this leaves open: a second `PlayableItem` on one container is a cut, a second `WatchedFile` on one item is a rendition. `docs/library.md` is the living description of the schema.

### Consequences

* The polymorphic tables have no database-level foreign key; integrity rests on the Library write paths.
* Every Library projection fans out from `playable_item_id`, so a new container type is a new enum value, not a new set of nullable columns.
