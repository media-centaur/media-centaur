---
status: implementing
started: 2026-09-24
last_updated: 2026-09-25
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

**Implementation approved 2026-09-25** ("execute implementation in a
new context"). The design was settled over rounds 4–9 plus the act-mark
iterations of the afternoon (disc → opaque with solid glyphs → fixed
slots above the poster; the grade at two tiers, gold from two friends). The Feed is `G-couch-feed`; the person card is `J-friends-page`
with the act disc; the spec's "What the user sees", "The model" and
acceptance criteria are written from those two pages
(`docs/superpowers/specs/2026-09-24-feed-appearance-design.md`), and
the implementation plan is rewritten to them
(`docs/plans/2026-09-25-cinematic-feed.md`, seven phases, test-first).
The review artifact carries every page, brief and critique. **The plan is
the contract**: `docs/plans/2026-09-25-cinematic-feed.md`, seven
test-first phases; its "Owner decisions this plan assumes" lists the
mechanics, each one line to flip. The grade threshold is **two or more
friends** ("more than one might be considered several; we can tweak it
from there").

**Phase 1 shipped 2026-09-25** (`Discovery.IdentityTile` at 48/56/64
with its contract test and story; the storybook fixtures
`priv/static/images/storybook/sample-{poster,backdrop}.jpg` from the
showcase's *The General* pair, downsized to 400×600 and 1280×720, and
the six stale story references repointed). Two departures from the
plan's text, both recorded in the code: the component raises on a size
outside 48/56/64 because Phoenix checks `values:` at compile time only,
and the fixtures are derivatives, not raw copies, so the release does
not carry a 2MB poster for a dev-only catalog. Under `/unify_design`:
the person card's inline monogram is the one existing drawing of a
person (the app-card and shelf initials draw apps and titles); it
converges on the tile when Phase 3 rebuilds the card, so two drawings
coexist only through Phase 2. Phases 2–7 follow the plan; the owner's
TV look at `/discovery` comes after Phase 5.

**Phase 2 under `/unify_design`** (2026-09-25, the owner: "use the
unify design premise on all future scopes"). The organizing idea is
*a title's artwork resolves down one ladder per role: the owning
library entity's image, then the referenced cache, then the TMDB
hotlink*. The code held it four ways: two batch library reads
(`Library.Posters.urls_by_refs/1` for posters,
`Library.Images.logo_urls_for_entities/1` for logos, keyed
differently); four TMDB CDN URL builders (`LiveHelpers.tmdb_cdn_url/2`,
`TMDB.Mapper.tmdb_image_url/1`, and a `@tmdb_cdn <> path` in
`TmdbArtwork` and `ImageRepair`); and the ladder itself hand-rolled in
`ActivityPosters.url/3` (poster), `TitleDetailHost.build_detail/4`
(poster, backdrop, logo), `LiveHelpers.title_poster_url/1` (poster,
no library rung) and `ReleaseTracking.logo_url_for_item/2` (logo) —
while `ReleaseTracking.list_releases_between/3` skipped the library
tier for backdrops altogether. Disposition, all fixed in this phase
as separate commits: `Library.Artwork.urls_by_refs(refs, role)` is the
one batch read (poster · backdrop · logo); `TMDB.Mapper.image_url/2`
the one CDN builder; `MediaCentaur.TitleArtwork.urls/3` the one
ladder, in core so release tracking composes it too; the four
composers call it and the release rows take the library backdrop like
every other surface. The Feed's `backdrop_url` then rides the same
call. Cost: about four times the plan's file count for the phase, all
mechanical; the behaviour changes are the release rows' backdrop (the
library's wins, as everywhere else) and nothing on the Feed.

**Phase 2 shipped 2026-09-25** in four commits (`29f45e82` the batch
read, `d678bb9f` the CDN builder, `b2fe8237` the ladder and its
composers, then the Feed's `backdrop_url`). Recorded for later: the
Coming Up events (`ReleaseTracking.UpcomingFeed.event_from/2`) still
dress from the referenced tier alone, per release, because a library
read there would be one query per event; converge on `TitleArtwork`
with a batched read when that shelf is next touched. Plans and
pursuits read the referenced tier by design — an acquisition subject
is not owned — and are not ladders.

**Phase 3 shipped 2026-09-25.** Under the unify pass: the flag
vocabulary (`Title.Flag`) is one thing the pennant and the act slots
compose, with a weight for the solid set; a person is their acts, each
act carrying its own ago (no `latest_*` on the person); the opened
card's row sentence is the old presence sentence renamed
(`ActivityWords.sentence/4` over `verb_phrase/3`), one row per title
with every flag after it; the grade is gold at two friends, counted
once per friend per title and flag over the rows the fold already
holds; the identity-banner family's ink literal became `--ink`. The
Friends tab renders the page card in today's column; the rail, the
grid and `?person=` are Phase 5.

**Phase 4 shipped 2026-09-25.** `Discovery.FeedBand` renders every
entry as the band — the still under the scrim, the tile, the poster,
the words at the couch floors — keeping the row's DOM contract, so the
Feed's page tests passed untouched. The crop offset is stamped by the
projection from adjacency in the scoped window. The bands sit in the
old 896px column until Phase 5 gives the page its frame.

**Phase 5 shipped 2026-09-25.** Discovery takes the layout's full
width: the Feed column beside the rail (person cards at the rail's
width, You first, seven by latest act, *All N friends* past the cap)
above 1600px of content and one column below — a container query, no
assign; the window is twenty to a cap of sixty with the foot line; an
arrival prepends live at the top and queues behind "N new" when the
`FeedHead` hook reports the column's head gone; a rail card opens the
Friends tab at its person (`?person=`), whose grid folds at 1700.
Two fixes followed the owner's first TV look (`796befb9`, `ef9fb655`):
the head row now shares the columns' grid with one hairline under both,
the tab strip and the segmented control gained a couch size (`:lg`)
that Discovery passes, and the head sentinel and "N new" left the
column's flow so the first band's top is level with the rail's first
card. **The owner looked at it on the TV (2026-09-25 evening): "seems
ok"; more tweaks are coming in a new context before anything ships.
Nothing is pushed. Phase 6 (the records and docs) waits for those
tweaks.**

**Riding along, unrelated to the Feed (2026-09-26):** `1120a736` fixes
the Connections request history being dropped after a reboot (the
time series snapshot was rejected as corrupt on a cold dev boot) and
adds MC0039. A `/ship patch` was asked for that day and held by the
owner so the Feed would not ship before its tweaks. The release that
carries this campaign carries that fix too. It needs no changelog line:
a release preloads every module at boot, so end users never hit the
cold-boot rejection — only the dev daily driver did.

**The owner's first desk look (2026-09-26): "bunches of dark boxes."**
Diagnosis: on a dark UI a surface is lighter than its page; the Feed
inverted that — ink units at 13% on a ground that is 27% under the blue
blob at the top, dimmed only from a third of the way down — so each unit
reads as a hole, and eight holes with corners and gaps read as a grid. The
mockup rounds had not shown it because `base.css` mirrored the ground as
one radial (28 → 17%). **Round 10** (`BRIEF-10.md`, `CRITIQUE-10.md`,
`round10.css`, built by `make-round-10`) rebuilds G's page under seven
knobs — page ground, unit ground, ink tone, edges, hairline, the still's
extent, its dissolve — as six presets, each a good idea (Q1 dark sheet,
Q2 film strip, Q3 open rows, Q4 glass list, Q5 matched cards, Q6 dark
sheet with the wide still), a switchboard with every knob live
(`Q-switchboard/index.html`, the state in the address) and a half-size
comparison sheet with today's page beside them (`compare.html`). The
critique recommends **Q6**. Nothing in a band's anatomy moved; every
direction is CSS on the shipped components. **Next: the owner picks a
preset or names a combination by its switchboard link.**

**The owner's second question (2026-09-26): backdrop and logo instead of
poster and backdrop** — "this may be causing some irritation for me…
what could we do with the ui with that?" Facts: 27 of 30 movies and 14 of
14 series in the library carry a logo; the Feed's artwork ladder already
returns `logo_url` and `FeedEntry` drops it; an unowned friend's title has
one only when the referenced cache holds it, so the Feed is a mix.
**Round 11** (`BRIEF-11.md`, `CRITIQUE-11.md`, `round11.css`,
`make-round-11`) removes the poster from every band of Q6's page and
draws four directions with wordmark stand-ins for the logos and four
titles typed as the fallback: R1 backdrop only (the subtraction, the
test), R2 logo headline (the logo as line 2 on the ink, the band 264),
R3 title card (the logo bottom right of the picture over a foot gradient,
the band 224), R4 hero band (the logo first over the full still). The
switchboard (`Q-logo-switchboard/index.html`) carries both rounds' knobs;
`compare.html` puts Q6 beside the four. The critique recommends **R2**.
**Next: the owner's answer to R1's test and, if the logo, a pick.**

**The owner's third complaint (2026-09-26): "i hate the timestamp being
in the middle of the row and the image on the right".** One cause: the
still's box begins at 700, the text zone ends there, and the time is
right-aligned to it. **Round 12** (`BRIEF-12.md`, `CRITIQUE-12.md`,
`round12.css`, `make-round-12`) moves the picture so the time can go to
the edge: S1 picture left (the still whole as a 16:9 thumbnail in the
poster's slot, tile · picture · words, the time at the edge), S2 picture
flush (the still as the band's left end, the tile after it), S3 full
bleed with the time at the top right over a vignette, S4 = S1 with the
typed title. The left-hand compositions show the whole frame, so the
crop rule, the 38% adjacency offset, the mask and the scrim all fall
away. The switchboard (`Q-place-switchboard/index.html`) carries all
three rounds' knobs; `compare.html` puts R2 beside the four. The
critique recommends **S1** — and notes that S1 is the page that answers
every complaint so far at once: Q6's ground and columns, R2's logo, the
still whole at the left, the time at the edge. **Next: the owner's pick
across the three rounds, then one implementation pass.**

**The owner's proposal (2026-09-26): "S2 but the logo is atop the
backdrop, like we do for the card view on the home page".** Built as
**S5** (S2's flush picture with `ContinueWatchingRow`'s treatment: the
to-top gradient, the logo bottom left, the white name as fallback; the
panel is the sentence alone, so the band stays 224) and **S6** (the same
on S1's inset thumbnail, the tile first). The critique moves its
recommendation to **S5**: it answers both complaints, keeps 224, shows the
frame whole, and makes the Feed's band and Home's card one artwork idiom
— the propagation round 4's brief asked for. The implementation would
extract the card's gradient-and-logo block into one component Home and
the Feed share.

## Handoff — start here in a fresh context

0. **Where it stands (2026-09-26):** Phases 1–5 are on `main`,
   unpushed (`de9deb2b` … `ef9fb655`); the owner's first tweak is the
   "dark boxes" complaint, answered by round 10 (Status above) and
   waiting on the owner's pick. Take the tweaks under
   `/unify_design` like every phase, one commit each with precommit
   clean, a `page-shot` of `/discovery` at 1920 and its half-size copy
   after each; then Phase 6 of the plan (UIDR-046, the amendments, the
   docs, the wiki), then the campaign's closure by destination. The
   plan's "Realized" notes under each phase say where the code differs
   from the plan's text; the `/storybook/iframe/discovery/<story>?
   variation_id=<id>` route shoots one variation in isolation.
1. Read this file (Status, Decisions made, Deferred), then the plan's
   ground rules and its "Owner decisions this plan assumes", then
   Phase 6. Do not re-read the mockup rounds unless a phase points at
   a page for a size; `G-couch-feed/REASONING.md` and
   `J-friends-page/REASONING.md` hold every number.
2. The review artifact (private, the owner's) shows the two settled
   pages and the spec/plan: https://claude.ai/code/artifact/7588de25-86db-4849-aab1-416ac323c8a4
3. Work phase by phase: tests first, `~/scripts/agents/agent-mix`
   never bare `mix`, `mix precommit` clean before each phase's commit,
   one commit per phase, no push. Verify visually with `page-shot`
   against the dev server at 1920 and at half size (the couch check).
4. Another session works in this checkout on bundled mpv scripts
   (`campaigns/bundled-mpv-scripts.md`); stage paths explicitly, never
   `git add -A`.
5. When Phase 5 lands, the owner looks at `/discovery` on the TV before
   Phase 6 writes the records. Steps 1–3
done: the diagnosis is in the spec's Problem section
(`docs/superpowers/specs/2026-09-24-feed-appearance-design.md`); five
directions are built under
`docs/superpowers/specs/2026-09-24-feed-appearance-mockups/` (brief
`BRIEF.md`, comparison sheet `index.html`, critique `CRITIQUE.md`;
PD/CC artwork regenerated into `art/` by `make-art`, git-ignored). The
critique recommends crossing 1 (cinematic rows) and 4 (front page) —
bands under the house scrim as the page, a lead for the newest action —
after measuring the crop risk on thirty real backdrops; it does not
recommend 2 (per-person hue), 3 (author runs) or 5 (tile column). The
five directions are also published as a private artifact for the owner
to view away from the desk. Next gate: the owner chooses, or asks for
round 5 as recommended.

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
* `2026-09-24` — The owner raised the bar past the author mark: the
  Feed page should be gorgeous, the reaction *holy crap*. The round is
  about presence (artwork, type, composition at 1920) as much as about
  authorship. Recorded in the spec's Problem section.
* `2026-09-24` — Mockups use real PD/CC artwork from the showcase
  (`priv/showcase/images`) rather than gradient thumbs: the decision
  turns on imagery, and gradient thumbs would undersell every
  artwork-led direction equally. The art is regenerated by a script and
  git-ignored.
* `2026-09-24` — Owner's note, not a mandate: a person may one day
  publish a photo through the social relay (kept until replaced or
  removed). Nothing is built for it; the design makes a space for it
  and a default for its absence. The brief names the element the
  *identity tile* — the Friends tab's monogram as the default, a
  circular photo when one exists — and every direction places it or
  argues why the Feed has no place for it.
* `2026-09-24` — The owner is willing to spend a great deal of effort
  here, so the round widened from three directions to five (cinematic
  rows, poster gallery, author runs, front page, tile column), a
  precedents section joined the brief, the designers iterate at least
  three render passes, and the round ends with a comparison sheet
  (`index.html` in the mockups folder) and a written critique before
  the owner chooses. A second round refines the chosen direction.
* `2026-09-24` — The owner: this step is unusually important; after
  seven months on the project (first commit 2026-02-19) the Feed's
  refinement "will set the stage for a new direction for some of this
  app". Treat the chosen direction as the reference for the app's next
  visual step, not as a one-page fix: what it establishes (artwork
  carrying rows, the identity tile, type hierarchy, full-width
  composition) is expected to propagate.
* `2026-09-24` (night) — The owner went to sleep with the instruction
  to continue autonomously, spend freely, ask nothing, and leave one
  reviewable artifact holding every version with its reasoning. Also:
  the production database and image cache may be used for
  experiments; nothing may be downloaded and no indexer or TMDB
  traffic may be generated. The review artifact is
  https://claude.ai/code/artifact/7588de25-86db-4849-aab1-416ac323c8a4
  (private; rebuilt by `build-review` plus a root page kept in the
  session's scratch folder).
* `2026-09-24` (night) — Crop measurement done (`MEASUREMENT.md`):
  on 24 real backdrops a fixed `object-position: 50% 30%` lands on
  the subject at both the band's 21% slice and the lead's 42% box;
  libvips attention/entropy crops fail on different stills and are
  rejected. The rule is fixed 30%, an 8% offset on the second of two
  adjacent rows of one title, no per-title positions.
* `2026-09-24` (night) — Round 5 (`BRIEF-5.md`) builds the 1×4 cross
  in four settings — full width, the 1280 container, a capped 900px
  image box, words-led bands — and a labelled motion exploration
  (`X-motion`: scroll parallax, ambient drift, hover ease, each
  switchable) so motion is judged rather than assumed away.
* `2026-09-24` (night) — Round 5 verdict (`CRITIQUE-5.md`): the
  cross holds in every setting. Settled by render: full width for
  Discovery; the band's still in a 900px right-aligned box (C); the
  time right-aligned at the body's edge (x≈576 on a band, top right
  on the lead); the lead's image boxed like the band's (A2); two
  review lines at 152px (D's words-led bands rejected, kept as the
  fallback); "You" neutral beside a tile filled with the button
  primary; adjacent repeats accepted with the 8% offset; motion
  limited to hover/cursor ease at most (X); the Watchlist takes the
  band next, the Friends card keeps its shape and gains the identity
  tile, Incoming after that, Home and History unchanged (P).
* `2026-09-25` (morning) — The owner is not sure of full width ("it
  still seems to waste some space") and pitched a Friends rail: at
  wide viewports the Friends section becomes a second column on the
  right, keeping its "what they've been watching" focus, ordered by
  latest activity; and named **couch readability on a TV as the
  primary design consideration for all of this**. Rounds 4–6 were
  desk-scale; round 7 (`BRIEF-7.md`) re-scales to couch floors (read
  text ≥ 22px at the 1920 composition, which is what the TV shows) and
  renders the rail (R1), full width at the same scale (R2) and a
  spanning lead over feed-plus-rail (R3), with a half-size "10-foot"
  check on every render.
* `2026-09-25` (morning) — Round 7 verdict (`CRITIQUE-7.md`): the
  couch floors work (every page reads at half size) and change the
  band into a photograph (47–74% slices at 220–236px); full width is
  no longer wasted at couch scale, so the question is what the width
  is spent on. Recommended: R3's structure — the masthead lead over a
  feed column beside a Friends rail whose row is the person's latest
  watch, folding to three tabs below 1700px — with R1's rail density;
  R2 (full width, no rail) is the fallback if the rail proves thin on
  a three-friend roster. Opened for the record: what a rail row opens
  (`/discovery/friends` as a route at every width), two nav graphs,
  one definition of presence, UIDR-038 rules 7–10. The couch floors
  belong in the `user-interface` skill as a house rule.
* `2026-09-25` (morning) — The owner's review of round 7: the masthead
  is busy and relegates the rail; friends may withhold watches and
  listings (both off by default), so person surfaces design for four
  sharing states; the reason to look at a friend is the few things
  they last watched, which never reach the Feed, so the rail's rows
  are compact person cards with the strip; many friends need a cap
  and an "All N friends" foot; feed paging must be deliberate (a
  window of twenty, Show older to sixty, "N new" queued at the head
  when scrolled). The Friends tab stays at every width as the full
  page where the roster is managed; the tab strip is constant; the
  rail is its summary. Round 8 (`BRIEF-8.md`) builds one Feed page
  and one Friends page from one person-card anatomy at two widths.
* `2026-09-25` — Round 8 verdict (`CRITIQUE-8.md`): `G-couch-feed`
  is the page — two columns, no lead, bands 224px (74% slice), the
  rail as person cards (You first, seven by latest act, All N
  friends), four sharing states drawn, a window of twenty to a cap of
  sixty with "N new" queued at the head; `G-friends-page` is the
  Friends tab, one component with the rail's card at two widths. The
  couch floors are a house rule.
* `2026-09-25` — The owner: the Feed is "really improved" —
  `G-couch-feed` stands as the Feed's page. The Friends tab is the one
  open surface: more space per friend, posters carrying the card, less
  text. Round 9 (`BRIEF-9.md`) redraws it as a two-column grid of
  poster-led cards (name, presence line, one note slot, the Recently
  watched strip with its caption; the text rows and management behind
  the card).
* `2026-09-25` — Round 9 verdict (`CRITIQUE-9.md`): the owner's
  acts-strip pitch wins over the presence sentence — a person's card
  is their latest acts as posters flying the pennant's flags (eye,
  heart, thumbs, bubble, bookmark; two on one poster), the mast
  placement at a 28px (rail) / 32px (page) outline glyph, the sharing
  note kept in one slot. UIDR-037's "never on poster cards" gets a
  person-card exception (the poster is the act's subject); UIDR-038
  rules 8–9 are replaced by the strip. H's grid frame stays; its holes
  were the sentence card's (reviews-only friends had no picture).
* `2026-09-25` — The owner on "never on poster cards": "sort of
  ridiculous, why would we be constrained by such a rule". Checked:
  it is one sentence in the `user-interface` skill (added 2026-09-05
  with the first pennant), with no rationale and no decision record;
  UIDR-037 never says it. Rewritten in the skill to its real scope —
  the Library grid and Home's poster rails carry no flags; a person
  card's acts strip flies them on posters because there the poster is
  the act. No record to amend.
* `2026-09-25` — The owner: "we don't need to be told who shares
  what; we just render what we have." No sharing notes on person
  cards ("Doesn't share watching", "You don't share watching",
  "Nothing shared yet" all go); a card is the person's acts as posters
  and nothing about what they withhold; a friend with no acts is a
  tile and a name. Then: no "How friends see you" either — the You
  card is your acts like anyone's, the filled own tile its only mark.
* `2026-09-25` — Round 9c verdict (`CRITIQUE-9.md` addendum,
  `K-flag-forms`): the act glyph's form on a poster is the **clipped
  corner** (a 44px notch on the rail, 56 on the page; the glyph on the
  card's ground in the notch; two acts grow the notch down), the
  footer band the runner-up, the mast rejected for its two-act stack.
  UIDR-037's pennant is a form for the title surfaces, not a rule for
  the person card.
* `2026-09-25` — The owner: "I think I'm liking corner disc." The act
  glyph's form is the **corner disc** (the owner's call over the
  critique's clipped corner): a 44px disc / 28px outline glyph on the
  rail's posters, 52 / 32 on the page's, ink at .85 with a 1px ring,
  top-right inset 8px, the love disc on `--color-love`; two acts as two
  discs stacked downward. Round 9b's disc failed at a 24px glyph; 28px
  at a 2px stroke is the size every form passed at in round 9c.
* `2026-09-25` — The owner: the heart in a rose disc was not as
  readable; the love disc is now the same ink disc as every other
  glyph and the heart alone is solid rose. Applied to G, J, the spec
  and the plan.
* `2026-09-25` — The owner: "we don't have to retain the current
  artifact history thing; we can just keep iterating on the latest
  best version." The review artifact is trimmed to the two settled
  pages (G, J), the spec, the plan and the campaign file; superseded
  pages are removed from it and live only in the repo. From here the
  pages are patched in place, not re-lettered. Open: the act glyph's
  legibility up close (the disc translucent, the glyphs thin) — a
  comparison of the current disc, an opaque disc with solid glyphs,
  and the footer band with solid glyphs.
* `2026-09-25` — Two owner brainstorms under render, both on the act
  disc: (a) for two acts on one poster, one joined capsule backing
  holding both glyphs instead of two stacked discs (the backing's
  length is the number of acts); (b) a **grade** — the glyph's shape
  says what was done and its colour says how many friends did it
  (tier 1 plain ink disc, tier 2 a ring, tier 3 a filled disc in rose
  or gold), so the heart is not pink by default. Concerns recorded:
  the grade un-pinks the heart app-wide if adopted (the pennant would
  take it too); attribution on a person card (the intensity may read
  as the person's); thresholds vs roster size; three tiers must
  survive the half-size check. Rendered (`L-glyph-legibility`,
  `M-graded-discs`): the capsule reads as one mark and is adopted
  with the opaque disc and solid glyphs; the grade's three tiers do
  **not** survive half size — the tier-2 ring is invisible, so only
  plain vs filled reads (two tiers); gold beats rose for the filled
  tier (rose on a thumb reads as love); a mixed capsule reads
  correctly; on a Feed band the graded disc reads as the person's act,
  not the roster's. Open for the owner: a two-tier grade (plain /
  filled gold, threshold to set) or no grade; if adopted, the heart is
  white at tier 1 and the pennant takes the same rule. Five
  approaches to the tier rendered (`N-tier-approaches`): fill (two
  tiers, minimal footprint), numeral (direct, but reads as a
  notification badge and eats the poster), stack (2 vs 3+ fails at
  half size), size (unreadable without a neighbour; ruled out), heavy
  ring (a 4px gold ring for 2, gold fill for 3+ — three tiers legible,
  no added footprint). Viable: fill or heavy ring; the owner decides,
  and whether a middle tier is worth having at today's roster size.
  The owner's steer (2026-09-25): three finishes at one size — ink /
  silver metal / gold metal — the gold must not read as sized up (a
  light filled disc reads larger than an ink one; a darker rim holds
  the edge), and the band should be tried as a **header** (poster
  titles live in the footer). Corrected by the owner mid-render: the
  finish goes on the **glyph**, not the backing — the disc stays ink at
  one size in every tier; the glyph is matte (white at 78%) for one
  friend, silver metal for two, gold metal for three or more. Under
  rendered as `O-metal-tiers`, disc and header band. Finding: gold
  separates at half size; **silver does not separate from matte**
  (the gradient averages to the same grey at 14px); a mixed capsule
  reads honestly; the header band costs the poster's top quarter,
  where faces sit; the filled disc still reads larger than ink at the
  same diameter. Viable with glyph materials: two tiers (matte /
  gold), not three. The owner's next argument: the disc covers face
  space too; a **header with three fixed slots** — the review glyph,
  the eye, the bookmark, one position each, empty slots drawn as
  nothing — would put every glyph in the same place on every poster
  (a scan, not a read), and needs no capsule since a person has at
  most one act of each kind per title. Under render as
  `P2-slot-header`: the header on the poster's top, the header above
  the poster on the card's ground, against the disc; with a count of
  fixture posters whose face sits under the disc vs under the band.
  Rendered: the fixed-slot scan works at half size; the face count is
  a wash (the disc covers a face on 7 of 16 posters, 3 partial; the
  band on 8, 1 partial); the header above the poster covers nothing
  for 36px of card height; a one-act band reads sparse only when the
  lone glyph is the right-hand bookmark. **Decided (owner, "agreed",
  2026-09-25): the act mark is the fixed-slot header above the
  poster** — three 28px slots on the card's ground (the opinion, the
  eye, the bookmark), empty slots drawn as nothing, no backing, the
  glyph matte by default and gold when several friends agree; the
  corner disc and the capsule are retired. G and J patched; the spec
  and the plan follow.
* `2026-09-25` — The owner: a hover / cursor "additional info" layer
  on the act discs (the verb, the episode, the title) is a **separate
  future scope**; the current iteration is readability only. Deferred,
  with the note that on the TV the cursor state is the hover.
* `2026-09-24` — Page-level fact for every direction: the app's content
  container is 1280px, left-aligned (`layouts.ex`, `max-w-7xl`); Home
  opts out with `full_width`. Discovery centres an 896px column inside
  it, which is why the list sits in the left third at 1920.
* `2026-09-26` — The owner, on the shipped Feed at the desk: "bunches of
  dark boxes"; then "show me a bunch of mockups with a variety of options
  and parameters. no false options, everything you show me should be a
  good idea", and "take your time to consider some good options". Round
  10 is that: six presets and a switchboard, all from G's page.
* `2026-09-26` — Round 10's mockup ground is the app's, layer for layer
  (`round10.css`, `data-ground="app"`): base-100, the two blobs, and
  `.page-side-dim` as `app.css` paints them. The earlier rounds' single
  radial had flattered the design; the reference cell now reproduces the
  owner's screenshot. A "dark" ground is that page with the vertical dim
  from the top (≈15%) — one scrim variant away.
* `2026-09-26` — Round 10 finding: the **wide still** (from x=400, 836 of
  the 1236, a 48% slice) frames every fixture's subject at the settled 30%
  crop and draws the frame larger for the couch; the **full-bleed** still
  (1236, 32%) cuts faces and stays a knob, not a preset. Lifting the unit's
  tone instead of darkening the page fades the boxes from the wrong side
  and costs the words; kept as a knob only.
* `2026-09-26` — The owner: the poster and the backdrop together "may be
  causing some irritation"; what could the UI do with the backdrop and
  the logo instead? Round 11 answers on Q6's page. Diagnosis for the
  record: with the poster, every band carried two pictures of one title
  in two aspects, the title twice (printed and typed), and three objects
  at the band's left; the rail repeats the posters a third time.
* `2026-09-26` — Round 11 findings: a headline logo needs the band at 264
  (the poster set 224); a logo placed on the picture at the seam covers
  the subject's face on most stills, so the title card's place is the
  bottom right over a foot gradient; **the typed fallback goes where the
  logo goes**, or the mix moves the title around the band; the fallback
  wants 34px beside a 50px wordmark. The wordmarks are stand-ins built
  from each title's name in the machine's fonts — TMDB has almost no
  logos for the showcase's public-domain titles, and real titles may not
  appear in committed mockups.
* `2026-09-26` — The owner: "i hate the timestamp being in the middle of
  the row and the image on the right". Round 12 answers by moving the
  picture. Finding: a 16:9 box at the band's height shows the still
  whole, which deletes the crop rule, the adjacency offset
  (`offset_crop?`), the mask and the scrim rather than tuning them; a
  time at the band's edge needs ground under it — ink, or a right-edge
  vignette over a full-bleed still (the round-5 lead's device); a review
  wants a 640px measure, not the band's width.
* `2026-09-26` — The owner: "what about S2 but the logo is atop the
  backdrop, like we do for the card view on the home page?" Rendered as
  S5 and S6 with Home's card treatment verbatim. Finding: with the title
  on the picture the panel has no title line, so the band does not grow;
  the Feed's band and Home's Continue Watching card become one idiom,
  which argues for extracting the card's gradient-and-logo block into a
  shared component when this lands. The tile moves to sit between the
  picture and the sentence in S5; S6 keeps it first on a smaller card.

## Next steps

1. **Reconcile.** Owner looks at the shipped Feed on the dev server under
   Everyone with the real roster; name what is hard to tell apart and at
   what roster size (three friends today; design for thirty).
2. **Diagnose before drawing.** Why the word alone reads as too quiet:
   the name is the smallest text on the row, the same weight for every
   author, and every row shares one tint. Write the diagnosis into the
   spec's Problem section before any mockup.
3. **Mockup round 4** — running. Five directions from
   `docs/superpowers/specs/2026-09-24-feed-appearance-mockups/BRIEF.md`,
   each a different structure and a different author-mark device
   (identity tile per row; per-friend hue on the name; author runs with
   own runs tinted; a size ramp by recency; a tile column marking runs).
   Then the comparison sheet and `CRITIQUE.md`, scoring each against the
   diagnosis, the house rules, and the "holy crap" bar; then the owner
   picks a direction, or asks for a round 5 that crosses two.
3b. **Round 5** — done (`BRIEF-5.md`, `CRITIQUE-5.md`): the cross in
   four settings plus A2; every open question settled by render.
3c. **Round 6** — done: `F-cinematic-feed`, the settled choices on one
   page with fourteen states; its REASONING's size table is the draft
   of the spec's "What the user sees".
3l. **Implementation** — approved; runs in a new context from the
   Handoff above, Phase 1 first. Phases 1–5 done.
3m. **Round 10 — the ground, the edges, the still** — running: the owner
   picks a preset (Q1–Q6) or names a combination by its switchboard link;
   then the tweak lands as CSS under `/unify_design`, one commit, the
   story's variations pinning the band and the card at rest and under
   the hover pin; the spec's size table and UIDR-046 take the ground, the
   sheet and the still's origin.
3n. **Round 11 — backdrop and logo** — running: the owner answers R1's
   test (is the poster the irritation?) and, if the logo, picks R2, R3 or
   R4 or a switchboard link. If a logo direction lands: `FeedEntry` takes
   `logo_url` from the ladder the projection already calls; the band
   loses the poster and gains the logo slot with the typed title as its
   fallback; the story pins a band with a logo, without, and without
   artwork; UIDR-046 records that the Feed's title is the logo, else the
   name, as the hero's is. The rail keeps its posters (UIDR-046: a
   person's card is their acts).
3o. **Round 12 — the picture's place and the time's place** — running:
   the owner picks S1–S6 or a switchboard link; the critique's pick is
   S5, the owner's own proposal. If S5 or S6 lands, the card's
   gradient-and-logo block is extracted from `ContinueWatchingRow` into
   one component Home and the Feed share. If a left-hand
   composition lands, the implementation pass deletes the crop machinery
   (`offset_crop?`, the adjacency pass in `FeedEntries`, the mask and
   scrim CSS) as part of the change, and the spec's size table is
   rewritten to the thumbnail. The three rounds' picks make one
   implementation pass, not three.
3k. **Round 9f** — done: the act mark settled as the fixed-slot header
   above the poster; G and J patched; the spec and plan rewritten to
   it; the grade threshold set at two friends.
3j. **Round 9e** — done: J carried the corner disc (since retired); the spec and the
   plan are re-derived from G and J. **Next: the owner's go, then
   Phase 1 of the plan.** Was: the spec's
   "What the user sees" and the implementation plan re-derived from G
   and J.
3i. **Round 9d** — done (the clipped corner picked). Was: `K-flag-forms`, five forms for the act
   glyph on a poster (footer band, clipped corner, stamp, under the
   poster, the mast as control) on the same cards at both widths; the
   owner asked whether the pennant is the right form.
3h. **Round 9c** — running: `J-friends-page`, H's grid with I's acts
   strip, and the rail column redrawn once beside it for the shared
   component.
3g. **Round 9** — done (`CRITIQUE-9.md`): adopt the acts strip on
   both person surfaces (the mast placement, a 28–32px outline glyph,
   the note kept); keep H's grid and card frame. Was: `H-friends-page`, the Friends tab
   breathable and poster-led in a grid; and `I-acts-strip`
   (`BRIEF-9b.md`), the owner's pitch of posters flying the pennant's
   flags (eye, heart, thumbs, bubble, bookmark) in place of the
   presence sentence, in three placements at both card widths. The
   Feed is settled.
3f. **Round 8** — done (`BRIEF-8.md`, `CRITIQUE-8.md`):
   `G-couch-feed` replaces F as the proposed page (two full-height
   columns at couch scale, no lead, the rail as person cards with four
   sharing states, paging drawn); `G-friends-page` is the Friends tab.
   Two small fixes (the strip's caption; one slot for the note and the
   You subtitle) and the Friends page's two-column grid at 1920 are
   the next render. Then the spec's "What the user sees" and the plan
   are re-derived from G, and UIDR-046 is written.
3e. **Round 7** — done (`BRIEF-7.md`, `CRITIQUE-7.md`): couch scale
   and the Friends rail. Round 8, on the owner's word: one assembled
   couch page (R3's structure, R1's rail density, every state)
   replacing F; then the spec and the plan re-derived.
3d. **Draft implementation plan** —
   `docs/plans/2026-09-25-cinematic-feed.md`, test-first, six phases,
   written before the owner's decision so a yes goes straight to
   work; its "Owner decisions this plan assumes" section lists the
   forks.
4. **Decide the records.** Choose a direction; write the spec and a UIDR
   that amends UIDR-045 rule 3 and, if an avatar-like or hue device is
   chosen, UIDR-038's anti-patterns and the colour rule, stating the
   exception precisely.
5. **Plan and implement** through the usual test-first plan; the row
   component's story pins every author state.
6. **Then the Feed's hardening pass**: nav zones for the rows and the
   scope pill, once the layout stops moving.

## Deferred from this campaign

* **A detail layer on the act disc** — hover on the desktop, the
  cursor state on the TV — showing the verb, the episode and the title
  the disc's poster stands for. The owner's call, 2026-09-25: a
  separate scope after readability is settled.

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
  does not exist**; several stories show a broken image. *Closed by
  Phase 1 (2026-09-25): every story reads
  `/images/storybook/sample-poster.jpg`, a tracked PD fixture.*
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
