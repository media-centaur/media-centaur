---
status: accepted
date: 2026-04-06
---
# Data has a TTL — delete over hide

## Context and Problem Statement

As the application grows, several features need a way to dismiss stale data — "now available" releases the user has already seen, old tracking events, completed releases. The instinct is to add a `hidden` or `dismissed` boolean flag, but this creates hidden data that accumulates silently, inflating tables, complicating queries (every query needs `where hidden == false`), and eventually requiring a separate cleanup pass to remove what should have been deleted in the first place.

## Decision Outcome

Chosen option: "Delete records when they've served their purpose", because data should exist only while it's useful.

**Principles:**

1. **Delete, don't flag.** When a user dismisses a record or it expires, delete it. Don't add `hidden`, `dismissed`, `archived`, or `soft_delete` columns. If the data might be needed for audit, log it before deletion — don't keep the row.

2. **Every table should have a TTL story.** For each table, be able to answer: "When does a row in this table stop being useful, and what removes it?" If the answer is "never" or "nothing", that's a design smell.

3. **Periodic cleanup as defense-in-depth.** Even with user-driven deletion, add periodic cleanup for records that age out naturally. Released tracking releases older than 30 days, events older than 90 days — these can be swept by the Refresher's periodic cycle.

4. **Cascade deletes handle the tree.** When a parent is deleted (e.g., a tracking Item), its children (releases, events) cascade automatically via the existing FK `on_delete: :delete_all`. No orphans.

**Application to release tracking:**

| Record | TTL trigger | Removal |
|--------|-------------|---------|
| Release (upcoming) | Becomes released, then dismissed or ages out | User dismiss or 30-day auto-cleanup |
| Release (released) | User dismisses via threshold on parent Item | Filtered by `dismiss_released_before` on Item |
| Event | 90 days | Periodic sweep |
| Item | User stops tracking | Explicit delete — cascades to all releases and events |

**Dismiss for released items:** When a user dismisses a "Now Available" release, delete the individual Release record. The Refresher may recreate it on its next cycle, but `mark_in_library_releases` will flag episodes the user already has (filtering them from the list). For movies, a recreated release would reappear — this is acceptable since it means TMDB still considers it relevant. The `dismiss_released_before` field on Item exists as a fallback for bulk suppression if needed.

### Consequences

* Good, because queries stay simple — one date comparison on the parent, not per-row flags
* Good, because table size stays bounded without manual intervention
* Good, because it forces explicit decisions about data lifecycle at design time
* Good, because stop-tracking is a full cleanup — zero residue
* Acceptable, because dismissed-release state lives on the Item (bounded, cascaded) not on individual Release records
