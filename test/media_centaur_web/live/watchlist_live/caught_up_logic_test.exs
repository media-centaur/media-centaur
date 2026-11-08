defmodule MediaCentaurWeb.WatchlistLive.CaughtUpLogicTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ReleaseTracking.Item, as: TrackingItem
  alias MediaCentaur.ReleaseTracking.Release
  alias MediaCentaurWeb.WatchlistLive.CaughtUpLogic

  @today ~D[2026-11-08]
  @ref {246_810, :tv_series}

  # A series payload as the store holds it: two seasons, the first of
  # eight episodes, the second of eight with five aired; TMDB's latest
  # aired is S02E05.
  defp payload do
    %{
      "id" => 246_810,
      "name" => "Sample Show",
      "seasons" => [
        %{"season_number" => 0, "episode_count" => 2, "air_date" => "2024-01-01"},
        %{"season_number" => 1, "episode_count" => 8, "air_date" => "2024-09-13"},
        %{"season_number" => 2, "episode_count" => 8, "air_date" => "2025-09-12"}
      ],
      "last_episode_to_air" => %{"season_number" => 2, "episode_number" => 5}
    }
  end

  # The stored season: eight episodes a week apart, the sixth onward ahead of today.
  defp season_payload(season \\ 2) do
    %{
      "season_number" => season,
      "episodes" =>
        for number <- 1..8 do
          %{
            "episode_number" => number,
            "name" => "Episode #{number}",
            "air_date" => @today |> Date.add((number - 6) * 7 + 1) |> Date.to_iso8601()
          }
        end
    }
  end

  defp tracking(releases \\ [], watermark \\ {0, 0}) do
    {season, episode} = watermark

    %TrackingItem{
      media_type: :tv_series,
      releases: releases,
      last_library_season: season,
      last_library_episode: episode
    }
  end

  defp open(point, tracking \\ tracking()) do
    "watchlist-row-x"
    |> CaughtUpLogic.open(@ref, payload(), point, tracking)
    |> CaughtUpLogic.season_loaded(2, season_payload())
  end

  describe "open/5" do
    test "the seasons newest first, specials left out, each with its year and size" do
      panel = open({2, 5})

      assert [%{number: 2, year: 2025, count: 8}, %{number: 1, year: 2024, count: 8}] = panel.seasons
      assert panel.latest == {2, 5}
      assert panel.id == "watchlist-row-x-caught-up-panel"
    end

    test "opens on the point's season with the point selected, the stored season's episodes dated" do
      panel = open({2, 5})

      assert panel.season == 2
      assert panel.selection == {2, 5}
      assert [%{number: 1, air_date: %Date{}, name: "Episode 1"} | _rest] = panel.episodes
      assert length(panel.episodes) == 8
    end

    test "with no point it opens on the latest aired season with nothing selected" do
      panel = open(nil)

      assert panel.season == 2
      assert panel.selection == :none
    end

    test "the episodes load until the page hands the panel the stored season" do
      panel = CaughtUpLogic.open("watchlist-row-x", @ref, payload(), {2, 5}, tracking())

      assert panel.episodes == :loading
    end
  end

  describe "choosing a season" do
    test "a chosen season loads, closes the list, and shows its episodes when they land" do
      panel = %{open({2, 5}) | menu_open?: true}

      loading = CaughtUpLogic.choose_season(panel, 1)
      assert loading.season == 1
      assert loading.episodes == :loading
      refute loading.menu_open?

      loaded = CaughtUpLogic.season_loaded(loading, 1, season_payload(1))
      assert length(loaded.episodes) == 8
      assert CaughtUpLogic.season_failed(loading, 1).episodes == :unavailable
    end

    test "a season that arrives after another was chosen is ignored" do
      panel = CaughtUpLogic.choose_season(open({2, 5}), 1)

      assert CaughtUpLogic.season_loaded(panel, 2, season_payload(2)).episodes == :loading
      assert CaughtUpLogic.season_failed(panel, 2).episodes == :loading
    end

    test "the season's label" do
      assert CaughtUpLogic.season_label(%{number: 2, year: 2025, count: 8}) ==
               "Season 2 · 2025 · 8 episodes"

      assert CaughtUpLogic.season_label(%{number: 1, year: nil, count: 1}) == "Season 1 · 1 episode"
    end
  end

  describe "selecting" do
    test "a chip selects it; Latest aired and Nothing yet are the two jumps" do
      panel = open({2, 5})

      assert CaughtUpLogic.pick(panel, {2, 3}).selection == {2, 3}

      assert panel |> CaughtUpLogic.pick({2, 3}) |> CaughtUpLogic.latest() |> Map.fetch!(:selection) ==
               {2, 5}

      assert CaughtUpLogic.nothing(panel).selection == :none
    end

    test "what Set point writes: the selection, a clear, or nothing when it is the point" do
      panel = open({2, 5})

      assert CaughtUpLogic.change(panel) == :unchanged
      assert panel |> CaughtUpLogic.pick({2, 3}) |> CaughtUpLogic.change() == {:set, {2, 3}}
      assert panel |> CaughtUpLogic.nothing() |> CaughtUpLogic.change() == :clear
      assert CaughtUpLogic.change(open(nil)) == :unchanged
      assert open(nil) |> CaughtUpLogic.pick({2, 1}) |> CaughtUpLogic.change() == {:set, {2, 1}}
    end

    test "the selection's words" do
      assert CaughtUpLogic.selection_words(open({2, 5})) == "S02E05"
      assert CaughtUpLogic.selection_words(open(nil)) == "Nothing yet"
    end
  end

  describe "chip/3" do
    test "the selected chip is the point; those at or before it, in the library or under the watermark are had; aired ones after are out; the rest unaired" do
      had_release = %Release{season_number: 2, episode_number: 7, in_library: true, air_date: @today}
      panel = open({2, 3}, tracking([had_release], {1, 8}))

      states = for episode <- panel.episodes, do: CaughtUpLogic.chip(panel, episode, @today)

      # E7 is in the library though TMDB dates it ahead: the library's word wins.
      assert states == [:had, :had, :point, :out, :out, :unaired, :had, :unaired]

      season_one =
        panel |> CaughtUpLogic.choose_season(1) |> CaughtUpLogic.season_loaded(1, season_payload(1))

      assert Enum.uniq(
               for(episode <- season_one.episodes, do: CaughtUpLogic.chip(season_one, episode, @today))
             ) == [:had]
    end

    test "an in-library episode that has aired is had even after the point" do
      had_release = %Release{season_number: 2, episode_number: 5, in_library: true, air_date: @today}
      panel = open({2, 3}, tracking([had_release]))

      assert CaughtUpLogic.chip(panel, Enum.at(panel.episodes, 4), @today) == :had
    end

    test "with nothing selected only the library and the watermark are had" do
      panel = open(nil)

      assert for(episode <- panel.episodes, do: CaughtUpLogic.chip(panel, episode, @today)) ==
               [:out, :out, :out, :out, :out, :unaired, :unaired, :unaired]
    end
  end
end
