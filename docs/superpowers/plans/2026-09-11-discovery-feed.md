# Discovery › Feed — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Recommendations tab with the Feed — friends' recommendations and listings, one entry per action, newest first, with a hover toolbar — and replace the Tracking activity kind (32162) with a Listing kind (32163) on the wire.

**Architecture:** Four phases, each leaving a working product. Phase 0 is the relay release (cross-repo, deployed first). Phase 1 changes the wire vocabulary and renames every surface that said tracking. Phase 2 moves the publisher onto the rung-transition event. Phase 3 builds the Feed. Phase 4 is documentation.

**Tech Stack:** Elixir, Phoenix LiveView, Phoenix Storybook, ExUnit; Go (social-relay).

**Spec:** `docs/superpowers/specs/2026-09-11-discovery-feed-design.md` · [UIDR-038](../../../decisions/user-interface/2026-09-11-038-the-feed-is-friends-actions-one-entry-each.md) · [ADR-067](../../../decisions/architecture/2026-09-11-067-listing-replaces-tracking-on-the-wire.md)

---

## Rules for this plan

- **Never run `mix` directly.** Every Mix command is `~/scripts/agents/agent-mix`. A bare `mix` in this checkout writes `.beam` files under the running dev server and can take it down.
- Tests are written before implementation. A test that has never failed proves nothing.
- `~/scripts/agents/agent-mix precommit` must pass before the last commit of each phase. Zero warnings.
- The feed **ships mouse-only** (standing rule for iteration-phase surfaces). No `data-nav-*` on the toolbar verbs; the entry card gets none either. Nav wiring is the hardening pass.
- No real show titles anywhere authored (tests, stories, docs).

## Glossary (this plan's additions to the spec's)

| Term | Meaning |
|---|---|
| **Rung transition** | One `Discovery.Events.RungChanged` message, now carrying both `previous_rung` and `rung` (either may be `nil`, meaning Off) plus the title snapshot. Every subscriber decides its own threshold from the two ends. |
| **Toolbar slot** | One of the three positions in an entry's toolbar. The List slot and the Download slot each resolve to a verb *or* a state; the Ignore slot is always the verb. `FeedEntries.list_slot/1` and `download_slot/1` are the one place that resolution lives. |
| **Friend provenance** | The attrs a title intent takes when a person acts on a friend's activity: `%{source: :friend, activity_id:, note:}`. Spelled once, `TitleIntent.friend_provenance/2`. |
| **Window** | `feed_window` on the socket: how many entries the Feed shows; starts at `FeedEntries.page_size/0` (50) and grows by one page per *Show older*. |

---

## Unify-design pass

### Core idea

A friend's action on a title is one signed statement — an activity — ingested once; every social surface (the Feed, the Friends card, the pennant) is a pure projection of the same activity rows joined with the reader's own facts (rung, library presence, acquisition state). On the sending side the person's only act is moving a rung; a shared statement is *derived* from the rung crossing a threshold.

### Greenfield shape

- **Sending.** `Discovery` owns the rung and emits one event per move that describes the transition (both ends + title). `Activities.Publisher` subscribes to that event and translates threshold crossings into statements: onto List → publish a listing (while the toggle is on); below List → withdraw it. No context reads state before writing in order to fake a transition event later.
- **Wire.** Three activity kinds: recommendation, watched, listing. Withdrawal of any own kind is one path (`delete_own/1`) reachable by row id (the modal) and by address (the publisher).
- **Reading.** `DiscoveryLive` loads the enriched rows once; `FeedEntries` (flat, windowed), `People` (per person) and the pennant mast project from them. A feed entry is a view-model struct; the card renders it and decides nothing. Toolbar state resolves from the same three facts `Logic.row_markers/2` reads, with `Logic.acquisition_marker/1` supplying the acquisition words so no state is spelled twice.

### Diff against the code — incoherences and dispositions

| # | Incoherence | Disposition |
|---|---|---|
| 1 | Two events for one transition: `RungChanged` carries only the end rung, so `ReleaseTracking.set_rung/3` pre-reads `followed_before?` and fires a second event, `TrackingStarted`, whose only consumer is the publisher. | **Fix now.** `RungChanged` gains `previous_rung` and `title`. `TrackingStarted`, `announce_tracking_started/1`, `followed_before?` and `events_test.exs` are removed. |
| 2 | Friend provenance is spelled in `TitleDetailHost.provenance/1` and inline in `DiscoveryLive.ignore_title`; the feed's List verb would be a third copy. | **Fix now.** `TitleIntent.friend_provenance(activity_id, note)`; both callers use it. |
| 3 | The one-click download and its flash live inside the modal host, behind an open modal; the feed toolbar starts the same plan with no modal. | **Fix now.** `Plans.plan_title/2` is already the seam; `TitleDetailHost.download_flash/2` becomes public and the feed handler uses both. No second wording. |
| 4 | `RecommendationRows` (grouped, re-sorting) and `TitleRow`'s `lead` / `ignorable?` attrs exist only for the tab being replaced. | **Remove.** Module, its test, the two attrs, and the story's `ignorable` variation. `TitleRow` stays for the watchlist and media-search rows. |
| 5 | The toolbar reads the same facts as `Logic.row_markers/2` in a different vocabulary (verb-or-state per slot vs marker words). | **Not a duplicate pipeline.** Slots are resolved in `FeedEntries`; acquisition words come from `Logic.acquisition_marker/1`. |
| 6 | The watchlist rows' pennants come from a second query (`Activities.friend_activity_for/1`) while feed titles' come from the page rows. | **Pre-existing, deferred.** Not touched by this change; convergence point: the projections campaign follow-up (Discovery width at 4K) already listed in the spec's Deferred. |
| 7 | `share_tracking` preference and its Settings row. | **Replace.** `ShareWatchlist` (key `share_watchlist`, default off). The migration deletes the `share_tracking` row: the new toggle shares more than the old one did, so it is a fresh consent, not an inheritance. |
| 8 | `Format.relative_ago/2` stops at days; the spec and the wiki copy show weeks (`3w ago`, `1w ago`). | **Fix now, droppable.** Add the week granularity at ≥ 7 days app-wide, one test. If cut, the spec's "3w ago" reads "21d ago". |
| 9 | Withdrawal while the toggle is off. ADR-067 gates *publishing* on the toggle; a listing published earlier and then dropped would otherwise stay true forever on friends' shelves. | **Decision:** withdrawal runs whenever an own live listing exists, toggle or not. A statement that is no longer true is withdrawn. Recorded in the Publisher moduledoc. |

### Coherence cost

The bolt-on would be: add kind 32163 beside 32162, listen for a new event, add a fourth projection. The coherent path above adds roughly one session: the `RungChanged` shape change (Discovery + its tests + `IntentAware` / host consumers unaffected since they pattern-match the struct), the `TrackingStarted` removal, the provenance helper, the `TitleRow` attr removal with its story, and a relay release in front of the app release.

---

## Test strategy

- **Factories to use:** `TestFactory.build_activity/1` (kind override), `MediaCentaur.DiscoveryRows.activity_row/1` (enriched rows for pure projection tests), `Translation.to_event/5` + `Event.sign/2` (signed friend events in LiveView tests, as `friend_event/3` does today), `TmdbStubs.setup_tmdb_client/0`.
- **New test helpers:** `friend_listing_event(tmdb_id)` in `discovery_live_test.exs` (a signed kind-32163 event from the fixture friend). `DiscoveryRows.activity_row/1` already accepts `kind: :listing`.
- **Test types:** pure (`FeedEntries`, `ActivityWords`, `Pennant`, `People`, `Translation`, `Format`), DataCase (`Activities`, `Publisher`, `Discovery` events, `Sync` against `FakeRelay`), ConnCase LiveView (`DiscoveryLive`, `SettingsLive` social section, page smoke).
- **Key assertions**, mapped to the spec's acceptance criteria:
  - `/discovery` mounts the Feed tab; the tab count equals `length(feed)`.
  - Two friends on one title → two entries; one friend recommending then listing → two adjacent entries, newest first; no grouping.
  - A listing entry renders name, "wants to watch", relative time, title, year — and no note line; a recommendation renders the note and a heart only for Love.
  - Watched, own, former-friend and ignored-title rows never become entries.
  - No `.pennant` inside a feed entry; the watchlist row and the modal still fly them.
  - The toolbar exists in the DOM at rest (fixed seat) and carries the resolved slots: `list_slot` ∈ `{:list, :listed, :following}`, `download_slot` ∈ `{:download, {:state, word}}`.
  - List toggles `nil → :list → :off`; at Follow or above the slot reads Following and pushes nothing.
  - Download creates an automatic plan and flashes the host's sentence; the slot then reads Downloading.
  - Ignore removes every entry for the title, the count follows, Undo restores the rung and the entries; provenance names the entry's activity.
  - A friend's deletion of a recommendation or listing removes the entry without a reload.
  - Publisher: crossing onto List with the toggle on publishes one listing (`listed_at` in content); Ignored → List publishes; List → Follow publishes nothing; dropping below List withdraws (kind 5 addressing 32163) with the toggle on *or off*; toggle off → nothing published.
  - Sync subscribes with kinds `[32_160, 32_161, 32_163, 5]`; an inbound 32162 is dropped as `:wrong_kind`.
  - Settings: the toggle is `toggle_share_watchlist`, labelled "Share your watchlist".
  - Migration: an `activities` row with `kind = 'tracking'` and a `share_tracking` settings row are gone after `up`; running `up` twice is a no-op.

---

## Phase 0 — Relay accepts Listing (cross-repo, deploy first)

Repo: `~/src/media-centaur/social-relay`. ADR-067 §5: the relay must accept the kind before the app ships it, or every own-events diff republishes the listing on each connect and logs a refusal.

### Task 0.1: Kind 32163 stored, 32162 refused
- [x] `internal/relay/kinds_test.go`: replace `kindTracking` in the stored-kinds loops with `kindListing` (32163); add a case asserting a 32162 `EVENT` answers `blocked: kind 32162 is not stored by this relay`. Run `scripts/check` — red.
- [x] `internal/relay/kinds.go`: `kindListing nostr.Kind = 32163`; `activityKinds` = recommendation, watched, listing. Delete the `kindTracking` constant (numbers are retired in the *protocol table*, not in code). `relay_test.go` constant likewise.
- [x] `README.md`, `docs/protocol.md`: the kind list and the rejection row name 32160, 32161, 32163, 5.
- [x] `scripts/check` green. Commit `feat: store listing (32163); tracking (32162) retired`.
- [ ] Tag **v0.5.0** (the tag push triggers the release workflow); deploy to the friend group's relay before the app release. **Left for the owner: a public release.**

---

## Phase 1 — Listing replaces Tracking in the app's vocabulary

Every surface that said tracking says listing. The Feed does not exist yet; the Recommendations tab keeps working on the renamed kind.

### Task 1.1: Translation and Activity
- [x] `test/media_centaur/activities/translation_test.exs`: "every activity kind has its own number" expects `%{recommendation: 32_160, watched: 32_161, listing: 32_163}`; "a listing activity carries the title and its time only" (content `listed_at`, `acted_at_field(:listing)`); a signed 32162 event → `{:error, :wrong_kind}`; a deletion coordinate `32163:<pubkey>:tmdb:movie:7` round-trips. Red.
- [x] `lib/media_centaur/activities/translation.ex`: `@kinds %{recommendation: 32_160, watched: 32_161, listing: 32_163}`; `kind_content(:listing, …)` → `%{"listed_at" => acted_at}`; `acted_at_field(:listing)`; `kind_payload(:listing, …)`; moduledoc table.
- [x] `lib/media_centaur/activities/activity.ex`: `@kinds [:recommendation, :watched, :listing]`, `@type kind`, moduledoc.
- [x] `test/support/factory.ex` `build_activity/1` unchanged (kind is an override). `test/support/discovery_rows.ex` unchanged.

### Task 1.2: `Activities.listing/1` and `Activities.withdraw/3`
- [x] `test/media_centaur/activities/activities_test.exs`: rename the "watched/2 and tracking/1" describe → `listing/1`; add `describe "withdraw/3"`: withdraws the own live row of a kind at an address (tombstone, kind-5 published, `Events.Deleted`), `:ok` no-op when no live own row, refuses nothing (there is no foreign case — the address is always own). Red.
- [x] `lib/media_centaur/activities.ex`: `listing/1` replaces `tracking/1` (`publish_own(:listing, title, [])`); `withdraw(kind, tmdb_id, media_type)` finds `existing/1` for `me` and calls the existing `delete_own/1`; `{:ok, activity} | :ok`. Moduledoc: three kinds; "Recommending always publishes. Watching and listing are published by `Activities.Publisher`…".
- [x] `lib/media_centaur/activities/sync.ex`: `refused(:listing)` → "a listing". `test/media_centaur/activities/sync_test.exs` line 81: kinds `[32_160, 32_161, 32_163, 5]` (red first).
- [x] `lib/mix/tasks/social.dev.ex` + `test/mix/tasks/social_dev_test.exs`: `listing` replaces `tracking` in dispatch, `parse_kind`, usage text.

### Task 1.3: Migration — drop stored tracking rows and the old toggle
- [x] `priv/repo/migrations/20260911120000_listing_replaces_tracking.exs`: `up` executes `DELETE FROM activities WHERE kind = 'tracking'` and `DELETE FROM settings WHERE key = 'share_tracking'` (confirm the settings table/column names from `MediaCentaur.Settings.Entry` before writing); `down` is a no-op with a comment (the rows cannot be reconstructed and the kind is retired). Idempotent by construction. Moduledoc cites ADR-067 §3.
- [x] Run it against the dev DB via `agent-mix ecto.migrate` (memory: **run migrations for me**).
- [x] CHANGELOG note for the release: stored tracking activities are removed; "Share what you track" is gone and "Share your watchlist" starts off.

### Task 1.4: Words and pennant
- [x] `test/media_centaur_web/live/discovery_live/activity_words_test.exs`: `verb(:listing, nil) == "wants to watch"`, `noun(:listing) == "listing"`, `presence(:listing, nil, "Sample Show") == "wants to watch Sample Show"`. Red.
- [x] `lib/media_centaur_web/live/discovery_live/activity_words.ex`: the three clauses; moduledoc examples.
- [x] Pennant test (find or add `test/media_centaur_web/components/title/pennant_test.exs`): `mast/1` orders `[:love, :like, :watched, :listing]`; `tooltip` reads "Nick wants to watch this" / "Nick and Sam want to watch this". Red.
- [x] `lib/media_centaur_web/components/title/pennant.ex`: `@flags [:love, :like, :watched, :listing]`, glyph `hero-bookmark`, verbs. `assets/css/app.css`: no per-flag rule exists for tracking (only `.pennant-love`), so no CSS change; verify with grep before moving on. `storybook/title/pennants.story.exs`: variation `:listing`, description "A friend wants to watch it: a bookmark on the neutral tint."
- [x] `assets/` is untouched except CSS in Phase 3; remember dev asset watchers are off — `agent-mix assets.build` after any CSS edit.

### Task 1.5: Friends card — Wants to watch
- [x] `test/media_centaur_web/live/discovery_live/people_test.exs`: the shelf field is `listed`, fed by `:listing` rows; presence reads "wants to watch Sample Show". Red.
- [x] `lib/media_centaur_web/components/discovery/person.ex`: field `tracking` → `listed`; typespec; moduledoc.
- [x] `lib/media_centaur_web/live/discovery_live/people.ex`: `listed: Map.get(shelves, :listing, [])`.
- [x] `lib/media_centaur_web/components/discovery/person_card.ex`: shelf label "Wants to watch", verb "wants to watch"; `own_subtitle` copy: "…what you recommend from a title's page, and what you watch and list once sharing is on under Settings → Social."; moduledoc. `storybook/discovery/person_card.story.exs`: `listed:` shelf, description text.
- [x] `discovery_live_test.exs` lines ~270–300 and ~1125: `Activities.tracking` → `Activities.listing`; the You-card delete assertion reads "Listing withdrawn"; test title "your own listing broadcast is not narrated back on the watchlist".
- [x] `agent-mix precommit`. Commit `feat(social): listing (32163) replaces tracking on the wire and on every surface`.

---

## Phase 2 — The publisher follows the rung transition

### Task 2.1: `RungChanged` carries the transition
- [x] `test/media_centaur/discovery_test.exs` (and `title_intent_test.exs` if it asserts the event): `put_rung` from no record broadcasts `%RungChanged{previous_rung: nil, rung: :list, title: %Title{}}`; from `:ignored` → `previous_rung: :ignored`; `forget/2` broadcasts `previous_rung: <old>, rung: nil, title: <snapshot>`. Red.
- [x] `lib/media_centaur/discovery/events.ex`: `@enforce_keys [:tmdb_id, :media_type, :title, :previous_rung, :rung]`; moduledoc: "one message, one transition, both ends".
- [x] `lib/media_centaur/discovery.ex`: `announce/2` takes the previous rung (`existing.rung` or `nil`); `forget/2` passes `intent.rung` and `intent.title`. Grep every `%Events.RungChanged{` constructor (Discovery only) and every `:title_intent_changed` consumer (`DiscoveryLive`, `TitleDetailHost`, `IntentAware`) — consumers match on the tuple/struct and need no change; confirm by running their tests.

### Task 2.2: Remove `TrackingStarted`
- [x] Delete `test/media_centaur/release_tracking/events_test.exs`, `lib/media_centaur/release_tracking/events.ex` (the module holds only `TrackingStarted`; if `Events.broadcast/1` has other callers, keep the module and drop the struct — grep first).
- [x] `lib/media_centaur/release_tracking.ex`: remove `announce_tracking_started/1`, the `Events.TrackingStarted` export, the `followed_before?` read in `set_rung/3` and its argument through `derive/4` → `derive/3`. Moduledoc and the `Topics` table row for `release_tracking:updates` (drop `{:tracking_started, _}` if listed).
- [x] `docs/GLOSSARY.md` **Following**: drop the sentence about announcing `TrackingStarted`.

### Task 2.3: `ShareWatchlist` preference and the Settings toggle
- [x] `test/media_centaur_web/live/settings_live_social_test.exs`: `toggle_share_watchlist`; label "Share your watchlist"; description "A title you list is shared with your friends; one you drop is withdrawn." Red.
- [x] `lib/media_centaur/settings/preferences/share_watchlist.ex` replaces `share_tracking.ex` (`key: "share_watchlist"`, default false; moduledoc from ADR-067 §1–2). `lib/media_centaur/settings/preferences.ex` export list.
- [x] `lib/media_centaur_web/live/settings_live.ex`: assign `share_watchlist?`, event `toggle_share_watchlist`, the two render sites. `lib/media_centaur_web/live/settings_live/social_section.ex`: attr, row copy, moduledoc; the Sharing intro sentence "…until you delete it from the Feed" stays true.

### Task 2.4: Publisher on `discovery:updates`
- [x] `test/media_centaur/activities/publisher_test.exs`: replace `describe "tracking"` with `describe "listing"`: off by default → nothing; `set_rung(title, :list)` with the toggle on → one `%Activity{kind: :listing}` sent; `:ignored → :list` publishes; `:list → :follow` publishes nothing more; `:list → :off` withdraws (the row is a tombstone, `list_sent()` empty) **with the toggle off too**; a title never listed dropping to Off publishes nothing. Use `ReleaseTracking.set_rung/3` as the act (the same call the ladder makes) and `settle/0`. Red.
- [x] `lib/media_centaur/activities/publisher.ex`: `Discovery.subscribe()` replaces `ReleaseTracking.subscribe()`; `handle_info({:title_intent_changed, %RungChanged{} = change}, state)`:
  - `listed_before? = TitleIntent.rung_at_least?(change.previous_rung, :list)`, `listed_now? = TitleIntent.rung_at_least?(change.rung, :list)`.
  - `not listed_before? and listed_now? and ShareWatchlist.enabled?()` → `run(fn -> share(:listing, Activities.listing(change.title)) end)`.
  - `listed_before? and not listed_now?` → `run(fn -> Activities.withdraw(:listing, change.tmdb_id, change.media_type) end)` (log at info when a row was withdrawn).
  - Moduledoc table: "Listed a title (rung crossed onto List) · `discovery:updates` · `share_watchlist` · `Activities.listing/1`" and the withdrawal rule (incoherence #9).
- [x] `lib/media_centaur/activities.ex` Boundary: `deps` add `MediaCentaur.Discovery`, drop `MediaCentaur.ReleaseTracking` (the publisher was its only user; `agent-mix compile` will say if not).
- [x] `agent-mix precommit`. Commit `feat(social): a listing is shared when a title reaches List and withdrawn when it drops`.

---

## Phase 3 — The Feed

### Task 3.1: `FeedEntries` projection and the `FeedEntry` view-model
- [x] `test/media_centaur_web/live/discovery_live/feed_entries_test.exs` (replaces `recommendation_rows_test.exs`, which is deleted): from `DiscoveryRows.activity_row/1` fixtures —
  - keeps friends' `:recommendation` and `:listing`; drops `:watched`, `own?`, `nickname: nil`, `rung: :ignored`;
  - one entry per row, newest first, never grouped (two friends × one title → two; same friend recommend + list → two adjacent);
  - `build(rows, now:, window: 2)` returns `%{entries: [_, _], has_older?: true}`; window ≥ count → `false`;
  - an entry carries `id: "feed-entry-<activity_id>"`, `activity_id`, `ref`, `title`, `poster_url`, `nickname`, `kind`, `sentiment` (nil for a listing), `note` (nil for a listing), `ago` from `Format.relative_ago(acted_at, now: now)`, `rung`, `library_owner_id`, `acquisition_state`;
  - `list_slot/1`: `nil | :ignored → :list`, `:list → :listed`, `:follow | :ask | :grab | :default → :following`;
  - `download_slot/1`: library owner → `{:state, "In library"}`; acquisition state → `{:state, Logic.acquisition_marker(state)}`; else `:download`.
  - `page_size/0 == 50`. Red.
- [x] `lib/media_centaur_web/components/discovery/feed_entry.ex`: the struct + `@type t` (view-model, like `Person`).
- [x] `lib/media_centaur_web/live/discovery_live/feed_entries.ex`: `build/2`, `list_slot/1`, `download_slot/1`, `page_size/0`; moduledoc names UIDR-038 and the four objectives.
- [x] Delete `lib/media_centaur_web/live/discovery_live/recommendation_rows.ex` and its test.

### Task 3.2: `Format.relative_ago/2` weeks (droppable)
- [x] `test/media_centaur/format_test.exs`: 14 days → `"2w ago"`, 6 days → `"6d ago"`. Red. Add the `< 7 days` / `else weeks` branches. Check `discovery_live_test`, `people_test` and the Status widget tests for day-strings ≥ 7 days and update them.

### Task 3.3: `FeedEntryCard` component, story, CSS
- [x] `storybook/discovery/feed_entry_card.story.exs`: variations `listing`, `recommendation_like_with_note`, `recommendation_love`, `listed_title` (slot `:listed`), `following_title`, `in_library`, `downloading`, `no_poster`. Index entry in `_discovery.index.exs`. (MC0009 fails the precommit until this exists.)
- [x] `lib/media_centaur_web/components/discovery/feed_entry_card.ex`, `feed_entry_card/1`, `attr :entry, FeedEntry, required: true`, `attr :list_slot`, `attr :download_slot` (resolved by the host, the card decides nothing):
  - `<div id={entry.id} role="button" class="feed-entry glass-surface" phx-click="open_title" phx-value-ref phx-value-activity data-entity-id=…>` — a `div[role=button]` because it contains controls (same reason as `TitleRow`).
  - Poster 48×72 via `sized_image_url(poster_url, 160)`, eager + sync, name fallback tile.
  - Line 1: `<span class="feed-entry-who">{nickname}</span> {verb} <heart if love> · <time>`; verb from `ActivityWords.verb(kind, nil)`; heart `<.icon name="hero-heart-solid" class="size-3 text-love">` for `:love` only.
  - Line 2: title name semibold + year (`Title.year`).
  - Line 3 (`:if={note}`): `feed-entry-note`, 4-line clamp.
  - Toolbar `<div class="feed-entry-toolbar">` always rendered: List slot → `<button phx-click="feed_list" phx-value-activity>` with outline/filled bookmark and "List"/"Listed", or `<span class="feed-entry-state">Following</span>`; Download slot → `<button phx-click="feed_download" phx-value-activity>` or `<span class="feed-entry-state" data-progress={…}>` with the 3px hairline only for "Downloading"; Ignore → `<button phx-click="ignore_title" phx-value-activity class="feed-entry-ignore">`. Every button has `phx-click` + `onclick="event.stopPropagation()"`? — no: use `phx-click` with the LiveView JS `JS.push(…)` and rely on the card's own click being on the outer div; verify in a real browser that a toolbar click does not also open the modal (add `phx-click-away`-free stopPropagation via the existing pattern in `TitleRow`'s Ignore control — copy that).
  - Data attributes for tests: `data-kind`, `data-list-slot`, `data-download-slot`.
- [x] `assets/css/app.css`: `.feed-entry`, `.feed-entry-toolbar` (fixed 20px seat, `opacity: 0`, shown on `:hover` / `:focus-within`), `.feed-entry-state`, the hairline, the note clamp. Translate mockup A's rules; use the theme's tokens, not the mockup's literal oklch values. Then `agent-mix assets.build`.
- [x] Storybook renders (`storybook_render_test`).

### Task 3.4: `DiscoveryLive` — Feed tab, window, toolbar verbs
- [x] `test/media_centaur_web/live/discovery_live_test.exs`: rewrite `describe "recommendations tab"` as `describe "feed tab"` against the assertions in *Test strategy*; add `friend_listing_event/1`. Keep every test the watchlist/friends/modal describes still need (`friend_event/3` stays). Add Show older: 51 activities → 50 entries + `#feed-show-older`; click → 51. `page_smoke_test.exs` label `"discovery feed"`. Red.
- [x] `lib/media_centaur_web/router.ex`: `live "/discovery", DiscoveryLive, :feed`.
- [x] `lib/media_centaur_web/live/discovery_live.ex`:
  - assigns: `feed: []`, `feed_has_older?: false`, `feed_window: FeedEntries.page_size()`; drop `recommendations`.
  - `project/1`: `%{entries:, has_older?:} = FeedEntries.build(activities, now: now, window: feed_window)`.
  - tabs: `%Tab{id: :feed, label: "Feed", navigate: "/discovery", count: length(feed)}`.
  - `handle_event("feed_show_older")` → `feed_window + page_size` then `project/1`.
  - `handle_event("feed_list", %{"activity" => id})`: find the entry; `case FeedEntries.list_slot(entry)`: `:list` → `ReleaseTracking.set_rung(title, :list, TitleIntent.friend_provenance(entry.activity_id, entry.note))`; `:listed` → `set_rung(title, :off)`; `:following` → no-op.
  - `handle_event("feed_download", %{"activity" => id})`: `Plans.plan_title(entry.title, approval_policy: "automatic")` + `put_flash(:info, TitleDetailHost.download_flash(name, false))`.
  - `handle_event("ignore_title", %{"activity" => id})`: provenance from that entry; keep `ignore_undo` / `ignore_undo_dismiss` unchanged.
  - `activity_row/3` default clause: the title's newest friend feed entry, else any friend activity (replace the `recommendations` lookup).
  - render: the Feed block — empty state (`id="feed-empty"`, headline "What your friends point at lands here", ready copy "Recommendations, and titles your friends want to watch, land here newest first."), `FeedEntryCard.feed_entry_card :for={entry <- @feed}` with slots from `FeedEntries`, Show older (`id="feed-show-older"`, `variant="ghost"`, `phx-click="feed_show_older"`, `:if={@feed_has_older?}`), the existing `ActionToast`.
  - moduledoc rewrite (Feed replaces Recommendations; the toolbar is where `ignore_title`, `feed_list`, `feed_download` live).
- [x] `lib/media_centaur/discovery/title_intent.ex`: `friend_provenance(activity_id, note) :: map()` + test in `title_intent_test.exs`. `lib/media_centaur_web/live/title_detail_host.ex`: `provenance/1` calls it; `download_flash/2` becomes `@doc`'d public.
- [x] `lib/media_centaur_web/components/title/row.ex`: remove `lead`, `ignorable?` and the Ignore sub-item; moduledoc; `storybook/title/title_row.story.exs` drops the `ignorable` variation and its doc line. Confirm `media_results.ex` passes neither attr.
- [x] Real-browser check (memory: green `render_click` ≠ working control): `page-shot --url http://localhost:2160/discovery --wait-ms 3000 --viewport 1920x1080`; `chromium-probe` a toolbar click and confirm the modal did **not** open; hover shows the toolbar without changing the card's height (compare `getBoundingClientRect().height` before/after adding the hover class).
- [x] `agent-mix precommit`. Commit `feat(discovery): the Feed — friends' actions, one entry each (UIDR-038)`.

---

## Phase 4 — Documentation

### Task 4.1: Protocol and contributor docs
- [x] `docs/social-protocol.md`: kind table row `32163 Listing Addressable`, `32162 Tracking — retired 2026-09-11` (row kept, marked retired); "Activities" intro: recommended it, watched it, listed it; replace the Tracking section with **Listing (kind 32163)** (`listed_at`; published when the title first reaches List, withdrawn by a deletion when it drops below); deletion `a` tag kinds `32160, 32161, 32163`; both subscription rows; relay requirements row; **Changes** row for 2026-09-11 (social-relay v0.5.0).
- [x] `docs/social.md`: Producers paragraph, Contexts (Publisher listens on `discovery:updates`), Web layer (Feed tab, `FeedEntries`, `FeedEntryCard`), PubSub table.
- [x] `docs/GLOSSARY.md`: **Feed** (rewrite: friends' recommendations and listings, one entry per action, `FeedEntries`), **Action**, **Listing**, **Entry** qualifier (feed entry vs library entry vs `Person.Entry`), **Ignored** ("keeps the title off the Feed"), **Sharing toggle** (`share_watchlist`), **Activity** (kinds), **Following** (no announcement).
- [x] `docs/architecture.md` if it lists the activity kinds or the Recommendations tab (grep).

### Task 4.2: Wiki
- [x] `~/src/media-centaur/media-centaur.wiki/Social.md`: intro (Feed, not Recommendations), *How it works* kinds, *Sharing* table (Share your watchlist), *Recommendations* section → **Feed** (the entry anatomy, the toolbar verbs, Show older, Ignore/Undo), *Friends* table (Wants to watch shelf, presence example "wants to watch Show F · 1w ago"), *Your card* delete verbs ("Delete listing"), *Where a friend's activity shows* (bookmark), the relay version note (listings need social-relay v0.5.0).
- [x] `Social-Protocol.md` via `scripts/sync-wiki-docs`.
- [x] `git commit -m "wiki: the Feed replaces Recommendations; listing replaces tracking"` (committed locally).
- [ ] Push the wiki with the app release, not before: the page describes a Feed users do not have until they update.

### Task 4.3: Decision-record cross-links
- [x] UIDR-038 and ADR-067 already exist. Update the spec's Status line to "implemented <date>" and this plan's checkboxes. `decisions/README.md` unchanged.

---

## Files to modify

| File | Change |
|---|---|
| `lib/media_centaur/activities/translation.ex` | kind 32163 `listing` / `listed_at`; 32162 gone |
| `lib/media_centaur/activities/activity.ex` | kinds |
| `lib/media_centaur/activities.ex` | `listing/1`, `withdraw/3`, Boundary deps |
| `lib/media_centaur/activities/publisher.ex` | subscribe `discovery:updates`; listing publish + withdrawal |
| `lib/media_centaur/activities/sync.ex` | refusal wording |
| `lib/media_centaur/discovery/events.ex`, `discovery.ex` | `RungChanged` carries `previous_rung` + `title` |
| `lib/media_centaur/discovery/title_intent.ex` | `friend_provenance/2` |
| `lib/media_centaur/release_tracking.ex` | drop `announce_tracking_started`, `followed_before?` |
| `lib/media_centaur/settings/preferences/share_watchlist.ex` (new, replaces `share_tracking.ex`), `preferences.ex` | the toggle |
| `lib/media_centaur_web/live/settings_live.ex`, `settings_live/social_section.ex` | toggle rename + copy |
| `lib/media_centaur_web/live/discovery_live.ex` | Feed tab, window, verbs |
| `lib/media_centaur_web/live/discovery_live/feed_entries.ex` (new), `activity_words.ex`, `people.ex` | projection, words, shelf |
| `lib/media_centaur_web/components/discovery/feed_entry.ex` (new), `feed_entry_card.ex` (new), `person.ex`, `person_card.ex` | view-model, card, shelf rename |
| `lib/media_centaur_web/components/title/pennant.ex`, `row.ex` | bookmark flag; drop `lead`/`ignorable?` |
| `lib/media_centaur_web/live/title_detail_host.ex` | `provenance/1` via `friend_provenance`; `download_flash/2` public |
| `lib/media_centaur_web/router.ex` | `:feed` |
| `lib/mix/tasks/social.dev.ex` | listing |
| `lib/media_centaur/format.ex` | weeks |
| `priv/repo/migrations/20260911120000_listing_replaces_tracking.exs` (new) | drop rows |
| `assets/css/app.css` | `.feed-entry*` |
| `storybook/discovery/feed_entry_card.story.exs` (new), `_discovery.index.exs`, `person_card.story.exs`, `storybook/title/pennants.story.exs`, `title_row.story.exs` | stories |
| `docs/social-protocol.md`, `docs/social.md`, `docs/GLOSSARY.md`, wiki `Social.md`, `Social-Protocol.md` | docs |
| social-relay: `internal/relay/kinds.go`, `kinds_test.go`, `relay_test.go`, `README.md`, `docs/protocol.md` | v0.5.0 |

**Removed:** `lib/media_centaur_web/live/discovery_live/recommendation_rows.ex` + test, `lib/media_centaur/release_tracking/events.ex` + test (if `TrackingStarted` is its only content), `lib/media_centaur/settings/preferences/share_tracking.ex`.

## Technical decisions

1. **`RungChanged` describes the transition** (`previous_rung`, `rung`, `title`). One event, both ends; subscribers pick their threshold. Replaces `TrackingStarted`.
2. **Withdrawal ignores the toggle.** A listing that exists is withdrawn when the title drops below List, whether or not sharing is still on.
3. **Toggle is a fresh consent.** `share_tracking` is deleted, `share_watchlist` starts off. No inheritance.
4. **Feed entry = view-model struct + pure card**, the `Person` / `PersonCard` pattern. Slots are resolved by `FeedEntries`, passed in as attrs; acquisition words come from `Logic.acquisition_marker/1`.
5. **The toolbar's Download is the modal's plain Download** (no scope → the planner's default), same `Plans.plan_title/2` call, same flash. Season scopes stay in the modal.
6. **Provenance is one function**, `TitleIntent.friend_provenance/2`, used by the host, the feed's List and Ignore.
7. **Window = count, not time.** 50 entries, Show older adds 50. The tab count is the window's size, per the spec.
8. **Mouse-only.** No nav attributes on the card or the toolbar this release.
9. **Relay first.** social-relay v0.5.0 accepts 32163 before the app tags; the app's release notes name the relay version.
10. **Migration deletes, never rewrites.** Tracking rows and the old setting row are removed; the kind number is retired in the protocol table only.
