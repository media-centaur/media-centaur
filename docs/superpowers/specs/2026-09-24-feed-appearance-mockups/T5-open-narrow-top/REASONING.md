# T5 · Open rows, 1500, the two notes — reasoning

**Knobs** T4's (surface `open`, width `narrow`, poster 100, logo none) plus acts `centred` · align `top`. The owner's notes on T4, which they liked most.

## Style

T4 with two changes. In the rail, the act glyphs over a poster are centred
as a group: one act in the middle, two as a pair with a 4px gap, three
where the slots had them. In the row, the tile and the poster hang from
the row's top line with the words instead of centring in the row.

## Decisions

* **Centred glyphs, amending the fixed slots.** UIDR-046 put the three
  acts in fixed positions so every glyph is found by its place — a scan,
  not a read. The owner's eye read a lone bookmark at the poster's right
  edge as off-centre, and that is what it is on every one-act poster,
  which is most of them. Centring trades the fixed position for balance;
  the order within a group (opinion, eye, bookmark) is kept, so a pair
  still reads in the same sequence.
* **The tile at the top.** Every text row with an avatar hangs the avatar
  from the first line — the person card does, and so does every list the
  reader knows. Centring the tile was the band's choice, where it stood
  beside a 224px picture; on a text row it floats. The poster hangs from
  the same line, so the row's three columns share one top edge and the
  remaining space falls to the bottom, as in a media object.

## Requirements

* *The icons centred over the poster* — done, as a group.
* *The tile aligned near the top like the friends' card* — done; the
  poster follows it.
* *T4 liked most* — T5 is T4 with nothing else moved.

## Trade-offs

Gains: the rail's glyphs sit where the eye expects them; the row reads
top-down like every list. Costs: the fixed-slot scan is given up — a
reader can no longer find "the eye" at one x on every poster; a row
without a review leaves more space at its foot than its head. In the app:
the act-slots strip becomes a centred flex row (the slot positions go),
`--x1/--x2/--x3` are deleted from the person card, and the band's tile and
poster take `top: var(--pad-y)`.
