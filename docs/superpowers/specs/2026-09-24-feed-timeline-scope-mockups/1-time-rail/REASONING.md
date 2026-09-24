# 1 · Time rail — reasoning

## Style

One 880px column. A 1px rail at 14% alpha runs down the left of the feed from
the scope pill to the last entry. Every entry hangs from an 8px marker on the
rail with the relative time beside it (`12m`, `1h`, `3d`, `2w`) at 12px/55%.
The entry itself is the round-2 poster-left glass card, slightly stepped up
for 1920: poster 56×84, sentence 14px, title 15px semibold, review 13.5px at
68%, 14/18px padding, 8px gap. Own entries fill their marker in the primary
colour; friends' markers are a hollow ring at 55%. The scope pill is the head
of the rail. Dark slate, glass, system fonts. Colour only where it signals:
the rose heart, the primary marker, the primary ring, the pill's lifted
option.

## Decisions

1. **The time leaves the card.** Line 1 is now only the sentence: "Cleo wants
   to watch", "You reviewed ♥". The time sits on the rail beside the marker,
   so the card carries who did what to which title, and the rail carries
   when. Two questions, two places.
2. **`12m`, not `12m ago`.** On an axis "ago" is the axis; repeating it beside
   every marker is noise, and it would triple the rail column's width.
3. **The rail is drawn per entry, not once.** Each rail column draws its own
   segment above and below the marker, so the rail is exactly as long as the
   entries: it ends at the last marker when there is nothing older (You, 3
   entries) and runs on and fades under "Show older" when there is. The end
   of the rail says whether the window is the whole story.
4. **The hollow marker breaks the rail.** A ring with the hairline passing
   behind it reads as a dot with a line through it; the segments stop 3px
   short of the marker on both sides.
5. **Marker on line 1's centre**, not the card's centre. Entries vary in
   height (a review adds a line); a marker at the top edge keeps the rhythm
   regular whatever the card holds, and the time sits on the sentence's line
   where it used to be.
6. **Own = a filled marker, nothing else.** "You" is set like any other name.
   The marker is on the axis, outside the entry, so the entry body stays free
   of any mark (see the UIDR-038 argument below).
7. **The scope pill is the rail's head.** It sits at the column's left on the
   tab strip's line and the rail emerges from under it; the page tabs move to
   the right end of that line (see *Where the scope control sits*).
8. **"Show older" hangs where the next entry would**, left-aligned beside the
   fading rail, rather than centred: it is the next node, not a page footer.
9. **The empty You state has no rail.** Nothing hangs, so nothing is drawn;
   the pill stands alone and the message sits where the first entry would.
10. **Per-title state is consistent across entries.** Movie A shows Listed ·
    In library on the own review and on Nick's two entries; Show B is In
    library on both Bob's and Cleo's; Harbor Lights is Downloading on Bob's
    listing and on the own review; The Long Field is Listed on Sam's entry
    because the own listing three days ago is what put it there. The slots
    show the title's state, and the title is the same title.

## Requirements mapping

| Brief item | How it is met |
|---|---|
| Own actions join the feed, interleaved by time | Entries 2, 6, 8 are own; they sit in time order among friends' in Everyone. |
| Watched stays off | No "watched" verb anywhere. |
| Author scope: Everyone · Friends · You | The house `.seg` pill, Everyone lifted by default. |
| Tab count follows the scope | Feed 11 / 8 / 3 / 0 across states 1–4. |
| Presence at 1920 | 880px column, larger poster and type, the rail as a second vertical. |
| Line 1: name, verb, glyph, separator, time | Name (500) + verb + glyph. The separator and time are gone from the line: the time is on the rail, which is this direction's defining move. |
| Glyphs: heart in `--love`, thumbs up/down, x-height, in the run | Inline SVG symbols (heroicons paths, the app's own choice), 13px, `inline-block; vertical-align: middle`, so they centre on the x-height instead of standing on the baseline. Heart `currentColor` = `var(--love)`. |
| Line 2: title semibold, year beside | `.l2 b` 15px/600 + `.y` 12.5px/55%. |
| Line 3: review clamped at 4 lines | `.l3` with `-webkit-line-clamp: 4`. |
| Poster left | `.thumb` gradient, 56×84, per-title `--h`. |
| Second person for own entries | "You reviewed", "You want to watch". |
| Toolbar: fixed seat, hover/cursor only, no height change | `.bar` is a 20px row always in flow with `opacity: 0`; 1 on `:hover`, `.cursor`, `:focus-within`, 120ms opacity. |
| Friend toolbar: List · Download · Ignore last | `.v` List (hollow bookmark), Download (arrow), `.v.last` Ignore pushed right. "Listed" filled when on your list; "In library" / "Downloading" (3px hairline) as plain state in the Download slot. |
| Own toolbar: same slots, Delete in Ignore's seat | State 6: Listed (filled) · In library · Delete. |
| Whole-entry click; names not links | The card is the click target; names are plain spans. |
| Own mark: no chips/badges/bars/avatars/alternation | The filled marker on the rail is the only mark; "You" is not coloured. |
| Scope control placement | Head of the rail, tab strip's line. |
| State 1 Everyone + Show older | 11 entries, rail fades into "Show older". |
| State 2 Friends | The first five of eight friend entries, all hollow, Feed 8. |
| State 3 You | The own entries, all filled, rail ends at the last one. |
| State 4 You, empty | Headline, body, one ghost action "Settings → Social". |
| State 5 friend hovered | List · Download · Ignore. |
| State 6 own hovered | Listed · In library · Delete. |
| State 7 cursor | 2px `var(--p)` outline, offset −1px, toolbar shown. |
| House rules | No chips, bars, avatars, dividers, headers, animations beyond the 120ms fade, real titles, external assets, icon fonts, light theme. No text below 55% except the rail hairline and the icons. |

**Data note.** The brief's list holds three own entries (2, 6, 8), not four;
the You state shows the three the data gives, and Friends is therefore eight.
If a fourth own entry was intended it needs adding to the data, not
inventing here.

## Trade-offs

- **An 84px column is spent on the rail.** At 880 the card is 796px wide,
  still wider than the whole round-2 column, so nothing is squeezed; but the
  rail is a fixed cost every entry pays, including in a three-entry feed.
- **The time is further from the sentence.** In round 2 "· 2h ago" ended the
  sentence; now the eye moves 90px left to read it. The gain is that the
  times align into one readable column instead of trailing sentences of
  different lengths — scanning "what happened yesterday" is a glance down
  the rail, not a read of every line 1.
- **The page tabs give up the left edge.** Feed / Watchlist / Friends sit at
  the right end of the strip. This is the price of the pill being the rail's
  head; argued below.
- **The marker carries meaning a chip would otherwise carry** (own vs
  friend). A user has to learn "filled = me" once; the You scope teaches it
  in one view, since every marker there is filled.
- **`12m` without "ago"** is terser than the app's other relative times. On
  an axis it is unambiguous; off one it would not be, so the form belongs to
  the rail only.

## Three entries and three hundred

**Three** (state 3 as rendered): the pill, a rail 300px long with three
filled markers, ending cleanly at the last. It reads as a short list, not a
broken long one, because the rail is exactly as long as the entries and the
end is drawn. Nothing on the page implies more.

**Three hundred**: the rail becomes the one continuous element on the page
while cards scroll past. The times down the rail turn into a coarse scale —
minutes, then hours, then `1d`, `3d`, `1w`, `2w`, `1mo` — which is what day
dividers try to fake with headers. Because the sort order *is* the time
axis, the rail never disagrees with the list and needs no grouping logic.
Filled markers let the eye pick own entries out of three hundred without
reading a word. Each entry costs one hairline segment and one 8px marker
beyond its card; there is no per-entry chrome that compounds. The window
still ends in "Show older"; the fade under it says the rail continues.

## Own entries among friends'

The name is "You", set exactly like "Nick". Inside the card there is no
difference at all — same glass, same border, same type. The difference is on
the axis: the marker is filled primary instead of hollow. This was chosen
over the two allowed alternatives:

- **`.own-border`** would put the mark on the card body, tinting the whole
  entry; in a mixed feed the tinted cards would form a pattern the eye reads
  as a second column, and at 300 entries a scattering of blue-edged boxes.
- **"You" in primary** is a mark inside the sentence, competing with the
  rose heart for the only warm/colour attention on the line.

A filled marker is a point, not an area; it lives on the structure the
direction already draws; and it maps to a clear sentence: "the rail is the
timeline, the filled points are yours". In the You scope every marker is
filled, which is the legend.

## Where the scope control sits, and why

At the head of the rail, on the tab strip's line, at the column's left. The
pill decides which entries hang on the rail, so it sits where the rail
begins: the control and the thing it controls are one vertical. The rail
emerges from under the pill's flat bottom edge at x = 22px, past the rounded
end.

The page tabs (Feed · Watchlist · Friends) move to the right end of the same
line. Two reasons this is acceptable rather than a hierarchy inversion: the
tabs are navigation between pages, and a page header with navigation at its
right end is a familiar shape; and the underline tab and the glass pill are
visually distinct controls, so "Friends" in each is not confused with the
other even on one line. On the Watchlist and Friends tabs the strip's left is
empty (or holds that tab's own control if it grows one); the tabs stay where
they are, so switching tabs never moves the navigation.

The alternative — tabs left, pill right — was rejected because the pill would
no longer be the rail's head and the direction would lose its one
organising idea.

## Page width

The Discovery column becomes **880px** (`.page` at 912 with the shared 16px
sides), from the shipped `max-w-3xl` (768). The Watchlist and Friends tabs
share it:

- **Watchlist** rows get 112px more line, which is room for the toolbar's
  states beside longer titles rather than under them; single column, no
  relayout.
- **Friends** cards: the Recently watched strip is fluid at one sixth of the
  card, so its posters grow from ~116px to ~135px wide and the "all N" tile
  with them; the Wants to watch / Reviewed text rows simply get longer
  before they wrap. Still one card per person, still one column.

880 was chosen over 1000 because the entry's text block is at most four
lines of a review; wider than ~800 the card's right half is empty air, and
the rail already gives the page a second vertical to compose against.

## Why the rail is not chrome (UIDR-038)

UIDR-038 rejects three things this direction could be mistaken for.

**State as decoration** — "badges, chips, markers or pennants on the entry
body." The rail and its markers are not on the entry body: they are the axis
the entries hang from, outside the card, and the card carries no mark at
all. What the marker encodes is not state (Listed, In library, Downloading —
those stay in the toolbar) but authorship, which is already in the sentence;
the fill only makes it scannable. The hollow ring means nothing but "an
entry hangs here".

**Day dividers** — "the sort order is the time axis." A divider is a header
that groups entries and re-sorts nothing; it adds a hierarchy the data does
not have. The rail adds no groups and no headers: one marker per entry, one
time per marker, in the same order the list already has. It is the sort
order drawn, not partitioned. Where a divider says "Yesterday" once, the rail
says `1d` beside the entry that was yesterday and `3d` beside the next; no
entry belongs to a bucket.

**Social-network chrome** — "avatars, handles, replies, reposts, reactions,
counts." The rail carries none of those; it carries the one datum the entry
already had (its relative time) and moves it. There is nothing to click on
the rail, nothing that counts, nothing that identifies a person beyond the
sentence's name.

The test UIDR-038 applies is whether an element shows what changed or
decorates it. The rail shows *when* it changed, which line 1 always did; it
only shows it in one place instead of eleven.
