defmodule MediaCentarrWeb.WatchHistoryLiveHelpersTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.WatchHistoryLive

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

  # --- heatmap_fill/1 ---

  describe "heatmap_fill/1" do
    test "returns base fill for 0 count" do
      assert WatchHistoryLive.heatmap_fill(0) == "fill: var(--color-base-300)"
    end

    test "returns faint success fill for 1 count" do
      assert WatchHistoryLive.heatmap_fill(1) ==
               "fill: color-mix(in oklch, var(--color-success) 30%, transparent)"
    end

    test "returns medium success fill for 2-3 counts" do
      fill = "fill: color-mix(in oklch, var(--color-success) 60%, transparent)"
      assert WatchHistoryLive.heatmap_fill(2) == fill
      assert WatchHistoryLive.heatmap_fill(3) == fill
    end

    test "returns full success fill for 4+ counts" do
      assert WatchHistoryLive.heatmap_fill(4) == "fill: var(--color-success)"
      assert WatchHistoryLive.heatmap_fill(10) == "fill: var(--color-success)"
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
