# Round 9 brief — the Friends page, breathable and poster-led (2026-09-25)

Round 8 (`BRIEF-8.md`, `CRITIQUE-8.md`) settled the Feed: the owner
says it is "really improved". This round is the **Friends tab only**.
The owner's note on `G-friends-page`: "the friends tab could take up
more space per friend and make each friend entry more breathable. We
should leverage poster images more on this page and cut back a bit on
the text; it's a bit busy."

Read that as three instructions:

1. **More space per friend.** A card is a place, not a row. Widen it,
   give it air, and let the posters set its height.
2. **Posters carry the card.** The Recently watched strip is the card's
   picture, at a size that reads from the couch (each poster at least
   120×180; the strip is the widest element on the card). A friend who
   shares no watches has no strip and a shorter card — not a placeholder.
3. **Less text.** Keep only what a poster cannot say: the name, the
   presence line (one line, the latest act), the sharing note when it
   applies. Drop the *Wants to watch* and *Reviewed* text rows from the
   card face — those lists belong on the person (open the card) and the
   Feed already carries them as bands. The key, the "added" date and
   Remove friend leave the card face too: they are management, and live
   behind the card (say where: a quiet "Manage" on the card, or the
   person's own view). Add a friend stays at the foot.

Also from `CRITIQUE-8.md`: the strip gets a **"Recently watched"**
caption (18px/66%) so its posters are never read as reviewed titles;
the sharing note and the You subtitle share one slot; and the page fills
its width with a **grid** at 1920 — two columns, one below 1500 — with a
row-major nav (Left/Right within a row, Up/Down across rows), which the
input system already handles for the Library grid.

## Couch floors

As `BRIEF-7.md`: name ≥ 24px here (the card's one confident line),
presence line ≥ 22px, note and caption ≥ 18px, tile 64px on this page,
posters ≥ 120×180, 32px targets, a 3–4px cursor ring, the half-size
check.

## The card, top to bottom

- **Head**: the identity tile (64), the name (24px semibold), the time
  of the latest act (18px) at the right.
- **Presence line** (22px): the latest act of any kind in the Friends
  card's vocabulary — the one definition of presence, shared with the
  rail. The sharing note ("Doesn't share watching") or the You subtitle
  ("How friends see you") in one 18px slot under it.
- **Recently watched** (caption 18px/66%): up to five posters at
  120×180 (or four at 140×210 — choose by render) with the "all N"
  tile, only when the person shares watches. This is the card's
  picture; give it the card's full width.
- Nothing else on the face. The card is a nav item; its cursor state is
  the 3–4px ring.

The **rail's card** (in `G-couch-feed`) stays as it is except the
caption and the shared note slot; note in REASONING every value this
page shares with it (tile states, name weight, presence line, caption
wording, poster radius) so the component stays one at two widths, and
every value that differs (tile 64 vs 48, name 24 vs 22, posters 120×180
vs 72×108, the page's grid).

## States, in order

1. The Friends tab at 1920: the strip (Friends active), no rail; a
   two-column grid; You first (own tile, reviews-only, "How friends see
   you" in the note slot); then Cleo (shares watches, five posters +
   all 9), Nick (reviews and listings, "Doesn't share watching"), Bob
   (watches, three posters), Sam (listings only), Ada (reviews only,
   photo tile), Femi (watches, one poster and a no-artwork slot), Theo
   (nothing shared); Add a friend at the foot spanning the grid's
   width. Say how thirty friends page (all on the page, in latest-act
   order, or a window with Show more).
2. The same at 1280 (one column).
3. Nick's card under the cursor ring, with the cursor idiom for a grid
   (Right from Nick goes to the next card in the row; Down to the card
   below).
4. Where management went: the card's "Manage" state or the person's
   view — draw it once, small, with the key, the added date and Remove
   friend.

## Deliverable

`H-friends-page/index.html` linking `../base.css` and `../art/`, and
`H-friends-page/REASONING.md` (under 1000 words): the size table; what
was cut from the face and where it went; the grid and its nav; the
shared and differing values against the rail's card; the 10-foot
check; the rules touched (UIDR-038 rules 7–10, each exception stated);
the one thing you are least sure of. Render with `page-shot` to the
scratch folder at 1920 (three passes), the half-size check, and 1280;
nothing outside your folder; no git, no mix.
