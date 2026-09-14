# Plan board — the empty outcome: calendar verdict and the watchlist

Date: 2026-09-14. Builds on UIDR-022 (the gap banner states the diagnosed
world with its evidence), UIDR-029 (the plan board narrates a diagnosis)
and UIDR-039 (add to watchlist first, then the tracking controls).

## Glossary

- **Plan board** (existing) — the live display of a draft plan on Incoming (`?plan=<id>`): verdict, episode grid, outcome rows, kept releases, footer.
- **Gap verdict** (existing) — the board's one diagnosis sentence for a ready plan with unfound units (`ViewModels.GapVerdict`): a closed set of *worlds* the counts prove, each with a headline and an evidence line.
- **Empty board** — a ready plan whose every wanted unit is unfound: nothing to approve. The footer carries no *Approve plan*; today it carries only *Discard*.
- **Release window** — where a movie stands in its release sequence, read from TMDB's US release dates by type: *theatrical* (type 3), *digital* (type 4), *physical* (type 5), plus TMDB's primary `release_date`. Read at a date it is a **stage**: `:unreleased` (every known date is ahead), `:theatrical` (opened in theaters, no home release yet), `:home` (a digital or disc release has passed), `:unknown` (TMDB says nothing usable). `MediaCentaur.TMDB.ReleaseWindow`. Unrelated to the corpus *freshness window* and the history *window* — those are spans of time, this is a position in a sequence.
- **Home release** — a movie's digital or physical release: the first date from which a release can exist on an indexer. The theatrical date is not one.
- **Calendar world** — a gap-verdict world whose diagnosis is the release window rather than the search evidence: `:unreleased` and `:in_theaters`. Movies only; a series plan wants aired episodes by construction.
- **Bookmark** (existing) — the one click that lists a title (`Components.Title.WatchlistToggle`; accessible name *Add to watchlist*); at List and above it is a marker. The listing verb everywhere a title appears (UIDR-039).
- **Subject** — the plan modal's word for the plan's title as the app-wide `TMDB.Title` value: what the bookmark acts on. The lockup's `title` is a display string; the subject is an identity.

## Problem

When a plan finds nothing, the board says why in search terms ("No indexer had anything for this title", "N results came back, but none looked like this movie") and offers *Search again* and *Discard*. Two things are missing:

1. **The calendar.** For a movie still in theaters, or not yet released, the search evidence is the wrong diagnosis: no release can exist yet. TMDB knows the dates; the board never says them, so the person searches again, or hunts by hand, for something that cannot be found.
2. **The remedy.** The app's answer to "not out yet" is the watchlist — list it, then set Follow on the watchlist and the release appears under Coming up (UIDR-039). The empty board offers no way onto the watchlist; the person has to close the plan, find the title again and bookmark it there.

The board must gain both without becoming a stack of rows. The verdict block is the one place the diagnosis lives; the footer is the one place the plan's actions live. Nothing new is added beside them.

## Decisions

### The calendar is a world of the diagnosis

1. **`MediaCentaur.TMDB.ReleaseWindow`** — a pure value built from a TMDB movie payload at a date: `from_payload(payload, today)`. Fields `stage`, `theatrical`, `digital`, `physical` (the earliest US date of each type, via `Mapper.us_typed_release_dates/1`), `primary` (TMDB's `release_date`). Stage rules, in order:
   - a home release (the earlier of digital and physical) has passed → `:home`;
   - every known date (typed or primary) is after today → `:unreleased`;
   - the theatrical date has passed and either a home date is known ahead, or the opening is within the last 180 days → `:theatrical`;
   - otherwise → `:unknown`.

   The 180-day bound is the only judgment in the module: TMDB's silence on a home date for a film that opened years ago means nothing, and "in theaters since 1994" would be false. Within a theatrical run's plausible length the silence is the state of the world. Named as `@theatrical_run_days` with that reason beside it.

2. **`GapVerdict.build/2` takes `release_window:`** (a `ReleaseWindow` or nil) and gains two worlds, `:unreleased` and `:in_theaters`, from stages `:unreleased` and `:theatrical`. Precedence: `:blind` outranks everything (an infrastructure fault must be fixed regardless); `:below_preference` outranks the calendar (real releases exist, so "not out" would be false); the calendar worlds outrank every search diagnosis (`:no_evidence`, `:rejected`, `:nothing_live`, `:nothing_stale`). A calendar world keeps the underlying search diagnosis's evidence line, rejected count and *Show them anyway* — the receipts are still true, and a rejected list may still hold the one real result. Stages `:home` and `:unknown` change nothing.

3. **Headlines.** Dates read as `Format.month_day/1` ("Oct 3"), with the year appended when it is not this year ("Oct 3, 2027").
   - `:unreleased` — "Not out yet — in theaters from Oct 3." When a home date is also known: "Not out yet — in theaters from Oct 3, digital release Dec 12." With no theatrical date: "Not out yet — digital release Oct 14." / "Not out yet — on disc Oct 14." With only the primary date: "Not out yet — releases Oct 3."
   - `:in_theaters` — "In theaters since Aug 21 — digital release Oct 14." / "In theaters since Aug 21 — on disc Oct 14." / "In theaters since Aug 21 — TMDB has no home release date yet."

   The calendar worlds render in the same warning row as the search worlds (the glass-inset row with the triangle): the shape of the block does not change, only the sentence.

4. **The host fetches the window once per movie board.** `IncomingLive.load_plan_board/2` starts `{:plan_release_window, plan_id}` (`start_async`, `TMDB.Client.get_movie/1`) on a fresh open of a movie board when TMDB is ready — the same trigger as the board's artwork. The handler derives the window against the page's `today`, assigns `plan_release_window`, and re-reads the board so a ready verdict picks it up. The fetch is served from the HTTP response cache the plan's own creation just filled. A failure leaves the window nil and the search diagnosis stands. Series boards fetch nothing. The window is not stored on the plan: a draft can sit for days, and the one case that matters — a digital date announced after the plan was made — must read TMDB's current answer.

### The empty board offers the watchlist

5. **The footer's action slot carries the bookmark, in its labelled form.** On an empty board (`status == :ready`, no releases) the footer's right group reads *Discard* then, in the primary position, **Add to watchlist** (`variant="secondary"`, bookmark glyph). Once the title is at List or above the same slot is the marker **On your watchlist** (solid bookmark, primary tint, no click). `WatchlistToggle.listed?/1` is the one rule that decides which. A board with releases shows neither: its primary action is *Approve plan*, and a partial plan's remedy is a follow-up, not this change.

6. **One event, one write path.** The button pushes the host's `set_rung` with `choice=list` and `ref` (`TitleRef.param/1`), exactly as the title view's bookmark does. `IncomingLive.resolve_title/3` learns a third source: the open plan's subject, when the ref matches. `ReleaseTracking.set_rung/3` writes; List never needs the calendar, so the move is synchronous. The marker follows `@title_rungs` from `IntentAware`, which the rung-change broadcast already refreshes — no new assign, no new message clause.

7. **The subject comes from the plan row.** `plan_title` is a `TMDB.Title` built from the plan's `tmdb_id`, `tmdb_type`, `title` and `year` when a board opens — the shape Incoming already builds for a tracked title in `resolve_title/3`. Artwork for a listed title comes from `Discovery.put_rung/3`'s own artwork fetch, keyed by id; the snapshot needs no paths.

8. **`PlanModal` attrs.** `subject` (`TMDB.Title`, default nil — nil hides the control) and `rung` (the subject's rung, nil for Off). The board stage renders the footer control from them.

### Unchanged

9. The verdict block's *Search again* and *Show them anyway*, the below-preference and offer rows, the grid, Discard's arm gesture, the input-system layout (`plan_body` is a TREE; a new nav item needs no config), the drop planner and the gate.

## Rejected

- **A second row under the verdict for the calendar.** Two stacked warning rows, two sentences, two icons — the "jamming" the owner named. The calendar *is* the diagnosis; it belongs in the verdict's sentence.
- **Storing release dates on the plan.** A snapshot goes stale exactly when it matters (the announced digital date). TMDB, through the response cache, is the owner.
- **Showing the window for a home-released movie** ("Digital release was Sep 10 — releases usually follow within days"). The second half is a guess, and the first adds nothing the search verdict does not already answer.
- **Offering Follow from the board.** UIDR-039: listing first, then the tracking controls on the watchlist or the title view. The board is a download surface; it lists, it does not track.
- **A toggle (remove) on the board once listed.** Removal belongs to the watchlist; a mis-click undo is a marker's worth of protection.
- **The control on partial boards** (three of four episodes found). Approve is the primary action there; adding a second labelled button crowds the footer. Follow-up if wanted.
- **Extending `TitlePreview.upcoming?`.** It gated a verb removed in v1.22.0 and nothing reads it; it is removed, and the release window is the one representation of "not out yet".

## Data changes

None.

## Testing

- `TMDB.ReleaseWindow`: each stage; the 180-day bound; primary-only payloads; the earliest date per type; a payload with no dates.
- `GapVerdict`: the two calendar worlds' headlines (each date combination); precedence against blind, below-preference and each search world; the evidence line and rejected escape hatch carried through; a series plan ignores the window; `:home` and `:unknown` change nothing.
- `Format.month_day/1`.
- `IncomingLive`: a movie plan whose TMDB payload says in theaters headlines the calendar and offers *Add to watchlist*; clicking it lists the title (`Discovery.rung/2` is `:list`) and the footer shows the marker; a title already listed opens with the marker; a series plan with nothing found offers the control; a board with releases offers neither; a TMDB failure leaves the search verdict.
- Storybook: the plan modal's gap variations carry a subject (control shown), plus `board_gap_in_theaters`, `board_gap_unreleased`, `board_gap_listed`.
- Real browser: the storybook variations on the dev server, the footer by mouse.

## Documentation

- Moduledocs: `ReleaseWindow`, `GapVerdict`, `PlanModal`, `Format.month_day/1`.
- UIDR-022: dated amendment — the release calendar is a world of the diagnosis; the empty board offers the watchlist.
- `docs/GLOSSARY.md`: release window, home release; the plan board row.
- Wiki *Searching-and-Downloading*: the two calendar verdicts in the verdict list; the footer's *Add to watchlist* on an empty board. *Watchlist*: a sentence under "What happens after Download".

## Coherence pass (unify_design, 2026-09-14)

**Core idea.** The board's verdict is the diagnosis of an empty search, and a movie's release window is that diagnosis's first witness: it is the one fact that decides whether a search could have found anything. The remedy for "not out yet" is the watchlist, so the empty board offers it where the plan's actions live.

**Greenfield shape.** One value for the release window, owned by the TMDB context and read at a date; the verdict takes it as one more input and speaks it as a world; the footer's action slot holds the bookmark in the same labelled form the Feed uses, pushing the same event the title view pushes.

**Diff against the code.** The extraction exists (`Mapper.us_typed_release_dates/1`, used by the release calendar); the interpretation did not — `TitlePreview.upcoming?` was a dead boolean cousin of it, and the Coming up shelf reads the same dates through tracked-title rows. The verdict had no calendar input. The board knew its title as a string, not an identity.

**Dispositions.** `upcoming?` → removed (fix now). The board's subject → a `TMDB.Title` assign built from the plan row, the existing tracked-title precedent (fix now). Coming up's theatrical labels → left as they are: they read calendar rows, not payloads, and converge only if the release window ever grows a row-backed constructor (not scheduled). The title detail modal's Download on an unreleased movie still plans and lands here; the window could inform that button — noted, not scheduled, since this board is where the answer is now given.

**Cost.** One TMDB read per movie board open, cache-served. Otherwise the change is additive at three seams (a value, a verdict input, a footer slot).
