---
status: accepted
date: 2026-09-28
---
# A person's colour is a hue on the app's ring

Extends UIDR-046 rule 2 and UIDR-047 rules 2–4 (the identity tile, the Settings profile card, the card foot). Design: `docs/superpowers/specs/2026-09-27-profiles-design.md` § Phase 5. Wire: ADR-073, amended 2026-09-28.

## Context and Problem Statement

Every person's circle is the primary blue, so a Feed of eight friends is eight blue tiles told apart by a letter. The owner asked for a colour a person chooses for their circle, from a set that matches the app's scheme, with a custom choice beside it, and the reader's own choice over it. The app's standing rule is that colour is signal — health and severity — and this is a deliberate exception for people, who are not statuses. The question was how to let a person choose without a free colour that fights the dark slate theme or a letter that disappears on its own tint.

## Decision Outcome

Chosen option: a **hue**, not a colour. One ring in oklch — lightness 70 %, chroma 0.15 — and the person picks the angle. The palette is eight named angles on that ring; **Custom** is any other angle on the same ring, from a slider whose track is the ring. On the wire the profile carries the angle as an integer, and a reader draws it at its own theme's lightness and chroma.

1. **One recipe, the hue where primary was.** A friend's letter or glyph in the hue on the hue at 20 % with a hairline ring; the reader's own filled in the hue with a near-white mark; a picture inside a 1 px ring in the hue for a friend and a 2 px one for the reader's own. Own-ness stays weight, as UIDR-046 drew it. A person with no hue is Blue 250, the primary's angle, so today's look.
2. **The reader's colour for a friend, in order**: your override, then their published hue, then Blue. The same order as the name.
3. **One swatch row everywhere a hue is chosen**: the palette, then Custom. On a friend's card foot it leads with **Theirs**, the friend's published hue, selected while there is no override; a swatch saves on the act. On Settings → Your profile it sits between the picture and the name; Save publishes it. A new profile's form starts on a random palette hue; a saved hue loads as saved.
4. **Nothing is invented.** A person who published no hue is drawn in the default, not in a hue derived from their key: a card says what was published, and a derived colour would change the day they chose one.

### Consequences

* Good, because every colour on the page is on one ring beside the theme's slate, so eight friends read as eight colours without a rainbow of unrelated tints, and the letter's contrast is constant by construction.
* Good, because the wire carries a choice, not a rendering; a reader with a lighter theme draws the same angle lighter.
* Good, because the reader keeps the last word on a friend's colour as on their name and picture.
* Bad, because a person cannot publish a colour off the ring — no navy, no pastel, no grey — and the custom choice is a hue only.
* Bad, because two friends who both chose Blue, or never chose, are two blue tiles again, told apart by the letter as today.

## Anti-patterns

* **A free colour picker**: a dark or pastel pick on the dark ground, and a letter whose colour has to be computed from it.
* **A colour from the key**: a hash-derived hue is a choice the person never made.
* **Colour as status on a person**: the tile is not a health dot; a Green friend is not healthy and a Rose one not in error. Health keeps `success`, `warning` and `error`; the tile keeps the ring.
* **Two recipes**: a primary tile for a person with no hue and a ring tile for one with. One recipe with a fallback.
* **A hex colour on the wire**: the app converting to and from oklch, and clamping to the ring, on both sides of every profile.
