---
status: proposed
date: 2026-09-27
---
# A profile is one replaceable event per identity

Design: `docs/superpowers/specs/2026-09-27-profiles-design.md`. Campaign: `campaigns/profiles.md`. Supersedes decision 6 of the 2026-09-02 friends design ("No profile events. Names are local.").

## Context and Problem Statement

The identity tile takes a picture (UIDR-046) and no event carries one. Friends learn about a person only through signed events on the relays they share; an install is not reachable from another, so a picture given as a URL to one's own server never loads for a friend, and Nostr's kind 0 `picture` field presumes public hosting. The owner asked for a required display name beside an optional picture, and proposed choosing a profile per relay.

## Decision Outcome

Chosen option: one profile per identity, as a replaceable event carrying the avatar bytes inline.

- **Kind 12160, replaceable**, the first kind in the app's 12160–12999 block: one record per signer, newer `created_at` wins, tie keeps what is stored. The relay stores it in the address slot with an empty `d`.
- **One per identity, not per relay.** A replaceable event is one per signer; a friend on two shared relays would receive two profiles for one key and keep the newer, so a per-relay choice survives only where memberships never overlap. Per-group personas require per-group keys, which is multi-identity and its own campaign.
- **Name optional on the wire, never a literal.** A missing name is rendered by the reader as Unnamed. Publishing the word would make a person who chose that name indistinguishable from one who never named themselves, and would need a migration that dispatches an event carrying no information.
- **Avatar inline**: base64 with its type, decoded size capped at 64 KB, the first bytes required to match the declared type. The sender writes a 256×256 WebP master. A reader never decodes what it receives; it checks the signature, stores the bytes and serves them with the declared type. No hosting, no third-party fetch from a friend's install.
- **Never withdrawn.** Removing the avatar or the name is a new profile without the field. A kind 5 may not name a profile.
- **Nothing published for the sake of it.** An identity that never saved a profile has no row and the own-events diff sends nothing for it.

### Consequences

* Good, because it works on a private allowlist relay with no image host and no outbound fetch.
* Good, because existing users need no wire event to appear as Unnamed; the first save publishes.
* Good, because the size bound is fixed: one record per member, under 30 KB on the wire.
* Bad, because it is another social-relay release (v0.7.0) and older relays refuse the kind until upgraded, re-sent on every connect as before.
* Bad, because per-group names are not served; they wait on multi-identity.
