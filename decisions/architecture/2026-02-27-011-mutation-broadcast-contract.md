---
status: accepted
date: 2026-02-27
---
# Mutation broadcast contract

## Context and Problem Statement

The UI needs to stay in sync with entity changes in real time. When entities are created, updated, or destroyed, the channel must push the updated state to connected clients. Without a consistent broadcast contract, some mutations could silently fail to notify the UI, leaving it stale.

## Decision Outcome

Chosen option: "all mutations broadcast `{:entities_changed, entity_ids}` to `\"library:updates\"`", because a single, uniform event type simplifies both the broadcaster and the channel handler.

**Contract rules:**
- Every operation that creates, updates, or destroys entities must broadcast `{:entities_changed, entity_ids}`
- Entity IDs must be collected before deletion (they are gone afterward)
- The channel handler resolves IDs into updated/removed sets — the broadcaster does not need to distinguish between create, update, and destroy
- All entity pushes to the channel must be chunked by `@batch_size` — bulk operations can touch every entity
- Bulk operations must pass `return_errors?: true` and check `error_count` — silent failures stall the UI

### Consequences

* Good, because one event type handles all mutation kinds — no separate create/update/destroy events to maintain
* Good, because the channel handler owns the resolution logic — it queries current state and determines what changed
* Good, because batching prevents WebSocket overload during bulk operations (e.g., full library rescan)
* Bad, because broadcasting IDs without distinguishing mutation type means the channel must always query the database to determine what happened
