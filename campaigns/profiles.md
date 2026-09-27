---
status: in-progress
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

Phase 1 (roster and Person) shipped on main 2026-09-27, precommit
clean; phase 2 (the profile on the wire, opening with the `friends`
rebuild and the optional name) next, social-relay v0.7.0 first.

## Decisions made

* `2026-09-27` — One profile per identity as a replaceable kind 12160 with the avatar bytes inline; name optional on the wire and never a literal; never withdrawn. ([ADR-073](../decisions/architecture/2026-09-27-073-a-profile-is-one-replaceable-event-per-identity.md))
* `2026-09-27` — Per-relay profile selection rejected: shared readers keep the newer of two profiles for one key. Per-group personas are multi-identity, a separate campaign. ([ADR-073](../decisions/architecture/2026-09-27-073-a-profile-is-one-replaceable-event-per-identity.md))
* `2026-09-27` — `Social.Person` is the one read model; Activities rows carry `author :: Person`; the web `Components.Discovery.Person` is retired. `Activities.Sync` moves to `MediaCentaur.RelaySync`. ([ADR-074](../decisions/architecture/2026-09-27-074-person-read-model-and-relay-sync-context.md))
* `2026-09-27` — Name order override → published → Unnamed; the tile's three marks; Settings opens on Your profile and mints on save; add friend's name is optional; the card foot carries the override and the Show avatar switch. ([UIDR-047](../decisions/user-interface/2026-09-27-047-what-a-reader-sees-of-a-person.md))
* `2026-09-27` — The word is **avatar**, in code, on the wire and in copy; "photo" in UIDR-046 and the storybook is renamed. (spec glossary)
* `2026-09-27` — Avatar bytes live as a file under `{data_dir}/images/social/`, served by the existing image server with `?v=`; no new controller. (spec § Storage)
* `2026-09-27` — Unify pass on the phase 1 plan: every shipped state is a whole product, nothing in a phase exists for a later one. The name stays required until the published name exists to fall back on, so the `friends` rebuild, the optional name, Unnamed and the person glyph open phase 2; `Person.published_name` and `Person.name/1` arrive with phase 2, `show_avatar` and `set_show_avatar/2` with phase 3. Phase 1 renames the field in code with `source: :nickname` and needs no migration. Re-adding a key already on the roster changes nothing; the card's foot is the one place to rename. The LiveView holds the people map alone, the friend count derived. (plan § What this phase does not do)
* `2026-09-27` — Phase 1 as built: `Activities` rows are `%{activity, author}`, an unknown author makes no row, and the author is nil only from `get_row/1`. `Format.person_name/1` has no clause for a nameless friend until phase 2 adds Unnamed. `Components.Discovery.Act` (with `Act.Entry`) replaced the web `Person`; `DiscoveryLive.People.build/3` returns `People.Card`s; `DiscoveryLive` holds `people_by_pubkey` and rebuilds it on every roster or identity broadcast. (commits `e08c673c`..`54446ed4`)

## Next steps

1. Phase 2, profile on the wire: social-relay v0.7.0 first; opens with the `friends` rebuild (`name_override` nullable beside a nullable `nickname`; dropped the release after), the optional name, `Person.published_name` and `Person.name/1`, Unnamed, the person glyph, the foot's placeholder through `person_name`; then `profiles`, `Social.Profile` and its translation, ingest, RelaySync with the kind and the own diff, `ProfileUpdated`, Settings' two cards with the name, mint-on-save, FakeRelay. Write its plan first; it opens with the phase 2 items under Follow-ups.
2. Phase 3, avatar: upload, the 256×256 WebP master in `ImageFiles`, file store and serving, the tile's avatar mark, the `show_avatar` column (a plain `add`), `Social.set_show_avatar/2` and the card's switch.
3. Phase 4, docs: protocol page and changes row, wiki (Social, Settings-Reference, Hosting-a-Private-Relay, Troubleshooting), `docs/social.md`, `docs/GLOSSARY.md`; records to accepted; close by destination. The following release drops `nickname`.

## Follow-ups from phase 1 reviews

Phase 2 plan opens with:

* The `friends` rebuild.
* The optional name in `add_friend/2`, `set_name_override/2` and the add form.
* `Person.published_name` and `Person.name/1`.
* The "Unnamed" clause in `Format.person_name/1`, in the same change as the optional name: the function's doc says so, and without it the Feed crashes on a nameless friend.
* The identity tile's person-glyph mark.
* The card foot's placeholder as `Format.person_name(%Person{person | name_override: nil})`, never a literal.

Phase 3 plan:

* `show_avatar` as a plain `add` column, `Social.set_show_avatar/2`, the card's switch.
* Normalise an empty-string `avatar_url` to nil in `Social.person_for/1`; the tile treats any binary as an avatar.

Deferred, any phase:

* `Identity.pubkey/0` derives the point from the secret on every call, and `people/0` and `own_person/0` (three times per review-modal render) pay it; candidate: derive once beside the secret.
* `mix social.dev` carries a third npub elision (`String.slice(0, 12) <> "…"`); unify on `Social.short_npub/1`.
* The add-friend inputs and the card's rename input wear `.library-filter`, the library search pill, padded for a glass and a clear they lack; a surface-neutral text-input class is owed.
* The rename input sits inside `<section role="button">`; belongs to the person card's nav hardening pass.
* A pre-existing runtime log line in the suite (`tmdb poster download failed for tv_series-5555`, from tests this phase did not touch) is a zero-warnings-policy item outside this campaign.

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
