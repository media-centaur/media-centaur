---
status: in-progress
started: 2026-09-27
last_updated: 2026-09-28
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

Phase 3 shipped on main 2026-09-28, precommit clean; phase 4 (records,
closure, the `nickname` drop) next. Phase 2 shipped on main the same day;
social-relay v0.7.0 is committed in `../social-relay` (`567d3d8`), its tag
and push await the owner's ship.

## Decisions made

* `2026-09-27` — One profile per identity as a replaceable kind 12160 with the avatar bytes inline; name optional on the wire and never a literal; never withdrawn. ([ADR-073](../decisions/architecture/2026-09-27-073-a-profile-is-one-replaceable-event-per-identity.md))
* `2026-09-27` — Per-relay profile selection rejected: shared readers keep the newer of two profiles for one key. Per-group personas are multi-identity, a separate campaign. ([ADR-073](../decisions/architecture/2026-09-27-073-a-profile-is-one-replaceable-event-per-identity.md))
* `2026-09-27` — `Social.Person` is the one read model; Activities rows carry `author :: Person`; the web `Components.Discovery.Person` is retired. `Activities.Sync` moves to `MediaCentaur.RelaySync`. ([ADR-074](../decisions/architecture/2026-09-27-074-person-read-model-and-relay-sync-context.md))
* `2026-09-27` — Name order override → published → Unnamed; the tile's three marks; Settings opens on Your profile and mints on save; add friend's name is optional; the card foot carries the override and the Show avatar switch. ([UIDR-047](../decisions/user-interface/2026-09-27-047-what-a-reader-sees-of-a-person.md))
* `2026-09-27` — The word is **avatar**, in code, on the wire and in copy; "photo" in UIDR-046 and the storybook is renamed. (spec glossary)
* `2026-09-27` — Avatar bytes live as a file under `{data_dir}/images/social/`, served by the existing image server with `?v=`; no new controller. (spec § Storage)
* `2026-09-27` — Unify pass on the phase 1 plan: every shipped state is a whole product, nothing in a phase exists for a later one. The name stays required until the published name exists to fall back on, so the `friends` rebuild, the optional name, Unnamed and the person glyph open phase 2; `Person.published_name` and `Person.name/1` arrive with phase 2, `show_avatar` and `set_show_avatar/2` with phase 3. Phase 1 renames the field in code with `source: :nickname` and needs no migration. Re-adding a key already on the roster changes nothing; the card's foot is the one place to rename. The LiveView holds the people map alone, the friend count derived. (plan § What this phase does not do)
* `2026-09-27` — Phase 1 as built: `Activities` rows are `%{activity, author}`, an unknown author makes no row, and the author is nil only from `get_row/1`. `Format.person_name/1` has no clause for a nameless friend until phase 2 adds Unnamed. `Components.Discovery.Act` (with `Act.Entry`) replaced the web `Person`; `DiscoveryLive.People.build/3` returns `People.Card`s; `DiscoveryLive` holds `people_by_pubkey` and rebuilds it on every roster or identity broadcast. (commits `e08c673c`..`54446ed4`)
* `2026-09-27` — `Person.avatar_url` and the tile's `:avatar` mark stayed in phase 1 without a writer, the one exception to "nothing in a phase exists for a later one", because they carry the photo state UIDR-046 shipped before the campaign. Phase 3 gave them their writer.
* `2026-09-27` — Every `Person` field added updates `test/support/discovery_rows.ex` and the eight story fixture builders (`identity_tile`, `person_card`, `feed_row`, `pennants`, `title_row`, `media_results`, `cinematic_shell`, `detail_panel`); stories cannot import test support, so the copies stay.
* `2026-09-28` — The relay's slot finds a replaceable record by signer and kind: for 12160 one record per signer, newer `created_at` replaces, a tie keeps the stored one. Which kinds are stored and which a kind 5 may name are separate lists: 12160 is stored but never deletable, so a deletion naming it is refused with the author wording. (social-relay ADR-003, v0.7.0)
* `2026-09-28` — The two rules both contexts need moved to their owners: `Social.known_key?/1` (the identity or the roster; hex in any case) and `Nostr.Event.stamp_after/2` (strictly after the stored record). `Activities` keeps the relay consequence in its own stamping. (commits `99768ae3`, `2eb9ebf2`)
* `2026-09-28` — The Discovery page reloads its people and rows on `{:profile_updated, _}`, so a friend's published name is live. (commit `08a1e77a`)
* `2026-09-28` — `Social.save_profile/1` (now `/2`) refuses a blank name (`:name_required`) and one over the 50-character cap (`:name_too_long`) before minting the identity; the form shows either as a flash instead of crashing. (commits `ed9f896e`, `de6930c4`)
* `2026-09-28` — Phase 2 as built: `Social.Profile` and `Profile.Translation`, `save_profile/1` (now `/2`), `ingest_profile/1`, `own_profile/0`, `own_events/0`, `own_event_kind/1`, `import_identity/1` (drops the old key's row unless the key is unchanged), `remove_friend/1` drops the friend's row; `ProfileUpdated` on `social:updates`; `MediaCentaur.RelaySync` replaces `Activities.Sync`, gated under `:test` by the kept `:start_activities_sync` key; Settings → Social opens on Your profile; the `friends` rebuild with `name_override` nullable beside the nullable `nickname` the outgoing release still reads. (commits `99768ae3`..`83da42fa`)
* `2026-09-28` — Unify pass on the phase 3 plan: one derivation of a data-dir image path in `ImageFiles` (`on_disk_path/1`, `web_path/2`), used by every store (`TmdbArtwork`, `Apps.Artwork`, `Social.AvatarStore`), the TMDB sweep's root and the image plug's lookup. An artwork path is never relative to the working directory, so `on_disk_path/1` raises when no data dir is configured; its doc is the citation for that rule. The profile row carries `avatar_type` only and the path is derived from key and type. An avatar URL never carries `?w=`. (commits `230b5a06`, `6e27c6ed`, `2b854888`)
* `2026-09-28` — The avatar on the wire as `docs/social-protocol.md` states it: `{"type", "data"}`, `image/webp`, `image/png` or `image/jpeg`, base64, 64 KB decoded inclusive, the type's signature at the start, anything else drops the profile. The reader never decodes; `raw_event` carries the encoded form for republish, and `people/0` selects four fields so a page load never reads it. (commits `2972d66f`, `7cca7201`, `f9cc0867`)
* `2026-09-28` — Row then file in `store_profile/2`: a write that fails after the row reads as no avatar until a newer profile arrives, where file first could serve new bytes under the old version. `:keep` with a missing file publishes no avatar. (commits `be50a610`, `f9cc0867`)
* `2026-09-28` — The Settings form checks the name (`Social.check_name/1`) before it consumes the upload, so a name error keeps the chosen picture. Remove steps aside while a file is chosen; a chosen file wins over a pending Remove. (commits `b5638786`, `3d21a04c`)
* `2026-09-28` — `Friend.show_avatar` is a plain add, on by default; hidden means `Person.avatar_url` is nil, applied at `Social`'s `person_for/2` alone; the switch, **Show their picture**, sits in the opened card's foot. (commits `c34dce4d`, `9e3869a1`)
* `2026-09-28` — `TmpDataDir.setup_tmp_data_dir/1` replaces the per-test data-dir setups copied across test files. (commit `f9cc0867`)
* `2026-09-28` — No relay change for the avatar: social-relay's Nostr layer, khatru, reads client messages up to 512 KB by default, and a profile with an avatar is about 90 KB. The protocol page states a 128 KB floor for any relay.
* `2026-09-28` — The final review: the master strips the source's metadata (a photo's EXIF carries GPS, device and time, and a profile is never withdrawn), flattens alpha onto black and steps quality down until it fits the cap, so `save_profile/2` never signs bytes its own reader refuses; the API still refuses over-cap bytes (`:avatar_too_large`) before minting. The image plug serves `images/social/` masters as they are, whatever the query, so a friend's bytes are never decoded here either. `Translation.master_type/0` names the sender's type. (commit after `dee2b95b`)

## Next steps

1. Ship: tag and push social-relay v0.7.0 with the app release that carries phases 2 and 3 (owner's instruction).
2. Phase 4: ADR-073, ADR-074 and UIDR-047 to accepted; close the campaign by destination; the release after the one carrying phase 2 drops `friends.nickname` (a paired migration; the outgoing release still reads it) and the `:start_activities_sync` key with it.

## Ship notes for phase 2 (the CHANGELOG draws on these)

* Settings → Social opens on **Your profile**: the name friends see you under, up to 50 characters; **Create profile** creates your identity. Opening the section no longer creates one. **Save** republishes the name.
* A friend's name is optional. A friend shows under your name for them, else the name they publish, else **Unnamed** with a person glyph. The opened card's empty name field shows the name it masks; saving it empty returns to the published name.
* Profiles need **social-relay v0.7.0**: an older relay refuses them (`blocked: kind 12160 is not stored by this relay`, "rejected a profile" on the relay row) and they are re-sent on every connect until it is upgraded. Tag and push v0.7.0 with the release.
* Two migrations: the `profiles` table; `friends` rebuilt so the name is nullable, `nickname` kept nullable for the outgoing release and dropped in the release after. A friend added in the seconds between migrate and restart shows as Unnamed until renamed. Rolling back is not lossless.
* Existing users publish nothing until they save a profile; friends see them under their own name for them, or as Unnamed, until then. Replacing the identity forgets the old key's profile; re-importing the same key keeps it.
* Internal: `Activities.Sync` is `MediaCentaur.RelaySync`; `{:profile_updated, _}` on `social:updates`; `:start_activities_sync` keeps its name until `nickname` is dropped, then both go.
* Not wired, by inheritance: the title detail and Incoming pages load pennant rows on open and react to neither `:friend_changed` nor `:profile_updated`; a new name shows on the next open, as a rename always has.

## Ship notes for phase 3 (the CHANGELOG draws on these)

* Settings → Social → **Your profile** takes a picture: one JPEG, PNG or WebP up to 10 MB, saved as a 256×256 WebP square and published with the name on **Save**. **Remove**, then **Save**, clears it. A file that is not a picture is refused with "That file is not a picture we can read".
* Friends see the picture in the identity tile on Feed rows, the rail and the Friends page.
* On a friend's opened card, **Show their picture** hides or shows their picture, for this reader only; on by default.
* Two migrations, plain adds safe for the outgoing release, which never reads them: `profiles.avatar_type` (nullable) and `friends.show_avatar` (not null, default true).
* Avatars live under `{data_dir}/images/social/`, one file per key.
* social-relay v0.7.0 carries avatars unchanged; no relay release.

## Follow-ups from reviews

Deferred, any phase:

* `Identity.pubkey/0` derives the point from the secret on every call, and `people/0` and `own_person/0` pay it once per Discovery load and per review-modal render; candidate: derive once beside the secret.
* The rename input and button in the card's foot carry no `data-nav-item`; a gamepad user cannot rename until the person card's nav hardening pass, which also owns the input-inside-`role="button"` note below.
* `mix social.dev` carries a third npub elision (`String.slice(0, 12) <> "…"`); unify on `Social.short_npub/1`.
* The add-friend inputs and the card's rename input wear `.library-filter`, the library search pill, padded for a glass and a clear they lack; a surface-neutral text-input class is owed.
* The rename input sits inside `<section role="button">`; belongs to the person card's nav hardening pass.
* A pre-existing runtime log line in the suite (`tmdb poster download failed for tv_series-5555`, from tests this phase did not touch) is a zero-warnings-policy item outside this campaign.
* The suite's intermittent `Exqlite.Connection … client exited` error line, seen once in phase 3's precommit run; pre-existing.
* `settings_input` carries `input-bordered`, a daisyUI v4 leftover.

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
* Image serving: `MediaCentaurWeb.Plugs.ImageServer`, `MediaCentaur.ImageFiles` (`on_disk_path/1`, `web_path/2`, `square_webp/3`); the avatar file: `MediaCentaur.Social.AvatarStore`
