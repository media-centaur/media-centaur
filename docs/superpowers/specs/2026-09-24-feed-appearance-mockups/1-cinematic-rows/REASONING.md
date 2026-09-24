# 1 · Cinematic rows — reasoning

Deliverable: `index.html` (links `../base.css`, images from `../art/`). Rendered with `page-shot` at 1920×1080, 1280×800 and 2560×1440, plus per-state clips from a tall viewport; every state in the brief is on the one page under a `.state` label, in the brief's order. Written from what is built.

## Style

Each action is a **band**: 152px tall, 10px radius, 6px between bands, the band's ground the theme's base-100 (`oklch(13% 0.02 264)` — darker than the page's radial ground, so the band's left half reads as a dark bar on the page and its right half as the picture). The title's backdrop occupies the band from x = 560px to the right edge, `object-fit: cover`, its left edge dissolved over 320px by a mask and the whole band under a left-weighted scrim in the same base hue. Nothing else frames the band: no border, no glass, no shadow, no padding box. The band is the image's edge.

On the dark side, left to right: the **identity tile** at 40px (x = 18px, centred on the band's height), the **poster** at 72×108 (x = 74px, y = 22px) with a `0 3px 12px` black/55 shadow so it stands on the band, then the **text block** from x = 164px: the sentence at 15px, the title at 18px semibold (the confident line), the review at 14px clamped at two lines, and the toolbar seat on the poster's foot line. The **time** is 13px tabular at the band's top-right corner (right 20px, on line 1's baseline), over the picture, under a right-edge vignette. All text over the band carries UIDR-011's `text-on-image` shadow.

Colour is the artwork's own plus three signals: the rose heart, the primary (the own tile, the cursor ring, the tab underline, the pill's chosen option), and nothing from the health palette. System fonts, dark only.

## Decisions

1. **The backdrop starts at 560px, not at 0.** The brief says "the backdrop filling [the band] under the house scrim". A 16:9 still covering an 1820×152 band is scaled to the band's width and shows a 15% slice of its height — an eye-strip. Under a 97% scrim the left 560px contributes nothing but a colour cast, so the image box begins where the text zone ends: box 1260px wide at 1920 → scale 0.79 → image 709px tall → **21% of the still visible**. The visible window's top edge sits at (1 − slice) × p for `object-position: 50% p`. On narrower rows the box shrinks and the slice grows (44% at a 1280 viewport); on wider rows it thins (14% at 2560, see the checks). The mask (transparent → opaque over the box's first 320px) hides the box's edge; the scrim does the rest.
2. **Scrim in the base hue with pixel stops.** `.page-side-dim` is a to-right black/50 → transparent at 35%. At row scale with 15px text over it, black at 50% is not a text surface, and percentage stops move the text zone with the row's width. The band's scrim is `linear-gradient(to right, base-100 at .97 0px, .93 540px, .55 800px, .16 1060px, .06 1260px)` — the shape of `.page-side-dim` (heavy left, clear right), the alpha ramp of `.image-scrim-r` (.92 → .72 → .3), anchored in pixels so the text zone is identical at every width. A second gradient, `to left, base-100 at .48 → 0 over 220px`, is the right-edge vignette under the time.
3. **Hover lightens the scrim a step, and the ground with it.** Every scrim alpha is multiplied by `--s`; hover sets `--s: .8` and lifts the band's ground from 13% to 16% lightness (without the ground lift, hover would show only on the picture, since no image lies under the text zone). Both changes are instant; the only transition on the page is the toolbar's 120ms opacity fade. The band's height never changes.
4. **The identity tile is the author mark, and "You" goes back to neutral.** Friend: base `.mono` — a 40px circle, the initial at 16px/600 in the primary. Own: the same circle filled with the theme's primary button fill (`oklch(62% 0.16 264)`, the lightness and chroma of app.css's `--color-primary`, not the 72% text primary) and the initial in primary-content (`oklch(96% 0.008 264)`, 700). Because the tile is now the own mark, the word "You" is set like any name: 500 weight at 96% — the second person is the text's job, the tile is the mark's. Two own signals on one row (a filled tile and a blue word) would be redundancy the diagnosis did not ask for.
5. **Monogram tone over ink.** `.mono`'s fill is the primary at 15% alpha, drawn on glass on the Friends tab. On 13% ink it is invisible. Here the fill is 18% with a 1px inset ring of the primary at 22% and a `0 2px 8px` black/35 shadow. The letter and its size are the Friends tab's.
6. **The photo state is a real portrait crop.** A 40px `object-fit: cover` of a 16:9 still shows a 56%-wide window of the whole frame — a face is 10px. The image inside the tile is sized 167×94 and offset (−63px, −15px) so the subject's face fills the circle; ring at neutral 18%. The face is One Step Beyond's presenter (`one-step-beyond-backdrop.jpg`, a spare slug).
7. **Toolbar seat at the poster's foot.** The text block is 108px tall (the poster's height); the seat is its bottom 20px (y 110–130 in the band), so the toolbar's y is the same on a listing and a review. Verbs 13px at 78% with 14px icons, 6px padding, 6px radius, a 10% fill on hover; Ignore last with a 10px gap before it; plain states at 66%; Downloading's 3px hairline at `--pct`. No Delete on an own row.
8. **Review at two lines, 58ch.** 22 + 24 + 5 + 40 = 91px of text over a 108px block with a 20px seat leaves 2px of slack; two lines is what a 152px band holds. The 58ch measure (≈420px) ends at x ≈ 590px, inside the ≥ .93 zone of the scrim. Round 3's four lines would need a 200px band.
9. **Per-title crop.** `object-position` is set per backdrop to the subject's band (Sintel 30%, Charade 28%, Metropolis 30%, Pioneer One 40%, Big Buck Bunny 42%, Night of the Living Dead 34%, Tears of Steel 24%, Nosferatu 42%, Spring 26%, The General 23%, Cosmos Laundromat 26%, Carnival of Souls 46%, Sprite Fright 58%). This is the mockup's hand; see Trade-offs.
10. **The cursor ring is the band's top layer.** An `outline` on the band paints under its positioned children (backdrop, scrim), so the 2px primary ring is a `::after` with `inset: 0`, `border-radius: inherit`, above everything.
11. **No-artwork band.** Ground `--glass-inset-bg`, a .35 → 0 scrim over the first 800px, the poster slot as `.poster-empty` with a 1px white/6 edge, text as on any band. Quiet by absence.
12. **Tab strip.** Zone tabs at the left, the house `.seg` pill on the same line at the right (6px above the strip's hairline), one hairline under both spanning the container. The count follows the scope: Feed 16 · 11 · 5; omitted at zero.

## Requirements mapping

| Brief item | How it is met |
|---|---|
| App shell: 52px sidebar, `main` 24px, `.content` | `.frame` > `.sidebar` + `main` > `.content{max-width:none}` (full width, argued below) |
| Line 1: author medium, verb, glyph; second person on own rows | `.l1` 15px/22 at 80%; `.who` 500 at 96%; "You reviewed" / "You want to watch" |
| Glyphs: love heart in `--love`, thumbs up/down, none | Round 3's sprite copied verbatim; 13px, `vertical-align: middle`, a drop-shadow so it sits on the band like the text |
| Line 2: title semibold + year | 18px/24 600 in `--bc`; year 13px at 60%, 9px gap |
| Line 3: review, clamped | 14px/20 at 78%, `-webkit-line-clamp: 2`, 58ch |
| Relative time in its own place | `.when` top-right of the band, never in line 1 |
| Poster: real artwork, size named | `img.poster` 72×108, `<slug>-poster.jpg`, eager |
| Backdrop under the house scrim | `.bd` box from 560px, cover, masked; `.scrim` recipe above |
| Toolbar: hover/cursor only, fixed seat, height constant | `.bar` opacity 0 → 1 in 120ms; seat at y 110–130; band 152px always |
| Friend toolbar: List/Listed/Tracking · Download/Downloading/In library · Ignore last | States 5 and 5 · continued: Sintel (List · Download · Ignore), Spring (Tracking · Download · Ignore), Pioneer One (List · In library · Ignore), Charade (Listed · In library · Ignore) |
| Own toolbar: List · Download only | State 6: Listed · In library; 6 · continued: List · Downloading; no Ignore, no Delete |
| Whole-row click; names not links | `cursor: pointer` on the band; names are spans |
| Scope: `.seg` pill on the strip's line at the right; count follows scope | Every strip; 16 / 11 / 5 / none |
| Identity tile: monogram, photo, own; both states shown | Monogram on every friend row; photo on Ada in state 8 (between a monogram and an own tile); own = filled tile on rows 2, 6, 9, 13, 16 |
| Data: sixteen rows, newest first, own at 2/6/9/13/16, Friends 30 | The table's rows and times verbatim; Feed 16 · Friends 11 · You 5; Friends tab reads 30 |
| Title state consistent per title | Charade: Listed · In library on rows 2 and 3; Big Buck Bunny: Listed on 6 and 7; Pioneer One: In library on 5 and 11; Spring: Tracking; Tears of Steel: Downloading; Sprite Fright: Listed |
| State 1 Everyone + Show older | `#f1`, sixteen bands; ghost "Show older" on the tile's edge after the last band |
| State 2 Friends — first six, own gone | `#f2`: rows 1, 3, 4, 5, 7, 8 |
| State 3 You — the five own rows | `#f3` |
| State 4 You, empty | Headline 17px/600, body 14px at 70%, one ghost "Settings → Social"; count omitted |
| State 5 friend hovered | `#f4` Cleo · Sintel, `.hovered` |
| State 6 own hovered | `#f6` You · Charade, `.hovered` |
| State 7 cursor | `#f8` Nick · Charade, `.cursor`: 2px primary ring following the radius, toolbar shown |
| State 8 friend with a photo | `#f9` Ada, photo tile |
| State 9 no artwork yet | `#f10` Femi · Coffee Run (a PD title in `art/`, drawn without its art) |
| UIDR-012 eager images | Plain `<img>`; no `loading="lazy"` |
| UIDR-033 artwork is the subject | Each band shows only its own title's backdrop and poster |
| No chips, badges, bars, dividers, group headers, entrance animation, light theme, real titles beyond `art/`, text < 55% | None present; lowest read text is the year at 60% (plain states 66%); the only transition is the toolbar fade |
| No JavaScript beyond a hover/cursor toggle | None at all; `.hovered` and `.cursor` are static classes |

## The author mark at three friends and at thirty

At three friends the page's left edge is a column of discs: dim primary discs with a letter for Cleo, Nick and Bob; a bright filled disc for You. Own rows are found without reading — the filled tile is a different luminance and fill, not a hue on a word — and the second person confirms on reading. One friend from another is the letter plus the name beside it.

At thirty the letter collides (a second C, a second S) and the monogram alone no longer separates two friends; the name does, as it does today. What scales is the photo: once a person has published one, the tile is a face, and a face is recognised before a word is read. So the honest claim is: own-versus-friend is pre-attentive at any roster size; friend-versus-friend is pre-attentive when a photo exists and otherwise is letter-then-name. The direction does not add a per-person hue (that is direction 2's device and the chip-palette objection stands against it here) — the tile stays the Friends tab's own drawing of a person, so recognition learned on one tab carries to the other (diagnosis point 6).

## Where the photo goes and its default

The photo is the identity tile's second state: a circular crop in the same 40px seat at the band's far left, before the poster. The default is the monogram. State 8 shows the three tile states in one column (monogram, photo, own). The design doc's model holds this: one `Discovery.IdentityTile` renders both states on both tabs; the photo URL or nil rides on `Person` and `FeedEntry`.

## Standing rules: kept, bent, broken

| Rule | Status | Exception, precisely |
|---|---|---|
| UIDR-033 — artwork when the artwork is the page's subject | Kept | A band shows the backdrop of its own row's title and nothing else. No unrelated band, no hero. |
| UIDR-038 rule 2 — flat, newest first, one entry per action | Kept | Sixteen bands in the brief's order; no grouping, no re-sorting. |
| UIDR-038 rule 3 — one anatomy | Kept | One band markup for every author; `.own` changes only the tile's fill. |
| UIDR-038 anti-pattern *wall of watching* | Bent | The page is two-thirds picture at 1920. The exception: every band leads with a sentence about a person in a fixed 560px text zone; the picture is the row's own title, placed after the words. A wall of posters with no author would be the anti-pattern; a column of captioned stills is not. |
| UIDR-038 *title-first row* | Kept | Line 1 is the author and verb; the title is line 2 and the picture is to the right. |
| UIDR-038 *grouped rows* | Kept | None. |
| UIDR-038 *state as decoration* | Kept | The band's colour is the artwork's own. The only added colour is the heart, the own tile and the cursor. |
| UIDR-038 *social-network chrome* | Bent | The identity tile is a person device. The exception: it is the Friends tab's monogram (`Discovery.PersonCard`), already the app's drawing of a person; the photo slot exists because the owner asked for a space; no handles, counts, reactions or links. |
| UIDR-038 *hover jump* | Kept | 152px at rest and hovered; the toolbar's seat is in the band's fixed layout. |
| UIDR-038 *day dividers* | Kept | None. |
| UIDR-045 rule 3 — own = the word You in the primary | Replaced | The primary moves from the word to the tile: a filled primary tile with the initial in primary-content. "You" is set like a friend's name. |
| UIDR-045 rule 5 — one inset list surface, hairlines between rows | Broken | Bands 6px apart on the page ground, no shared container, no hairlines. A band of imagery needs its own edge; a hairline between two pictures is a third picture. |
| UIDR-045 toolbar contract | Kept | Same slots, same states, same seat idiom; Ignore last; no Delete. |
| Colour is signal | Kept | Primary = own tile + interaction; rose = love; no health palette; the artwork's colours are the artwork's. |
| Round 3's *no card per entry* | Bent | The band is a per-row surface again. The exception: it carries no border, glass, shadow, padding or chrome — it is the image's edge and the ink the text needs. |
| `.mono` tint at 15% | Bent | 18% fill + a 1px inset ring at 22% over 13% ink, where 15% vanishes. Letter, size and hue unchanged. |
| `--p` for the own fill | Bent | The theme's `--color-primary` lightness/chroma (62% / 0.16) for the fill, so a white initial has contrast; `--p` (72%) stays the text primary. |
| The brief's "backdrop filling the band" | Bent | The image box begins at 560px (decision 1). Under a 97% scrim the difference is invisible; the slice gained is the point. |
| Text ≥ 55% | Kept | Year 60%, plain states 66%, verbs 78%, review 78%, sentence 80%, time 78%. |
| Animations | Kept | Toolbar opacity 120ms only. |

## Page width, and what Watchlist and Friends do

**Full width** (`.content{max-width:none}`, Home's opt-out): bands 1820px wide at 1920. Tried against a 1280 left-aligned column with the same rows (rendered both at 1920): the column shows more of each still (a 37% slice) and leaves 540px of the monitor to the scrim — the diagnosis's point 5 at a smaller scale, on the page whose brief is presence. The strip is this direction's identity; the poster beside it carries recognition when the strip catches only an eye.

The tab strip and its hairline span the container; the pill sits at the far right. The Watchlist and Friends tabs share the container and keep their cards; their grids gain columns at 1920 and lose them at 1280. The constants across the three tabs are the strip, the left edge and the h1; what fills the strip's width differs by tab, as it does between Home and the Library.

A row narrower than 1280: the text zone is fixed at 560px, so the image box shrinks from its left. At a 1280 viewport the row is 1180px, the box 620px, the still scaled to 349px tall — a 44% window (a whole face and the dragon on Sintel's row). Below roughly 900px the box is the mask alone and the band shows ink; the page is not designed under that.

## At 3 rows and at 300

Three rows: three bands under the strip, ~490px, no Show older. Three pictures on a dark page is a composition, not a sparse list; nothing frames an absence.

Three hundred: 300 × 158px ≈ 47,000px. What holds it is the fixed left zone — tile, poster, sentence at the same x on every band — forming a spine, and the pictures changing on every band, which is what diagnosis point 3 asked for. Costs: adjacent rows of one title repeat one still (rows 2–3, 6–7 here, by the data's design); and 300 eager backdrops is 300 image loads — the host resolves them like posters (`ActivityPosters`' ladder; `TmdbArtwork` warms backdrops), and the derivative should be `?w=1280` (the longest side), ~150KB each. "Show older" pages the list, so a window is 16–32 bands, not 300.

## The 1280 and 2560 checks

**1280×800**: rows 1180px; the box is 620px and the window 44% of the still — squarer, whole faces. The text zone, tile, poster and type are identical to 1920. The pill fits the strip; five bands fill the height. Holds, and arguably shows the stills best.

**2560×1440**: rows 2460px; the box 1900px; the still scaled to 1069px and the window 14% — a letterbox. Faces still land (Sintel's eyes, Hepburn's eyes, the robot's head) because the crops aim at them, but Night of the Living Dead reads as a colour field. The text zone stays 560px, so the type does not drift and the page is two-thirds picture. It holds as a wider cinema strip; it does not gain information. Note that the app's UI scale (auto = screen/1920 × preference) renders a 2560 monitor at ~1920 CSS px, so the 1× 2560 check is the edge case, not the common one.

## Trade-offs

- **The crop is a hand-tuned sliver.** Thirteen `object-position` values were set by eye against the stills. The app has no per-title subject position; a fixed value (30% suits most stills, whose subjects sit upper-middle) will sometimes land on a wall. Nosferatu is the example on this page: a dark painting with the face at the frame's far right edge, under the vignette — at 42% the strip catches an eclipse's rim and a brow, and no value of p makes it a face at 152px. This is the least certain part of the direction: the strip's beauty depends on where 21% of the still falls.
- **The window changes with viewport width** — 44% at 1280, 21% at 1920, 14% at 2560 — because the band's aspect changes and the still's does not. A capped image box would fix the slice and leave ink between text and picture on wide monitors; not done.
- **Two adjacent rows of one title show the same picture twice**, the data's own repetition made visible.
- **The time is far from the words** at full width (≈1,700px). It is at the band's edge, where the brief put it, over the vignette; it is an orientation, not a read.
- **Listing bands have an empty middle** (y 68–110) because the seat is fixed at the poster's foot. The constant seat is worth more than a tighter listing.
- **Bright stills fight the time**: Big Buck Bunny's sky needs the 48% vignette; a whiter still would need more.
- **Eager backdrops cost bandwidth** on a page that already loads posters; paged by Show older.
- **The own tile is 40px of solid primary on every fifth row**; on a page that is otherwise the artwork's colour it is the loudest constant. That is its job, and it is one hue, one shape, in one seat.
