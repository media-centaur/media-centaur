defmodule MediaCentarr.CacheTest do
  use ExUnit.Case, async: false

  alias MediaCentarr.Cache

  defmodule AlwaysRelevantFake do
    @behaviour MediaCentarr.Cache

    @impl true
    def subscribe do
      send(:cache_test_recorder, :subscribed)
      :ok
    end

    @impl true
    def refresh_cache do
      send(:cache_test_recorder, :refreshed)
      :ok
    end

    @impl true
    def relevant?(message) do
      send(:cache_test_recorder, {:relevant_checked, message})
      true
    end
  end

  defmodule NeverRelevantFake do
    @behaviour MediaCentarr.Cache

    @impl true
    def subscribe do
      send(:cache_test_recorder, :subscribed)
      :ok
    end

    @impl true
    def refresh_cache do
      send(:cache_test_recorder, :refreshed)
      :ok
    end

    @impl true
    def relevant?(message) do
      send(:cache_test_recorder, {:relevant_checked, message})
      false
    end
  end

  defmodule SelectiveFake do
    @behaviour MediaCentarr.Cache

    @impl true
    def subscribe do
      send(:cache_test_recorder, :subscribed)
      :ok
    end

    @impl true
    def refresh_cache do
      send(:cache_test_recorder, :refreshed)
      :ok
    end

    @impl true
    def relevant?({:setting_changed, "the_key", _} = message) do
      send(:cache_test_recorder, {:relevant_checked, message})
      true
    end

    def relevant?(message) do
      send(:cache_test_recorder, {:relevant_checked, message})
      false
    end
  end

  setup do
    Process.register(self(), :cache_test_recorder)
    :ok
  end

  describe "Worker boot" do
    test "calls subscribe and refresh_cache exactly once at init" do
      start_supervised!({Cache.Worker, context: AlwaysRelevantFake, name: :cache_worker_boot})

      assert_receive :subscribed
      assert_receive :refreshed
      refute_receive :subscribed, 50
      refute_receive :refreshed, 50
    end
  end

  describe "Worker handle_info" do
    test "asks the context whether each message is relevant" do
      worker =
        start_supervised!({Cache.Worker, context: AlwaysRelevantFake, name: :cache_worker_relevant})

      assert_receive :subscribed
      assert_receive :refreshed

      send(worker, :arbitrary_event)
      assert_receive {:relevant_checked, :arbitrary_event}
    end

    test "refreshes when relevant?/1 returns true" do
      worker =
        start_supervised!({Cache.Worker, context: AlwaysRelevantFake, name: :cache_worker_refresh})

      assert_receive :subscribed
      assert_receive :refreshed

      send(worker, :trigger)
      assert_receive {:relevant_checked, :trigger}
      assert_receive :refreshed
    end

    test "does not refresh when relevant?/1 returns false" do
      worker =
        start_supervised!({Cache.Worker, context: NeverRelevantFake, name: :cache_worker_skip})

      assert_receive :subscribed
      assert_receive :refreshed

      send(worker, :ignored)
      assert_receive {:relevant_checked, :ignored}
      refute_receive :refreshed, 50
    end

    test "selectively refreshes by message content" do
      worker =
        start_supervised!({Cache.Worker, context: SelectiveFake, name: :cache_worker_selective})

      assert_receive :subscribed
      assert_receive :refreshed

      send(worker, {:setting_changed, "wrong_key", "x"})
      assert_receive {:relevant_checked, {:setting_changed, "wrong_key", "x"}}
      refute_receive :refreshed, 50

      send(worker, {:setting_changed, "the_key", "x"})
      assert_receive {:relevant_checked, {:setting_changed, "the_key", "x"}}
      assert_receive :refreshed
    end

    test "survives unrelated messages without crashing" do
      worker =
        start_supervised!({Cache.Worker, context: NeverRelevantFake, name: :cache_worker_survive})

      assert_receive :subscribed
      assert_receive :refreshed

      send(worker, :anything)
      send(worker, {:tuple, :message})
      send(worker, %{map: :message})

      assert Process.alive?(worker)
    end
  end

  describe "child_spec/1" do
    test "derives child id from the context module" do
      spec = Cache.Worker.child_spec(context: AlwaysRelevantFake)
      assert spec.id == {Cache.Worker, AlwaysRelevantFake}
    end

    test "raises when context option is missing" do
      assert_raise KeyError, fn -> Cache.Worker.child_spec([]) end
    end
  end
end
