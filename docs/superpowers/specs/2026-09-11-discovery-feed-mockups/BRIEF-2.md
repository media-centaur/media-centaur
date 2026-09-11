# Round 2 brief — noise out, toolbar in (2026-09-11)

Supersedes BRIEF.md where they differ. Round 1 chose direction 3's idea
(a recommendation with a note unfolds; everything else is one line) and
then stripped the entry further. Read the round-1 mockup
`3-two-weights/index.html` for tone, but the anatomy below is new.

## Vocabulary changes

* **Action** (not "act"): what a friend did — a recommendation, or wants
  to watch. Sentence voice: "Nick recommended", "Cleo wants to watch".
* **Verbs**: the controls a reader can use on an entry. They live in the
  **toolbar**, never on the entry body.

## What an entry shows, and nothing else

1. **Name** — the friend's nickname, medium weight.
2. **Action** — the verb. Like = plain "recommended". Love = "recommended"
   followed by a small rose heart (`var(--love)`), the ONE colour on the
   page. "wants to watch" has no glyph.
3. **Title identification** — poster, title name, year. No type badge, no
   overview/synopsis, no markers ("In library" etc.), NO PENNANTS anywhere
   on the feed.
4. Relative time, quiet.
5. The note, when there is one (recommendations only), as what the person
   said. Long note: clamp at 4 lines.

## The toolbar

A row of quiet text/icon controls that appears ONLY while the entry is
hovered or holds the keyboard/gamepad cursor (the app's existing Ignore
idiom, widened to a bar). Bluesky's action bar is the model for its
placement and for "state and verb are one control". Contents, in order:

* **List** — bookmark icon + word. Toggles the title onto your watchlist.
  Filled/solid when the title is on your list ("Listed"). When the title is
  higher on the ladder (Follow+) it is not a toggle: reads "Following".
* **Download** — arrow-down icon + word. Replaced by plain state text when it
  no longer applies: "Downloading" (with a tiny 3px progress hairline under
  the word), "In library".
* **Ignore** — word only, last, right-aligned or after a gap. Hides every
  entry for the title; toast offers Undo (not shown).

Rest state: the toolbar's space is NOT reserved in a way that makes entries
jump on hover — either reserve a fixed-height strip that is empty at rest,
or overlay the bar in the entry's bottom padding. Say which you chose and
why in REASONING.md. Show at least these states: rest; hovered with the
toolbar; cursor (keyboard) on the entry with the ring; cursor on one
toolbar item (ring on the item); a toolbar where Download reads
"Downloading"; one where it reads "In library"; one where List is filled.

Whole-entry click still opens the title modal (not shown). The name is not
a link.

## Data (same eight entries; markers now expressed via toolbar state)

1. Cleo wants to watch Sample Show (2024) · 12m ago
2. Nick recommended ♥ Movie A (2026) · 2h ago · note: "Saw it twice. The last twenty minutes are the whole film."
3. Nick wants to watch Movie A (2026) · 2h ago
4. Bob recommended Show B (2021) · 1d ago · note: "Slow start, give it three episodes." · title is In library (show this one hovered → toolbar with "In library")
5. Sam wants to watch The Long Field (2025) · 3d ago · title is on your list (show hovered → List filled)
6. Nick recommended Sample Show (2024) · 6d ago · no note
7. Cleo recommended Show B (2021) · 1w ago · note: "Fine."
8. Bob wants to watch Harbor Lights (2023) · 2w ago · title is Downloading (show hovered → "Downloading")
Then "Show older".

Then, under a small state label as the round-1 mockups did: entry 2 with the
keyboard cursor on the entry; entry 2 with the cursor on "List".

## House rules — unchanged from BRIEF.md

Dark slate, glass, system fonts, calm, no chips, no accent bars, no
animations beyond a 120ms opacity fade, no real titles. Poster thumbs are
the `.thumb` gradient; keep `--h` per title consistent across entries
(Sample Show 350, Movie A 200, Show B 264, The Long Field 140, Harbor
Lights 60).

## Deliverable

`index.html` + `REASONING.md` (style, decisions, requirements mapping,
trade-offs, how it holds at 30 friends, and a paragraph on whether losing
the pennants loses the "Cleo agrees" signal and whether that matters).
