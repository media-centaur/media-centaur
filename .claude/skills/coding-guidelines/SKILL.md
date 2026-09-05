---
name: coding-guidelines
description: "Use this skill for any implementation task — adding features, fixing bugs, modifying resources, changing pipeline stages, or updating channels. Always consult this before writing code."
---

## Workflow

1. **Write tests first.** The test is the executable specification. If you can't write the test, the requirements aren't clear enough — stop and clarify before writing any implementation code. Load the `automated-testing` skill for patterns and policies.
2. **Implement the minimum change** to make the tests pass.
3. **Run `mix precommit`** before finishing. Fix all warnings and failures — zero warnings policy.

## Modular Cohesion

Before adding a function, handler, or piece of state to an existing
module, **read the moduledoc**. If it already names more than one
responsibility — look for "and" between concerns, numbered lists like
"Two responsibilities:", or `# ---` section dividers separating
distinct domains — that's a smell, and the new code is the cheapest
moment to fix it. Split the module into collaborators *as part of the
change*, not as follow-up work.

The split rule:

- Each module's `@moduledoc` names **one** thing it owns.
- Relationships are **one-way**: the consumer module names the
  data-source module in its moduledoc; the data-source module says
  nothing about the consumer.
- Tests live next to the module they describe. Integration tests
  assert the *contract* between modules, never the internals (per
  ADR-026).

**Canonical examples in this repo:**

| Consumer | Data source | Pattern |
|---|---|---|
| `MediaCentaur.Library.AbsenceSweeper` | `MediaCentaur.Library.FilePresence` | The TTL purge reads presence-tracking primitives. |
| `MediaCentaur.Library.Availability` | `MediaCentaur.WatcherStatus` | Library reads watcher state through a boundary-neutral helper. |

When in doubt: write the moduledoc you'd want to see for the new code
*first*. If you can't fit it in one short sentence, the work belongs
in (or as) a separate module.

## Lookup Naming Contract

A lookup's name announces what it returns, so a call site can be written
without opening the module:

| Name | Returns |
|---|---|
| `fetch…` | `{:ok, record} \| {:error, :not_found}` |
| `get…` | the record, or `nil` |
| `…!` | the record, or raises |

Enforced by **MC0022**, which only opines where the return shape is
statically determinable — a tail call to `Repo.get/get_by/one`, `Map.get`
or `Enum.find`, or a `case` with both `{:ok, _}` and `{:error, _}` branches.
HTTP clients, GenServer readers, and cache-then-database reads named `get_*`
are deliberately left alone; the contract is about repository-style lookups.

## Event Publication (ADR-060)

Two seams, and the inner one is usually the right target:

| Reach for | When |
|---|---|
| `Context.Events.broadcast/1` | the topic has a chokepoint — always prefer this |
| `Topics.publish/2` | inside the owning context, for a topic with no chokepoint yet |
| `Topics.subscribe/1` | subscribing where no `subscribe/0` facade exists |
| `Phoenix.PubSub.*` | never — **MC0025** flags it outside `topics.ex` |

**A topic with a closed message set gets an `Events` module** in its owning
context: one `events.ex`, a nested struct per message with `@enforce_keys`,
and one `broadcast/1` whose heads enumerate the set. `Library.Events`,
`Playback.Events` and `Review.Events` are the worked examples — pinned by
MC0013, MC0012 and MC0026.

This is **not** the `Acquisition.Pursuits.Events` shape. Its 20 files buy
database persistence and cold replay, not payload typing; don't generalise
`Define` to events that are only broadcast.

New topics start typed. Existing bare-tuple topics convert **when you are
already changing the context** — never in a sweep. Convert positional
tuples first: `{:group_error, key, message}` lets a publisher swap two
same-typed arguments with nothing to catch it.

Exporting matters: subscribers pattern-match the structs, so the owning
context's `use Boundary` must `exports:` them — a typed payload turns an
implicit runtime coupling into a declared one.

## Testing

The test policy lives in one place — the `automated-testing` skill: test-first
for bug fixes and features, the factory (`MediaCentaur.TestFactory`, never
inline `Repo` writes — MC0023), `TmdbStubs` / `Req.Test` for every outbound
client, page smoke tests per route, ADR-030 LiveView logic extraction, and
what is never tested. Load it before writing a test; do not restate it here.
