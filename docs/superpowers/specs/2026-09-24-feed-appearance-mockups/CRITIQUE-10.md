# Round 10 critique — the ground, the edges, the still

Rendered 2026-09-26 at 1920×1080 and read at half size on
`Q-switchboard/compare.html`, with today's page beside them. Every
direction is G's page under `round10.css`; the band's anatomy did not move
in any of them, so the comparison is tonal and structural only.

## What the reference showed

With the app's ground reproduced layer for layer, the "today" cell matches
the owner's screenshot: ink units at 13% on a ground that is 27% under the
blue blob at the top and only reaches the ink's neighbourhood two thirds of
the way down. The earlier rounds' `base.css` ground (one radial, 28 → 17%)
had been kinder to the design than the app is. The root is the inversion —
a unit darker than its page reads as a hole — and every direction fixes it
from one side or the other.

## The six, scored

| | Boxes gone? | Presence | Readability | Change in the app | Verdict |
|---|---|---|---|---|---|
| **Q1 Dark sheet** | Yes — nothing to show against; two columns | As G | As G | A scrim variant; the sheet rules; two hairlines | Sound. The safe answer. |
| **Q2 Film strip** | Yes — one dark page of pictures | Highest | Words on a faint picture; the shadow works | The still's origin and scrim; an ink page; sheet rules | The "holy crap" candidate; soft where dark stills meet |
| **Q3 Open rows** | Yes — nothing enclosed | Lowest | As any app page, no shadow | Grounds off; scrim off; sheet rules | Coherent, but a dark still on the blue-grey ground leaves a soft hole |
| **Q4 Glass list** | Two panels instead of eight units | Low | As Settings | Glass on the columns; grounds off | The house answer; a card again at column scale |
| **Q5 Matched cards** | Mostly — the seams remain | As G | As G | One scrim variant | Least change, least effect; the rail still reads as cards |
| **Q6 Dark sheet, wide still** | Yes — as Q1 | High — faces at 48% | As Q1 under the words | Q1's rules plus the still's origin and scrim | **Recommended** |

## Findings by knob

* **Ground.** *dark* (the app's ground with the dim from the top, ≈15%) is
  the right darkening: the blobs survive as a whisper and the page still
  belongs to the app. *ink* (flat 13%) is purer and loses them; the
  difference shows only above the fold. *app* keeps today's ground and
  needs the unit to give up its ink (Q3, Q4) to work.
* **Edges.** *sheet* is what makes a dark ground sufficient; on *cards*
  the 6px gaps stay visible as lighter seams wherever a blob shows through
  (Q5), most of all in the rail. The hairline earns its keep where two dark
  stills meet; stopping it at the picture's edge keeps it off the
  photograph.
* **The still.** *wide* (836, a 48% slice) is the find of the round: the
  frame is drawn larger, every fixture still frames its subject at the
  settled 30% crop, and the words keep ≥ .86 ink. *full* (1236, 32%)
  renders more picture and cuts faces — Sintel's forehead, Cary Grant
  gone — so it stays a knob, not a preset. *box* is the settled 74% slice
  and remains right for the open and glass units, which have nothing to
  put words on.
* **Tone.** Lifting the unit (16, 19%) instead of darkening the page
  reduces the contrast from the wrong side: the words lose ground and the
  boxes only fade. Kept as a knob for the owner to confirm.
* **Dissolve.** 360 helps only the open rows, where the still fades into a
  lighter ground; on ink 240 is right.

## Recommendation

**Q6** — Q1's page (the dark ground, the flush columns, the hairline across
the words) carrying Q2's wider still. It removes the boxes by the same
mechanism as Q1 and adds the one thing Q2 had over it: a frame drawn large
enough to read from the couch. Q2 is the alternative if the owner wants
the flat ink page and the reel with no hairlines; Q1 if nothing about the
still should move.

Q3 and Q4 are honest options that keep the app's ground, and either would
be right for a page that was not meant to be cinematic. The Feed was. Q5 is
what to do if the settled cards must stand.

## In the app, for whichever is chosen

All of it is CSS on `.feed-band`, `.feed-column`, `.person-card`,
`.discovery-rail` and a Discovery variant of `.page-side-dim`; the DOM
contract and the page tests are untouched. The story's variations pin the
new band and card at rest and under the hover pin. The spec's size table
gains the still's origin and the scrim's stops; UIDR-046 records the ground
and the sheet.
