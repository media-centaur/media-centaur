# Profiles: a person's name and avatar on the wire

Design approved 2026-09-27. Campaign: [`campaigns/profiles.md`](../../../campaigns/profiles.md).
Records: [ADR-073](../../../decisions/architecture/2026-09-27-073-a-profile-is-one-replaceable-event-per-identity.md),
[ADR-074](../../../decisions/architecture/2026-09-27-074-person-read-model-and-relay-sync-context.md),
[UIDR-047](../../../decisions/user-interface/2026-09-27-047-what-a-reader-sees-of-a-person.md).
Supersedes decision 6 of the
[2026-09-02 friends design](2026-09-02-friends-recommendations-design.md)
("No profile events. Names are local.").

## Glossary

Terms are defined here before first use and refined as the campaign
runs; they graduate to `docs/GLOSSARY.md` at completion.

| Term | Meaning |
|---|---|
| **Identity** | The install's keypair. The public half is the npub friends add. Exists today (`Social.Identity`). |
| **Profile** | What a key published about itself: a name, an avatar, both, or neither. One per key, replaced whole by a newer one. Kind 12160. New. |
| **Avatar** | The picture inside a person's identity tile. The word replaces "photo" in UIDR-046 and the storybook. |
| **Friend** | A roster entry: a followed key plus the reader's choices for it. Exists today; gains the two choices below. |
| **Name override** | The reader's own name for a friend, masking the published one. Today's `nickname`, made optional. |
| **Show avatar** | The reader's per-friend switch; off hides that friend's avatar and the tile falls back to the letter, or the person glyph when there is no name. |
| **Person** | A key as this reader sees it: the resolved name, the resolved avatar, whether it is the reader's own. The read model every surface draws. New (`Social.Person`). Carries the override and, from phase 2, the published name; `Person.name/1` resolves. |
| **Unnamed** | The word a reader renders for a Person with no name. Never on the wire. |
| **Identity tile** | The circle that draws a person (UIDR-046). |
| **Person glyph** | The tile's mark for a person with neither a name nor an avatar. |
| **RelaySync** | The context whose loop keeps stored rows in step with relays. Today `Activities.Sync`; moved because it now carries two contexts' rows. |
| **Own-events diff** | On a relay's `own:<url>` end-of-stored-events, publishing every own event that relay did not send. Exists today; gains the own profile. |

## Core idea

A person on the network is a public key. What a reader sees of one is
the key's own published self-description, overlaid by the reader's
roster choices. Today there is no published half, so every name in the
app is the reader's roster entry or the literal "You".

## What exists

The identity tile already takes a photo at both sizes; the storybook
pins the state and nothing feeds it (UIDR-046 rule 2). A person's name
is represented five ways:

1. `Social.Friend.nickname`, required, the reader's word for a friend.
2. `Activities.list_activities/0`, `friend_activity_for/1` and
   `get_row/1` join a pubkey-to-nickname map from `Social.list_friends/0`
   onto every row as `nickname` plus `own?`; a former friend is a row
   with `own?: false, nickname: nil`.
3. `DiscoveryLive.FeedEntries` writes `"You"` or the nickname into
   `FeedEntry.author`.
4. `DiscoveryLive.People` copies name, own flag, pubkey, short npub and
   added date from `Friend` into `Components.Discovery.Person`, and
   builds one named `"You"`.
5. `Components.Title.Pennant` collects row nicknames and appends the
   literal `"You"`, then special-cases that literal in the tooltip;
   `DetailPanel.note_words` and the review modal's preview row read the
   same fields.

The sync loop is `Activities.Sync`, whose filters come from
`Activities.Translation.kinds/0`, a title-shaped module in every clause.
The identity is minted when Settings → Social is opened
(`SettingsLive.load_social/2`) and when an own activity is published.

## Design

### On the wire

A new kind in the replaceable block, the first one used there.

| Kind | Name | Rule | Defined by |
|---|---|---|---|
| 12160 | Profile | Replaceable | Media Centaur. Checked against the public kind registry: no NIP defines it. |

**Tags**: none. The replaceable rule keys on signer and kind alone.

**Content** is a JSON object:

| Field | Type | Cap | Notes |
|---|---|---|---|
| `v` | integer | | Content schema version. Absent means 1. |
| `name` | string | 50 characters | Optional. Trimmed by the sender; empty is treated as absent. |
| `avatar` | object | | Optional. Below. |

`avatar`:

| Field | Type | Cap | Notes |
|---|---|---|---|
| `type` | `"image/webp"`, `"image/jpeg"` or `"image/png"` | | Required. |
| `data` | string, standard base64 with padding | 64 KB decoded | Required. The first bytes must carry the signature of `type`. |

**Rules**

- Between two profiles from one signer the newer `created_at` wins; on
  a tie what is stored is kept. Same as activities.
- A profile is never withdrawn. Removing the avatar or the name is a
  new profile without that field. A profile with neither field is
  valid: the key says nothing about itself. A kind 5 may not name a
  profile; the deletion rule that the `a` tag names an activity kind
  stands.
- Malformed is dropped whole, nothing repaired: an unknown `v`, a name
  over the cap, an unknown `type`, bad base64, decoded bytes over the
  cap, or bytes whose signature does not match `type`.
- A reader never decodes a received avatar. It checks the signature
  bytes, stores the bytes and serves them with the declared type.
- The sender writes the master as a 256×256 WebP, centre-cropped from
  the chosen file. Readers accept the three types so a future sender
  may differ.
- A missing name is rendered by the reader in the reader's language.
  No literal for it exists on the wire.

**Sync.** The `feed` and `own:<url>` subscriptions add kind 12160 to
their kinds. Ingest requires the author to be the identity or on the
roster, as for activities. The own-events diff includes the own profile
event when a profile row exists; nothing is published for an identity
that has never saved one.

### The relay

social-relay v0.7.0 stores kind 12160 in the address slot
`12160:<pubkey>:` with an empty `d`, one record per signer, newer
`created_at` taking the slot. Every other kind stays refused with
`blocked:`. A pre-0.7.0 relay answers `blocked: kind 12160 is not stored
by this relay`; the app shows "rejected a profile: …" on the relay row
and re-sends on every connect until the relay is upgraded, as with every
kind before.

### Storage

`profiles` table, owned by Social:

| Column | Notes |
|---|---|
| `pubkey` | hex, unique |
| `name` | nullable |
| `avatar_type` | nullable; the file's path derives from the key and the type |
| `raw_event` | the signed wire form, for republish |
| `created_at` | the wire time; decides which copy wins |

A row exists only for the identity and roster members. Removing a
friend deletes theirs. Replacing the identity deletes the old own row;
the new key's profile arrives from the relays if one was ever published,
otherwise the reader is Unnamed and the Settings form is empty.

The avatar file lives at `{data_dir}/images/social/<pubkey>.<ext>`,
written whenever a profile with an avatar is stored, removed when a
newer profile has none or the row is deleted. It is served by the
existing image server at `ImageFiles.web_path/1` with `?v=<created_at>`,
so a replaced avatar busts the browser cache and an unchanged one is
immutable. No new controller. `Social.people/0` yields an avatar URL
only for a file that exists; a missing file reads as no avatar until the
next profile arrives.

2026-09-28, as built: no `avatar_path` column; `Social.AvatarStore`
derives `images/social/<pubkey>.<ext>` from the key and `avatar_type`
through `ImageFiles.on_disk_path/1`, and the URL is
`ImageFiles.web_path/2` with `created_at` as the version, never `?w=`.

`friends`: `nickname` becomes `name_override`, nullable; `show_avatar`
boolean, not null, default true.

### The Person read model

```elixir
%Social.Person{
  pubkey: hex | nil,                 # nil for the reader before an identity exists
  name_override: String.t() | nil,   # the reader's word for a friend; nil for the reader's own
  published_name: String.t() | nil,  # what the key said about itself (phase 2)
  avatar_url: String.t() | nil,      # nil when none, hidden, or the file is missing (phase 3)
  own?: boolean,
  short_npub: String.t() | nil,
  added_on: Date.t() | nil           # nil for the reader's own
}
```

The struct grows with its writers. Phase 1 builds it with
`name_override` required and `avatar_url` nil; phase 2 adds
`published_name`, `Person.name/1` (the override, else the published
name, else nil) and the optional override; phase 3 fills `avatar_url`.
The card's foot shows the override with the published name as its
placeholder, which is why both ride on the struct. `Social.people/0`
returns `%{pubkey => Person}` for the identity (when one exists) and
every roster member; `Social.own_person/0` is the reader with or
without an identity. The own Person always shows its own avatar; the
switch is a friend's field.

Activities keeps the enriched-list join it owns today, but the actor is
a Person: `list_activities/0`, `friend_activity_for/1` and `get_row/1`
rows are `%{activity, author :: Person | nil}`. `list_activities/0` and
`friend_activity_for/1` exclude rows whose author is neither the
identity nor on the roster; `get_row/1` returns `author: nil` for one,
since a watchlist row may still point at a removed friend's activity.

### The web reads a Person

- `Discovery.IdentityTile` takes `person` and `size`. It derives the
  mark: the avatar when `avatar_url` is set, inside a neutral ring for a
  friend and a 2px primary ring for the reader's own; else the name's
  first letter; else the person glyph. The own tile's fill and white
  mark are as UIDR-046.
- One function renders a Person's words, `Format.person_name/1`:
  "You" when own, the name, else "Unnamed". Feed rows, person cards,
  the pennant's label and tooltip and the detail panel's attributed
  words all call it. The pennant's second-person branch keys on `own?`,
  not on a literal.
- `FeedEntry.author` is a Person. `Components.Discovery.Person` is
  retired; `PersonCard` takes `person` and `acts` as two attrs, and the
  `Act` and `Entry` structs move to their own module.
- The person glyph is heroicons' solid user mark, sized like the letter.

### Identity minting

Two callers of `Identity.ensure/0` remain: publishing an own activity,
silent as today; and saving the Settings profile form. Opening
Settings → Social no longer mints. `Social.save_profile/2` ensures the
identity, writes the row and the file, publishes to every connected
relay, and broadcasts `ProfileUpdated`.

### Settings → Social

Two cards replace "Your identity":

1. **Your profile**: Name, required to save, capped at 50; Avatar, the
   current tile at 48 with Choose and Remove, optional; Save. With no
   identity this is the only card in the section and its button creates
   the profile, which mints the identity. Uploads accept JPEG, PNG and
   WebP up to 10 MB; the app writes the master.
2. **Your identity**: the npub with Copy, the secret key disclosure
   with reveal, copy, hide and replace, exactly as today. Shown once an
   identity exists, with Relays and Sharing below it.

An identity with no profile row shows both cards, the name empty and
required.

### Friends

- **Add friend** takes an npub and an optional name, the override.
- The opened card's foot gains, above the key and the added date: the
  override field, with the published name or Unnamed as its
  placeholder; the **Show avatar** switch, on by default. Remove friend
  stays last.
- A card says what a person published and nothing about what they did
  not: an Unnamed friend is Unnamed, with no note about a missing
  profile.

### Events

On `social:updates`: `FriendChanged{pubkey}` for an override or switch
change (so `FriendAdded` means added and nothing else), and
`ProfileUpdated{pubkey}` when a profile is ingested or saved.
DiscoveryLive re-projects on both; SettingsLive refreshes the own card
on `ProfileUpdated`. RelaySync ignores both; roster membership is
unchanged.

### Contexts

`Activities.Sync` moves to `MediaCentaur.RelaySync`, a Boundary with
deps `Activities`, `Social`, `Nostr`. Its kinds are the two contexts'
lists concatenated; its ingest dispatches by kind; its own-events diff
publishes `Activities.own_events/0 ++ Social.own_events/0`. Activities
is then content only: rows, translation, publisher. The dependency
diagram in `docs/social.md` gains the row.

`Social.Profile.Translation` is the pure event-to-Profile module, beside
`Activities.Translation`, which stays title-shaped. `ImageFiles` gains
one bytes-in, bytes-out function that writes the 256×256 WebP master;
the caps live in `Social.Profile`.

### Errors

| Situation | Behaviour |
|---|---|
| Upload of a rejected type or size | Form error, nothing saved |
| The image cannot be decoded for the master | Form error naming the file |
| Relay refuses the profile | "rejected a profile: <reason>" on the relay row; re-sent on the next connect |
| Malformed inbound profile | Debug log under `:social`, dropped whole |
| Avatar file missing on disk | No avatar until the next profile arrives; the tile shows the letter |
| Own profile for a replaced identity | Old row deleted on `IdentityChanged` |

### Migration

Paired, per the release rule. Release N: add `name_override` (copied
from `nickname`) and `show_avatar`, make `nickname` nullable so the new
code stops writing it while the old release, in the seconds between
migrate and restart, still reads it. Release N+1: drop `nickname`. Both
idempotent; the CHANGELOG names them.

### Testing

No network. `FakeRelay` stores and serves kind 12160.

- Translation round trip and the malformed matrix: cap, type,
  signature, base64, `v`.
- Ingest: author gate, newer-wins, tie, avatar file written and removed.
- `Social.people/0`: override over published over nil; own; hidden
  avatar; missing file.
- RelaySync against a FakeRelay: filters carry 12160; the own diff
  publishes the profile once and not when no row exists.
- Settings: no mint on open; mint on save; name required; the three
  upload types accepted, others refused.
- Friends: add without a name; override masks and clears; the switch
  hides and reveals.
- Stories: the tile's three marks, own and friend, at 40 and 48; the
  person card and feed row over a Person; every story that builds
  activity rows carries an author Person.
- Migration on a friend row with a nickname.
- Generic names throughout; no real titles.

## Scope

In: the kind, the relay release, Profile storage and translation, the
Person read model through Activities and every web site, RelaySync, the
Settings cards with upload and resize, the tile's marks, the friend
override and switch, the paired migration, the protocol page and wiki.

Deferred: multi-identity personas (per-group names need per-group keys;
its own campaign); an avatar given as a URL; a global hide-all-avatars
setting; showing the reader's own name anywhere but Settings; a
boot-time heal for a missing avatar file.

## Acceptance

- A named profile with an avatar saved on one install shows the name
  and the picture on a friend's Feed rows, rail card and Friends card
  after one connect.
- Removing the avatar clears it on the friend's install; a new name
  replaces the old everywhere.
- On a pre-0.7.0 relay the relay row warns and the profile is re-sent
  on the next connect.
- An override masks the published name; clearing it reveals it. The
  switch reverts the tile to the letter.
- An identity that never saved a profile renders as Unnamed with the
  person glyph and publishes nothing.
- Opening Settings → Social on a fresh install mints nothing; Create
  profile mints the identity.
- `mix precommit` clean; every changed component's story updated in the
  same commit.

## Build order

Each phase ships on its own.

1. **Roster and Person.** `Friend.name_override` over the `nickname`
   column with `source:`, `FriendChanged`, `Social.Person` and
   `people/0`, Activities rows carry `author`, every web site and story
   reads a Person, the override field on the card. No wire change, no
   schema change, the name still required.
2. **Profile on the wire.** The `friends` rebuild and the optional
   name, Unnamed and the person glyph open this phase, since the
   published name is what a missing override falls back to. `profiles`, `Social.Profile` and its
   translation, ingest, RelaySync with the new kind and the own diff,
   `ProfileUpdated`, Settings' two cards with the name alone,
   mint-on-save, FakeRelay. social-relay v0.7.0 first. Names travel.
3. **Avatar.** Upload and the master, the file store and serving, the
   tile's avatar mark, the Show avatar switch.
4. **Docs and records.** Protocol page and its changes row, wiki
   (Social, Settings-Reference, Hosting-a-Private-Relay,
   Troubleshooting), `docs/social.md`, `docs/GLOSSARY.md`, the records
   marked accepted, the campaign closed by destination. The following
   release drops `nickname`.

## Phase 5: the hue, the crop, the name field (designed 2026-09-28)

Three items the owner asked for after v1.42.0: a colour for a person's
circle, chosen by the person and overridable by the reader; a cropper
with a preview when a picture is chosen; the Settings name field's
width. Decided with the owner on 2026-09-28 over two mockups
(`mockups/profiles-phase-5/`, git-ignored): the tinted circle over the
filled one; `hue` as an integer on the wire over a hex colour; croppr
over Cropper.js and a hand-rolled hook. Records:
[UIDR-048](../../../decisions/user-interface/2026-09-28-048-a-persons-colour-is-a-hue-on-the-apps-ring.md);
ADR-073 and UIDR-047 amended.

### Glossary, continued

| Term | Meaning |
|---|---|
| **Hue** | The colour a person's circle takes, as an angle 0–359 on one ring in oklch: the theme fixes lightness and chroma (`--person-l`, `--person-c` in `app.css`), the person picks the angle. The word in code and on the wire; user copy says **colour**. `Social.Hue`. |
| **Palette** | The eight named hues offered as swatches: Rose 12, Orange 45, Amber 80, Green 150, Teal 195, Blue 250, Violet 290, Magenta 335. `Social.Hue.palette/0`. |
| **Custom** | Any hue not in the palette, chosen on the slider under the swatches, whose track is the ring. The slider is always shown; a swatch moves its thumb, dragging it deselects the swatches. |
| **Published hue** | The hue a key gives in its profile. `Person.published_hue`. |
| **Hue override** | The reader's hue for a friend, on the roster row beside the name override; wins over the published hue. `Friend.hue_override`. |
| **Theirs** | The first swatch on a friend's card foot: the friend's published hue (Blue when none), selected while there is no override. |
| **Default hue** | Blue 250, the primary's hue, for a person with neither an override nor a published hue. Lives in CSS as the `--hue` fallback; `Person.hue/1` returns nil, never a made-up value. |
| **Crop** | The square of the chosen picture the sender picks by dragging a box over the whole picture; the server cuts that square and makes the master from it. |
| **Preview** | The tile as it will look after Save: the crop inside the own tile's ring at 48 and 40, beside the cropper, drawn client-side. |

### Core idea

A person's appearance is one published record — name, avatar, hue —
overlaid by the reader's choices for a friend — name override, show
avatar, hue override. The hue is the third field of the same structure
on both sides, resolved at the one seam that resolves the other two.

### The hue

**A colour is a hue.** The ring is oklch lightness 70 %, chroma 0.15,
the slate theme at hue 264 behind it; a hue is the angle. Nothing a
person publishes can be dark, pastel or grey, so the letter's contrast
is constant by construction and nothing is computed from luminance.
The palette is eight angles on the ring; Custom is any other angle. A
reader draws a hue at its own theme's lightness and chroma, which is
why the wire carries the angle and not a colour.

**On the wire**: `"hue"`, an integer 0–359, optional; absent or `null`
means the key gives none. The sender's `Translation.to_event/3` takes
the content as one map of fields (`name`, `avatar`, `hue`), the same
shape `from_event/1` returns (2026-09-28 unify pass: a fourth
positional argument was the bolt-on). A non-integer, a float, or an integer out of
range drops the whole profile, the one rule for malformed. `v` stays 1:
a reader ignores unknown fields.

**Storage**: `profiles.hue` integer nullable; `friends.hue_override`
integer nullable. Both plain adds, safe for the outgoing release, which
never reads them. `Social.set_hue_override/2` (nil clears) through
`apply_change/2`, broadcasting `FriendChanged`. `Social.people/0`
selects `hue` with the other profile fields.

**The read model**: `Person` gains `published_hue` and `hue_override`;
`Person.hue/1` is the override, else the published hue, else nil. The
own Person's `hue_override` is nil. `Social.Hue` owns what a hue is:
the type `0..359`, `valid?/1`, `palette/0` (`[{name, hue}]`),
`random/0` (a palette member).

**The tile**: one recipe, in `app.css` as `.identity-tile` variants
over `--hue`, with `var(--hue, 250)` as the fallback. A friend's letter
or glyph in the hue on the hue at 20 % with a hairline ring at 25 %;
the reader's own filled in the hue with a near-white mark
(`oklch(97% 0.01 hue)`); a friend's picture inside a 1 px ring in the
hue, the reader's own inside a 2 px one. The tile sets `style="--hue:
N"` when `Person.hue/1` is non-nil and nothing otherwise. Own-ness
stays a matter of weight, as UIDR-046 drew it.

**Choosing**: one function component, `Discovery.HueSwatches`
(`hue_swatches/1`): the palette as round swatches, the selected one
outlined, and under them a range input 0–359 named `hue` with the ring
as its track, its thumb at the chosen hue (2026-09-28 unify pass: a
ninth Custom swatch that reveals the slider would need state a function
component has not; the slider is always there and is the custom
choice). It takes `selected` (a hue or nil), `theirs?` with
`theirs_hue` (the first swatch, the friend's published hue, selected
when `selected` is nil), `event` and `values` as `Switch` does; each
swatch is a button pushing the event with `hue` (an integer, or empty
for Theirs). The slider carries no event of its own: it is a form field
named `hue`, and the host's enclosing form's `phx-change` receives it —
the profile form's `validate_profile` on Settings, a small
`phx-change="set_hue_override"` form with the key as a hidden field on
the card foot — so a click and a drag reach one handler with one
payload shape (`pubkey`, `hue`). Every swatch and the slider are nav
items.

- **Settings → Your profile**: a Colour row between the picture row
  and the name row. A swatch pushes `set_profile_hue` and the slider
  reaches `validate_profile`; either sets the form's pending hue, the
  one source the card's tile previews and Save publishes with the name
  and the avatar. When the form loads with
  no profile row, or a row without a hue, the pending hue is
  `Social.Hue.random/0`; the tile shows it at once, the rest of the app
  keeps the default until Save. A saved profile with a hue loads with
  that hue.
- **A friend's opened card**: a Colour row after *Show their picture*:
  Theirs, the palette, the slider. A swatch or a drag saves on the act
  (`set_hue_override`), like the switch.

**Not chosen**: a hue derived from the key for a person who published
none (it invents a choice and changes the day they publish; a card says
what was published); a free colour picker (a dark or pastel pick
fights the theme and needs contrast math); a hex colour on the wire
(the app would convert to and from oklch and clamp to the ring on both
sides); the filled circle (louder beside the poster on a page of many
people; own-ness would need a new mark).

### The crop

**croppr** (MIT, 5 KB gzipped, no dependencies, vendored under
`assets/vendor/croppr.js` with its stylesheet folded into `app.css`
under one comment) draws a square box the person drags and resizes
over the whole picture; no zoom. The server keeps the crop: the client
sends the box, the server cuts it.

- The `AvatarCrop` hook mounts on the pending entry's `live_img_preview`
  once the image has loaded, with `aspectRatio: 1`, the box starting as
  the largest centred square, `returnMode: "real"`. On every crop end
  it writes `crop_x`, `crop_y` and `crop_side`, in the picture's own
  pixels with orientation applied (the browser draws EXIF orientation
  into the preview and reports the oriented size), into hidden inputs
  in the profile form, and draws the crop onto two canvases at 48 and
  40 inside preview elements wearing the own tile's avatar recipe:
  *How it will look*.
- On Save, `avatar_change/1` reads the three fields and
  `ImageFiles.square_webp/4` takes `crop: {x, y, side}`: autorotate,
  crop, thumbnail to 256, flatten, strip, fit the cap. Missing or
  malformed fields, or a box outside the image, fall back to the centre
  crop, the master today; the form never refuses a crop.
- Cancel discards the entry and the box with it. Remove stays as it is.

### The name field, and the card's two columns

The Settings name field is 16 rem, no longer stretched to the card; the
card foot's rename input takes the same width. One width for a person's
name field.

2026-09-28, owner's request after the first build: the profile card
uses its width as two columns of the Settings kit's stacked fields
(`settings_field layout={:stacked}`, UIDR-041), the idiom the
acquisition section's connection forms already use — **Picture** on the
left (the tile, *Choose picture* opening the hidden file input, Remove,
the chosen file's line; the cropper goes under them in 5b), **Name**
and **Colour** stacked on the right — with Save in the form's footer at
the right, where every kit form keeps its buttons. No hand-rolled
labels: a surface composes from the kit or adds a component to it.

### Errors

| Situation | Behaviour |
|---|---|
| Hue out of range on the API (`save_profile/3`, `set_hue_override/2`) | `{:error, :invalid_hue}`; the form cannot produce one |
| Malformed inbound hue | Dropped whole, debug log under `:social` |
| Crop fields missing or off the image | Centre crop |

### Migration

Release N (the one carrying phase 5, the first after v1.42.0): add
`profiles.hue` and `friends.hue_override`, both nullable; drop
`friends.nickname` as owed, since v1.42.0 was the release that stopped
writing it. The `:start_activities_sync` key goes with it.

### Testing

- Translation: the hue round trip; the malformed matrix (string, float,
  −1, 360, null, absent).
- `Social.people/0`: override over published over nil; the own Person.
- `set_hue_override/2`: set, clear, not a friend, out of range.
- Stories: the tile's marks at every palette hue and with no hue; the
  swatches with and without Theirs, Custom selected; the person card's
  foot; the Settings section with the Colour row.
- Settings: a fresh form seeds a palette hue; Save publishes it; a
  saved hue loads; the slider's value publishes.
- Friends: Theirs clears; a swatch saves.
- The hook (bun): the box writes the fields; the canvases draw.
- `square_webp/4` with a crop and with none; the fallback on a bad box.
- Migration on a friend row with a nickname (dropped) and none.

### Build order

Each phase ships whole.

5a. **The hue and the name field.** `Social.Hue`, the columns, the
    wire field, `Person`, the tile's CSS recipe, `HueSwatches`, the
    Settings Colour row and the random seed, the card foot's row, the
    name width, stories, the protocol page's field and Changes row, the
    `nickname` drop.
5b. **The crop.** croppr vendored, the hook, the hidden fields, the
    previews, `square_webp/4`, the wiki's Social and Settings pages.
