defmodule MediaCentaurWeb.IncomingLive.WatchlistRowsTest do
  @moduledoc """
  Pure unit tests for the Watchlist tab's row builder: the watchlist
  read joined with the forecast, the acquisition states, the social
  activity and the posters, then sorted the way the tab reads.
  """
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

  defp watchlist_row(intent, library_owner_id \\ nil),
    do: %{intent: intent, library_owner_id: library_owner_id}

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

  # A feed whose only scheduled bucket holds `events`. The bucket is
  # irrelevant to these tests: the builder sorts on `air_date`.
  defp feed(events), do: %UpcomingFeed{buckets: %{this_week: events}, unscheduled: []}

  defp inputs(overrides) do
    Map.merge(
      %{
        watchlist: [],
        feed: feed([]),
        social_activity: %{},
        acquisition_states: %{},
        posters: %{},
        today: @today
      },
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
        event(5, :movie, ~D[2026-09-01], %{status: :in_library, kind: :movie}),
        event(6, :movie, ~D[2026-10-20], %{status: :armed_fallback, kind: :movie})
      ])

    watchlist =
      for id <- 1..6 do
        media_type = if id > 3, do: :movie, else: :tv_series
        watchlist_row(intent(id, media_type, :grab, ~N[2026-09-01 00:00:00]))
      end

    rows = WatchlistRows.build(inputs(%{watchlist: watchlist, feed: feed}))
    by_id = Map.new(rows, &{elem(&1.ref, 0), &1.next_release})

    assert by_id[1].status == :armed
    assert by_id[2].status == :searching
    assert %NextRelease{status: :in_pursuit, pursuit_id: "p-3"} = by_id[3]
    assert by_id[4].status == :in_theaters
    assert by_id[5].status == :landed
    assert by_id[6].status == :tracked
  end

  test "a listed-only title not in the library carries no markers and no next release" do
    rows =
      WatchlistRows.build(
        inputs(%{watchlist: [watchlist_row(intent(1, :movie, :list, ~N[2026-09-01 00:00:00]))]})
      )

    assert [%{markers: [], next_release: nil}] = rows
  end

  test "a followed title TMDB has not dated carries no next release" do
    rows =
      WatchlistRows.build(
        inputs(%{watchlist: [watchlist_row(intent(1, :tv_series, :follow, ~N[2026-09-01 00:00:00]))]})
      )

    assert [%{rung: :follow, markers: ["Tracking"], next_release: nil}] = rows
  end

  test "a season drop's subtitle names the season and the count" do
    rows =
      WatchlistRows.build(
        inputs(%{
          watchlist: [watchlist_row(intent(1, :tv_series, :follow, ~N[2026-09-01 00:00:00]))],
          feed:
            feed([
              event(1, :tv_series, ~D[2026-10-09], %{
                kind: :season_drop,
                episode_number: nil,
                episode_count: 8
              })
            ])
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
