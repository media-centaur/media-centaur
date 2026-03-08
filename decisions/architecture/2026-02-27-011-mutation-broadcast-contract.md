---
status: accepted
date: 2026-02-27
---
# Mutation broadcast contract

## Context and Problem Statement

The UI needs to stay in sync with entity changes in real time. When entities are created, updated, or destroyed, subscribers must receive the updated state. Without a consistent broadcast contract, some mutations could silently fail to notify the UI, leaving it stale.

## Decision Outcome

Chosen option: "all mutations broadcast `{:entities_changed, entity_ids}` to `\"library:updates\"`", because a single, uniform event type simplifies both the broadcaster and the channel handler.

**Contract rules:**
- Every operation that creates, updates, or destroys entities must broadcast `{:entities_changed, entity_ids}`
- Entity IDs must be collected before deletion (they are gone afterward)
- PubSub subscribers resolve IDs into updated/removed sets — the broadcaster does not need to distinguish between create, update, and destroy
- Bulk operations must pass `return_errors?: true` and check `error_count` — silent failures stall the UI

### Consequences

* Good, because one event type handles all mutation kinds — no separate create/update/destroy events to maintain
* Good, because subscribers own the resolution logic — they query current state and determine what changed
* Bad, because broadcasting IDs without distinguishing mutation type means subscribers must always query the database to determine what happened
