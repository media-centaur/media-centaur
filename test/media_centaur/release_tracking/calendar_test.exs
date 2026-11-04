defmodule MediaCentaur.ReleaseTracking.CalendarTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ReleaseTracking.{Calendar, Item, Release}

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

  test "tv_releases/3 lists the episodes after the have-point" do
    assert Enum.map(Calendar.tv_releases(show(), [season_two()], {2, 10}), & &1.episode_number) ==
             [11, 12, 13]

    assert Enum.map(Calendar.tv_releases(show(), [season_two()], {0, 0}), & &1.episode_number) ==
             Enum.to_list(1..13)
  end

  test "tv_releases/3 falls back to next_episode_to_air when no stored season yields an episode" do
    assert [%{season_number: 2, episode_number: 11, air_date: ~D[2026-09-24]}] =
             Calendar.tv_releases(show(), [], {2, 10})
  end

  describe "read/3 — what a followed series' calendar says" do
    defp release(season, episode, air_date, in_library \\ false),
      do: %Release{
        season_number: season,
        episode_number: episode,
        air_date: air_date,
        in_library: in_library
      }

    defp followed(releases, watermark \\ {0, 0}) do
      {season, episode} = watermark

      %Item{
        media_type: :tv_series,
        last_library_season: season,
        last_library_episode: episode,
        releases: releases
      }
    end

    test "out is the aired releases not had, oldest first; next the nearest date ahead" do
      item =
        followed([
          release(2, 3, ~D[2026-09-17]),
          release(2, 2, ~D[2026-09-10]),
          release(2, 1, ~D[2026-09-03], true),
          release(2, 4, ~D[2026-09-24]),
          release(2, 5, ~D[2026-10-01])
        ])

      assert %{out: out, next: ~D[2026-09-24]} = Calendar.read(item, nil, @today)
      assert Enum.map(out, & &1.episode_number) == [2, 3]
    end

    test "the caught-up point and the library watermark both count as had" do
      releases = [
        release(2, 2, ~D[2026-09-10]),
        release(2, 3, ~D[2026-09-17]),
        release(2, 4, ~D[2026-09-24])
      ]

      assert %{out: [%{episode_number: 3}]} = Calendar.read(followed(releases), {2, 2}, @today)
      assert %{out: [%{episode_number: 3}]} = Calendar.read(followed(releases, {2, 2}), nil, @today)
      assert %{out: []} = Calendar.read(followed(releases), {2, 3}, @today)
    end

    test "nothing dated ahead reads next nil; an undated row is neither out nor next" do
      assert Calendar.read(
               followed([release(1, 1, nil), release(1, 2, ~D[2026-09-01], true)]),
               nil,
               @today
             ) ==
               %{out: [], next: nil}
    end
  end

  describe "latest_aired/1" do
    test "reads TMDB's last_episode_to_air as season and episode numbers" do
      payload = %{"last_episode_to_air" => %{"season_number" => 3, "episode_number" => 12}}
      assert Calendar.latest_aired(payload) == {3, 12}
    end

    test "nil when the payload has none, or names a special" do
      assert Calendar.latest_aired(%{"last_episode_to_air" => nil}) == nil
      assert Calendar.latest_aired(%{}) == nil

      assert Calendar.latest_aired(%{
               "last_episode_to_air" => %{"season_number" => 0, "episode_number" => 1}
             }) == nil
    end
  end

  test "season_sizes/3 sizes a stored season by aired episodes and the rest by episode_count, specials excluded" do
    assert Calendar.season_sizes(show(), [season_two()], @today) == %{"1" => 22, "2" => 10}
  end

  test "seasons_wanted/2 is the have-point's season and the next season to air" do
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
