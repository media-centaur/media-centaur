---
status: accepted
date: 2026-02-20
---
# Stable entity UUIDs and one-image-per-role storage

## Context and Problem Statement

Entities need stable identity for cross-references between the backend and UI, for image directory naming, and for PubSub event correlation. Images need a storage convention that is simple, predictable, and avoids duplication.

## Decision Outcome

Chosen option: "UUID v4 as permanent entity identity, UUID-keyed image directories with one file per role", because these two decisions are interdependent — the UUID doubles as the image directory name, making identity stability a prerequisite for reliable image paths.

**Identity rules:**
- An entity's `@id` is a UUID v4 assigned once at creation and never changed
- The UUID is the sole key for image directories, PubSub events, and channel references
- Never reassign or reuse a UUID

**Image storage rules:**
- Each entity's images live under `data/images/{entity-@id}/`
- One high-quality file per role: `poster.jpg`, `backdrop.jpg`, `logo.png`, `thumb.jpg`
- Never store multiple resolutions — the UI renders via Vulkan and GPU texture scaling is free
- The `Image` resource has a unique constraint on `(entity_id, role)` enforced at the database level

### Consequences

* Good, because image paths are fully deterministic from entity ID and role — no lookup needed
* Good, because one-image-per-role eliminates resolution management, cache invalidation, and storage bloat
* Good, because UUID stability means external references (UI bookmarks, PubSub events) never break
* Bad, because if an entity is accidentally created with a wrong UUID, it cannot be corrected — the entity must be destroyed and recreated
