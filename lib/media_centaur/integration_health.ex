defmodule MediaCentaur.IntegrationHealth do
  @moduledoc """
  Owns the per-integration "is this thing actually working?" answer.

  Each external integration — the four `Capabilities` subjects `:tmdb`,
  `:prowlarr`, `:download_client` (the torrent slot) and
  `:usenet_download_client` — is tracked along two orthogonal axes:
  `configured?` (`Capabilities.configured?/1`) and `test_state` (last
  network probe result). State lives in a named ETS
  table owned by this module's GenServer; reads bypass the GenServer
  entirely. Writes go through the GenServer to serialise verify
  scheduling and broadcast emission.

  ## Lifecycle

    * On boot: seed each id from `Capabilities.configured?/1` and the
      persisted test (`Capabilities.load_test_result/1`) — its status and
      `tested_at` when there is one, `:unknown` when there is none.
      Nothing is probed (UIDR-041 §7): an integration reads as it last
      tested until someone tests it.
    * On `{:config_updated, key, _value}` for any tracked key: re-seed
      the id from Config and the persisted test. A person's save clears
      the persisted test before it writes a field
      (`Capabilities.save_integration/2`), so the row reads `:unknown`
      afterwards; the boot-time config load leaves it in place, so the
      row keeps its last result. A verify in flight keeps its `:pending`
      through a re-seed. The verify itself is the caller's explicit act
      (`verify/1`, from the setup tour or Settings), so a multi-field
      save cannot race a probe against half-written credentials.
    * On `verify/1`: spawn the test on `Task.Supervisor`, set
      `test_state: :pending`, broadcast the change. The result arrives
      via `handle_info({:test_result, id, ...})`, is written here,
      persisted through `Capabilities.save_test_result/2` (the readiness
      gates read that), and broadcast again. This module is the one
      writer of the persisted test.

  ## Read API (bypass-GenServer)

      IntegrationHealth.status(:tmdb)        # %Status{} | nil
      IntegrationHealth.all_statuses()       # %{id => %Status{}}
      IntegrationHealth.healthy?(:tmdb)      # boolean

  ## Write API (serialise through GenServer)

      IntegrationHealth.verify(:tmdb)        # :ok — kicks async test

  ## PubSub

  Every state change broadcasts `{:integration_health_changed,
  %Status{}}` on `Topics.integration_health()`. Subscribers (SetupLive,
  Status page, future pipeline retry) react.

  ## Why a bespoke GenServer instead of `Cache.Worker`

  Cache.Worker (ADR-041) rebuilds a projection from upstream events.
  IntegrationHealth is the source of truth for "did this integration
  test :ok"; nothing upstream owns that answer. We're write-side, so
  Cache.Worker's read-projection shape doesn't fit. The GenServer +
  ETS pattern (otp-thinking) is the right tool.
  """
  use Boundary,
    deps: [
      MediaCentaur.TMDB,
      MediaCentaur.Capabilities,
      MediaCentaur.Downloads,
      MediaCentaur.Search
    ],
    exports: [Status, Verifier]

  use GenServer

  alias MediaCentaur.Settings.Config
  alias MediaCentaur.{Capabilities, Topics}
  alias MediaCentaur.IntegrationHealth.{Status, Verifier}
  require MediaCentaur.Log, as: Log

  @table :integration_health
  @integrations [:tmdb, :prowlarr, :download_client, :usenet_download_client]

  # The Config keys whose change can flip an integration's `configured?`
  # (the predicate itself is `Capabilities.configured?/1`). One slot, one
  # integration: a usenet key never touches the torrent row (UIDR-041 §7).
  @config_keys %{
    tmdb: [:tmdb_api_key],
    prowlarr: [:prowlarr_url, :prowlarr_api_key],
    download_client: [
      :download_client_type,
      :download_client_url,
      :download_client_username,
      :download_client_password
    ],
    usenet_download_client: [
      :usenet_download_client_type,
      :usenet_download_client_url,
      :usenet_download_client_api_key
    ]
  }

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc "Starts the IntegrationHealth GenServer + ETS table."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "List of integrations this module tracks. Stable, ordered for UI."
  @spec known() :: [Status.id()]
  def known, do: @integrations

  @doc """
  Returns the current status for `id`, or `nil` if the table isn't
  initialised yet (test mode without the worker started, etc.).
  """
  @spec status(Status.id()) :: Status.t() | nil
  def status(id) do
    case :ets.whereis(@table) do
      :undefined ->
        nil

      _ref ->
        case :ets.lookup(@table, id) do
          [{^id, status}] -> status
          [] -> nil
        end
    end
  end

  @doc "Returns every tracked integration's status as a map keyed by id."
  @spec all_statuses() :: %{Status.id() => Status.t()}
  def all_statuses do
    Map.new(@integrations, fn id -> {id, status(id) || unknown(id, configured_for?(id))} end)
  end

  @doc "True when the integration is configured AND last test was `:ok`."
  @spec healthy?(Status.id()) :: boolean()
  def healthy?(id) do
    case status(id) do
      %Status{configured?: true, test_state: :ok} -> true
      _ -> false
    end
  end

  @doc """
  Kicks an async test for `id`. Immediately marks `test_state: :pending`
  and broadcasts the change. The eventual `:ok | :error` result also
  broadcasts when it lands.
  """
  @spec verify(Status.id()) :: :ok
  def verify(id) when id in @integrations do
    GenServer.cast(__MODULE__, {:verify, id})
  end

  @doc "Subscribes the caller to `Topics.integration_health()` broadcasts."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.integration_health())

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    ensure_table()
    :ok = Config.subscribe()
    {:ok, %{}, {:continue, :seed}}
  end

  @impl true
  def handle_continue(:seed, state) do
    Enum.each(@integrations, fn id -> write(id, seeded(id)) end)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:verify, id}, state) when id in @integrations do
    kick_test(id)
    {:noreply, state}
  end

  @impl true
  def handle_info({:test_result, id, result}, state) do
    apply_test_result(id, result)
    {:noreply, state}
  end

  def handle_info({:config_updated, key, _value}, state) do
    case integration_for_key(key) do
      nil ->
        {:noreply, state}

      id ->
        # Re-seed from the persisted test rather than resetting outright:
        # a person's save has already cleared it (so this reads :unknown),
        # while the boot-time config load has not (so the last result
        # stays). We deliberately do NOT auto-kick a verify here: writes
        # arrive in bursts (the tour saving URL + key in one submit) and a
        # per-key cascade races on stale config, so verification is always
        # explicit via `verify/1`.
        reseed(id)
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
      _ -> :ok
    end
  end

  defp configured_for?(id), do: Capabilities.configured?(id)

  defp integration_for_key(key) do
    Enum.find(@integrations, fn id -> key in Map.fetch!(@config_keys, id) end)
  end

  defp kick_test(id) do
    # Mark pending immediately so consumers see the right state even
    # before the Task starts running.
    write_field(id, :test_state, :pending)
    broadcast(id)

    parent = self()
    verifier = verifier_module()

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      result = verifier.run(id)
      send(parent, {:test_result, id, result})
    end)

    :ok
  end

  defp apply_test_result(id, :ok) do
    current = status(id) || %Status{id: id, configured?: configured_for?(id), test_state: :unknown}
    %{tested_at: tested_at} = Capabilities.save_test_result(id, :ok)

    write(id, %{current | test_state: :ok, test_error: nil, last_tested_at: tested_at})

    Log.info(:system, "#{id} test ok")
    broadcast(id)
  end

  defp apply_test_result(id, {:error, reason}) do
    current = status(id) || %Status{id: id, configured?: configured_for?(id), test_state: :unknown}
    %{tested_at: tested_at} = Capabilities.save_test_result(id, :error)

    write(id, %{current | test_state: :error, test_error: reason, last_tested_at: tested_at})

    Log.warning(:system, "#{id} test failed — #{inspect(reason)}")
    broadcast(id)
  end

  # Re-read one id from Config and the persisted test, keeping a verify
  # that is still in flight, and tell subscribers when anything moved.
  defp reseed(id) do
    current = status(id)
    fresh = seeded(id)

    next =
      case current do
        %Status{test_state: :pending} -> %{fresh | test_state: :pending}
        _settled -> fresh
      end

    if current != next do
      write(id, next)
      broadcast(id)
    end

    :ok
  end

  # The boot state of one id: configured? from Config, and the persisted
  # test when there is one (its status and when it ran). Never a probe.
  defp seeded(id) do
    configured? = configured_for?(id)

    case Capabilities.load_test_result(id) do
      %{status: status, tested_at: tested_at} when configured? ->
        %Status{id: id, configured?: true, test_state: status, last_tested_at: tested_at}

      _none ->
        %Status{id: id, configured?: configured?, test_state: :unknown}
    end
  end

  defp write(id, %Status{} = status) do
    :ets.insert(@table, {id, status})
  end

  defp write_field(id, field, value) do
    current = status(id) || %Status{id: id, configured?: configured_for?(id), test_state: :unknown}
    write(id, Map.put(current, field, value))
  end

  defp broadcast(id) do
    case status(id) do
      nil ->
        :ok

      %Status{} = status ->
        Topics.publish(
          Topics.integration_health(),
          {:integration_health_changed, status}
        )
    end
  end

  defp unknown(id, configured?) do
    %Status{id: id, configured?: configured?, test_state: :unknown}
  end

  defp verifier_module do
    Application.get_env(:media_centaur, :integration_health_verifier, Verifier)
  end
end
