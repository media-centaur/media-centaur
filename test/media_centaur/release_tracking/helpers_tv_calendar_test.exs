defmodule MediaCentaur.ReleaseTracking.HelpersTvCalendarTest do
  # The TV calendar fetch hits the TMDB client, so this lives apart from
  # the pure `HelpersTest`.
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmdbStubs

  alias MediaCentaur.ReleaseTracking.Helpers

  setup do
    setup_tmdb_client()
    :ok
  end

  describe "fetch_tv_releases/5 — season sizes" do
    # The calendar holds only the episodes after the library's last one,
    # so it cannot say how big a season is. The fetch already has what
    # can: every season's `episode_count` from the show details, and the
    # air date of every episode in the seasons it walks. A fetched
    # season is sized by what has aired; the rest by `episode_count`.
    test "sizes a fetched season by aired episodes and the others by episode_count" do
      today = ~D[2026-09-17]

      show = %{
        "id" => 424_242,
        "name" => "Sample Show",
        "number_of_seasons" => 2,
        "next_episode_to_air" => %{
          "air_date" => "2026-09-24",
          "season_number" => 2,
          "episode_number" => 11
        },
        "seasons" => [
          %{"season_number" => 0, "episode_count" => 3},
          %{"season_number" => 1, "episode_count" => 22},
          %{"season_number" => 2, "episode_count" => 13}
        ]
      }

      # Episodes 1..10 aired on or before today (episode 10 today), 11..13 after.
      season_two = %{
        "season_number" => 2,
        "episodes" =>
          Enum.map(1..13, fn number ->
            %{
              "episode_number" => number,
              "name" => "Episode #{number}",
              "air_date" => Date.to_iso8601(Date.add(today, (number - 10) * 7))
            }
          end)
      }

      stub_get_tv_with_seasons(424_242, show, %{2 => season_two})

      {releases, season_sizes} = Helpers.fetch_tv_releases(424_242, 2, 10, show, today: today)

      assert season_sizes == %{"1" => 22, "2" => 10}
      assert Enum.map(releases, & &1.episode_number) == [11, 12, 13]
    end
  end
end
