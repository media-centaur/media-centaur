---
status: accepted
date: 2026-08-06
---
# Events publish through a per-topic `Events` chokepoint, over a `Topics` transport

## Context and Problem Statement

Two event-publication idioms coexist repo-wide, and nothing decides
between them.

* **Typed structs behind an `Events` module** — four contexts:
  `library/events.ex`, `library/progress/events.ex`, `playback/events.ex`,
  `acquisition/pursuits/events.ex`. Each defines structs with
  `@enforce_keys` and routes every message through one `broadcast/1`.
  Two Credo checks (MC0012, MC0013) already pin two of them.
* **Bare inline tuples** — roughly 48 other modules broadcast directly,
  with no struct, no `@type`, and no single place to discover what a
  topic carries.

Measured on `main`, 2026-08-06 (each figure re-run at decision time):

| Fact | Command | Value |
|---|---|---|
| `MediaCentaur.PubSub` as a literal in `lib/` | `grep -rho 'MediaCentaur\.PubSub' lib/ --include='*.ex' \| wc -l` | 134 |
| …spread across | `grep -rl 'MediaCentaur\.PubSub' lib/ --include='*.ex' \| wc -l` | 73 files |
| `Phoenix.PubSub.broadcast` call sites | `grep -rn 'Phoenix.PubSub.broadcast' lib/ --include='*.ex' \| wc -l` | 69 |
| `Phoenix.PubSub.subscribe` call sites | `grep -rn 'Phoenix.PubSub.subscribe' lib/ --include='*.ex' \| wc -l` | 66 |

The cost of the typed idiom has been consistently overstated, because
`Pursuits` is read as representative of it. It is not. `Pursuits` spends
20 files in one directory — 18 one-struct modules plus `define.ex` and
`event_behaviour.ex` — because pursuit events are **persisted**: the
macro generates `to_payload/1` and `from_payload/1` for a JSONB column so
a pursuit can be replayed cold from the database. That ceremony buys
event sourcing, not payload typing.

The idiom as `Library` and `Playback` actually practise it is **one file
per topic**: nested struct modules inside a single `events.ex`, plus a
`broadcast/1` whose function heads enumerate the topic's closed message
set. The migration unit is one file, not twenty.

Separately, every publisher and subscriber names the PubSub server by
hand. `MediaCentaur.PubSub` appears 134 times across 73 files purely as
transport plumbing that no caller has an opinion about.

## Decision Outcome

Chosen option: **typed structs are the target, in the `Library`/`Playback`
shape, published over a `Topics` transport seam** — because the
`@enforce_keys` guarantee is what stops the payload-mismatch bug class
(`Playback.Events`' moduledoc names two shipped instances, v0.31.0 and
v0.31.1), and because at one file per topic that guarantee is cheap
enough to be the default rather than a special case.

Three parts:

1. **A topic with a closed message set gets an `Events` module.** One
   `events.ex` per owning context, containing a nested struct per message
   with `@enforce_keys`, and a single `broadcast/1` whose heads
   pattern-match those structs. Subscribers keep map-matching — a struct
   *is* a map, so `%{entity_id: id}` still destructures.

2. **The `Pursuits` shape is not the idiom, and does not spread.**
   One-struct-per-file plus a `Define` macro is the price of
   *persistence*. A topic whose events are only broadcast, never stored,
   uses nested structs in one file. Do not generalise `Define` to
   non-persisted events.

3. **`Topics` owns the transport.** `Topics.publish/2`,
   `Topics.subscribe/1` and `Topics.unsubscribe/1` wrap `Phoenix.PubSub`,
   so no other module names `MediaCentaur.PubSub`. Topic *names* stay
   zero-arity functions rather than atoms — a misspelt `Topics.review_updates()`
   is a compile error, which is the module's whole reason to exist; a
   misspelt `:review_updates` atom is a silent missed subscription.

**Migration is per-context, on next touch — never a sweep.** The audit
that triggered this ADR found the repo's characteristic defect is the
refactor that starts well and stops at 80%. A single pass across 52
broadcasting modules is that defect. A context converts when someone is
already changing it, and `Review` is the worked example to copy.

Positional tuples are the shape to convert first when a context comes up:
`{:group_error, key, message}` gives a subscriber no way to notice a
reordered argument, and it is exactly the failure the structs prevent.

### Consequences

* Good, because the guarantee that fixed two shipped bugs becomes the
  default for new topics instead of a four-context exception.
* Good, because a topic's message set becomes discoverable in one file —
  the `broadcast/1` heads *are* the contract, and adding a variant is a
  reviewable edit to one module.
* Good, because 134 transport literals collapse to one seam, and the
  PubSub server name stops being copied by hand into every new module.
* Good, because the rule is enforceable per topic by the MC0012/MC0013
  pattern rather than by prose, and the transport seam is enforceable
  outright (MC0025).
* Bad, because the repo carries both idioms for as long as migration
  takes, and "on next touch" has no completion date by construction. The
  ADR is the tiebreaker for which one a given change moves toward; it is
  not a promise that the other disappears.
* Bad, because converting a positional-tuple payload is a breaking change
  for its subscribers — every `handle_info` head on that topic changes in
  the same commit. This is why the unit is one context.
* Neutral, because `Pursuits` keeps its 20 files. They are justified by
  persistence, and this ADR neither expands nor unwinds them.

## Verification

* `MediaCentaur.Credo.Checks.PubSubTransport` (MC0025) fails any
  `Phoenix.PubSub.broadcast/subscribe/unsubscribe` call outside
  `lib/media_centaur/topics.ex`. This is the runnable form of "134 → 0";
  note that `MediaCentaur.PubSub` itself legitimately survives in
  `application.ex`, which starts the server, so a raw grep for the literal
  correctly reports 1 rather than 0.
* `Review.Events` is on `main` as the worked example: four message
  structs, one `broadcast/1`, subscribers converted, MC0026 pinning the
  chokepoint.
