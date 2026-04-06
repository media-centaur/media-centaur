---
status: accepted
date: 2026-04-06
---
# Name modules by domain purpose, not design pattern

## Context and Problem Statement

As the module tree grows, many modules get named after the design pattern they implement — Processor, Handler, Worker, Mapper, Resolver, Builder — rather than what they do in the domain. A reader scanning the module tree needs to already understand the underlying patterns before the names communicate anything. The codebase should be self-narrating: a new reader should understand the business process from module names alone, without architecture knowledge.

This extends ADR-019 (human-readable names, domain-driven structure). ADR-019 established that variables should be named for what the value *is* and modules should be organized by domain context. This decision takes the next step: within each context, individual modules should be named for what they *do*, not what pattern they *are*.

## Decision Outcome

Chosen option: "domain-purpose naming", because module names should describe what happens in the domain, not how the system is built.

**Context names** describe the domain purpose of the bounded context — what the context *does*, not what it *contains*.

**Internal module names** read as actions or domain descriptions:
- Name the module for what it does: `ExtractMetadata` not `MetadataProcessor`
- Name integrations for the external system: `Tmdb` not `TmdbImporter`
- Name jobs for what they accomplish: `PeriodicallyRefreshMetadata` not `MetadataRefreshWorker`

**What stays unchanged:**
- Table names are stable database identifiers — they don't change
- PubSub topic strings are stable wire identifiers — they don't change
- Data structs that describe what they *are* rather than a pattern (Entry, Filter, etc.)

**The test:** when naming a module, ask "what does this do?" not "what pattern is this?" If the name only makes sense to someone who knows the pattern, rename it.

### Consequences

* Good, because new contributors can read the module tree and understand the business process without architecture knowledge
* Good, because module names become greppable by domain concept
* Good, because pattern knowledge is still useful for understanding *how* a module works, but is no longer required to understand *what* it does
* Bad, because some names are longer than their pattern equivalents — acceptable trade-off for clarity
* Bad, because existing ADRs and documentation must be updated when renaming — a one-time cost
