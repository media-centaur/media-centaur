# Remove the pennant and the rose — implementation plan

Design: `docs/superpowers/specs/2026-09-28-remove-pennant-and-rose-design.md`.

Six layers. Each ends with a working app, `agent-mix precommit` green,
and one commit. Stories change before components (storybook skill).

## Layer 1 — the social glyph as one component

1. `Grade.grades/1` (moved from `People`): `[row] -> %{{ref, flag} => grade}`,
   one count per person per title and flag. Unit tests first
   (`grade_test.exs`), then `People` calls it.
2. `Title.Flag`: drop the `:line` weight; `glyph/2` takes `:outline | :solid`
   with love hollow at `:outline` (`hero-heart`). `mast_order/0` →
   `order/0`, `sort_by_mast/1` → `sort/1`. Update `flag_test.exs`.
3. New `Title.SocialGlyph`: `social_glyph/1` (`flag`, `grade`, `class`)
   draws one glyph — `data-flag`, `data-grade`, outline at plain, solid
   under the metal otherwise; `social_glyphs/1` (`flags`, `grades`, `class`)
   draws a title's glyphs in flag order. Story
   `storybook/title/social_glyph.story.exs`: flag × grade matrix.
4. CSS: `.act-glyph`/`.act-icon` → `.social-glyph`/`.social-icon`; the
   `--act-brush` token moves to `:root` as `--social-brush` so the metal
   works outside a person card.
5. `PersonCard` renders its strip and its opened rows through the new
   component (opened rows: graded, per the design § 3.7). Person card
   story and tests follow the rename.

## Layer 2 — the rose goes

1. Feed row: the sentiment glyph is `social_glyph` at plain.
2. Delete `Title.Sentiment`, its story; `--color-love`, `.text-love`.
3. Update feed row story/tests.

## Layer 3 — the Review modal's choice

1. `review_modal.ex`: the sentiment group is `segmented_control`
   (`options` Dislike/Like/Love, `selected` the flow's sentiment,
   `event` `review_sentiment`). The clear-on-second-press rule stays in
   the handler; its test stays.
2. Delete `.pennant-choice` CSS.

## Layer 4 — one feed, graded, on the title rows

1. `Activities.friend_activity_for/1` → `activity_for/1`: every known
   person's live acts, the reader's included (drop `pennant_author?/2`'s
   own-kind rule; keep the former-friend exclusion). DataCase tests
   first: the reader's watched and listing rows are returned.
2. `Title.Row`: the pennant becomes `social_glyphs/1` at the row's right,
   vertically centred, grades from `Grade.grades/1` over the row's
   activity, the sentence as each glyph's `title` (the pennant's
   `tooltip/1` moves to a pure `Title.SocialWords` — label and tooltip
   tests move with it).
3. Hosts (`discovery_live.ex`, `media_results.ex`, `incoming_live.ex`,
   `title_detail_host.ex`) rename the call; stories for the title row and
   media results follow.

## Layer 5 — the social capsule and the social panel

1. `Title.SocialPanel.entries/1` (pure): the reviews newest first, then
   one `{flag, people}` per text-less flag in flag order (reviews
   excluded from the sentences). Unit tests first.
2. Components `social_capsule/1` (button: the glyphs at 24px on the ink
   pill, the chevron, `aria-expanded`, `phx-click="social_panel_toggle"`,
   zone `detail_social`) and `social_panel/1` (the glass panel, click-away
   and `data-nav-dismiss-event="social_panel_close"`). Stories: capsule on
   imagery at rest and open; panel reviews only, acts only, both, long.
3. `ModalState.open_menu` gains `:social`; `TitleDetailHost` handles
   `social_panel_toggle` / `social_panel_close` (LiveView tests: toggle,
   close, and opening another menu closes it).
4. `CinematicShell` slot `:hero_mast` → `:hero_corner`; `.detail-hero-mast`
   → `.detail-hero-corner` (12px inset). `DetailPanel` fills it with the
   capsule and the panel; the lead review line replaces `note_line` for an
   activity (tile, name, glyph, text); the watchlist note keeps its line.
5. Input: `config.js` — `detail_social` (TOOLBAR) in `contextSelectors`,
   `instanceTypes`, the `detail` overlay's layout
   (`detail_social: { down: ["detail_actions"], back: ["detail_actions"] }`,
   `detail_actions.up: ["detail_social"]`); not in `entry`. Bun nav-graph
   test. Verify with `mc-nav-trace`.
6. Delete `Components.Title.Pennant`, its story, the index entry,
   `pennant_test.exs`, the `.pennant*` CSS; rewrite the detail panel
   story's pennant variations as capsule variations.

## Layer 6 — docs

- New UIDR "Friend activity on a title is the social capsule"
  superseding UIDR-037 (records the social glyph rename); dated
  amendments on UIDR-040 (no warm hue) and UIDR-046 (the pennant is gone;
  the grade is on every title surface); `scripts/gen-decisions-index`.
- `docs/GLOSSARY.md` (Pennant out; Social glyph, Social capsule, Social
  panel in; Review, Sentiment, Ignored, Feed, Grade), `docs/social.md`,
  the user-interface skill (Pennant recipe → Social capsule; UIDR table;
  inventory).
- Wiki: `Social.md` (§ where a friend's activity shows, the Review
  dialog, List; commit the pending grade edit with it), `Watchlist.md`.
- Memory: retire `project-remove-pennants-and-rose` when done.

Verification at the end: page-shots of the hero at rest and open, a
watchlist row, the Review modal, a Feed row; `mc-nav-trace` up from the
action row to the capsule, SELECT, BACK.
