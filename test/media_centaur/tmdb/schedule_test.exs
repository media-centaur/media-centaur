defmodule MediaCentaur.TMDB.ScheduleTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TMDB.Schedule

  @today ~D[2026-09-20]
  @fetched_at ~U[2026-09-20 08:00:00Z]
  @heartbeat ~U[2026-09-27 08:00:00Z]

  defp movie(overrides) do
    Map.merge(%{"id" => 1, "title" => "Sample Movie", "status" => "Released"}, overrides)
  end

  defp series(overrides) do
    Map.merge(
      %{"id" => 2, "name" => "Sample Show", "status" => "Returning Series", "seasons" => []},
      overrides
    )
  end

  defp us_dates(entries) do
    %{
      "release_dates" => %{
        "results" => [
          %{
            "iso_3166_1" => "US",
            "release_dates" =>
              Enum.map(entries, fn {type, date} ->
                %{"type" => type, "release_date" => "#{date}T00:00:00.000Z"}
              end)
          }
        ]
      }
    }
  end

  defp day_after_noon(date), do: DateTime.new!(Date.add(date, 1), ~T[12:00:00], "Etc/UTC")

  describe "plan/5 for a movie" do
    test "a movie past its digital release is settled and never due" do
      payload =
        movie(
          Map.merge(
            %{"release_date" => "2026-05-01"},
            us_dates([{3, ~D[2026-05-01]}, {4, ~D[2026-07-01]}])
          )
        )

      assert %{settled?: true, next_check_at: nil, next_event_on: nil} =
               Schedule.plan(:movie, payload, [], @today, @fetched_at)
    end

    test "a theatrical movie with a digital date ahead is due the day after it" do
      payload =
        movie(
          Map.merge(
            %{"release_date" => "2026-09-01"},
            us_dates([{3, ~D[2026-09-01]}, {4, ~D[2026-09-23]}])
          )
        )

      assert %{settled?: false, next_event_on: ~D[2026-09-23], next_check_at: next_check_at} =
               Schedule.plan(:movie, payload, [], @today, @fetched_at)

      assert next_check_at == day_after_noon(~D[2026-09-23])
    end

    test "an event more than a week away yields to the heartbeat" do
      payload =
        movie(Map.merge(%{"release_date" => "2026-12-25"}, us_dates([{3, ~D[2026-12-25]}])))

      assert %{settled?: false, next_event_on: ~D[2026-12-25], next_check_at: @heartbeat} =
               Schedule.plan(:movie, payload, [], @today, @fetched_at)
    end

    test "released more than 180 days ago with no typed home date is settled" do
      payload = movie(%{"release_date" => "2026-01-01"})

      assert %{settled?: true, next_check_at: nil} =
               Schedule.plan(:movie, payload, [], @today, @fetched_at)
    end

    test "released within 180 days with no typed home date keeps the heartbeat" do
      payload = movie(%{"release_date" => "2026-07-01"})

      assert %{settled?: false, next_event_on: nil, next_check_at: @heartbeat} =
               Schedule.plan(:movie, payload, [], @today, @fetched_at)
    end

    test "a canceled movie is settled" do
      payload = movie(%{"status" => "Canceled", "release_date" => "2027-03-01"})

      assert %{settled?: true, next_check_at: nil} =
               Schedule.plan(:movie, payload, [], @today, @fetched_at)
    end

    test "a movie with no dates at all keeps the heartbeat" do
      payload = movie(%{"status" => "Rumored", "release_date" => ""})

      assert %{settled?: false, next_event_on: nil, next_check_at: @heartbeat} =
               Schedule.plan(:movie, payload, [], @today, @fetched_at)
    end
  end

  describe "plan/5 for a series" do
    test "the next episode to air is the next event, due the day after" do
      payload =
        series(%{
          "next_episode_to_air" => %{
            "air_date" => "2026-09-23",
            "season_number" => 2,
            "episode_number" => 4
          }
        })

      assert %{settled?: false, next_event_on: ~D[2026-09-23], next_check_at: next_check_at} =
               Schedule.plan(:tv_series, payload, [], @today, @fetched_at)

      assert next_check_at == day_after_noon(~D[2026-09-23])
    end

    test "a returning series between seasons keeps the heartbeat" do
      payload =
        series(%{
          "next_episode_to_air" => nil,
          "seasons" => [%{"season_number" => 1, "air_date" => "2025-01-05"}]
        })

      assert %{settled?: false, next_event_on: nil, next_check_at: @heartbeat} =
               Schedule.plan(:tv_series, payload, [], @today, @fetched_at)
    end

    test "a future season air date is an event" do
      payload = series(%{"seasons" => [%{"season_number" => 2, "air_date" => "2026-09-25"}]})

      assert %{next_event_on: ~D[2026-09-25]} =
               Schedule.plan(:tv_series, payload, [], @today, @fetched_at)
    end

    test "an ended series with every episode aired is settled" do
      payload =
        series(%{
          "status" => "Ended",
          "seasons" => [%{"season_number" => 1, "air_date" => "2020-01-01"}]
        })

      season = %{
        "season_number" => 1,
        "episodes" => [%{"episode_number" => 1, "air_date" => "2020-01-01"}]
      }

      assert %{settled?: true, next_check_at: nil} =
               Schedule.plan(:tv_series, payload, [season], @today, @fetched_at)
    end

    test "an ended series whose stored season still has a future air date is not settled" do
      payload = series(%{"status" => "Ended"})

      season = %{
        "season_number" => 3,
        "episodes" => [%{"episode_number" => 1, "air_date" => "2026-09-22"}]
      }

      assert %{settled?: false, next_event_on: ~D[2026-09-22]} =
               Schedule.plan(:tv_series, payload, [season], @today, @fetched_at)
    end
  end

  describe "open_season?/3" do
    @title %{
      "seasons" => [%{"season_number" => 1}, %{"season_number" => 2}, %{"season_number" => 0}]
    }

    test "the latest season is open even when every episode has aired" do
      season = %{"season_number" => 2, "episodes" => [%{"air_date" => "2026-01-01"}]}
      assert Schedule.open_season?(season, @title, @today)
    end

    test "an earlier season is closed once every episode has aired" do
      season = %{"season_number" => 1, "episodes" => [%{"air_date" => "2026-01-01"}]}
      refute Schedule.open_season?(season, @title, @today)
    end

    test "an earlier season with an unannounced or future episode is open" do
      unannounced = %{"season_number" => 1, "episodes" => [%{"air_date" => nil}]}
      future = %{"season_number" => 1, "episodes" => [%{"air_date" => "2026-10-01"}]}
      assert Schedule.open_season?(unannounced, @title, @today)
      assert Schedule.open_season?(future, @title, @today)
    end
  end
end
