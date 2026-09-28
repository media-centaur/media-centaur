---
status: accepted
date: 2026-09-27
---
# What a reader sees of a person: their published name under your override, or Unnamed

Extends UIDR-046 rule 2 (the identity tile). Design: `docs/superpowers/specs/2026-09-27-profiles-design.md`. Architecture: ADR-073, ADR-074.

## Context and Problem Statement

Until now a friend had only the name the reader typed, and the reader had none. With a published profile (ADR-073) a person can have a published name and an avatar, the reader can still prefer their own word for a friend, and a picture from a friend is something the reader may not want to see.

## Decision Outcome

1. **A person's name, in order**: your override, then their published name, then **Unnamed**. The reader's own is **You** everywhere but Settings. One function renders the words and every surface calls it: Feed rows, person cards, the pennant's label and tooltip, the attributed words under a hero.
2. **The tile's three marks**: the avatar when there is one and it is not hidden, inside a neutral ring for a friend and a 2px primary ring for the reader's own; else the name's first letter; else the person glyph. The own tile keeps UIDR-046's fill and white mark under the letter and the glyph.
3. **Settings → Social opens on Your profile**: Name, required to save; Avatar, optional, with Choose and Remove; the button creates the profile and, with it, the identity. Your identity (npub, secret key) appears below once one exists, then Relays and Sharing. Nothing is minted by opening the section.
4. **Add friend** takes an npub and an optional name, the override. The opened card's foot carries the override field, with the published name or Unnamed as its placeholder, the **Show avatar** switch on by default, then the key, the added date and Remove friend.
5. **A card says what was published.** An Unnamed friend is Unnamed; no note says a profile is missing, no note says an avatar is hidden.

### Consequences

* Good, because the reader keeps the last word on a friend's name and picture, and the network has one at all.
* Good, because a nameless person is drawn without inventing a letter.
* Bad, because two friends who never named themselves are two Unnamed tiles, told apart by the glyph alone until an override is set.

## Anti-patterns

* **A literal on the wire** for a missing name.
* **A letter from "Unnamed"**: a U in the tile.
* **The npub as a name**: a key is not what a person is called.
* **A sharing note**: "hasn't set a name", "avatar hidden".
* **A global avatar switch**: the choice is per friend.
* **The identity before the profile**: an npub shown with no name behind it on the Settings path.

**Amendment 2026-09-28.** As built, the switch in rule 4 reads **Show their picture**, not "Show avatar": user copy says *picture*; *avatar* is the word in code and on the wire (`docs/GLOSSARY.md`). Rule 3's Choose is a file input taking one JPEG, PNG or WebP up to 10 MB; the save makes a 256×256 WebP master with the photo's metadata stripped, and Remove steps aside while a file is chosen. The switch is `Components.Switch`, shared with the Settings row and the title tracking block.

**Amendment 2026-09-28 (phase 5; UIDR-048).** Rule 2's tile draws in the person's **hue** — the reader's override, else the published one, else the primary's Blue — with one recipe: a friend's mark in the hue on the hue at 20 %, the reader's own filled in the hue, a picture ringed in it (1 px for a friend, 2 px for the reader's own). Rule 3's card is two columns from the Settings kit's stacked fields (UIDR-041): **Picture** on the left (the tile, *Choose picture*, Remove; the cropper with its preview, *How it will look*, while a picture is chosen), **Name** and **Colour** on the right (the swatch row, starting on a random palette hue for a new profile), Save in the form's footer at the right, as every kit form; the name field is 16 rem. Rule 4's foot gains a Colour row after *Show their picture*, leading with **Theirs**, saving on the act; its rename field takes the name field's width.
