---
status: accepted
date: 2026-09-27
---
# A person is read through `Social.Person`; RelaySync owns the reconciliation loop

Design: `docs/superpowers/specs/2026-09-27-profiles-design.md`. Extends ADR-029 (context boundaries) to the social layer.

## Context and Problem Statement

A person's name was represented five ways: the roster's required `nickname`; a pubkey-to-nickname map joined onto every activity row in three Activities functions, with a nil nickname standing for a former friend; the literal `"You"` written into `FeedEntry.author`; a web `Person` struct copying five fields from `Friend`; and the pennant collecting nicknames and appending, then special-casing, the literal. A published profile (ADR-073) adds a second source for the name and a first for the avatar, and every one of those five sites would need the same fallback chain.

The sync loop, `Activities.Sync`, takes its kinds from `Activities.Translation`, a title-shaped module. A profile has no title and no address, and Social cannot depend on Activities, so neither context can own a loop that reconciles both contexts' rows.

## Decision Outcome

Chosen option: one read model, one loop above both contexts.

- **`Social.Person`** is a key as this reader sees it: the resolved name (the reader's override, else the published name, else nil), the resolved avatar URL (nil when none, hidden, or the file is missing), the own flag, the short npub, the added date. `Social.people/0` builds the map for the identity and the roster. Activities keeps the enriched-list join it owns and puts a Person on each row as `author`; every web surface takes a Person. "You" and "Unnamed" are rendering rules of the web layer keyed on the own flag and the nil name. The web `Components.Discovery.Person` is retired; the card takes a Person and their acts.
- **`MediaCentaur.RelaySync`** is a Boundary with deps `Activities`, `Social`, `Nostr`, holding the moved loop. Its kinds are the two contexts' lists concatenated, its ingest dispatches by kind, and its own-events diff publishes both contexts' own events. Activities is then content only. `Social.Profile.Translation` is a pure module beside `Activities.Translation`, which stays title-shaped.
- **Roster events say what happened.** `FriendAdded` means added; `FriendChanged` carries an override or switch change; `ProfileUpdated` carries an ingested or saved profile.

### Consequences

* Good, because a person is represented once and the fallback chain exists in one function.
* Good, because a former friend is decided by roster membership in Activities, not by a nil name downstream.
* Good, because the context named for content no longer carries the transport loop.
* Bad, because a fifth social context exists for one GenServer and its tests.
* Bad, because three component contracts and their stories, and five stories that build activity rows, are rewritten in the same change (MC0009).
