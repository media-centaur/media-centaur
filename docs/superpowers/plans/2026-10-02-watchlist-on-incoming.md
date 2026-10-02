# Watchlist on Incoming — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Incoming's first tab is the Watchlist — every listed title once, a followed title's row carrying its next release and its status — and the Coming up tab, the Incoming shelf and the Discovery page's Watchlist tab are gone.

**Architecture:** One pure builder (`IncomingLive.WatchlistRows`) joins the watchlist read (`Discovery.list_watchlist/0`) with the forecast the page already builds (`UpcomingFeed`), the social glyphs and the acquisition states, and sorts: dated next release nearest first, then followed titles with no date, then listed-only titles newest first. `IncomingLive.View` composes it in place of the shelf section; `Title.Row` gains an optional next-release block drawn with the existing `StatusPill`. The zone `:coming_up` becomes `:watchlist`; the rows' nav zone is the `title_rows` TREE the Discovery tab used.

**Tech Stack:** Phoenix LiveView, ExUnit (`MediaCentaur.Case` for pure tests, `ConnCase` + `live_async!` for the page), Phoenix Storybook, bun for the JS nav-config tests.

Campaign: [`campaigns/social-and-watchlist.md`](../../../campaigns/social-and-watchlist.md), Phase 1. Run every `mix` command through `~/scripts/agents/agent-mix` (CLAUDE.md § Build & Run).

---

## File map

| File | Change |
|---|---|
| `lib/media_centaur/release_tracking/upcoming_feed.ex` | `Event` gains `tmdb_id`; `shelf_items/2` becomes `next_per_title/1` |
| `test/media_centaur/release_tracking/upcoming_feed_test.exs` | the `shelf_items/2` describe becomes `next_per_title/1`; the cap cases go |
| `lib/media_centaur_web/components/title/row.ex` | `Row.NextRelease` struct; `next_release` attr; the right-side block |
| `storybook/title/title_row.story.exs` | two variations: a next release, one in pursuit |
| `lib/media_centaur_web/live/incoming_live/watchlist_rows.ex` | **new** — the pure builder |
| `test/media_centaur_web/live/incoming_live/watchlist_rows_test.exs` | **new** |
| `lib/media_centaur_web/live/incoming_live/view.ex` | `watchlist` replaces `shelf`; `with_progress/2` stamps rows |
| `test/media_centaur_web/live/incoming_live/view_test.exs` | shelf describes become watchlist describes |
| `lib/media_centaur_web/live/incoming_live/logic.ex` | `:coming_up` → `:watchlist` |
| `test/media_centaur_web/live/incoming_live/logic_test.exs` | same |
| `lib/media_centaur_web/live/incoming_live.ex` | reads in `build_view/1`; the section; zone rename; `select_event` / `expand_shelf` / `shelf_cards` removed |
| `test/media_centaur_web/live/incoming_live_test.exs` | `coming_up_list` → `title_rows`, "Coming up" → "Watchlist", `#shelf-<id>` → `#watchlist-item-<ref>`; the Discovery row tests ported |
| `lib/media_centaur_web/components/incoming/shelf.ex`, `storybook/incoming/shelf.story.exs`, `storybook/incoming/shelf_row.story.exs`, `storybook/incoming/_incoming.index.exs` | deleted / entries removed |
| `lib/media_centaur_web/components/title/logic.ex`, `test/media_centaur_web/components/title/logic_test.exs` | the `next_air_date` marker and `next_air_date/2` go |
| `lib/media_centaur_web/live/discovery_live.ex`, `lib/media_centaur_web/router.ex`, `lib/media_centaur_web/components/layouts.ex`, `test/media_centaur_web/page_smoke_test.exs`, `test/media_centaur_web/live/discovery_live_test.exs` | the Watchlist tab, route and `load_items/1` go |
| `assets/js/input/config.js`, `assets/js/input/__tests__/index.test.js` | `coming_up_list` → `title_rows` on `incoming`; `title_rows` leaves `discovery` |
| `lib/media_centaur_web/components/title/tracking_controls.ex`, `lib/media_centaur_web/live/title_detail_host/acquisition.ex`, `lib/media_centaur/discovery/title_intent.ex`, `lib/media_centaur/format.ex` | copy that names Coming up |
| `decisions/user-interface/2026-10-02-050-the-watchlist-is-incomings-first-tab.md`, amendments to UIDR-015, UIDR-035, UIDR-042; `decisions/README.md` | the record |
| `docs/GLOSSARY.md`, `.claude/skills/user-interface/SKILL.md`, `priv/guide/*.md`, wiki pages | docs |

---

### Task 1: `UpcomingFeed` — an event knows its title's ref; one next event per title

**Files:**
- Modify: `lib/media_centaur/release_tracking/upcoming_feed.ex`
- Test: `test/media_centaur/release_tracking/upcoming_feed_test.exs`

- [ ] **Step 1: Rewrite the `shelf_items/2` describe (line ~551) as `next_per_title/1`**

Keep the existing fixtures of that describe (they build a feed with several titles and dates). Replace every `UpcomingFeed.shelf_items(feed, 6)` / `(feed, :all)` call and the `{items, overflow}` destructuring with:

```elixir
describe "next_per_title/1 — one event per title, nearest first" do
  # (existing fixture helpers of the shelf_items describe stay)

  test "returns the soonest scheduled event of each tracked title, nearest first" do
    feed = feed_with_two_titles()   # the describe's existing helper for two titles, several dates
    events = UpcomingFeed.next_per_title(feed)
    assert Enum.map(events, & &1.item_id) == Enum.uniq(Enum.map(events, & &1.item_id))
    assert events == Enum.sort_by(events, & &1.air_date, Date)
  end

  test "an event carries its title's TMDB ref" do
    feed = feed_with_two_titles()
    assert [%UpcomingFeed.Event{tmdb_id: tmdb_id, media_type: media_type} | _] = UpcomingFeed.next_per_title(feed)
    assert is_integer(tmdb_id) and media_type in [:movie, :tv_series]
  end

  test "an unscheduled title has no event here" do
    # the describe's existing unscheduled fixture
    refute Enum.any?(UpcomingFeed.next_per_title(feed_with_unscheduled()), &is_nil(&1.air_date))
  end
end
```

Delete the cases that assert an overflow count or a cap. In the `shelf_date_label/2` describe, `defp shelf_event(feed), do: feed |> UpcomingFeed.shelf_items(6) |> …` becomes `feed |> UpcomingFeed.next_per_title() |> hd()` (check the rest of that pipe and keep it).

- [ ] **Step 2: Run the file to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/release_tracking/upcoming_feed_test.exs`
Expected: failures — `next_per_title/1` undefined, `tmdb_id` not a key of `Event`.

- [ ] **Step 3: Implement**

In `Event`'s `defstruct` add `:tmdb_id` after `:item_id`. In `event_from/2` add `tmdb_id: item.tmdb_id,` after `item_id: release.item_id,`. Replace both `shelf_items/2` clauses and their `@doc`/`@spec` with:

```elixir
@doc """
One event per tracked title — its soonest scheduled release — nearest
first. The watchlist row's next release. A title with nothing scheduled
has no event here (`unscheduled` holds it).
"""
@spec next_per_title(t()) :: [Event.t()]
def next_per_title(%UpcomingFeed{} = feed) do
  feed |> scheduled_events() |> Enum.uniq_by(& &1.item_id)
end
```

Update the moduledoc's first line to say the feed is "behind the Incoming page's Watchlist tab and per-title detail timeline".

- [ ] **Step 4: Run the file to see it pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur/release_tracking/upcoming_feed_test.exs`
Expected: all pass. `view.ex` will not compile yet; that is Task 4.

---

### Task 2: `Title.Row` — the next-release block

**Files:**
- Modify: `lib/media_centaur_web/components/title/row.ex`
- Modify: `storybook/title/title_row.story.exs`

- [ ] **Step 1: Add the two story variations first (the acceptance criterion, storybook skill)**

Add to `variations/0`, before the social-glyph variations:

```elixir
%Variation{
  id: :next_release,
  description: "A followed show with a dated next release: the date, the episode and its status at the right.",
  attributes: %{
    id: "row-next-release",
    title: title(%{media_type: :tv_series, name: "Sample Show"}),
    markers: ["Tracking"],
    next_release: %MediaCentaurWeb.Components.Title.Row.NextRelease{
      air_date: ~D[2026-10-09],
      date_label: "Fri Oct 9",
      subtitle: "S02E04",
      status: :tracked
    }
  }
},
%Variation{
  id: :in_pursuit,
  description: "Its release dropped and a pursuit is grabbing it: the pill carries the percent and anchors to the pursuit row.",
  attributes: %{
    id: "row-in-pursuit",
    title: title(%{media_type: :tv_series, name: "Sample Show"}),
    markers: ["Auto-grab"],
    next_release: %MediaCentaurWeb.Components.Title.Row.NextRelease{
      air_date: ~D[2026-10-01],
      date_label: "Yesterday",
      subtitle: "S02E03",
      status: :in_pursuit,
      percent: 62,
      pursuit_id: "7f1d2a0e-0000-4000-8000-000000000001"
    }
  }
}
```

- [ ] **Step 2: Run the storybook tests to see them fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: FAIL — `Row.NextRelease` undefined / unknown attr `next_release`.

- [ ] **Step 3: Implement the struct, the attr and the block**

In `row.ex`, after `use Phoenix.Component`, add `import MediaCentaurWeb.Components.Incoming.StatusPill, only: [status_pill: 1]` and the nested struct:

```elixir
defmodule NextRelease do
  @moduledoc """
  A followed title's next release, as the row draws it: the date label
  (`UpcomingFeed.shelf_date_label/2`), the release (an episode, a
  season drop, a film's date type), the `StatusPill` status, and the
  percent and pursuit id an in-pursuit release carries.
  """
  @enforce_keys [:air_date, :date_label, :status]
  defstruct [:air_date, :date_label, :subtitle, :status, :percent, :pursuit_id]

  @type t :: %__MODULE__{
          air_date: Date.t(),
          date_label: String.t(),
          subtitle: String.t() | nil,
          status: :armed | :in_pursuit | :in_theaters | :tracked | :searching | :landed | nil,
          percent: integer() | nil,
          pursuit_id: Ecto.UUID.t() | nil
        }
end
```

Add the attr after `social_activity`:

```elixir
attr :next_release, NextRelease,
  default: nil,
  doc: "a followed title's next release — date, release and status at the row's right; nil for a listed-only title"
```

Replace the `<SocialGlyph.social_glyphs …/>` element with a right-side group holding both:

```heex
<div class="ml-auto flex shrink-0 items-center gap-4 self-center">
  <div :if={@next_release} class="flex flex-col items-end gap-1 text-right">
    <span class="text-xs font-medium text-base-content/55">{@next_release.date_label}</span>
    <span :if={@next_release.subtitle} class="text-xs text-base-content/55">{@next_release.subtitle}</span>
    <.status_pill
      :if={@next_release.status}
      status={@next_release.status}
      percent={@next_release.percent}
      anchor={pursuit_anchor(@next_release)}
    />
  </div>
  <SocialGlyph.social_glyphs
    :if={@flags != []}
    flags={@flags}
    grades={@grades}
    tips={@sentences}
    class="gap-3 [--glyph:1.25rem]"
  />
</div>
```

and the helper at the bottom of the module:

```elixir
# The in-pursuit pill jumps to the pursuit row — the same object's other
# zoom level (UIDR-015 §6).
defp pursuit_anchor(%NextRelease{status: :in_pursuit, pursuit_id: id}) when is_binary(id), do: "#pursuit-#{id}"
defp pursuit_anchor(%NextRelease{}), do: nil
```

Update the moduledoc's first sentence: "One title row — a watchlist entry or a media-search result — … the next release a followed title carries at its right (`NextRelease`), and the social glyphs."

- [ ] **Step 4: Run the storybook tests to see them pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: PASS (the `incoming` stories still compile until Task 7 deletes them).

---

### Task 3: `IncomingLive.WatchlistRows` — the pure builder

**Files:**
- Create: `lib/media_centaur_web/live/incoming_live/watchlist_rows.ex`
- Test: `test/media_centaur_web/live/incoming_live/watchlist_rows_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule MediaCentaurWeb.IncomingLive.WatchlistRowsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.ReleaseTracking.UpcomingFeed
  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.Row.NextRelease
  alias MediaCentaurWeb.IncomingLive.WatchlistRows

  @today ~D[2026-10-02]

  defp intent(tmdb_id, media_type, rung, inserted_at) do
    %TitleIntent{
      tmdb_id: tmdb_id,
      media_type: media_type,
      rung: rung,
      inserted_at: inserted_at,
      title: Title.new!(%{tmdb_id: tmdb_id, media_type: media_type, name: "Title #{tmdb_id}"})
    }
  end

  defp watchlist_row(intent, library_owner_id \\ nil), do: %{intent: intent, library_owner_id: library_owner_id}

  defp event(tmdb_id, media_type, air_date, overrides \\ %{}) do
    Map.merge(
      %Event{
        id: "r-#{tmdb_id}",
        item_id: tmdb_id,
        tmdb_id: tmdb_id,
        media_type: media_type,
        item_name: "Title #{tmdb_id}",
        air_date: air_date,
        season_number: 2,
        episode_number: 4,
        status: :upcoming,
        kind: :episode,
        episode_count: 1
      },
      overrides
    )
  end

  # A feed whose only scheduled bucket holds `events`.
  defp feed(events), do: %UpcomingFeed{buckets: %{this_week: events}, unscheduled: []}

  defp inputs(overrides) do
    Map.merge(
      %{watchlist: [], feed: feed([]), social_activity: %{}, acquisition_states: %{}, posters: %{}, today: @today},
      overrides
    )
  end

  test "a followed title with a dated release carries its next release" do
    rows =
      WatchlistRows.build(
        inputs(%{
          watchlist: [watchlist_row(intent(1, :tv_series, :follow, ~N[2026-09-01 00:00:00]))],
          feed: feed([event(1, :tv_series, ~D[2026-10-09])])
        })
      )

    assert [%{ref: {1, :tv_series}, rung: :follow, next_release: %NextRelease{} = next}] = rows
    assert next.air_date == ~D[2026-10-09]
    assert next.date_label == "Fri Oct 9"
    assert next.subtitle == "S02E04"
    assert next.status == :tracked
  end

  test "sorts dated releases nearest first, then followed titles with no date, then listed-only newest first" do
    rows =
      WatchlistRows.build(
        inputs(%{
          watchlist: [
            watchlist_row(intent(10, :movie, :list, ~N[2026-09-30 00:00:00])),
            watchlist_row(intent(11, :movie, :list, ~N[2026-09-20 00:00:00])),
            watchlist_row(intent(20, :tv_series, :follow, ~N[2026-09-10 00:00:00])),
            watchlist_row(intent(30, :tv_series, :grab, ~N[2026-09-01 00:00:00])),
            watchlist_row(intent(31, :tv_series, :follow, ~N[2026-09-02 00:00:00]))
          ],
          feed: feed([event(31, :tv_series, ~D[2026-10-05]), event(30, :tv_series, ~D[2026-10-20])])
        })
      )

    assert Enum.map(rows, &elem(&1.ref, 0)) == [31, 30, 20, 10, 11]
  end

  test "statuses map onto the pill vocabulary; a past armed release reads Searching; in pursuit keeps its pursuit id" do
    feed =
      feed([
        event(1, :tv_series, ~D[2026-10-09], %{status: :armed}),
        event(2, :tv_series, ~D[2026-09-30], %{status: :armed}),
        event(3, :tv_series, ~D[2026-09-29], %{status: :under_pursuit, pursuit_id: "p-3"}),
        event(4, :movie, ~D[2026-09-01], %{status: :theatrical_info, kind: :movie}),
        event(5, :movie, ~D[2026-09-01], %{status: :in_library, kind: :movie})
      ])

    watchlist = for id <- 1..5, do: watchlist_row(intent(id, if(id > 3, do: :movie, else: :tv_series), :grab, ~N[2026-09-01 00:00:00]))
    rows = WatchlistRows.build(inputs(%{watchlist: watchlist, feed: feed}))
    by_id = Map.new(rows, &{elem(&1.ref, 0), &1.next_release})

    assert by_id[1].status == :armed
    assert by_id[2].status == :searching
    assert %NextRelease{status: :in_pursuit, pursuit_id: "p-3"} = by_id[3]
    assert by_id[4].status == :in_theaters
    assert by_id[5].status == :landed
  end

  test "a season drop's subtitle names the season and the count" do
    rows =
      WatchlistRows.build(
        inputs(%{
          watchlist: [watchlist_row(intent(1, :tv_series, :follow, ~N[2026-09-01 00:00:00]))],
          feed: feed([event(1, :tv_series, ~D[2026-10-09], %{kind: :season_drop, episode_number: nil, episode_count: 8})])
        })
      )

    assert [%{next_release: %NextRelease{subtitle: "S2 · all 8 episodes at once"}}] = rows
  end

  test "a row carries library presence, the acquisition state, the social activity and the poster" do
    rows =
      WatchlistRows.build(
        inputs(%{
          watchlist: [watchlist_row(intent(1, :movie, :list, ~N[2026-09-01 00:00:00]), "owner-1")],
          social_activity: %{{1, :movie} => [:an_activity_row]},
          acquisition_states: %{{1, :movie} => :downloading},
          posters: %{{1, :movie} => "/poster.jpg"}
        })
      )

    assert [row] = rows
    assert row.in_library?
    assert row.acquisition_state == :downloading
    assert row.social_activity == [:an_activity_row]
    assert row.poster_url == "/poster.jpg"
    assert row.markers == ["In library"]
  end
end
```

- [ ] **Step 2: Run to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live/watchlist_rows_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement**

```elixir
defmodule MediaCentaurWeb.IncomingLive.WatchlistRows do
  @moduledoc """
  The Watchlist tab's rows (UIDR-050): every title intent at List or
  above, once, joined with what the page already holds — the forecast
  (`UpcomingFeed`) for a followed title's next release, the social
  activity for the glyphs, the acquisition state for the marker, the
  poster — and sorted the way the tab reads: titles with a dated next
  release nearest first, then followed titles TMDB has not dated, then
  listed-only titles newest first (the watchlist read's own order).

  Pure: every fact is injected (ADR-030). The status vocabulary is the
  `StatusPill`'s; this is the one mapping from the feed's statuses onto
  it — an armed release that already came out is one the app is
  searching for, so it reads Searching, never "Will grab".
  """

  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.ReleaseTracking.UpcomingFeed
  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.Components.Title.Row.NextRelease

  @type ref :: {integer(), :movie | :tv_series}

  @type row :: %{
          ref: ref(),
          title: Title.t(),
          rung: TitleIntent.rung(),
          in_library?: boolean(),
          acquisition_state: Logic.acquisition_state(),
          markers: [String.t()],
          notes: [map()],
          social_activity: list(),
          poster_url: String.t() | nil,
          next_release: NextRelease.t() | nil
        }

  @doc """
  Inputs: `:watchlist` (`Discovery.list_watchlist/0` rows), `:feed`
  (`UpcomingFeed.t()`), `:social_activity` (`Activities.activity_for/1`),
  `:acquisition_states` (`TitleStates.for_refs/1`), `:posters`
  (`ref => url`), `:today`.
  """
  @spec build(map()) :: [row()]
  def build(inputs) do
    next_by_ref = Map.new(UpcomingFeed.next_per_title(inputs.feed), &{{&1.tmdb_id, &1.media_type}, &1})

    inputs.watchlist
    |> Enum.map(&row(&1, next_by_ref, inputs))
    |> Enum.sort_by(&sort_key/1)
  end

  defp row(%{intent: intent, library_owner_id: owner_id}, next_by_ref, inputs) do
    ref = {intent.tmdb_id, intent.media_type}
    in_library? = not is_nil(owner_id)
    acquisition_state = Map.get(inputs.acquisition_states, ref)

    %{
      ref: ref,
      title: intent.title,
      rung: intent.rung,
      in_library?: in_library?,
      acquisition_state: acquisition_state,
      markers: Logic.row_markers(%{in_library?: in_library?, acquisition_state: acquisition_state, rung: intent.rung}, true),
      notes: Logic.note_list(intent.note),
      social_activity: Map.get(inputs.social_activity, ref, []),
      poster_url: Map.get(inputs.posters, ref),
      next_release: next_release(Map.get(next_by_ref, ref), inputs.today)
    }
  end

  # Stable sort: within the undated and the listed-only groups the
  # watchlist read's order (newest first) stands.
  defp sort_key(%{next_release: %NextRelease{air_date: date}}), do: {0, Date.to_erl(date)}
  defp sort_key(%{rung: rung}), do: if(TitleIntent.follows_releases?(rung), do: {1}, else: {2})

  defp next_release(nil, _today), do: nil

  defp next_release(%Event{} = event, today) do
    %NextRelease{
      air_date: event.air_date,
      date_label: UpcomingFeed.shelf_date_label(event, today),
      subtitle: subtitle(event),
      status: pill_status(event, today),
      pursuit_id: event.pursuit_id
    }
  end

  defp pill_status(%Event{status: :armed, air_date: date}, today),
    do: if(Date.before?(date, today), do: :searching, else: :armed)

  defp pill_status(%Event{status: :under_pursuit}, _today), do: :in_pursuit
  defp pill_status(%Event{status: :armed_fallback}, _today), do: :tracked
  defp pill_status(%Event{status: :theatrical_info}, _today), do: :in_theaters
  defp pill_status(%Event{status: :in_library}, _today), do: :landed
  defp pill_status(%Event{status: :upcoming}, _today), do: :tracked

  # The shelf's words, moved here unchanged (`View.subtitle_for/1` and
  # `Shelf.subtitle_line/1` before this): a season drop names the
  # season and the count; an episode its code and, when the release
  # has one, its title; a movie's edition title only when it differs
  # from the movie's own name.
  defp subtitle(%Event{kind: :season_drop, season_number: season, episode_count: count}),
    do: "S#{season} · all #{count} episodes at once"

  defp subtitle(%Event{kind: :episode} = event) do
    code = "S#{pad(event.season_number)}E#{pad(event.episode_number)}"
    if event.title, do: "#{code} · “#{event.title}”", else: code
  end

  defp subtitle(%Event{kind: :movie, title: title, item_name: title}), do: nil
  defp subtitle(%Event{kind: :movie} = event), do: event.title

  defp pad(number), do: number |> to_string() |> String.pad_leading(2, "0")
end
```

- [ ] **Step 4: Run to see it pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live/watchlist_rows_test.exs`
Expected: PASS.

---

### Task 4: `IncomingLive.View` — the watchlist replaces the shelf

**Files:**
- Modify: `lib/media_centaur_web/live/incoming_live/view.ex`
- Test: `test/media_centaur_web/live/incoming_live/view_test.exs`

- [ ] **Step 1: Rewrite the shelf describes**

In `view_test.exs`: drop the `Card` alias, add `alias MediaCentaurWeb.Components.Title.Row.NextRelease` and `alias MediaCentaur.Discovery.TitleIntent`. In `inputs/1` replace `shelf_expanded?: false` with `watchlist: [], social_activity: %{}, acquisition_states: %{}, posters: %{}`. Add a helper that lists a fixture item:

```elixir
defp listed(item, rung \\ :grab) do
  %{
    intent: %TitleIntent{
      tmdb_id: item.tmdb_id,
      media_type: item.media_type,
      rung: rung,
      inserted_at: ~N[2026-06-01 00:00:00],
      title: MediaCentaur.TMDB.Title.new!(%{tmdb_id: item.tmdb_id, media_type: item.media_type, name: item.name})
    },
    library_owner_id: nil
  }
end
```

Rename `describe "build/1 — shelf projection"` to `"build/1 — watchlist rows"`; in each test pass `watchlist: [listed(item), …]` for every fixture item and assert on `view.watchlist` rows' `next_release` instead of `view.shelf.cards`: `first.next_release.date_label`, `.status`, `.pursuit_id`, `.subtitle`. Delete the overflow/cap assertions and any `expand_shelf` test. The honest-degradation test ("acquisition off ⇒ no `:armed`") stays, asserting `next_release.status == :tracked`.

Add:

```elixir
test "with_progress/2 stamps the percent onto an in-pursuit row and leaves the rest alone" do
  rows = [
    %{ref: {1, :tv_series}, next_release: %NextRelease{air_date: @today, date_label: "Today", status: :in_pursuit, pursuit_id: "p-1"}},
    %{ref: {2, :tv_series}, next_release: %NextRelease{air_date: @today, date_label: "Today", status: :tracked}},
    %{ref: {3, :movie}, next_release: nil}
  ]

  [a, b, c] = View.with_progress(rows, %{"p-1" => 62})
  assert a.next_release.percent == 62
  assert b.next_release.percent == nil
  assert c.next_release == nil
end
```

- [ ] **Step 2: Run to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live/view_test.exs`
Expected: FAIL (compile error on `Shelf.Card`, then `view.watchlist` missing).

- [ ] **Step 3: Implement**

In `view.ex`:
- Remove `alias MediaCentaurWeb.Components.Incoming.Shelf.Card`, `@shelf_cap`, `ShelfSection`, `expand_shelf/2`, `shelf_section/3`, `card_from_event/2`, `pill_status/*`, `subtitle_for/1`, `art_url/1` (everything the shelf used and nothing else uses).
- Add `alias MediaCentaurWeb.Components.Title.Row.NextRelease` and `alias MediaCentaurWeb.IncomingLive.WatchlistRows`.
- `defstruct watchlist: [], in_flight: [], drafts: [], feed: %UpcomingFeed{}` and the `@type t` to match (`watchlist: [WatchlistRows.row()]`).
- `build/1`:

```elixir
def build(inputs) do
  feed = UpcomingFeed.build(inputs.releases, feed_context(inputs))

  %View{
    watchlist:
      WatchlistRows.build(%{
        watchlist: inputs.watchlist,
        feed: feed,
        social_activity: inputs.social_activity,
        acquisition_states: inputs.acquisition_states,
        posters: inputs.posters,
        today: inputs.today
      }),
    in_flight: if(inputs.prowlarr_ready?, do: inputs.pursuit_rows, else: []),
    drafts: if(inputs.prowlarr_ready?, do: inputs.drafts, else: []),
    feed: feed
  }
end
```

- `with_progress/2`:

```elixir
@doc """
Stamp live download percentages onto in-pursuit rows —
`%{pursuit_id => percent}` comes from the render-time queue pairing. A
row whose pursuit has no paired torrent yet stays percentless.
"""
@spec with_progress([WatchlistRows.row()], %{optional(Ecto.UUID.t()) => non_neg_integer()}) :: [WatchlistRows.row()]
def with_progress(rows, progress_by_pursuit) do
  Enum.map(rows, fn
    %{next_release: %NextRelease{status: :in_pursuit, pursuit_id: id} = next} = row when is_binary(id) ->
      %{row | next_release: %{next | percent: Map.get(progress_by_pursuit, id)}}

    row ->
      row
  end)
end
```

- Moduledoc: "a wanted title moving from the watchlist (its next release) through pursuit (in flight) to outcome (ledger)"; the `build/1` doc lists the new inputs (`:watchlist`, `:social_activity`, `:acquisition_states`, `:posters`) and drops `:shelf_expanded?`.

- [ ] **Step 4: Run to see it pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live/view_test.exs`
Expected: PASS.

---

### Task 5: `IncomingLive.Logic` — the zone is `:watchlist`

**Files:**
- Modify: `lib/media_centaur_web/live/incoming_live/logic.ex`
- Test: `test/media_centaur_web/live/incoming_live/logic_test.exs`

- [ ] **Step 1: Update the tests**

In `logic_test.exs` replace every `:coming_up` with `:watchlist` and every `"coming_up"` with `"watchlist"`; where a test's name says "Coming up" say "Watchlist". Add:

```elixir
test "the retired zone name is unrecognised and falls back to the watchlist" do
  assert Logic.parse_zone("coming_up") == :watchlist
end
```

- [ ] **Step 2: Run to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live/logic_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `logic.ex`: `zone_path(:watchlist)`, `parse_zone("watchlist")`, the `:watchlist` fallback, `initial_zone/3` returning `:watchlist`, the specs and the docs ("the Watchlist is the fallback", "a bare path is plainly the Watchlist").

- [ ] **Step 4: Run to see it pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live/logic_test.exs`
Expected: PASS.

---

### Task 6: `IncomingLive` — the Watchlist tab

**Files:**
- Modify: `lib/media_centaur_web/live/incoming_live.ex`
- Test: `test/media_centaur_web/live/incoming_live_test.exs`

- [ ] **Step 1: Update the page tests**

Mechanical, across the file: `[data-nav-zone='coming_up_list']` → `[data-nav-zone='title_rows']`; `"Coming up"` (the tab label assertions) → `"Watchlist"`; `phx-value-zone='coming_up'` → `phx-value-zone='watchlist'`; `~p"/incoming?zone=coming_up"` → `~p"/incoming?zone=watchlist"`; `#shelf-#{item.id}` → `#watchlist-item-tv_series-#{item.tmdb_id}` (l.~4094); the describe name at l.2564 → `"zone tabs (Watchlist | Activity | History)"`; test names that say "Coming up" / "the agenda" / "the forecast" say "the Watchlist".

Then port the Discovery row tests (from `discovery_live_test.exs` l.60–170) into a new describe. They need the `list/4` helper from that file — copy it (it stores the title record then `Discovery.put_rung/3`) and the `ids/2` helper if used:

```elixir
describe "the Watchlist tab (UIDR-050)" do
  test "an empty watchlist states what fills it", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, ~p"/incoming")
    assert has_element?(view, "#watchlist-empty")
    refute has_element?(view, "[data-nav-zone='title_rows']")
  end

  test "a listed-only title is a row with no next release; a followed one carries its next release", %{conn: conn} do
    {:ok, _} = list(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}), :list)
    {item, _release} = tracked_with_release(%{name: "Tabbed Forecast Show"})

    {:ok, view, _html} = live_async!(conn, ~p"/incoming")

    assert has_element?(view, "[data-nav-zone='title_rows'] #watchlist-item-movie-777")
    refute has_element?(view, "#watchlist-item-movie-777 [data-component='status-pill']")
    assert has_element?(view, "#watchlist-item-tv_series-#{item.tmdb_id}", "S01E01")
    assert has_element?(view, "#watchlist-item-tv_series-#{item.tmdb_id} [data-component='status-pill']")
    # Dated first, listed-only after.
    assert ids(view, "[data-nav-zone='title_rows'] [data-component='title-row']") ==
             ["watchlist-item-tv_series-#{item.tmdb_id}", "watchlist-item-movie-777"]
  end

  test "a row never says On your list about itself", %{conn: conn} do
    {:ok, _} = list(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}), :list)
    {:ok, view, html} = live_async!(conn, ~p"/incoming")
    assert has_element?(view, "[id^='watchlist-item-']")
    refute html =~ "On your list"
  end

  test "listing a title lands it on the tab without a reload", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, ~p"/incoming")
    {:ok, _} = list(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}), :list)
    render_until(view, "Sample Movie")
    await_supervised_tasks()
  end

  test "library changes flip a row to In library without a reload", %{conn: conn} do
    {:ok, _} = list(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}), :list)
    {:ok, view, html} = live_async!(conn, ~p"/incoming")
    refute html =~ "In library"

    movie = create_standalone_movie(%{name: "Sample Movie"})
    create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
    create_linked_file(%{movie_id: movie.id})
    Library.broadcast_entities_changed([movie.id])

    render_until(view, "In library")
    await_supervised_tasks()
  end

  test "a row opens the title detail; the modal's bookmark removes the row and stays open", %{conn: conn} do
    {:ok, _} = list(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}), :list)
    {:ok, view, _html} = live_async!(conn, ~p"/incoming")

    view |> element("#watchlist-item-movie-777") |> render_click()
    assert_patch(view, "/incoming?title=movie-777")
    assert has_element?(view, "#detail-modal[data-state=open]")

    view |> element("#detail-watchlist-toggle") |> render_click()
    refute has_element?(view, "#watchlist-item-movie-777")
    assert has_element?(view, "#detail-modal[data-state=open]")
    await_supervised_tasks()
  end
end
```

`StatusPill` has no `data-component` today: add `data-component="status-pill"` to both of its root elements (the `<a :if={@anchor}>` and the `<span>` after it) in `lib/media_centaur_web/components/incoming/status_pill.ex`. `render_until/2` comes from `MediaCentaurWeb.ConnCase` (`test/support/conn_case.ex:115`), already in scope.

- [ ] **Step 2: Run to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_test.exs`
Expected: FAIL (compile error on `View.expand_shelf` / `shelf` first).

- [ ] **Step 3: Implement the LiveView**

In `incoming_live.ex`:

1. Aliases: drop `Shelf` from `alias MediaCentaurWeb.Components.Incoming.{Ledger, Shelf}`; add `alias MediaCentaurWeb.Components.Title.Row, as: TitleRow`, `alias MediaCentaur.Acquisition.TitleStates`, `alias MediaCentaur.TMDB.Store` (check `Discovery`, `Activities`, `TitleRef` are already aliased — they are used). `import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1]` if not already imported (check how `media_results.ex` resolves posters and use the same function).

2. `mount/3`: add `Store` to the subscription list `[MediaCentaur.Library, Activities, Discovery, Store, IntegrationAvailability]`; delete `shelf_expanded?: false` from the initial assigns.

3. `build_view/1` reads the watchlist facts:

```elixir
defp build_view(socket) do
  releases = forecast_releases()
  acquisition? = Capabilities.acquisition_ready?()
  approval_policy = PlanningMode.approval_policy(PlanningMode.value())
  grab = grab_status_by_key(releases, acquisition?)
  watchlist = Discovery.list_watchlist()
  refs = Enum.map(watchlist, &{&1.intent.tmdb_id, &1.intent.media_type})

  view =
    View.build(%{
      releases: releases,
      watchlist: watchlist,
      social_activity: Activities.activity_for(refs),
      acquisition_states: TitleStates.for_refs(refs),
      posters: Map.new(watchlist, &{{&1.intent.tmdb_id, &1.intent.media_type}, title_poster_url(&1.intent.title)}),
      pursuit_rows: socket.assigns.pursuit_rows,
      drafts: socket.assigns.plan_drafts,
      today: socket.assigns.today,
      prowlarr_ready?: Capabilities.prowlarr_ready?(),
      acquisition_ready?: acquisition?,
      approval_policy: approval_policy,
      rungs: socket.assigns.title_rungs,
      grab_status_by_key: grab
    })

  assign(socket, view: view, grab_status_by_key: grab, approval_policy: approval_policy)
end
```

4. `assign_zone/3`: the forecast-only branch returns `:watchlist`; the comment says "Watchlist | Activity | History" and "everything renders as the Watchlist". `incoming_path/2` and `build_pursuit_modal_path/2`: `socket.assigns.zone == :watchlist` / `!= :watchlist`. `handle_event("switch_zone", …)` guard: `when zone in ~w(watchlist activity history)`. The `zone_tab` component's `values: [:watchlist, :activity, :history]`; the tab: `<.zone_tab zone={:watchlist} active_zone={@zone} label="Watchlist" />`.

5. `render/1`: replace the `:shelf_cards` assign with

```elixir
|> Phoenix.Component.assign(
  :watchlist_rows,
  View.with_progress(assigns.view.watchlist, shelf_progress(download_cards))
)
```

(rename `shelf_progress/1` to `progress_by_pursuit/1` and its comment: "the paired downloads stamp their progress onto in-pursuit watchlist rows").

6. The section. Replace the `<Shelf.shelf …/>` element with:

```heex
<%!-- The Watchlist (UIDR-050): every listed title once, a followed
      title's next release at its right. Centered at the omnibox's
      measure. The empty tab says what fills it (UIDR-034). --%>
<section :if={!@search_owns? && @zone == :watchlist} id="incoming-watchlist" class="mx-auto w-full max-w-3xl">
  <.empty_state :if={@watchlist_rows == []} id="watchlist-empty" headline="Titles you save land here">
    Search above, open a title and add it to your watchlist. A title you track shows its next release here.
  </.empty_state>
  <div :if={@watchlist_rows != []} data-nav-zone="title_rows" class="space-y-2">
    <TitleRow.title_row
      :for={row <- @watchlist_rows}
      id={"watchlist-item-#{TitleRef.param(row.ref)}"}
      title={row.title}
      poster_url={row.poster_url}
      markers={row.markers}
      notes={row.notes}
      social_activity={row.social_activity}
      next_release={row.next_release}
    />
  </div>
</section>
```

7. Delete `handle_event("expand_shelf", …)` and `handle_event("select_event", …)` (the row's `open_title` is `TitleDetailHost`'s). Delete the `Item` alias if `select_event` was its last use (`grep -n "Item\b" incoming_live.ex`).

8. Live updates: the `{tag, _event} when tag in [:activity_received, :activity_sent, :activity_deleted]` handler also rebuilds: pipe `|> build_view()` after the `assign`. Add `def handle_info({:tmdb_title_changed, _ref}, socket), do: {:noreply, build_view(socket)}` next to the forecast handlers (check the message shape in `Discovery`/`Store` — `discovery_live.ex:417` handles `{:tmdb_title_changed, _ref}`).

9. Moduledoc: the tab list becomes **Watchlist** (default), **Activity**, **History**; the Watchlist paragraph:

```
**Watchlist** — every title at List or above, once (`"title_rows"`):
`Title.Row` per title with its markers, social glyphs and, for a
followed title, its next release and status (`WatchlistRows`), dated
nearest first. The watchlist is read in `build_view/1` with the
forecast, so one rebuild path serves both.
```

- [ ] **Step 4: Run to see it pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_test.exs test/media_centaur_web/live/incoming_live_pursuit_modal_test.exs`
Expected: PASS. If a test asserts the *order* of rows seeded by `tracked_with_release` against listed-only rows, the sort is dated-first; fix the expectation, not the sort.

---

### Task 7: Delete the shelf and the next-date marker

**Files:**
- Delete: `lib/media_centaur_web/components/incoming/shelf.ex`, `storybook/incoming/shelf.story.exs`, `storybook/incoming/shelf_row.story.exs`
- Modify: `storybook/incoming/_incoming.index.exs`, `lib/media_centaur_web/components/title/logic.ex`, `test/media_centaur_web/components/title/logic_test.exs`

- [ ] **Step 1: Delete the shelf**

```bash
git rm lib/media_centaur_web/components/incoming/shelf.ex storybook/incoming/shelf.story.exs storybook/incoming/shelf_row.story.exs
```

Remove the two `entry("shelf")` / `entry("shelf_row")` lines from `_incoming.index.exs`. `grep -rn "Incoming.Shelf\|shelf_row\|incoming-shelf" lib test storybook assets docs .claude` must come back empty except prose.

- [ ] **Step 2: Remove the next-date marker from `Title.Logic`**

In `logic_test.exs` delete the `next_air_date/2` describe (l.~266–278) and the `next_air_date:` keys in the `row_markers/2` cases (l.~252, ~260), with the assertion that expected a `"Next: …"` marker. Run `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/logic_test.exs` — passes still (the keys are optional).

In `logic.ex`: delete the `next` computation and its `optional(:next_air_date)` / `optional(:today)` spec keys so `row_markers/2` returns `[state, tracking]`; delete `next_air_date/2`, its `@doc`/`@spec`, and the `Release` alias if unused; update the `row_markers` doc (the sentence at l.~141 about "the next release date when the facts carry one").

- [ ] **Step 3: Compile and run the two files**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors && ~/scripts/agents/agent-mix test test/media_centaur_web/components/title/logic_test.exs test/media_centaur_web/storybook_compile_test.exs`
Expected: clean compile, PASS.

---

### Task 8: Discovery loses the Watchlist tab

**Files:**
- Modify: `lib/media_centaur_web/router.ex:46`, `lib/media_centaur_web/live/discovery_live.ex`, `lib/media_centaur_web/components/layouts.ex:139-144`, `test/media_centaur_web/page_smoke_test.exs:229,264`, `test/media_centaur_web/live/discovery_live_test.exs`

- [ ] **Step 1: Update the tests**

`page_smoke_test.exs`: delete the two `/discovery/watchlist` rows. `discovery_live_test.exs`: delete the tests at l.60–180 that mount `/discovery/watchlist` to test rows (they now live in Task 6); for every remaining test that mounts `~p"/discovery/watchlist…"` to test the *modal*, mount `~p"/discovery…"` instead (same params) — the modal opens by identity on any page (UIDR-043). `grep -n "discovery/watchlist" test/` must come back empty.

- [ ] **Step 2: Run to see the removed route fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs`
Expected: the moved tests pass (route still exists); proceed.

- [ ] **Step 3: Remove the tab**

- `router.ex`: delete `live "/discovery/watchlist", DiscoveryLive, :watchlist`.
- `layouts.ex`: delete `"/discovery/watchlist",` from the sidebar's active-path list.
- `discovery_live.ex`: delete `load_items/1`, `next_air_date/2`, the `:items` assign and the `items` half of `stamp_acquisition_states/1` (keep the activities half — `refs` is `Enum.map(socket.assigns.activities, &activity_ref/1)` alone), the `:watchlist` `Tab`, `current_path(:watchlist)`, `discovery_path(… :watchlist …)`, the `:watchlist` template block (l.~830–875), every `|> load_items()` in the handlers (l.388–397; keep `load_activities`), the `{:tmdb_title_changed, _ref}` handler if `load_items` was its only work (check — a feed row paints from the store too; if `load_activities` reads the store, route it there instead), the `TitleRow`, `ReleaseTracking` and `Logic` aliases if now unused. The `rail` renders on the Feed only: `:if={@live_action == :feed}`. Moduledoc: delete the watchlist paragraph; "Three tabs" → "two tabs"; "Every watchlist and feed row" → "Every feed row".

- [ ] **Step 4: Compile and run**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors && ~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/page_smoke_test.exs`
Expected: clean, PASS.

---

### Task 9: The nav config

**Files:**
- Modify: `assets/js/input/config.js`, `assets/js/input/__tests__/index.test.js`

- [ ] **Step 1: Update the JS tests**

In `index.test.js` (l.~110–185): every `coming_up_list` → `title_rows`; the test names "the agenda" → "the watchlist". Add inside the Incoming describe:

```js
test("Discovery has no title_rows zone any more — the watchlist lives on Incoming", () => {
  expect(inputConfig.zoneLayouts.discovery.title_rows).toBeUndefined()
})
```

(check the exported layout object's name — `grep -n "zoneLayouts\|export" assets/js/input/config.js`).

- [ ] **Step 2: Run to see it fail**

Run: `cd assets && bun test js/input/__tests__/index.test.js`
Expected: FAIL.

- [ ] **Step 3: Implement**

`config.js`: delete the `coming_up_list` selector and context lines (l.~64–70, ~98) and their comment; in the `incoming` layout replace `coming_up_list` with `title_rows` in `omnibox.down`, `zone_tabs.down`, the row itself (`title_rows: { up: ["zone_tabs", "omnibox"] }`) and `sidebar.right`; in `cursorStartPriority.incoming` likewise. In the `discovery` layout delete `title_rows` from `zone_tabs.down`, its own row, and `sidebar.right`; in `cursorStartPriority.discovery` likewise; the comment above it: "the person cards on Friends; the Feed's rows and rail are not nav items until the hardening pass". The Incoming comment: "Watchlist shows title_rows".

- [ ] **Step 4: Run to see it pass**

Run: `cd assets && bun test`
Expected: PASS.

---

### Task 10: Copy that named Coming up

**Files:**
- Modify: `lib/media_centaur_web/components/title/tracking_controls.ex:7-8,92,163-175`, `lib/media_centaur_web/live/title_detail_host/acquisition.ex:67`, `lib/media_centaur/discovery/title_intent.ex:17`, `lib/media_centaur/format.ex:78`

- [ ] **Step 1: Find the tests pinning the Follow switch's label and line**

Run: `grep -rn "Notify you via Coming up\|under Coming up\|Coming up will" test/ storybook/`
Update each to the words below.

- [ ] **Step 2: Change the words**

- `tracking_controls.ex` l.92: `label="Track release dates"`. The moduledoc bullet: "**Track release dates** — on at Follow and above. The app keeps the title's calendar and its next release shows on the watchlist." The `track_line/…` doc at l.163 and its strings: wherever the line says the dates show "under Coming up", say "on your watchlist" (read the function; keep its structure).
- `acquisition.ex` l.67: `"Tracking #{title.name} — its next release shows on your watchlist"` (read the full string first; keep any second clause).
- `title_intent.ex` l.17: `` | `:follow` | keeps its calendar, so its next release shows on the watchlist | ``.
- `format.ex` l.78: replace "Coming up's" with "the watchlist's" in the doc comment.

- [ ] **Step 3: Run the touched tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title test/media_centaur_web/live/title_detail_host`
Expected: PASS.

---

### Task 11: The decision record and the docs

**Files:**
- Create: `decisions/user-interface/2026-10-02-050-the-watchlist-is-incomings-first-tab.md`
- Modify: `decisions/user-interface/2026-07-11-015-incoming-page.md`, `decisions/user-interface/2026-09-07-035-two-title-surfaces.md`, `decisions/user-interface/2026-09-14-042-tracking-is-the-bookmark-and-two-switches.md`, `decisions/README.md` (generated), `docs/GLOSSARY.md`, `.claude/skills/user-interface/SKILL.md`, `campaigns/social-and-watchlist.md`

- [ ] **Step 1: Write UIDR-050**

```markdown
---
status: accepted
date: 2026-10-02
---
# The watchlist is Incoming's first tab, and the schedule is on its rows

Amends UIDR-015 (the Coming up tab) and UIDR-035 rule 5 (three lists).

## Context and Problem Statement

The watchlist was a tab of the Discovery page and Coming up a tab of Incoming. Both listed title intents: the watchlist every one at List or above, Coming up the followed ones by date. One record, two lists on two pages — and the watchlist was reachable only while the social preference was on.

## Decision Outcome

1. **Incoming's tabs are Watchlist (default), Activity, History.** `/discovery/watchlist` is gone; the Discovery page keeps the Feed and Friends.
2. **One row per title at List or above**, the `Title.Row`: poster, markers, social glyphs. A followed title's row carries its **next release** at the right — date label, the release, and its status in the `StatusPill` vocabulary; an in-pursuit pill carries the percent and anchors to the pursuit row (UIDR-015 §6 stands).
3. **Order:** titles with a dated next release nearest first, then followed titles TMDB has not dated, then listed-only titles newest first.
4. **No cap.** The list is the list.
5. **Home's Coming up shelf is unchanged.** The words *Coming up* name that shelf only.
6. **The Follow switch reads *Track release dates*.** It no longer names a tab.

### Consequences

* Good, because the watchlist is always reachable and one record is listed once.
* Bad, because a long watchlist puts listed-only titles below the fold; the omnibox above is the way to a specific title.
```

- [ ] **Step 2: Amend the three records**

Under each record's front matter add `amended: 2026-10-02` and, after the title, a dated blockquote:

- UIDR-015: "> **Amendment 2026-10-02 — superseded in part by UIDR-050.** The Coming up tab (rule 3, and the 2026-08-02 amendment's tab list) is the Watchlist tab: every listed title once, the schedule on the followed rows. Rules 2, 4–7 stand."
- UIDR-035: "> **Amendment 2026-10-02 (UIDR-050).** Rule 5's three lists are two: the watchlist carries the schedule on its rows; Coming up is Home's shelf alone."
- UIDR-042: "> **Amendment 2026-10-02 (UIDR-050).** The Follow switch's label is *Track release dates*; *Notify you via Coming up* named a tab that no longer exists."

Run `scripts/gen-decisions-index`.

- [ ] **Step 3: Glossary and skill**

`docs/GLOSSARY.md`: the **Rung** and **Tracking controls** rows: "Notify you via Coming up" → "Track release dates"; the **Discovery** row: "Feed and Friends tabs at `/discovery`"; the **Feed** (tab) row: "The Discovery tab … (one of two)"; add a row after **Bookmark**:

```
| **Watchlist** (tab) | Incoming's first tab, the default (UIDR-050): every title intent at List or above, once, as a `Title.Row`; a followed title's row carries its **next release** (`Title.Row.NextRelease`, built by `IncomingLive.WatchlistRows`) — date, release, `StatusPill` status. Dated nearest first, then undated followed, then listed-only newest first. |
```

`.claude/skills/user-interface/SKILL.md`: the Page Structure table — Incoming "Watchlist, Activity, History and the omnibox (UIDR-015, UIDR-050)"; Discovery `/discovery`, `/discovery/friends` "Feed, friends"; the UIDR table gains `| 050 | The watchlist is Incoming's first tab; the schedule is on its rows |`; the Component Inventory loses nothing (the shelf had no row there) — check `grep -n "Shelf\|coming_up" .claude/skills/user-interface/SKILL.md`.

`campaigns/social-and-watchlist.md`: Status → "Phase 1 shipped <commit>".

- [ ] **Step 4: Guide and wiki**

`priv/guide/watchlist-and-tracking.md`: l.8 "at **Incoming → Watchlist**"; l.40 `| **Follow** | Its next release shows on the row; nothing is downloaded |`; l.59 "the schedule on the watchlist". `priv/guide/release-tracking-and-upcoming.md`: l.11 and the `## The Coming up shelf` section describe the watchlist row's next release and Home's shelf. `priv/guide/search-and-download.md` l.18: `| Watchlist | Every title you listed; a tracked one shows its next release — see …`. `priv/guide/a-tour-of-the-app.md` l.17: "your watchlist with tracked releases coming up". Run `~/scripts/agents/agent-mix test test/media_centaur/guide` (the guide library has tests on its pages).

Wiki (`~/src/media-centaur/media-centaur.wiki`): `Watchlist.md` (l.3 "a tab of the Incoming page (`/incoming`)", l.7 drop the preference gate sentence, l.23 "## The Watchlist tab" body: the row's next release, the order; l.35 the Follow row's label and effect; l.72), `Release-Tracking.md` (l.7, 12, 18–22, 51, 64: "Track release dates"; the schedule is the watchlist row's next release; a release still missing stays on the row as how long the app has searched), `Searching-and-Downloading.md` (l.3, 9, 13: the tab table and "the Watchlist otherwise"), `Social.md` (l.3, 62, 77, 169: Discovery is Feed and Friends; the watchlist link points at Incoming), `Keyboard-and-Gamepad.md` (grep "Coming up"). Commit there: `git add -A && git commit -m "wiki: the watchlist is Incoming's first tab" && git push`.

---

### Task 12: Precommit and commit

- [ ] **Step 1: Full precommit**

Run: `~/scripts/agents/agent-mix precommit`
Expected: clean — zero warnings, Credo clean (MC0009: every component has a story; `Row.NextRelease` is a struct, not a component), all tests green.

- [ ] **Step 2: Look at it**

With the dev server running: `page-shot --url http://127.0.0.1:2160/incoming --viewport 1920x1080 --wait-ms 3000` and read the PNG — the tab reads Watchlist, a followed title's row has its date and pill at the right, a listed-only row has none, the empty state renders when the list is empty (`?zone=watchlist` on an empty dev DB).

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(incoming): the watchlist is Incoming's first tab; Coming up folds into its rows (UIDR-050)"
```

One commit for the phase is fine; split at Task 7 (deletions) and Task 11 (docs) if the diff reads better that way.
