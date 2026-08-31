# Direction 2 — Verdict first

## Style description

Editorial standfirst inside the existing cinematic frame. The body opens with one
sentence in comfortable reading type (1.35rem, weight 400, base-content 90%) that
states what the counts prove and nothing more. The decision buttons sit directly
under it, followed by a one-line scope note. A hairline separates that from the
supporting material, which is set as quiet prose at 70% / 50% opacity: a short
"what we found" paragraph with the receipts (searches, results, indexers, freshness)
on a single muted line, the season grid, the kept-release row(s), and a collapsed
"How we searched" disclosure. No panels except the glass inset used by release rows,
no chips, no bars, no tiles. Colour appears only in grid cells and the primary button:
success tint for kept, info tint for available-but-below-preference, hollow dashed for
nothing. Counts use tabular numerals throughout.

## Design decisions

- **Verdict replaces the status line and the descent headline.** "Plan ready · 1 of
  22 covered" and "Season packs — covered 1 — 21 still missing" both narrated
  arithmetic. The verdict says the thing a person actually needs: this show exists
  almost entirely in SD; one episode in 1080p; the other 21 only in SD.
- **Action directly under the verdict.** The decision is the reason the popup exists
  in this case, so it is the second thing on the page, not the last. One primary
  ("Take SD for this show"), one neutral secondary ("Show the SD releases"), one scope
  line. Nothing else above the hairline.
- **Scope stated once, in the place the eye lands after the button.** "This show only —
  your 1080p preference doesn't change." The lockup meta line repeats the preference
  as context ("1080p or better") but does not restate the scope.
- **The hold-out path is not hidden, but it is demoted.** "Grab only the 1080p episode"
  sits under the kept-release row as a small neutral button with a one-clause
  consequence ("The other 21 stay wanted at 1080p."). It is a different action from the
  primary, so it is not a duplicate CTA; placing it near the release it acts on keeps
  the above-the-fold to exactly one decision.
- **Receipts as a muted line, not tiles.** "24 searches · 253 results · 3 indexers
  answered · live, just now" carries the credibility of the verdict without asking for
  attention. The impostor is one clause in the prose ("One result was another show and
  was set aside"), where it belongs — it is evidence of filtering, not a headline.
- **Grid is the only structured element, and it stays small.** Three visual states
  (kept / SD available / nothing found), plus a fourth in State C that separates kept-SD
  from kept-1080p with a lighter success tint so the accepted state is visibly
  different from the 1080p hit. The legend carries counts so the grid never needs a
  caption sentence. Capsule fusing is not exercised because every release here is a
  single episode.
- **State A has no buttons.** While searching, the verdict slot holds a live sentence
  with a small spinner ("Searching… 2 of 24 searches done — so far 153 results, 1
  kept"). Offering "Take SD" before the per-episode pass has finished would be a
  premature decision; the slot simply waits. Pending cells pulse at low opacity and a
  few settle into "SD available" on staggered CSS delays, which is the only motion on
  the page. `prefers-reduced-motion` disables it.
- **State C keeps the same skeleton.** The verdict becomes the confirmation ("Taking
  Murphy Brown in SD — 21 releases queued. This show will keep accepting SD."), the
  primary button disappears, and a quiet underlined "Change" link follows the scope
  note. The grid fills; the release list grows to 22 with a "Show all 22" link rather
  than 22 rows.
- **Ladder internals live only in the disclosure.** Three short paragraphs — whole
  series, season, episode by episode — each stating what was searched, what came back,
  and what was done with it. No dots, no rung bars, no per-rung counters outside it.

## Requirements mapping

### Evidence narrative (looked for / offered / rejected / kept)
- *What we looked for*: lockup meta ("Season 1 · 22 episodes wanted · 1080p or
  better") and the disclosure's three rungs.
- *What the world offered*: verdict sentence + "what we found" paragraph (every result a
  single episode; no packs; 253 results; about 97 SD results for Season 1).
- *What we rejected and why*: "One result was another show and was set aside"; the SD
  results are described as below the preference, not as missing.
- *What we kept*: the kept-release row(s) and the success-tinted grid cell(s).

### Policy B flow
- One action meaning "SD is fine for this show": **Take SD for this show** (primary,
  stated once).
- Grabs now and keeps treating the show that way: the State C verdict says both
  ("21 releases queued. This show will keep accepting SD.").
- Global preference untouched: the scope note under the button, and again under the
  State C verdict. The lockup meta line in State C changes to "SD accepted for this
  show" so the per-show scope is visible in the pinned header too.
- Quieter secondary: **Show the SD releases** as a neutral button beside the primary.
- Reversibility: "Change" link in State C.
- The word "floor" does not appear. Copy uses "your preference" / "what you asked for"
  phrasing.

### Consistency with the app
- Same shell: backdrop + scrim + pinned title lockup + scrolling body, close button top
  right.
- Tokens from the brief: base-100/200/300, base-content opacity ladder (90/70/50/40),
  primary, success, info, glass-inset bg + border, radius-box 0.5rem, radius-field
  0.25rem, system sans, tabular-nums.
- Buttons: one primary per view; neutral buttons are translucent white 8% with a
  hairline border; small variants for row-level actions.
- Release rows keep the existing shape (title, quality, size, seeders, Options /
  Remove).
- Colour only carries meaning: success = we have it, info = available below
  preference, no decorative colour anywhere.

## Trade-offs

- **Verdict wording is hand-authored for this case.** The sentence is the strongest
  part of the direction and the hardest to generate. It needs a small template family
  (all found / mostly SD / partly missing / nothing anywhere) with the numbers filled
  in; the mock shows only the "mostly SD" branch.
- **The hold-out path is below the fold.** A user who wants to approve the single
  1080p release without accepting SD has to scroll past the grid. That is deliberate
  for this case (the SD decision is the important one) but it would be wrong when the
  found-in-preference count is high; the template family above should swap which
  action is primary.
- **State A cannot show the verdict early.** Until the per-episode pass finishes, the
  slot is a progress sentence. Someone impatient sees no decision for the duration of
  ~22 searches. The alternative — showing a provisional verdict — would risk stating
  something the counts do not yet prove.
- **Grid legend repeats counts that the verdict already gives.** Accepted because the
  legend is 50% opacity and the grid needs a key for the cell states regardless.
- **Prose paragraphs need discipline in code.** Sentence templates with numbers are
  easy to make ungrammatical ("1 episodes"). Pluralisation and the "about" qualifier
  for aggregated counts must be handled in the view helper.

## Mock-data notes

- Sizes and seeder counts on release rows are invented; the brief does not supply them.
- The State A partial grid (12 SD available, 9 pending after two searches) is
  illustrative; the brief says the first two searches returned single episodes across
  S01–S10 without saying which Season 1 episodes were covered.
- The direction specifies 24 searches; the brief's arithmetic (1 + 1 + 21) gives 23.
  The mock follows the direction's numbers verbatim.
