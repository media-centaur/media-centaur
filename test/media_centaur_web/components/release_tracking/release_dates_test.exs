defmodule MediaCentaurWeb.Components.ReleaseTracking.ReleaseDatesTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaur.TMDB.ReleaseWindow
  alias MediaCentaurWeb.Components.ReleaseTracking.ReleaseDates

  defp movie_event(type, overrides) do
    struct!(
      %Event{
        id: "movie-#{type}",
        item_id: "item-1",
        item_name: "Sample Movie",
        media_type: :movie,
        kind: :movie,
        release_type: type,
        status: :upcoming
      },
      overrides
    )
  end

  defp episode(id, overrides) do
    struct!(
      %Event{
        id: id,
        item_id: "item-2",
        item_name: "Sample Show",
        media_type: :tv_series,
        kind: :episode,
        season_number: 2,
        episode_number: 1,
        status: :upcoming
      },
      overrides
    )
  end

  describe "movie_rows/2 — theaters, digital, disc" do
    test "the window's dates first, the calendar's where the window has none, else not announced" do
      window = %ReleaseWindow{stage: :theatrical, theatrical: ~D[2026-07-24]}
      timeline = [movie_event("digital", %{air_date: ~D[2026-09-15], status: :armed})]

      assert [theaters, digital, disc] = ReleaseDates.movie_rows(window, timeline)
      assert %{id: "theatrical", label: "Theaters", date: ~D[2026-07-24], status: nil} = theaters
      assert %{id: "digital", label: "Digital", date: ~D[2026-09-15], status: :armed} = digital
      assert %{id: "physical", label: "Disc", date: nil, status: nil} = disc
    end

    test "with no window and no calendar every row is not announced" do
      assert Enum.map(ReleaseDates.movie_rows(nil, []), & &1.date) == [nil, nil, nil]
    end

    test "the calendar's status and pursuit ride along with its date" do
      timeline = [
        movie_event("digital", %{air_date: ~D[2026-08-01], status: :under_pursuit, pursuit_id: "p1"})
      ]

      assert [_theaters, %{status: :under_pursuit, pursuit_id: "p1"}, _disc] =
               ReleaseDates.movie_rows(nil, timeline)
    end
  end

  describe "series_rows/1 — the next dated episodes" do
    test "keeps the calendar's order, drops landed episodes, caps at five" do
      timeline =
        [episode("landed", %{air_date: ~D[2026-07-27], status: :in_library})] ++
          for n <- 1..7,
              do: episode("e#{n}", %{episode_number: n, air_date: Date.add(~D[2026-08-03], n)})

      rows = ReleaseDates.series_rows(timeline)

      assert Enum.map(rows, & &1.id) == ["e1", "e2", "e3", "e4", "e5"]
      assert hd(rows).label == "S02E01"
    end

    test "an empty calendar is no rows" do
      assert ReleaseDates.series_rows([]) == []
    end
  end

  describe "date_text/1 and heading/1" do
    test "a date reads as TMDB posted it; none reads as not announced" do
      assert ReleaseDates.date_text(~D[2026-09-15]) == "Sep 15, 2026"
      assert ReleaseDates.date_text(nil) == "Not announced"
    end

    test "movies have release dates, series have upcoming episodes" do
      assert ReleaseDates.heading(:movie) == "Release dates"
      assert ReleaseDates.heading(:tv_series) == "Upcoming episodes"
    end
  end
end
