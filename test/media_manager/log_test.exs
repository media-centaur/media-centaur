defmodule MediaManager.LogTest do
  use MediaManager.DataCase, async: false

  alias MediaManager.Log

  setup do
    # Start with a clean state
    :persistent_term.put({Log, :enabled}, MapSet.new())

    on_exit(fn ->
      :persistent_term.put({Log, :enabled}, MapSet.new())
    end)

    :ok
  end

  describe "state management" do
    test "none/0 sets empty enabled set" do
      Log.enable(:pipeline)
      Log.none()
      assert Log.enabled() == []
    end

    test "all/0 enables every component" do
      Log.all()
      assert Enum.sort(Log.enabled()) == Enum.sort(Log.components())
    end

    test "enable/1 adds a single component" do
      Log.enable(:pipeline)
      assert :pipeline in Log.enabled()
    end

    test "disable/1 removes a single component" do
      Log.all()
      Log.disable(:pipeline)
      refute :pipeline in Log.enabled()
    end

    test "solo/1 enables only the given component" do
      Log.all()
      Log.solo(:tmdb)
      assert Log.enabled() == [:tmdb]
    end

    test "mute/1 enables all except the given component" do
      Log.mute(:playback)
      enabled = Log.enabled()
      refute :playback in enabled
      assert length(enabled) == length(Log.components()) - 1
    end

    test "status/0 returns enabled and all components" do
      Log.enable(:watcher)
      {enabled, all} = Log.status()
      assert :watcher in enabled
      assert all == Log.components()
    end

    test "enabled_set/0 returns a MapSet" do
      Log.enable(:channel)
      set = Log.enabled_set()
      assert MapSet.member?(set, :channel)
    end
  end

  describe "persistence" do
    test "state persists to database and restores on init" do
      Log.enable(:pipeline)
      Log.enable(:tmdb)

      # Simulate restart by clearing persistent_term and re-initializing
      :persistent_term.put({Log, :enabled}, MapSet.new())
      assert Log.enabled() == []

      Log.init()
      assert :pipeline in Log.enabled()
      assert :tmdb in Log.enabled()
    end
  end

  describe "filter/2" do
    test "passes info logs with enabled component" do
      Log.enable(:pipeline)

      event = %{level: :info, meta: %{component: :pipeline}}
      assert Log.filter(event, []) == :ignore
    end

    test "stops info logs with disabled component" do
      Log.none()

      event = %{level: :info, meta: %{component: :pipeline}}
      assert Log.filter(event, []) == :stop
    end

    test "passes non-component info logs" do
      event = %{level: :info, meta: %{}}
      assert Log.filter(event, []) == :ignore
    end

    test "passes warning logs regardless of component" do
      event = %{level: :warning, meta: %{component: :pipeline}}
      assert Log.filter(event, []) == :ignore
    end

    test "passes error logs" do
      event = %{level: :error, meta: %{}}
      assert Log.filter(event, []) == :ignore
    end
  end
end
