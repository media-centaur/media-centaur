defmodule MediaCentaur.IntegrationHealthTest.OkVerifier do
  @behaviour MediaCentaur.IntegrationHealth.Verifier
  @impl true
  def run(_id), do: :ok
end

defmodule MediaCentaur.IntegrationHealthTest.RejectVerifier do
  @behaviour MediaCentaur.IntegrationHealth.Verifier
  @impl true
  def run(_id), do: {:error, :rejected}
end

defmodule MediaCentaur.IntegrationHealthTest do
  # `async: false` — IntegrationHealth registers under a global name and
  # owns a named ETS table, so concurrent tests would clobber each other.
  # DataCase: an explicit verify persists its result through Capabilities,
  # and the shared sandbox (async: false) lets the GenServer write it.
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Settings.Config
  alias MediaCentaur.IntegrationHealth
  alias MediaCentaur.IntegrationHealth.Status
  alias MediaCentaur.IntegrationHealthTest.{OkVerifier, RejectVerifier}

  setup do
    # The application doesn't start IntegrationHealth in :test (see
    # `cache_children/1`), so every test must start its own and tear
    # it down between tests so the named GenServer and ETS table reset.
    #
    # The verifier is injected via Application.put_env so tests don't
    # touch real network. Default to a stub that returns :ok unless a
    # specific test overrides it.
    Application.put_env(:media_centaur, :integration_health_verifier, OkVerifier)

    :ok
  end

  describe "boot + seed" do
    test "every known integration is registered with configured? from Config" do
      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()

      for id <- IntegrationHealth.known() do
        status = IntegrationHealth.status(id)
        # Nothing persisted and nothing probed at boot: every id is :unknown.
        assert %Status{id: ^id, test_state: :unknown} = status
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

  describe "the four ids are the Capabilities subjects" do
    test "known/0 lists them in UI order" do
      assert IntegrationHealth.known() == [
               :tmdb,
               :prowlarr,
               :download_client,
               :usenet_download_client
             ]
    end

    test "each slot's configured? is its own" do
      config = :persistent_term.get({Config, :config})

      :persistent_term.put(
        {Config, :config},
        config
        |> Map.put(:download_client_type, nil)
        |> Map.put(:download_client_url, nil)
        |> Map.put(:usenet_download_client_type, "sabnzbd")
        |> Map.put(:usenet_download_client_url, "http://localhost:8080")
      )

      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()

      assert %Status{id: :download_client, configured?: false} =
               IntegrationHealth.status(:download_client)

      assert %Status{id: :usenet_download_client, configured?: true} =
               IntegrationHealth.status(:usenet_download_client)
    end

    test "a usenet key change flips only the usenet slot" do
      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()
      IntegrationHealth.subscribe()

      # The message `Config.update/2` broadcasts, delivered directly so the
      # test needs no database ownership.
      send(Process.whereis(IntegrationHealth), {:config_updated, :usenet_download_client_url, "x"})

      assert_receive {:integration_health_changed, %Status{id: :usenet_download_client}}, 1_000
      refute_receive {:integration_health_changed, %Status{id: :download_client}}, 100
    end
  end

  describe "verify/1 persists for readiness (UIDR-041 §7)" do
    test "an :ok result is saved through Capabilities" do
      Config.update(:prowlarr_url, "http://localhost:9696")
      Config.update(:prowlarr_api_key, "k")
      Application.put_env(:media_centaur, :integration_health_verifier, OkVerifier)
      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()
      IntegrationHealth.subscribe()

      IntegrationHealth.verify(:prowlarr)

      assert_receive {:integration_health_changed, %Status{id: :prowlarr, test_state: :pending}},
                     1_000

      assert_receive {:integration_health_changed, %Status{id: :prowlarr, test_state: :ok}},
                     1_000

      assert %{status: :ok} = MediaCentaur.Capabilities.load_test_result(:prowlarr)
    end

    test "an error result is saved too" do
      Config.update(:tmdb_api_key, "k")
      Application.put_env(:media_centaur, :integration_health_verifier, RejectVerifier)
      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()
      IntegrationHealth.subscribe()

      IntegrationHealth.verify(:tmdb)

      assert_receive {:integration_health_changed, %Status{id: :tmdb, test_state: :error}},
                     1_000

      assert %{status: :error} = MediaCentaur.Capabilities.load_test_result(:tmdb)
    end
  end

  describe "boot" do
    test "seeds from the persisted test and probes nothing" do
      Config.update(:tmdb_api_key, "k")
      Application.put_env(:media_centaur, :integration_health_verifier, RejectVerifier)
      %{tested_at: tested_at} = MediaCentaur.Capabilities.save_test_result(:tmdb, :ok)
      IntegrationHealth.subscribe()

      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()

      assert %Status{configured?: true, test_state: :ok, last_tested_at: ^tested_at} =
               IntegrationHealth.status(:tmdb)

      # A boot probe would have gone :pending then :error under RejectVerifier.
      refute_receive {:integration_health_changed, %Status{id: :tmdb, test_state: :pending}}, 100
      assert %Status{test_state: :ok} = IntegrationHealth.status(:tmdb)
    end

    test "a configured integration with no persisted test is :unknown" do
      Config.update(:tmdb_api_key, "k")
      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()

      assert %Status{configured?: true, test_state: :unknown} = IntegrationHealth.status(:tmdb)
    end
  end

  describe "a config change" do
    test "resets the integration to :unknown, never :pending" do
      Config.update(:tmdb_api_key, "k")
      start_supervised!(IntegrationHealth)
      :ok = drain_initial_seed_broadcasts()
      IntegrationHealth.subscribe()

      send(Process.whereis(IntegrationHealth), {:config_updated, :tmdb_api_key, "k2"})

      assert_receive {:integration_health_changed,
                      %Status{id: :tmdb, configured?: true, test_state: :unknown}},
                     1_000
    end
  end

  describe "verify/1 — happy path" do
    test "transitions :unknown → :pending → :ok and broadcasts each step" do
      IntegrationHealth.subscribe()
      Application.put_env(:media_centaur, :integration_health_verifier, OkVerifier)

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
      Application.put_env(:media_centaur, :integration_health_verifier, RejectVerifier)

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
      # Built at runtime: the type checker already rejects an unknown literal.
      unknown = String.to_atom("made_up")
      assert_raise FunctionClauseError, fn -> IntegrationHealth.verify(unknown) end
    end
  end

  describe "subscribe/0" do
    test "subscriber receives broadcasts for any tracked integration" do
      IntegrationHealth.subscribe()
      Application.put_env(:media_centaur, :integration_health_verifier, OkVerifier)

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
      Application.put_env(:media_centaur, :integration_health_verifier, OkVerifier)
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
