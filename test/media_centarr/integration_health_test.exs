defmodule MediaCentarr.IntegrationHealthTest.OkVerifier do
  @behaviour MediaCentarr.IntegrationHealth.Verifier
  @impl true
  def run(_id), do: :ok
end

defmodule MediaCentarr.IntegrationHealthTest.RejectVerifier do
  @behaviour MediaCentarr.IntegrationHealth.Verifier
  @impl true
  def run(_id), do: {:error, :rejected}
end

defmodule MediaCentarr.IntegrationHealthTest do
  # `async: false` — IntegrationHealth registers under a global name and
  # owns a named ETS table, so concurrent tests would clobber each other.
  use ExUnit.Case, async: false

  alias MediaCentarr.Config
  alias MediaCentarr.IntegrationHealth
  alias MediaCentarr.IntegrationHealth.Status
  alias MediaCentarr.IntegrationHealthTest.{OkVerifier, RejectVerifier}

  setup do
    # The application doesn't start IntegrationHealth in :test (see
    # `cache_children/1`), so every test must start its own and tear
    # it down between tests so the named GenServer and ETS table reset.
    #
    # The verifier is injected via Application.put_env so tests don't
    # touch real network. Default to a stub that returns :ok unless a
    # specific test overrides it.
    previous_verifier =
      Application.get_env(:media_centarr, :integration_health_verifier)

    Application.put_env(:media_centarr, :integration_health_verifier, OkVerifier)

    # Snapshot + reset Config persistent_term directly (not via
    # Config.update, which writes to the Settings DB and would need a
    # DataCase sandbox). A prior test that set `tmdb_api_key` etc. via
    # its own write path can leak into persistent_term; null those keys
    # so IntegrationHealth's boot seed sees `configured? = false`
    # deterministically.
    original_config = :persistent_term.get({Config, :config})

    :persistent_term.put(
      {Config, :config},
      original_config
      |> Map.put(:tmdb_api_key, nil)
      |> Map.put(:prowlarr_api_key, nil)
      |> Map.put(:download_client_password, nil)
    )

    on_exit(fn ->
      :persistent_term.put({Config, :config}, original_config)

      if previous_verifier do
        Application.put_env(:media_centarr, :integration_health_verifier, previous_verifier)
      else
        Application.delete_env(:media_centarr, :integration_health_verifier)
      end
    end)

    :ok
  end

  describe "boot + seed" do
    test "every known integration is registered with configured? from Config" do
      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()

      for id <- IntegrationHealth.known() do
        status = IntegrationHealth.status(id)
        assert %Status{id: ^id, test_state: state} = status
        assert state in [:unknown, :pending, :ok]
        # No Config key is set in test mode → configured? always false.
        assert status.configured? == false
      end
    end

    test "all_statuses/0 returns every known integration" do
      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()

      statuses = IntegrationHealth.all_statuses()
      assert Enum.sort(Map.keys(statuses)) == Enum.sort(IntegrationHealth.known())
    end
  end

  describe "verify/1 — happy path" do
    test "transitions :unknown → :pending → :ok and broadcasts each step" do
      IntegrationHealth.subscribe()
      Application.put_env(:media_centarr, :integration_health_verifier, OkVerifier)

      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()

      assert :ok = IntegrationHealth.verify(:tmdb)

      # Pending intermediate (kick_test marks pending and broadcasts BEFORE
      # spawning the Task, so the order is deterministic).
      assert_receive {:integration_health_changed, %Status{id: :tmdb, test_state: :pending}},
                     1_000

      # Final result.
      assert_receive {:integration_health_changed,
                      %Status{id: :tmdb, test_state: :ok, last_tested_at: %DateTime{}}},
                     1_000

      assert IntegrationHealth.healthy?(:tmdb) == false
      # `healthy?/1` requires both configured? = true AND test_state = :ok.
      # In test mode the Config key isn't set so configured? stays false.
      # The transition assertion above is the public-API proof.
    end
  end

  describe "verify/1 — failure path" do
    test "transitions :unknown → :pending → :error and surfaces the reason" do
      IntegrationHealth.subscribe()
      Application.put_env(:media_centarr, :integration_health_verifier, RejectVerifier)

      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()

      assert :ok = IntegrationHealth.verify(:tmdb)

      assert_receive {:integration_health_changed, %Status{id: :tmdb, test_state: :pending}},
                     1_000

      assert_receive {:integration_health_changed,
                      %Status{id: :tmdb, test_state: :error, test_error: :rejected}},
                     1_000
    end
  end

  describe "verify/1 — only accepts known integration ids" do
    test "raises FunctionClauseError for unknown ids" do
      start_supervised!(IntegrationHealth)
      assert_raise FunctionClauseError, fn -> IntegrationHealth.verify(:made_up) end
    end
  end

  describe "subscribe/0" do
    test "subscriber receives broadcasts for any tracked integration" do
      IntegrationHealth.subscribe()
      Application.put_env(:media_centarr, :integration_health_verifier, OkVerifier)

      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()

      IntegrationHealth.verify(:prowlarr)

      assert_receive {:integration_health_changed, %Status{id: :prowlarr, test_state: :pending}},
                     1_000

      assert_receive {:integration_health_changed, %Status{id: :prowlarr, test_state: :ok}},
                     1_000
    end
  end

  describe "status/1 — read-after-write via ETS bypass" do
    test "status/1 reflects the latest write without going through the GenServer" do
      IntegrationHealth.subscribe()
      Application.put_env(:media_centarr, :integration_health_verifier, OkVerifier)
      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()

      IntegrationHealth.verify(:tmdb)

      assert_receive {:integration_health_changed, %Status{id: :tmdb, test_state: :ok}}, 1_000
      # Read immediately after the broadcast — should reflect the final state.
      assert %Status{test_state: :ok} = IntegrationHealth.status(:tmdb)
    end

    test "status/1 returns nil when the worker isn't running" do
      assert IntegrationHealth.status(:tmdb) == nil
    end
  end

  # The boot-seed step emits :unknown for every configured? = false
  # integration. Drain those so tests asserting on later broadcasts
  # don't false-positive on seed events.
  defp drain_initial_seed_broadcasts do
    receive do
      {:integration_health_changed, _} -> drain_initial_seed_broadcasts()
    after
      50 -> :ok
    end
  end
end
