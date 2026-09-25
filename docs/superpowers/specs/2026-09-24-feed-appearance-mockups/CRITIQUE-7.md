# Round 7 critique — the couch, and the Friends rail

Morning of 2026-09-25. Three pages rendered at 1920 (the TV's
composition), at half size (the couch), and at 1280 (a narrow window).
Two questions: does the couch scale work, and does the owner's Friends
rail beat full width once both are at that scale.

## The couch scale works, and it changes the band

All three pages pass the half-size check: the sentence, the title, the
time and the tile's letter read at 960×540, which is roughly a 65"
panel from three metres. The floors cost about half the rows per fold
(the lead and two bands, against the lead and four at desk scale) and
that is right for a couch. Two things the re-scale changed that the
desk rounds could not see:

- **The band's picture becomes a picture.** At 220–236px tall the
  900px box shows 47% of the still (F showed 30%), and a 536px box
  beside a rail shows 70–74%. The strip that made direction 1
  "cinematic" is now a photograph on every band, and the fixed 30%
  crop lands the subject on every still rendered. The measured crop
  rule holds at every height this round used.
- **Full width stops looking wasted once the type is couch-sized.**
  R2's 1820px bands carry a 120×180 poster, 22px words and a 900px
  picture; nothing on them is air. The owner's "wasted space"
  objection was made against desk-scale bands, where a 15px sentence
  sat in 560px of ink beside a strip. The question is no longer
  whether the width is wasted but what it is spent on: picture (R2)
  or people (R1, R3).

## The three pages

**R2 · full width, no rail.** The purest cinema: the lead and two
bands per fold, each band a 900px photograph. The lead at 940×404 is a
76% slice, a near-complete still, so the lead is now less dominant
than the bands are cinematic — R2's designer would start its box 300px
earlier to restore the front-page feel. Nothing on the page says who
is around. This is the page if the rail proves thin.

**R1 · feed column beside the rail, the lead at the column's width.**
The feed at 1236px beside a 560px rail of 108px rows: tile, the poster
of the person's last watched title, name, an `ActivityWords` presence
line, the time. Eight people in the fold, You first, "Manage friends"
at the foot; at 1280 the rail folds into a Friends tab whose page shows
the same rows in two columns. Its costs: the lead's picture reaches no
further right than a band's (its designer's own doubt: "whether the
lead is enough of a lead at 1236"), and the rail's row carries two
facts when the person's latest act is not a watch (Nick reviewed
Charade beside a Caligari poster), which reads as a mismatch.

**R3 · the lead spans both columns; bands beside the rail below it.**
The masthead lead at 1820×388 (a 75% slice — Sintel and the dragon in
the clear) keeps the page's dominant element; below it the feed column
at 1236 sits beside the rail. The rail's rule is cleaner than R1's:
**a row is the person's latest watch**, the fact the Feed excludes by
rule, and its poster is that title, so a row is one fact; the card's
presence is the fallback when a person has shared no watch. That also
answers the same-person-twice case by construction: when the lead is
your review, the rail's You row is what you watched. At 1920 the tab
strip is Feed · Watchlist and "Friends" is the rail's heading; below
1700px the rail folds into a Friends tab. Its costs: four people in the
fold instead of eight (the masthead takes the first 388px), rows at
132px where R1's 108px were enough, and a layout with three regions
where R1 has two.

## Verdict

**Take R3's structure.** The masthead keeps the one thing the feed
needs from Home, a dominant element per screen; the rail beside the
bands spends the width on people, which is what the owner asked the
width for; the rail's one-fact rule is the honest version of "what
they've been watching". Refine it with two things R1 did better: the
rail's row density (108px: tile, poster, name and time on one line,
one presence line) so six to eight people sit in the fold under the
masthead, and R1's fold-to-tab page for narrow windows (the same rows
in two columns).

**Not R1**, because its lead is a taller band, and a page whose
newest action is not visibly the newest loses the front page. **Not
R2**, unless the rail proves thin: with three friends today the rail
is four rows and a link, which is honest ("who's around") but small
beside a 1236px feed. That is the one thing to watch on the real
roster.

## What the rail settles and what it opens

Settled by this round: the rail is presence, one row per person,
ordered by latest activity, You first, bounded by the roster, never
paged — not a timeline, so not the wall of watching; the roster's
management lives behind "Manage friends"; the rail ignores the scope
pill; it scrolls with the page in one scroll region, which a gamepad
wants.

Opened, for the record that follows:

1. **What a rail row opens.** Today's Friends card holds the Recently
   watched strip, the text rows, the key and Remove. The coherent
   answer is that `/discovery/friends` stays a route at every width,
   showing the full cards; the tab strip lists it only below the fold
   width; "Manage friends" and a rail row go there (a row scrolled to
   its person). A route without a tab at wide widths is unusual and
   should be said in the record.
2. **Two nav graphs.** Above 1700px the page has a feed column and a
   rail; below, three tabs. The hardening pass wires both; the
   container query decides which zones exist.
3. **The presence word.** R3's rail defines presence as the latest
   watch; the Friends card defines it as the latest act of any kind.
   One definition: the card should adopt the rail's (a person's
   presence is what they are watching; what they said is the Feed's).
4. **UIDR-038 rules 7–10.** The Friends tab's card rules become the
   rail's at wide widths and the card's below; rule 10 (the You card as
   the audit view) is already the You scope's job since UIDR-045, and
   the You row's subtitle names the mirror.

## The couch floors are a house rule

Nothing here is specific to the Feed. Read text ≥ 22px, secondary ≥
18px, titles ≥ 28px, tiles 48–64px, 32px targets, a 3–4px cursor ring,
4.5:1 over imagery, the half-size check — these belong in the
`user-interface` skill and in a record, and every surface the app
composes should be judged by them. The Feed is the first page designed
under them; Home, Library, Incoming and Settings have not been.

## Next

Round 8, if the owner agrees: one assembled couch page — R3's masthead
and rail with R1's row density and fold page, all fourteen Feed states
plus the rail's, the Watchlist with the rail — replacing F as the
proposed page; the spec's "What the user sees" and the draft plan
re-derived from it (the plan's phases 3 and 4 change: the band grows,
the page gains a rail and a fold width; the identity tile gains its
48px rail size).
