---
status: accepted
date: 2026-11-06
---
# Only a person's act is shared

## Context and Problem Statement

An activity — a review, a title watched, a listing — is a statement this install's identity makes to its friends about something the person did. `Activities.Publisher` derived the watched and listing activities from domain events: every `RungChanged` crossing onto List, and every completed watch, was read as the person's act.

On 2026-11-05 a one-off repair on the owner's own install moved seven series onto Follow through the Watchlist context. Each write broadcast `RungChanged`; the publisher shared seven listings to the owner's friends in one second. Nothing in the event said that no person had acted, so nothing could tell a repair from a press of the bookmark. Any future write through those contexts — a sweep, a job, a seed, a backfill, an import — would have done the same, and a statement on the relays cannot be taken back.

The line this draws is narrow. Most effects of a write follow the state, whoever made it: a title at Follow gets its calendar and its wants, a title at Grab is downloaded, a view refreshes. Those are right after a repair too. Only an effect that **reports an act** — tells other people what the person just did — is false when no person acted.

## Decision Outcome

Chosen option: "an actor is the proof that a person acted, and only the edges can make one", because it puts the check at the one place an activity leaves the install and makes forgetting it fail closed.

1. **`Profiles.Actor`** is the profile that acted. It is made with `Actor.new/1` only where a person is present: the web layer, from the session's profile (`ProfileAware.actor/1`), and playback, from the profile playing. Credo MC0044 (`ActorAtTheEdge`) refuses `Actor.new/1` anywhere else, and refuses a struct literal with fields, an update or `struct/2` on the module everywhere but the module itself.
2. **The sending door takes an actor and nothing else.** `Activities.review/4`, `watched/3` and `listing/2` require an `%Actor{}`; they are the only way an activity of this identity is signed and sent. A new kind of activity is a new function on that door, so it cannot be written without an actor.
3. **Writes that can be shared state who acted.** `ReleaseTracking.set_rung/4`, `Watchlist.put_rung/4` and `forget/3`, and `Library.ProgressRecords.mark_completed/2` take the actor or `nil` as an explicit argument, so every caller decides. `RungChanged.actor` (an enforced key) and `{:watch_event_created, event, actor}` carry it to the publisher, which shares only for an `%Actor{}` and passes it on.
4. **Withdrawing follows the state.** A listing whose title drops below List is withdrawn whoever dropped it; a statement that is no longer true comes down.
5. **The actor is not the owner.** A watch-progress row's `profile_id` says whose viewing it is; the actor says a person did it just now. The actor is not stored.

A repair or a migration passes `nil` — a data migration writes raw SQL and broadcasts nothing at all (ADR-040). An `iex` or eval session on a running node is outside Credo's reach; there the rule is the operator's: a repair never builds an actor.

### Consequences

* Good, because a write the system makes can never post, and a forgotten actor on a new UI path fails closed — nothing is shared — rather than open.
* Good, because the acting profile has one representation: it replaced `set_rung`'s optional `:profile_id` attr, which already meant the profile acting.
* Bad, because every caller of the four writes, tests included, names an actor or `nil`, and the `watch_history:events` message grew a third element its subscribers match.
