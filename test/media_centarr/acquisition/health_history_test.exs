defmodule MediaCentarr.Acquisition.HealthHistoryTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.Health
  alias MediaCentarr.Acquisition.HealthHistory
  alias MediaCentarr.Acquisition.QueueItem

  @mb 1024 * 1024
  @gb 1024 * @mb

  defp item(opts) do
    %QueueItem{
      id: Keyword.fetch!(opts, :id),
      title: Keyword.get(opts, :title, "x"),
      state: Keyword.get(opts, :state, :downloading),
      status: Keyword.get(opts, :status, "downloading"),
      size: Keyword.get(opts, :size, 100 * @gb),
      size_left: Keyword.get(opts, :size_left, 50 * @gb)
    }
  end

  describe "update/3 — sample bookkeeping" do
    test "empty history + one item appends a sample at `now` and attaches health" do
      {history, [it]} = HealthHistory.update(%{}, [item(id: "a")], 1_000)

      assert history == %{"a" => [{1_000, 50 * @gb}]}
      # Single fresh sample → warming_up
      assert it.health == :warming_up
    end

    test "second poll appends a newer sample at the head" do
      {history1, _} = HealthHistory.update(%{}, [item(id: "a", size_left: 50 * @gb)], 1_000)

      {history2, _} =
        HealthHistory.update(history1, [item(id: "a", size_left: 49 * @gb)], 2_000)

      assert history2 == %{"a" => [{2_000, 49 * @gb}, {1_000, 50 * @gb}]}
    end

    test "missing items are dropped from history" do
      {history1, _} = HealthHistory.update(%{}, [item(id: "a"), item(id: "b")], 1_000)
      assert Map.has_key?(history1, "a")
      assert Map.has_key?(history1, "b")

      {history2, _} = HealthHistory.update(history1, [item(id: "a")], 2_000)
      assert Map.has_key?(history2, "a")
      refute Map.has_key?(history2, "b")
    end

    test "backwards motion (size_left increased) resets history for that id" do
      # Recheck or file replacement made size_left larger. We can't
      # reason about throughput across that boundary — start over.
      {history1, _} = HealthHistory.update(%{}, [item(id: "a", size_left: 30 * @gb)], 1_000)

      {history1, _} =
        HealthHistory.update(history1, [item(id: "a", size_left: 25 * @gb)], 2_000)

      # Now size_left jumps back up to 40 GB — recheck found missing data
      {history2, [it]} =
        HealthHistory.update(history1, [item(id: "a", size_left: 40 * @gb)], 3_000)

      assert history2 == %{"a" => [{3_000, 40 * @gb}]}
      # Reset history → warm-up for this item
      assert it.health == :warming_up
    end

    test "size_left = nil → no sample appended; existing history preserved" do
      {history1, _} = HealthHistory.update(%{}, [item(id: "a", size_left: 30 * @gb)], 1_000)

      {history2, [it]} =
        HealthHistory.update(history1, [item(id: "a", size_left: nil)], 2_000)

      assert history2 == history1
      assert it.health == nil
    end

    test "samples older than the health window are truncated" do
      max_us = Health.max_window_us()
      now = max_us * 5

      # Build history with samples spanning 2× the window
      old_samples = [
        {now - max_us - 1_000_000, 50 * @gb},
        {now - max_us - 500_000, 49 * @gb},
        {now - 100_000_000, 40 * @gb}
      ]

      history0 = %{"a" => old_samples}

      {history1, _} =
        HealthHistory.update(history0, [item(id: "a", size_left: 39 * @gb)], now)

      samples = history1["a"]

      # All samples should be within the window from `now`
      for {ts, _} <- samples do
        assert now - ts <= max_us
      end

      # The two stale samples are gone
      assert length(samples) <= 2
    end
  end

  describe "update/3 — health attachment" do
    test "attaches :healthy when throughput is strong over the full window" do
      max_us = Health.max_window_us()
      now = 10 * max_us

      history0 = %{
        "a" => [
          {now - 1_000_000, 30 * @gb + 100 * @mb},
          {now - max_us, 30 * @gb + 2 * @gb}
        ]
      }

      {_, [it]} = HealthHistory.update(history0, [item(id: "a", size_left: 30 * @gb)], now)
      assert it.health == :healthy
    end

    test "attaches :soft_stall when delta over the hour is < 100 MB" do
      max_us = Health.max_window_us()
      now = 10 * max_us

      history0 = %{
        "a" => [
          {now - 1_000_000, 30 * @gb},
          {now - max_us, 30 * @gb + 50 * @mb}
        ]
      }

      {_, [it]} = HealthHistory.update(history0, [item(id: "a", size_left: 30 * @gb)], now)
      assert it.health == :soft_stall
    end

    test "attaches nil for :completed items (they shouldn't appear, but defence in depth)" do
      {_, [it]} = HealthHistory.update(%{}, [item(id: "a", state: :completed)], 1_000)
      assert it.health == nil
    end
  end
end
