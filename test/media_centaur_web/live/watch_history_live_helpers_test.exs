defmodule MediaCentaurWeb.WatchHistoryLiveHelpersTest do
  use MediaCentaur.Case, async: true

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

  describe "empty_reason/1" do
    defp state(overrides) do
      Map.merge(
        %{events: [], filter_type: nil, filter_search: "", filter_date: nil},
        Map.new(overrides)
      )
    end

    test "rows present means no empty state at all" do
      assert WatchHistoryLive.empty_reason(state(events: [:a])) == :none
    end

    test "no rows and no filter is a history that has never been written to" do
      assert WatchHistoryLive.empty_reason(state([])) == :no_history
    end

    test "no rows with any filter active is the filter's doing, not an empty history" do
      assert WatchHistoryLive.empty_reason(state(filter_type: :movie)) == :no_matches
      assert WatchHistoryLive.empty_reason(state(filter_search: "abc")) == :no_matches
      assert WatchHistoryLive.empty_reason(state(filter_date: ~D[2026-01-01])) == :no_matches
    end
  end
end
