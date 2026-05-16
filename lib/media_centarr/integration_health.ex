defmodule MediaCentarr.IntegrationHealth do
  @moduledoc """
  Owns the per-integration "is this thing actually working?" answer.

  Each external integration (`:tmdb`, `:prowlarr`, `:download_client`) is
  tracked along two orthogonal axes — `configured?` (read of Config) and
  `test_state` (last network probe result). State lives in a named ETS
  table owned by this module's GenServer; reads bypass the GenServer
  entirely. Writes go through the GenServer to serialise verify
  scheduling and broadcast emission.

  ## Lifecycle

    * On boot: read Config, mark each integration `configured?` accordingly,
      and kick a verify for every configured integration so the cached
      state reflects reality without waiting for user action.
    * On `{:config_updated, key, _value}` for any tracked key: flip
      `configured?` to match, reset `test_state` to `:pending`, kick a
      verify.
    * On `verify/1`: spawn the test on `Task.Supervisor`, set
      `test_state: :pending`, broadcast the change. The test result
      arrives via `handle_info({:test_result, id, ...})` and updates the
      cache + emits another broadcast.

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
      MediaCentarr.TMDB,
      MediaCentarr.Acquisition,
      MediaCentarr.Downloads
    ],
    exports: [Status, Verifier]

  use GenServer

  alias MediaCentarr.{Config, Secret, Topics}
  alias MediaCentarr.IntegrationHealth.{Status, Verifier}
  require MediaCentarr.Log, as: Log

  @table :integration_health
  @integrations [:tmdb, :prowlarr, :download_client]

  # Map an integration id to the Config key whose presence flips
  # `configured?`. Single source of truth so adding a new integration is
  # one line.
  @config_key %{
    tmdb: :tmdb_api_key,
    prowlarr: :prowlarr_api_key,
    download_client: :download_client_password
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
    Map.new(@integrations, fn id -> {id, status(id) || unknown(id, false)} end)
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
  def subscribe, do: Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.integration_health())

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
    Enum.each(@integrations, fn id ->
      configured? = configured_for?(id)
      write(id, %Status{id: id, configured?: configured?, test_state: :unknown})
      if configured?, do: kick_test(id)
    end)

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
        configured? = configured_for?(id)
        # Reset test_state when the key changes — the previous :ok is no
        # longer valid evidence for the new value.
        write(id, %Status{
          id: id,
          configured?: configured?,
          test_state: if(configured?, do: :pending, else: :unknown)
        })

        broadcast(id)
        if configured?, do: kick_test(id)
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

  defp configured_for?(id) do
    @config_key
    |> Map.fetch!(id)
    |> Config.get()
    |> Secret.present?()
  end

  defp integration_for_key(key) do
    Enum.find(@integrations, fn id -> Map.get(@config_key, id) == key end)
  end

  defp kick_test(id) do
    # Mark pending immediately so consumers see the right state even
    # before the Task starts running.
    write_field(id, :test_state, :pending)
    broadcast(id)

    parent = self()
    verifier = verifier_module()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      result = verifier.run(id)
      send(parent, {:test_result, id, result})
    end)

    :ok
  end

  defp apply_test_result(id, :ok) do
    current = status(id) || %Status{id: id, configured?: configured_for?(id), test_state: :unknown}

    write(id, %{
      current
      | test_state: :ok,
        test_error: nil,
        last_tested_at: DateTime.utc_now()
    })

    Log.info(:integration_health, "#{id} test ok")
    broadcast(id)
  end

  defp apply_test_result(id, {:error, reason}) do
    current = status(id) || %Status{id: id, configured?: configured_for?(id), test_state: :unknown}

    write(id, %{
      current
      | test_state: :error,
        test_error: reason,
        last_tested_at: DateTime.utc_now()
    })

    Log.warning(:integration_health, "#{id} test failed — #{inspect(reason)}")
    broadcast(id)
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
        Phoenix.PubSub.broadcast(
          MediaCentarr.PubSub,
          Topics.integration_health(),
          {:integration_health_changed, status}
        )
    end
  end

  defp unknown(id, configured?) do
    %Status{id: id, configured?: configured?, test_state: :unknown}
  end

  defp verifier_module do
    Application.get_env(:media_centarr, :integration_health_verifier, Verifier)
  end
end
