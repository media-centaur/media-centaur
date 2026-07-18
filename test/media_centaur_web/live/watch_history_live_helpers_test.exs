defmodule MediaCentaurWeb.WatchHistoryLiveHelpersTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.WatchHistoryLive

  # --- format_hours/1 ---

  describe "format_hours/1" do
    test "returns 0 hrs for zero seconds" do
      assert WatchHistoryLive.format_hours(0) == "0 hrs"
    end

    test "returns 1 hrs for exactly one hour" do
      assert WatchHistoryLive.format_hours(3600) == "1 hrs"
    end

    test "rounds to nearest hour" do
      # 7261 seconds = ~2.017 hours → rounds to 2
      assert WatchHistoryLive.format_hours(7261) == "2 hrs"
    end
  end

  # --- type_label/1 ---

  describe "type_label/1" do
    test "returns Movie for :movie" do
      assert WatchHistoryLive.type_label(:movie) == "Movie"
    end

    test "returns Episode for :episode" do
      assert WatchHistoryLive.type_label(:episode) == "Episode"
    end

    test "returns Video for :video_object" do
      assert WatchHistoryLive.type_label(:video_object) == "Video"
    end
  end

  # --- heatmap_class/1 ---

  # Fill intensity moved from inline style strings to CSS classes
  # (instant-navigation P2): the ~70-char color-mix string on every one of
  # 365 <rect>s tripled the heatmap's share of the navigation payload.
  describe "heatmap_class/1" do
    test "returns base class for 0 count" do
      assert WatchHistoryLive.heatmap_class(0) == "hm-fill-0"
    end

    test "returns faint class for 1 count" do
      assert WatchHistoryLive.heatmap_class(1) == "hm-fill-1"
    end

    test "returns medium class for 2-3 counts" do
      assert WatchHistoryLive.heatmap_class(2) == "hm-fill-2"
      assert WatchHistoryLive.heatmap_class(3) == "hm-fill-2"
    end

    test "returns full class for 4+ counts" do
      assert WatchHistoryLive.heatmap_class(4) == "hm-fill-3"
      assert WatchHistoryLive.heatmap_class(10) == "hm-fill-3"
    end
  end

  # --- heatmap_tooltip/1 ---

  describe "heatmap_tooltip/1" do
    test "returns date string only when count is 0" do
      assert WatchHistoryLive.heatmap_tooltip(%{count: 0, date: ~D[2026-01-01]}) ==
               "2026-01-01"
    end

    test "uses singular form for count of 1" do
      assert WatchHistoryLive.heatmap_tooltip(%{count: 1, date: ~D[2026-01-01]}) ==
               "2026-01-01 — 1 watched"
    end

    test "uses plural form for count > 1" do
      assert WatchHistoryLive.heatmap_tooltip(%{count: 3, date: ~D[2026-01-01]}) ==
               "2026-01-01 — 3 watched"
    end
  end

  # --- update_rewatch_counts/3 ---

  describe "update_rewatch_counts/3" do
    test "refetches only the requested entity types and leaves others untouched" do
      current = %{
        movie: %{"a" => 1, "b" => 2},
        episode: %{"x" => 3},
        video_object: %{"v" => 4}
      }

      called_with = :ets.new(:called, [:set, :public])

      fetch_fn = fn type ->
        :ets.insert(called_with, {type, true})
        %{type => 99}
      end

      result = WatchHistoryLive.update_rewatch_counts(current, [:movie], fetch_fn)

      assert result.movie == %{movie: 99}
      assert result.episode == %{"x" => 3}
      assert result.video_object == %{"v" => 4}
      assert :ets.lookup(called_with, :movie) == [{:movie, true}]
      assert :ets.lookup(called_with, :episode) == []
      assert :ets.lookup(called_with, :video_object) == []
    end

    test "refetches multiple types when given a set" do
      current = %{movie: %{}, episode: %{}, video_object: %{}}
      fetch_fn = fn type -> %{type => :fetched} end

      result =
        WatchHistoryLive.update_rewatch_counts(
          current,
          MapSet.new([:movie, :episode]),
          fetch_fn
        )

      assert result.movie == %{movie: :fetched}
      assert result.episode == %{episode: :fetched}
      assert result.video_object == %{}
    end

    test "returns the input unchanged for an empty type list" do
      current = %{movie: %{"a" => 1}, episode: %{}, video_object: %{}}

      result =
        WatchHistoryLive.update_rewatch_counts(current, [], fn _ ->
          flunk("fetch_fn should not be called")
        end)

      assert result == current
    end
  end
end
