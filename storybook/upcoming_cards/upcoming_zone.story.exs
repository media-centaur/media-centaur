defmodule MediaCentarrWeb.Storybook.UpcomingCards.UpcomingZone do
  @moduledoc """
  Upcoming releases zone — monthly calendar, active-shows section,
  recent-changes feed, tracking list, unscheduled list, and a
  stop-tracking confirmation modal.

  This is the most complex single component in the catalog (11 attrs,
  most loosely-typed `:map`/`:list`/`:any`). The contract is documented
  in `MediaCentarrWeb.Components.UpcomingCards.upcoming_zone/1`.

  ## Why representative coverage rather than exhaustive

  An exhaustive matrix (every release status × every kind × every
  acquisition combination) would balloon the fixture surface to 800+
  lines without proportional value — the component branches on so many
  axes simultaneously that each "interesting" combination is its own
  bespoke setup. Instead, the variations below cover the **shapes** the
  zone takes in practice:

    1. `:typical_month` — calendar populated, an active TV show + an
       active movie, a few tracked items, both readiness flags on.
    2. `:empty_month` — the empty-state pass: no releases, no events,
       no tracked items.
    3. `:tmdb_offline` — `tmdb_ready: false` hides the "Track New
       Releases" button on the calendar header.
    4. `:acquisition_offline` — `acquisition_ready: false` strips the
       per-row download icons / "Queue all" affordances.
    5. `:confirm_stop_modal` — the stop-tracking modal in its open
       state.
    6. `:selected_day` — the day-detail panel below the calendar with
       a date selected.

  ## Contract observations

  The contract is a Phase 3 candidate in
  `~/src/media-centarr/component-contract-plan.md` (paired migration
  with `library_cards.ex`). Notable smells observed while wiring this
  story:

    * `releases: %{upcoming: [...], released: [...]}` — opaque map. A
      typed `UpcomingFeed` struct would document the bucket invariant
      and give the component a real signature.
    * `images: %{...}` — the `attr` declaration carries no doc text.
      The actual key is `item.id` (the local UUID), not the
      obvious-from-the-variable-name `tmdb_id`. Phase 3 should either
      rename the attr or add a doc clarifying the key shape.
    * `tracked_items` is a list of bespoke maps assembled by
      `UpcomingLive.build_tracked_items_from_watching/0`. There's no
      schema or struct — fixtures here mirror the keys
      (`item_id`, `name`, `media_type`, `status_text`).
    * `grab_statuses` is keyed by
      `{tmdb_id_string, media_type_string, season_number, episode_number}`
      — a four-tuple constructed at three call sites
      (`home_live.ex`, `upcoming_live.ex`, `upcoming_cards.ex`). A small
      typed `GrabKey` would prevent accidental drift.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.ReleaseTracking.{Event, Item, Release}

  def function, do: &MediaCentarrWeb.Components.UpcomingCards.upcoming_zone/1
  def render_source, do: :function

  # The upcoming zone is a full-page composition — narrow it into a
  # two-column preview and the calendar collapses into single-column
  # mode and the "active-shows" pair stacks. One column shows the
  # production layout.
  def layout, do: :one_column

  # The `:confirm_stop_modal` variation renders a `position: fixed; inset: 0`
  # backdrop that would otherwise escape the variation block and cover the
  # whole storybook chrome (and the `body:has(.modal-backdrop[data-state=open])`
  # rule would lock the page scroll). Iframing every variation isolates each
  # preview so the modal only covers its own zone.
  def container, do: {:iframe, style: "width: 100%; height: 1800px;"}

  def variations do
    [
      %Variation{
        id: :typical_month,
        description:
          "Happy path — calendar populated with a mix of upcoming and recently-released " <>
            "tiles, two active shows (one TV, one streaming movie), three tracked items, " <>
            "and a small recent-changes feed. `tmdb_ready: true`, `acquisition_ready: true`.",
        attributes: typical_month_attrs()
      },
      %Variation{
        id: :empty_month,
        description:
          "Empty-state pass. No releases on any day, no events, no tracked items. " <>
            "The calendar grid still renders but every cell is blank; the Active / " <>
            "Recent Changes / Tracking sections each show their fallback copy.",
        attributes: empty_month_attrs()
      },
      %Variation{
        id: :tmdb_offline,
        description:
          "`tmdb_ready: false` — hides the **Track New Releases** action in the " <>
            "calendar header. No other surface is affected; the zone stays usable for " <>
            "browsing the existing schedule.",
        attributes: %{typical_month_attrs() | tmdb_ready: false}
      },
      %Variation{
        id: :acquisition_offline,
        description:
          "`acquisition_ready: false` — strips the per-row download icons, the " <>
            "**Queue all** button on TV cards, and the day-detail status badges. " <>
            "Calendar tiles still render, the user can still browse, just without " <>
            "the download affordances.",
        attributes: %{typical_month_attrs() | acquisition_ready: false}
      },
      %Variation{
        id: :selected_day,
        description:
          "`selected_day` set to a date that has releases — the day-detail panel " <>
            "renders below the calendar header showing wider release cards.",
        attributes: %{typical_month_attrs() | selected_day: ~D[2026-05-15]}
      },
      %Variation{
        id: :confirm_stop_modal,
        description:
          "`confirm_stop_item` populated — the stop-tracking confirmation modal is " <>
            "open over the zone. Cancel and Stop tracking buttons render; the rest " <>
            "of the zone is unchanged underneath.",
        attributes: %{typical_month_attrs() | confirm_stop_item: sample_item_tv()}
      }
    ]
  end

  # --- Fixtures ---------------------------------------------------------

  # Pinned month/day so the calendar layout and the "selected_day"
  # variation are stable. `today` inside the component is
  # `Date.utc_today/0` — that's the only piece of clock state we can't
  # control without fake-time machinery, and it only changes the
  # `is_today` highlight.
  @calendar_month {2026, 5}

  defp typical_month_attrs do
    item_tv = sample_item_tv()
    item_movie = sample_item_movie()

    upcoming = [
      tv_release(item_tv, ~D[2026-05-08], 1, 3, "Sample Episode 3"),
      tv_release(item_tv, ~D[2026-05-15], 1, 4, "Sample Episode 4"),
      tv_release(item_tv, ~D[2026-05-22], 1, 5, "Sample Episode 5"),
      movie_release(item_movie, ~D[2026-05-15], "digital"),
      # Multi-release-on-same-day exercises the 2x2 calendar tile layout.
      tv_release(item_tv, ~D[2026-05-15], 1, 6, "Sample Episode 6")
    ]

    released = [
      tv_release(item_tv, ~D[2026-05-01], 1, 1, "Sample Episode 1", released: true),
      tv_release(item_tv, ~D[2026-05-04], 1, 2, "Sample Episode 2",
        released: true,
        in_library: true
      )
    ]

    %{
      releases: %{upcoming: upcoming, released: released},
      events: sample_events(),
      images: %{
        item_tv.id => %{
          backdrop: "https://placehold.co/1280x720/0f172a/ffffff?text=Sample+Show",
          poster: "https://placehold.co/300x450/0f172a/ffffff?text=Sample+Show",
          logo: nil
        },
        item_movie.id => %{
          backdrop: "https://placehold.co/1280x720/1e293b/ffffff?text=Sample+Movie",
          poster: "https://placehold.co/300x450/1e293b/ffffff?text=Sample+Movie",
          logo: nil
        }
      },
      calendar_month: @calendar_month,
      selected_day: nil,
      tracked_items: sample_tracked_items(item_tv, item_movie),
      confirm_stop_item: nil,
      tmdb_ready: true,
      grab_statuses: %{
        # Episode 1: completed grab (no live queue item) → :downloading
        {"1001", "tv_series", 1, 1} => %Grab{
          tmdb_id: "1001",
          tmdb_type: "tv_series",
          title: "Sample Show",
          season_number: 1,
          episode_number: 1,
          status: "grabbed"
        },
        # Episode 3: still searching
        {"1001", "tv_series", 1, 3} => %Grab{
          tmdb_id: "1001",
          tmdb_type: "tv_series",
          title: "Sample Show",
          season_number: 1,
          episode_number: 3,
          status: "searching"
        }
      },
      queue_items: [],
      acquisition_ready: true
    }
  end

  defp empty_month_attrs do
    %{
      releases: %{upcoming: [], released: []},
      events: [],
      images: %{},
      calendar_month: @calendar_month,
      selected_day: nil,
      tracked_items: [],
      confirm_stop_item: nil,
      tmdb_ready: true,
      grab_statuses: %{},
      queue_items: [],
      acquisition_ready: false
    }
  end

  # --- Items ------------------------------------------------------------

  # Both items use a stable UUID so the `images` map keys match across
  # builds. `library_entity_id: nil` matches a freshly-tracked item that
  # hasn't been linked to a library entity yet.

  defp sample_item_tv do
    %Item{
      id: "00000000-0000-0000-0000-000000000001",
      tmdb_id: 1001,
      media_type: :tv_series,
      name: "Sample Show",
      status: :watching,
      source: :manual,
      library_entity_id: nil,
      poster_path: nil,
      backdrop_path: nil,
      last_library_season: 0,
      last_library_episode: 0
    }
  end

  defp sample_item_movie do
    %Item{
      id: "00000000-0000-0000-0000-000000000002",
      tmdb_id: 2002,
      media_type: :movie,
      name: "Sample Movie",
      status: :watching,
      source: :manual,
      library_entity_id: nil,
      poster_path: nil,
      backdrop_path: nil,
      last_library_season: 0,
      last_library_episode: 0
    }
  end

  # --- Releases ---------------------------------------------------------

  defp tv_release(item, air_date, season, episode, title, opts \\ []) do
    %Release{
      id: Ecto.UUID.generate(),
      air_date: air_date,
      title: title,
      season_number: season,
      episode_number: episode,
      released: Keyword.get(opts, :released, false),
      in_library: Keyword.get(opts, :in_library, false),
      release_type: nil,
      item_id: item.id,
      item: item
    }
  end

  defp movie_release(item, air_date, release_type) do
    %Release{
      id: Ecto.UUID.generate(),
      air_date: air_date,
      title: nil,
      season_number: nil,
      episode_number: nil,
      released: false,
      in_library: false,
      release_type: release_type,
      item_id: item.id,
      item: item
    }
  end

  # --- Events -----------------------------------------------------------

  defp sample_events do
    [
      %Event{
        id: Ecto.UUID.generate(),
        event_type: :began_tracking,
        description: "began tracking Sample Show",
        item_name: "Sample Show",
        inserted_at: ~U[2026-04-28 14:00:00Z]
      },
      %Event{
        id: Ecto.UUID.generate(),
        event_type: :new_episodes_announced,
        description: "3 new episodes announced for Sample Show",
        item_name: "Sample Show",
        inserted_at: ~U[2026-04-29 09:30:00Z]
      },
      %Event{
        id: Ecto.UUID.generate(),
        event_type: :stopped_tracking,
        description: "stopped tracking Old Sample Series",
        item_name: "Old Sample Series",
        inserted_at: ~U[2026-04-30 18:15:00Z]
      }
    ]
  end

  # --- Tracked items ----------------------------------------------------

  # Mirrors the shape produced by
  # `UpcomingLive.build_tracked_items_from_watching/0` — a list of bespoke
  # maps, NOT `Item` structs. Keys: `item_id`, `name`, `media_type`,
  # `status_text`.
  defp sample_tracked_items(item_tv, item_movie) do
    [
      %{
        item_id: item_tv.id,
        name: item_tv.name,
        media_type: :tv_series,
        status_text: "3 upcoming, 1 released"
      },
      %{
        item_id: item_movie.id,
        name: item_movie.name,
        media_type: :movie,
        status_text: "1 upcoming"
      },
      %{
        item_id: "00000000-0000-0000-0000-000000000003",
        name: "Quiet Sample",
        media_type: :tv_series,
        status_text: "tracking"
      }
    ]
  end
end
