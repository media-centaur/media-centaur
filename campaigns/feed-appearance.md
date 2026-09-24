---
status: planning
started: 2026-09-24
last_updated: 2026-09-24
---
# The Feed's appearance: telling authors apart

## Goal

Consider the whole look of the Feed, with two things it must do better
than it does today: a reader should tell their own rows from friends'
at a glance, and tell one friend from another. The scope work of
2026-09-24 (UIDR-045) put every author on one row anatomy and marked
an own row with the word You alone; that was the coherent minimum, and
the owner finds it too quiet. This campaign is a design conversation
first, code second: diagnosis, mockups in distinct directions, then a
decision on which standing rules to amend.

## Glossary

Existing terms are in [`docs/GLOSSARY.md`](../docs/GLOSSARY.md): *Feed*,
*feed row*, *Scope*, *Author*, *Action*, *Review*, *Listing*, *Pennant*.
This campaign adds:

* **Author mark** — whatever visual device says who wrote a row, beyond
  the name itself. Today it is the word You in the primary colour on an
  own row and nothing on a friend's. The thing this campaign designs.
* **Own mark** — the author mark for the reader's own rows.
* **Friend mark** — the author mark that tells one friend from another.
  Candidates are named in Next steps; none is chosen.
* **List surface** — the one inset glass container the rows sit in,
  with a hairline between rows (Watch History's idiom).
* **Row anatomy** — poster, three text lines, time column, toolbar seat
  (UIDR-038, amended by UIDR-045). Every author shares it.

## Status

Planning. Nothing started. The shipped Feed (commits `496546cf..c26cee28`
on `main`, 2026-09-24) is the starting point; the owner has asked for the
look to be reconsidered in full.

## Standing rules this campaign will have to face

Each of these is a recorded decision that a stronger author mark may
contradict. None is overridden by this file; each is amended, kept, or
superseded by the design this campaign produces, and the record says so.

* **UIDR-045 rule 3** — an own row differs by the word You, in the
  primary colour, and the second-person verb; no border, tint, marker or
  badge. The owner's ask reopens this rule directly.
* **UIDR-038 anti-patterns** — *state as decoration* (badges, chips,
  markers on the body) and *social-network chrome* (avatars, handles).
  A friend mark that is an avatar or a chip collides with this.
* **House rules on colour** — colour is signal: the health palette, the
  primary for interaction, rose for Love, nothing else. A per-friend hue
  collides with this and with the standing objection to a chip palette;
  edge or accent bars are rejected outright.
* **UIDR-037** — friend provenance is the pennant on every title surface
  but the Feed. A friend mark on the Feed must not become a second
  provenance idiom with its own words.

## Decisions made

* `2026-09-24` — Campaign opened at the owner's request, immediately
  after UIDR-045 shipped. Design conversation first; no code until a
  direction is chosen and the affected records are amended.

## Next steps

1. **Reconcile.** Owner looks at the shipped Feed on the dev server under
   Everyone with the real roster; name what is hard to tell apart and at
   what roster size (three friends today; design for thirty).
2. **Diagnose before drawing.** Why the word alone reads as too quiet:
   the name is the smallest text on the row, the same weight for every
   author, and every row shares one tint. Write the diagnosis into the
   spec's Problem section before any mockup.
3. **Mockup round, distinct directions**, with the visual-designer skill
   and the round-3 brief as the base
   (`docs/superpowers/specs/2026-09-24-feed-timeline-scope-mockups/BRIEF.md`).
   Candidates to draw, each a different device, each argued against the
   standing rules above:
   * a monogram tile per author (an initial in a neutral tile) in the
     poster column's gutter or replacing the row's left edge;
   * a stable per-friend hue applied to the name only, derived from the
     public key, with You keeping the primary;
   * own rows on a distinct surface tone or indent, friends' rows plain;
   * typographic weight and size for the name, no colour, no tile;
   * grouping consecutive rows by the same author under one name line
     (a change to UIDR-038's "one entry per action, flat").
4. **Decide the records.** Choose a direction; write the spec and a UIDR
   that amends UIDR-045 rule 3 and, if an avatar-like or hue device is
   chosen, UIDR-038's anti-patterns and the colour rule, stating the
   exception precisely.
5. **Plan and implement** through the usual test-first plan; the row
   component's story pins every author state.
6. **Then the Feed's hardening pass**: nav zones for the rows and the
   scope pill, once the layout stops moving.

## Follow-ups inherited from the feed timeline scope work

Each carries a note on whether it still applies once this campaign is
done. Close or re-home them at this campaign's completion.

* **Status drill-in walks the window pill with Down.** The drill-in is a
  vertical MENU context, so the strip chart's options (now nav items)
  walk vertically and the drill-in enters on the chosen window. A
  Right-walk needs the zone's context type changed in
  `assets/js/input/config.js`, never an opt-out on the component.
  *Unrelated to the Feed's look; still applies.*
* **Feed rows and the scope pill are mouse-only.** No nav zones until
  the hardening pass. *Still applies; sequenced after this campaign
  (step 6), since nav wiring is per-geometry.*
* **The wiki's Keyboard-and-Gamepad page has no Status-page section.**
  *Unrelated; still applies.*
* **Incoming and Home hand-roll query strings** where the route sigil
  would do (`incoming_live.ex`, `home_live.ex`). *Unrelated; still
  applies.*
* **Friends card's Recently watched tiles grew at the 896px column**;
  check the 240px derivative at 2× scale. *Re-evaluate at close: this
  campaign may change the column or the Friends tab's cards.*
* **Feed → Watchlist → Feed through the tabs resets the scope to
  Everyone** (the tabs navigate to fresh mounts; the sidebar returns to
  the last scope). *Behaviour, not appearance; still applies unless
  this campaign changes tab navigation to patch within the page.*
* **Storybook sample poster path `/images/sample-nosferatu-poster.jpg`
  does not exist**; several stories show a broken image. *Unrelated but
  in the way: fix early in this campaign's story work.*
* **The user-interface skill's UIDR-042 row still says "Track release
  dates"**, the old switch label. *Unrelated; still applies. Check
  UIDR-042's own wording first.*
* **A listing row's two lines sit at the top of the row**, level with
  the poster's top edge (the spec was corrected to say so). *Appearance;
  absorbed here. The row design decides whether they centre.*
* **Row type sizes grew** (line 1 to 15px, title to 16px, poster to
  56×84) without the spec naming the sizes. *Appearance; absorbed here.
  The spec this campaign writes names every size.*
* **Library's type tabs changed ARIA semantics** from tablist/tab to
  group/aria-pressed when they moved onto the shared control; correct
  for a filter, but recorded nowhere user-facing. *Unrelated; still
  applies as a one-line note wherever assistive-technology behaviour is
  documented, if anywhere.*

## Completion criteria

* A reader can name the author of any row without reading the name, at
  a roster of thirty, in a browser check the owner performs.
* Own rows and friends' rows are distinguishable at a glance under
  Everyone; the You and Friends scopes remain useful, not necessary.
* The spec names every size, tone and device on the row; the story pins
  every author state; the records amended are listed with the exception
  each carries.
* Every inherited follow-up above is closed, re-homed, or restated with
  its reason for staying open.

## Pointers

* [`docs/superpowers/specs/2026-09-24-feed-timeline-scope-design.md`](../docs/superpowers/specs/2026-09-24-feed-timeline-scope-design.md) — the shipped design this campaign starts from, and its mockup rounds.
* [UIDR-045](../decisions/user-interface/2026-09-24-045-own-actions-join-the-feed-under-an-author-scope.md), [UIDR-038](../decisions/user-interface/2026-09-11-038-the-feed-is-friends-actions-one-entry-each.md), [UIDR-037](../decisions/user-interface/2026-09-08-037-friend-provenance-is-the-pennant.md).
* `lib/media_centaur_web/components/discovery/feed_entry_row.ex`, `lib/media_centaur_web/live/discovery_live/feed_entries.ex`, story `storybook/discovery/feed_entry_row.story.exs`.
