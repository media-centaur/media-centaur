defmodule MediaCentaur.ReleaseTracking.CalendarTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ReleaseTracking.Calendar

  @today ~D[2026-09-17]

  defp show do
    %{
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
  end

  # Episodes 1..10 aired on or before today (episode 10 today), 11..13 after.
  defp season_two do
    %{
      "season_number" => 2,
      "episodes" =>
        Enum.map(1..13, fn number ->
          %{
            "episode_number" => number,
            "name" => "Episode #{number}",
            "air_date" => Date.to_iso8601(Date.add(@today, (number - 10) * 7))
          }
        end)
    }
  end

  test "tv_releases/4 lists the episodes after the library's last one" do
    assert Enum.map(Calendar.tv_releases(show(), [season_two()], 2, 10), & &1.episode_number) ==
             [11, 12, 13]
  end

  test "tv_releases/4 falls back to next_episode_to_air when no stored season yields an episode" do
    assert [%{season_number: 2, episode_number: 11, air_date: ~D[2026-09-24]}] =
             Calendar.tv_releases(show(), [], 2, 10)
  end

  test "season_sizes/3 sizes a stored season by aired episodes and the rest by episode_count, specials excluded" do
    assert Calendar.season_sizes(show(), [season_two()], @today) == %{"1" => 22, "2" => 10}
  end

  test "seasons_wanted/2 is the library's last season and the next season to air" do
    assert Calendar.seasons_wanted(show(), 1) == [1, 2]
    assert Calendar.seasons_wanted(show(), 0) == [1, 2]
    assert Calendar.seasons_wanted(show(), 2) == [2]
  end

  test "movie_releases/1 carries the film's own id as the part" do
    movie = %{"id" => 550, "title" => "Sample Movie", "release_date" => "2026-10-01"}

    assert [
             %{
               part_tmdb_id: 550,
               release_type: "theatrical",
               air_date: ~D[2026-10-01],
               season_number: nil,
               episode_number: nil
             }
           ] = Calendar.movie_releases(movie)
  end
end
