# Direction 3 — The grid is the story

## Style description

The season grid is promoted from a mid-body afterthought to the primary surface of the
popup body, directly under the cinematic lockup. Cells are 38px — big enough to read the
episode number — and every cell's fill IS its outcome. Three visual states, rendered by
fill and border only, never by chip color:

- **Kept at preference** — solid soft success tint (success at 18% alpha fill, 45% border).
  The only color on the surface, and it means exactly one thing: "you have this at what
  you asked for."
- **Available only in SD** — neutral dim outline with a small inner dot near the bottom
  edge. The dot says "something exists here" without claiming it satisfies you; the
  neutral tone says "informational, not failure."
- **Nothing anywhere** — hollow dashed outline (defined in CSS, unused in these states
  because the count is 0 — no redundant empty state, per the brief).
- State C adds a fourth: **SD, accepted** — solid neutral fill (white 9%), visually "held"
  but deliberately not success-green, because it is below the stated preference.

Below the grid, a single caption line acts as the hover/focus readout (E04 is mocked as
hovered in State B): episode number, title, best release, and the honest qualifier
"4 releases, none at 1080p". The line is reserved even when idle (a 40%-opacity hint) so
the layout never jumps.

Beneath that, **outcome groups as calm rows** — hairline-divided rows, not tiles, not a
table. Each row opens with a 14px swatch drawn in the exact cell style, so the rows double
as the grid's legend without a separate legend block. Everything else is the app's normal
hierarchy: base-content at 90/70/50/40%, tabular numerals, one primary button per view,
neutral translucent buttons otherwise, glass hairlines, radius tokens from the brief.

Search mechanics are one 12.5px footnote line under everything, with a `<details>`
disclosure ("How we searched") that opens three short prose paragraphs — the descent
narrative in quiet sentences, not rungs, bars, or logs.

## Design decisions

1. **The grid carries the truth in one glance.** 21 dim-outlined-with-a-dot cells next to
   one green cell reads instantly as "this show exists, almost entirely in SD" — the exact
   correction of today's false "couldn't be found anywhere." No prose is needed to make
   the point; the prose only totals it.
2. **Swatches-as-legend.** The outcome rows start with a miniature of the cell style they
   summarize. This binds grid and rows into one system and avoids both a dedicated legend
   row and any temptation to reach for colored chips.
3. **The decision lives on the group it decides.** "Take SD for this show" (the view's
   only primary) sits on the 21-episode SD row, with the quiet "Show them" beside it and
   the scope sentence directly underneath: "This show only; your 1080p preference is
   unchanged." Policy B's two promises — grabs now, and no re-asking later — are stated
   where they apply, once.
4. **Approve stays neutral and explains the hold-out path.** The commit row keeps the
   shell's Approve action but demotes it to a neutral button with one sentence: "Approve
   grabs the 1080p episode now and keeps waiting for 1080p on the other 21." That makes
   "hold out" a real, named alternative without a second primary.
5. **Nothing-anywhere row omitted.** Count is 0, so the row does not exist. The hollow
   cell style exists in CSS for the day the count is nonzero.
6. **State A resolves cells as searches land.** Cells 1–8 have resolved to SD-only, E13
   is kept (from the season-pack rung), the rest pulse faintly at the border — a state
   indicator, not an entrance animation. Outcome rows show partial counts with "so far"
   and carry no buttons; the only decision-shaped text is "Decide once the search
   finishes." Footnote shows live progress ("10 of 24 searches done") — no per-rung bars.
7. **State C shows the policy's consequence.** All 22 cells filled, but only E13 is green;
   the 21 accepted-SD cells are neutral solid — the grid keeps telling the truth about
   quality even after acceptance. The row copy states the durable scope ("Later seasons
   and episodes of Murphy Brown will take SD without asking") with an Undo escape, and
   Approve becomes the primary because the plan is now complete.

## Requirements mapping

- **Evidence narrative**: grid = what the world offered per episode; caption = the proof
  for any single episode on demand; outcome rows = the totals ("1 kept in 1080p", "21
  only in SD · 97 releases"); footnote = the audit line (24 searches, 3 indexers, live
  just now, 253 results, 1 impostor "was another show" — a count-provable rejection, no
  inferred causes); disclosure = the three-rung descent as prose for whoever cares.
- **Policy B flow**: one action, "Take SD for this show"; grabs now + persists per show;
  scope sentence names both what changes and what does not; "Show them" is the quieter
  inspect-first path; State C confirms the persistence in copy and offers Undo.
- **Consistency with the app**: cinematic frame shell untouched (backdrop, scrim, lockup,
  status line); dark slate oklch tokens, glass insets and hairlines, radius and button
  conventions verbatim from the brief; success/info color used only for meaning; sentence
  case, no exclamation marks, the word "floor" never appears.

## Trade-offs

- **Grid width scales linearly with episode count.** 22 cells at 38px fit one row at
  1100px; a 60-episode anime season would wrap to three rows. Wrapping is acceptable (the
  cells stay readable), but very long seasons dilute the "one glance" effect.
- **The SD dot is subtle by design.** At a distance the SD cells read close to hollow.
  That is intentional — SD-only must not read as "covered" — but it means the outcome
  rows, not the grid alone, carry the exact 21-vs-0 distinction between "SD exists" and
  "nothing exists." The swatch legend mitigates this.
- **Hover-dependent detail.** Per-episode release evidence lives behind hover/focus, which
  is weaker for the gamepad flow; the caption line is keyboard/gamepad-focusable in a real
  build (cells are nav items), but a controller user must walk cells to survey titles.
- **Result-count honesty.** The footnote uses the specified "253 results"; the per-episode
  rung is worded as "a few results each" so the disclosure never states arithmetic the
  brief's ~2-per-query figure would contradict. In a real build the total is computed, and
  the rung sentences should quote the real per-rung counts.
- **Options/Remove is reduced to a single quiet "Options" on the kept row.** Release-level
  management (swap, remove) moves behind it; this direction bets that the common case is
  the accept/hold-out decision, not release surgery.
