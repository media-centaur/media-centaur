defmodule MediaCentaur.CacheTest do
  use ExUnit.Case, async: false

  alias MediaCentaur.Cache

  defmodule AlwaysRelevantFake do
    @behaviour MediaCentaur.Cache

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
    @behaviour MediaCentaur.Cache

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

  defmodule PartialRefreshFake do
    @behaviour MediaCentaur.Cache

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

    @impl true
    def handle_message(message) do
      send(:cache_test_recorder, {:partial_refresh, message})
      :ok
    end
  end

  defmodule SelectiveFake do
    @behaviour MediaCentaur.Cache

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

    test "routes to handle_message/1 when the context implements it (partial-refresh path)" do
      worker =
        start_supervised!({Cache.Worker, context: PartialRefreshFake, name: :cache_worker_partial})

      assert_receive :subscribed
      assert_receive :refreshed

      send(worker, {:row_updated, "uuid-1"})

      assert_receive {:relevant_checked, {:row_updated, "uuid-1"}}
      assert_receive {:partial_refresh, {:row_updated, "uuid-1"}}
      refute_receive :refreshed, 50
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

  defmodule BlockingPrimeFake do
    @behaviour MediaCentaur.Cache

    @impl true
    def subscribe do
      send(:cache_test_recorder, :subscribed)
      :ok
    end

    @impl true
    def refresh_cache do
      send(:cache_test_recorder, :refresh_started)

      receive do
        :unblock -> :ok
      end

      send(:cache_test_recorder, :refreshed)
      :ok
    end

    @impl true
    def relevant?(message) do
      send(:cache_test_recorder, {:relevant_checked, message})
      true
    end
  end

  describe "Worker refresh_interval_ms" do
    test "refreshes periodically without any PubSub message" do
      start_supervised!(
        {Cache.Worker,
         context: AlwaysRelevantFake, refresh_interval_ms: 30, name: :cache_worker_interval}
      )

      # boot prime
      assert_receive :refreshed
      # two consecutive interval ticks
      assert_receive :refreshed, 500
      assert_receive :refreshed, 500
    end

    test "interval ticks do not go through relevant?/1" do
      start_supervised!(
        {Cache.Worker,
         context: AlwaysRelevantFake, refresh_interval_ms: 30, name: :cache_worker_interval_filter}
      )

      assert_receive :refreshed
      assert_receive :refreshed, 500
      refute_received {:relevant_checked, _}
    end

    test "without the option no interval refresh ever fires" do
      start_supervised!({Cache.Worker, context: AlwaysRelevantFake, name: :cache_worker_no_interval})

      assert_receive :refreshed
      refute_receive :refreshed, 100
    end
  end

  describe "Worker prime: :async" do
    test "init returns before the prime completes" do
      worker =
        start_supervised!(
          {Cache.Worker, context: BlockingPrimeFake, prime: :async, name: :cache_worker_async_prime}
        )

      # start_supervised! returned even though refresh_cache is still blocked —
      # the prime runs after init, not inside it.
      assert Process.alive?(worker)
      assert_receive :subscribed
      assert_receive :refresh_started
      refute_received :refreshed

      send(worker, :unblock)
      assert_receive :refreshed
    end

    test "messages arriving during the prime are processed afterwards, not lost" do
      worker =
        start_supervised!(
          {Cache.Worker,
           context: BlockingPrimeFake, prime: :async, name: :cache_worker_async_prime_queue}
        )

      assert_receive :refresh_started

      # Arrives while the prime is still blocked; must queue behind it.
      send(worker, :queued_event)
      send(worker, :unblock)

      assert_receive :refreshed
      assert_receive {:relevant_checked, :queued_event}
      # The queued relevant event triggers its own refresh (which blocks
      # again in this fake — unblock it so the worker exits cleanly).
      assert_receive :refresh_started
      send(worker, :unblock)
      assert_receive :refreshed
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
