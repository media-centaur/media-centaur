---
status: accepted
date: 2026-08-06
---
# Events publish through a per-topic `Events` chokepoint, over a `Topics` transport

## Context and Problem Statement

Two publication idioms coexisted: typed structs behind an `Events` module in
four contexts, and bare inline tuples in roughly fifty other modules, with
nothing deciding between them. Every publisher and subscriber also named
`MediaCentaur.PubSub` by hand. The typed idiom's cost was overstated because
`Pursuits` — twenty files, one struct per file — was read as representative;
that ceremony pays for persistence and replay, not payload typing.

## Decision Outcome

Typed structs are the target, in the one-file-per-topic shape, published
over a `Topics` transport seam. The `@enforce_keys` guarantee is what stops
the payload-mismatch bug class that shipped twice in `Playback`.

1. **A topic with a closed message set gets an `Events` module**: one
   `events.ex` per owning context, a nested struct per message with
   `@enforce_keys`, and a single `broadcast/1` whose heads pattern-match
   those structs. Subscribers keep map-matching; a struct is a map.
2. **The `Pursuits` shape does not spread.** One struct per file plus a
   `Define` macro is the price of persisted, replayable events. Topics whose
   events are only broadcast use nested structs in one file.
3. **`Topics` owns the transport.** `Topics.publish/2`, `subscribe/1` and
   `unsubscribe/1` wrap `Phoenix.PubSub`; no other module names
   `MediaCentaur.PubSub` (MC0025). Topic names stay zero-arity functions, so
   a misspelt topic is a compile error rather than a silent missed
   subscription.
4. **Migration is per context, on next touch — never a sweep.** A context
   converts when someone is already changing it; positional tuples convert
   first, since a reordered element is exactly the failure structs prevent.
   MC0012, MC0013 and MC0026 pin the chokepoints that exist.

### Consequences

* Both idioms coexist with no completion date by construction; this record
  is the tiebreaker for which way a change moves.
* Converting a positional-tuple payload changes every `handle_info` head on
  that topic in the same commit, which is why the unit is one context.
