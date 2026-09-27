---
status: planning
started: 2026-09-27
last_updated: 2026-09-27
---
# Profiles

## Goal

A person on the network publishes how they appear: a name, required
in the form, and an avatar, optional. Friends see it in the identity
tile and the words on every surface, under the reader's own override
and a per-friend switch to hide the picture. The tile has taken a
picture since UIDR-046 and nothing feeds it; friend names are the
reader's alone.

## Status

Design approved 2026-09-27; spec, records and this file written. No
code.

## Decisions made

* `2026-09-27` — One profile per identity as a replaceable kind 12160 with the avatar bytes inline; name optional on the wire and never a literal; never withdrawn. ([ADR-073](../decisions/architecture/2026-09-27-073-a-profile-is-one-replaceable-event-per-identity.md))
* `2026-09-27` — Per-relay profile selection rejected: shared readers keep the newer of two profiles for one key. Per-group personas are multi-identity, a separate campaign. ([ADR-073](../decisions/architecture/2026-09-27-073-a-profile-is-one-replaceable-event-per-identity.md))
* `2026-09-27` — `Social.Person` is the one read model; Activities rows carry `author :: Person`; the web `Components.Discovery.Person` is retired. `Activities.Sync` moves to `MediaCentaur.RelaySync`. ([ADR-074](../decisions/architecture/2026-09-27-074-person-read-model-and-relay-sync-context.md))
* `2026-09-27` — Name order override → published → Unnamed; the tile's three marks; Settings opens on Your profile and mints on save; add friend's name is optional; the card foot carries the override and the Show avatar switch. ([UIDR-047](../decisions/user-interface/2026-09-27-047-what-a-reader-sees-of-a-person.md))
* `2026-09-27` — The word is **avatar**, in code, on the wire and in copy; "photo" in UIDR-046 and the storybook is renamed. (spec glossary)
* `2026-09-27` — Avatar bytes live as a file under `{data_dir}/images/social/`, served by the existing image server with `?v=`; no new controller. (spec § Storage)

## Next steps

1. Phase 1 plan written: `docs/superpowers/plans/2026-09-27-profiles-phase-1-roster-and-person.md` (13 tasks; the suite is red between its Tasks 2 and 11 by design). Phases 2 to 4 get their own plans when phase 1 lands.
2. Phase 1, roster and Person: paired migration's first half, `FriendChanged`, `Social.Person` and `people/0`, Activities rows carry `author`, every web site and story reads a Person, add friend with an optional name, the override field. Ships alone.
3. Phase 2, profile on the wire: social-relay v0.7.0 first; `profiles`, `Social.Profile` and its translation, ingest, RelaySync with the kind and the own diff, `ProfileUpdated`, Settings' two cards with the name, mint-on-save, FakeRelay.
4. Phase 3, avatar: upload, the 256×256 WebP master in `ImageFiles`, file store and serving, the tile's avatar mark, the switch.
5. Phase 4, docs: protocol page and changes row, wiki (Social, Settings-Reference, Hosting-a-Private-Relay, Troubleshooting), `docs/social.md`, `docs/GLOSSARY.md`; records to accepted; close by destination. The following release drops `nickname`.

## Completion criteria

* A name and avatar saved on one install show on a friend's Feed rows, rail card and Friends card after one connect; removing the avatar clears it there.
* An override masks the published name and clearing it reveals it; the switch hides and reveals the avatar.
* An identity that never saved a profile is Unnamed with the person glyph and publishes nothing; opening Settings → Social mints nothing.
* A pre-0.7.0 relay warns on the relay row and the profile is re-sent on the next connect.
* One representation of a person in the code; `mix precommit` clean; stories updated with their components.
* Protocol page, wiki and glossary updated; ADR-073, ADR-074 and UIDR-047 accepted; `nickname` dropped in the following release.

## Pointers

* Spec: `docs/superpowers/specs/2026-09-27-profiles-design.md`
* Contract: `docs/social-protocol.md`; relay: `../social-relay` (`internal/relay/slot.go`, `kinds.go`)
* The tile: `lib/media_centaur_web/components/discovery/identity_tile.ex`, `storybook/discovery/identity_tile.story.exs`
* The five name sites: `lib/media_centaur/activities.ex` (`activity_row/3`), `discovery_live/feed_entries.ex`, `discovery_live/people.ex`, `components/title/pennant.ex`, `components/detail_panel.ex`
* Image serving: `MediaCentaurWeb.Plugs.ImageServer`, `MediaCentaur.ImageFiles.web_path/1`
