defmodule MediaCentarr.Acquisition.HealthTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.Health
  alias MediaCentarr.Acquisition.QueueItem

  # All histories are expressed as `{age_seconds, size_left_bytes}` tuples
  # newest-first, then converted to monotonic-time form by `mk_history/2`
  # against a chosen `now`. This keeps the test cases readable.

  @now 1_000_000_000_000

  @mb 1024 * 1024
  @gb 1024 * @mb

  defp mk_history(now, samples) do
    for {age_s, size_left} <- samples do
      {now - age_s * 1_000_000, size_left}
    end
  end

  defp downloading(opts \\ []) do
    %QueueItem{
      id: Keyword.get(opts, :id, "h"),
      title: Keyword.get(opts, :title, "x"),
      state: :downloading,
      status: Keyword.get(opts, :status, "downloading"),
      size_left: Keyword.get(opts, :size_left, 50 * @gb)
    }
  end

  describe "classify/3 — non-downloading states" do
    test "size_left is nil → nil (no signal from driver)" do
      item = %{downloading() | size_left: nil}
      assert Health.classify(item, [], @now) == nil
    end

    test ":stalled (hard-stall from client) → nil — keeps existing UI" do
      item = %{downloading() | state: :stalled}
      assert Health.classify(item, mk_history(@now, [{0, 50 * @gb}]), @now) == nil
    end

    test ":paused → nil" do
      item = %{downloading() | state: :paused}
      assert Health.classify(item, mk_history(@now, [{0, 50 * @gb}]), @now) == nil
    end

    test ":error → nil" do
      item = %{downloading() | state: :error}
      assert Health.classify(item, mk_history(@now, [{0, 50 * @gb}]), @now) == nil
    end

    test ":completed → nil — though monitor filters these out before classification anyway" do
      item = %{downloading() | state: :completed}
      assert Health.classify(item, [], @now) == nil
    end

    test ":other → nil" do
      item = %{downloading() | state: :other}
      assert Health.classify(item, [], @now) == nil
    end
  end

  describe "classify/3 — :queued items" do
    test ":queued < 30 min → nil" do
      item = %{downloading() | state: :queued}
      history = mk_history(@now, [{0, 50 * @gb}, {29 * 60, 50 * @gb}])
      assert Health.classify(item, history, @now) == nil
    end

    test ":queued ≥ 30 min → :queued_long" do
      item = %{downloading() | state: :queued}
      history = mk_history(@now, [{0, 50 * @gb}, {30 * 60, 50 * @gb}])
      assert Health.classify(item, history, @now) == :queued_long
    end

    test ":queued with empty history → nil (warm-up wins; we just saw it)" do
      item = %{downloading() | state: :queued}
      assert Health.classify(item, [], @now) == nil
    end
  end

  describe "classify/3 — metadata fetch (qBit metaDL)" do
    test "metaDL < 5 min → :warming_up" do
      item = %{downloading() | status: "metaDL"}
      history = mk_history(@now, [{0, 50 * @gb}, {4 * 60, 50 * @gb}])
      assert Health.classify(item, history, @now) == :warming_up
    end

    test "metaDL ≥ 5 min → :meta_stuck" do
      item = %{downloading() | status: "metaDL"}
      history = mk_history(@now, [{0, 50 * @gb}, {5 * 60, 50 * @gb}])
      assert Health.classify(item, history, @now) == :meta_stuck
    end

    test "metaDL with empty history → :warming_up (just appeared)" do
      item = %{downloading() | status: "metaDL"}
      assert Health.classify(item, [], @now) == :warming_up
    end
  end

  describe "classify/3 — :downloading throughput cases" do
    test "empty history → :warming_up" do
      assert Health.classify(downloading(), [], @now) == :warming_up
    end

    test "history < 2 min old → :warming_up" do
      history = mk_history(@now, [{0, 50 * @gb}, {90, 50 * @gb + 100 * @mb}])
      assert Health.classify(downloading(), history, @now) == :warming_up
    end

    test "spans 1 hr, 0 bytes in last 10 min → :frozen" do
      # 10-min delta is 0 (size_left identical between newest sample and the
      # sample 10 min ago). Older history has progress so we know warm-up
      # has elapsed.
      now_left = 30 * @gb

      history =
        mk_history(@now, [
          {0, now_left},
          {10 * 60, now_left},
          {3600, now_left + 500 * @mb}
        ])

      assert Health.classify(downloading(size_left: now_left), history, @now) == :frozen
    end

    test "spans 1 hr, 50 MB downloaded in last hour → :soft_stall" do
      now_left = 30 * @gb

      history =
        mk_history(@now, [
          {0, now_left},
          {600, now_left + 8 * @mb},
          {3600, now_left + 50 * @mb}
        ])

      assert Health.classify(downloading(size_left: now_left), history, @now) == :soft_stall
    end

    test "spans 1 hr, 300 MB downloaded in last hour → :slow" do
      now_left = 30 * @gb

      history =
        mk_history(@now, [
          {0, now_left},
          {600, now_left + 50 * @mb},
          {3600, now_left + 300 * @mb}
        ])

      assert Health.classify(downloading(size_left: now_left), history, @now) == :slow
    end

    test "spans 1 hr, 2 GB downloaded in last hour → :healthy" do
      now_left = 30 * @gb

      history =
        mk_history(@now, [
          {0, now_left},
          {600, now_left + 350 * @mb},
          {3600, now_left + 2 * @gb}
        ])

      assert Health.classify(downloading(size_left: now_left), history, @now) == :healthy
    end

    test "30 min old, delta_10min = 0 → :frozen (10-min check fires before missing-window)" do
      now_left = 30 * @gb

      history =
        mk_history(@now, [
          {0, now_left},
          {10 * 60, now_left},
          {30 * 60, now_left + 500 * @mb}
        ])

      assert Health.classify(downloading(size_left: now_left), history, @now) == :frozen
    end

    test "30 min old, delta_10min > 0, no full-hour sample → :warming_up" do
      # We don't have data going back a full hour, so we can't classify
      # against 1-hr thresholds. The 10-min check passes (some progress).
      # Result: still :warming_up — withhold judgement until we have a
      # full window.
      now_left = 30 * @gb

      history =
        mk_history(@now, [
          {0, now_left},
          {10 * 60, now_left + 80 * @mb},
          {30 * 60, now_left + 200 * @mb}
        ])

      assert Health.classify(downloading(size_left: now_left), history, @now) == :warming_up
    end

    test "boundary: delta_1hr exactly 100 MB → :soft_stall (< 100 MB rule, so 100 MB exactly is not soft-stall)" do
      # 100 MB is the threshold; soft_stall is `< 100 MB`. So exactly
      # 100 MB falls into :slow.
      now_left = 30 * @gb

      history =
        mk_history(@now, [
          {0, now_left},
          {600, now_left + 16 * @mb},
          {3600, now_left + 100 * @mb}
        ])

      assert Health.classify(downloading(size_left: now_left), history, @now) == :slow
    end

    test "boundary: delta_1hr exactly 500 MB → :healthy" do
      now_left = 30 * @gb

      history =
        mk_history(@now, [
          {0, now_left},
          {600, now_left + 80 * @mb},
          {3600, now_left + 500 * @mb}
        ])

      assert Health.classify(downloading(size_left: now_left), history, @now) == :healthy
    end
  end

  describe "label/1" do
    test "every status has a non-empty label" do
      for status <- [
            :healthy,
            :warming_up,
            :slow,
            :soft_stall,
            :frozen,
            :meta_stuck,
            :queued_long
          ] do
        label = Health.label(status)
        assert is_binary(label)
        assert String.length(label) > 0
      end
    end

    test "soft_stall label calls out the 100 MB / 1 hr threshold" do
      assert Health.label(:soft_stall) =~ "100"
      assert Health.label(:soft_stall) =~ "hour"
    end

    test "frozen label calls out the 10-minute window" do
      assert Health.label(:frozen) =~ "10"
    end

    test "meta_stuck label mentions metadata or magnet" do
      label = Health.label(:meta_stuck)
      assert label =~ "metadata" or label =~ "magnet"
    end

    test "queued_long label mentions 30 minutes" do
      assert Health.label(:queued_long) =~ "30"
    end
  end

  describe "short_label/1" do
    test "every status has a short non-empty label" do
      for status <- [
            :healthy,
            :warming_up,
            :slow,
            :soft_stall,
            :frozen,
            :meta_stuck,
            :queued_long
          ] do
        short = Health.short_label(status)
        assert is_binary(short)
        assert String.length(short) > 0
      end
    end
  end

  describe "badge_variant/1" do
    test "soft_stall, frozen, meta_stuck → warning" do
      assert Health.badge_variant(:soft_stall) == "warning"
      assert Health.badge_variant(:frozen) == "warning"
      assert Health.badge_variant(:meta_stuck) == "warning"
    end

    test "slow, queued_long → ghost" do
      assert Health.badge_variant(:slow) == "ghost"
      assert Health.badge_variant(:queued_long) == "ghost"
    end

    test "healthy, warming_up → nil (no extra chrome)" do
      assert Health.badge_variant(:healthy) == nil
      assert Health.badge_variant(:warming_up) == nil
    end
  end

  describe "degraded?/1" do
    test "true for :soft_stall, :frozen, :meta_stuck" do
      assert Health.degraded?(:soft_stall)
      assert Health.degraded?(:frozen)
      assert Health.degraded?(:meta_stuck)
    end

    test "false for everything else" do
      refute Health.degraded?(:healthy)
      refute Health.degraded?(:warming_up)
      refute Health.degraded?(:slow)
      refute Health.degraded?(:queued_long)
      refute Health.degraded?(nil)
    end
  end

  describe "slow?/1" do
    test "true only for :slow" do
      assert Health.slow?(:slow)
    end

    test "false for everything else, including degraded states" do
      refute Health.slow?(:healthy)
      refute Health.slow?(:warming_up)
      refute Health.slow?(:soft_stall)
      refute Health.slow?(:frozen)
      refute Health.slow?(:meta_stuck)
      refute Health.slow?(:queued_long)
      refute Health.slow?(nil)
    end
  end
end
