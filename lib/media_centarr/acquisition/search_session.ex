defmodule MediaCentarr.Acquisition.SearchSession do
  @moduledoc """
  Singleton GenServer holding the user's current acquisition search session.

  Decouples the search workflow from `MediaCentarrWeb.AcquisitionLive`'s
  process lifetime so search state — query, brace-expanded groups, results,
  user selections, grab feedback — survives navigation, reconnect, and
  browser refresh. Lost on BEAM restart.

  All public access goes through the `MediaCentarr.Acquisition` facade —
  no module outside the Acquisition context calls this GenServer directly.

  See `docs/superpowers/specs/2026-04-30-acquisition-search-session-design.md`.
  """

  use GenServer

  alias MediaCentarr.Acquisition.QueryExpander
  alias MediaCentarr.Acquisition.Quality
  alias MediaCentarr.Acquisition.SearchResult
  alias MediaCentarr.Topics

  require MediaCentarr.Log, as: Log

  @type group_status :: :loading | :ready | {:failed, term()} | :abandoned

  @type group :: %{
          term: String.t(),
          status: group_status(),
          results: [SearchResult.t()],
          expanded?: boolean()
        }

  @type t :: %__MODULE__{
          query: String.t(),
          expansion_preview: :idle | {:ok, pos_integer()} | {:error, atom()},
          groups: [group()],
          selections: %{String.t() => String.t()},
          grab_message: nil | {:ok | :partial | :error, String.t()},
          grabbing?: boolean(),
          searching_pid: nil | pid(),
          monitor_ref: nil | reference()
        }

  defstruct query: "",
            expansion_preview: :idle,
            groups: [],
            selections: %{},
            grab_message: nil,
            grabbing?: false,
            searching_pid: nil,
            monitor_ref: nil

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Returns the current session struct."
  @spec current(GenServer.server()) :: t()
  def current(server \\ __MODULE__) do
    GenServer.call(server, :current)
  end

  @doc """
  Starts a new search session, replacing any existing one.

  Returns `{:ok, %{session: session, queries: queries}}` on success — the
  caller spawns Tasks for each `query` and sends results back via
  `record_search_result/3`.

  Returns `{:error, :invalid_syntax}` for malformed brace expansion. The
  existing session is unchanged in that case.

  The caller's pid becomes the monitored `searching_pid`. If the caller
  dies, any group still in `:loading` is swept to `:abandoned`.
  """
  @spec start_search(GenServer.server(), String.t()) ::
          {:ok, %{session: t(), queries: [String.t()]}}
          | {:error, :invalid_syntax}
  def start_search(server \\ __MODULE__, query) when is_binary(query) do
    GenServer.call(server, {:start_search, query, self()})
  end

  @doc """
  Records the outcome of a per-query Prowlarr search.

  Idempotent: a result for a term whose group is already in a terminal
  state (`:ready`, `{:failed, _}`, `:abandoned`) is silently dropped, as
  is a result for a term not in the current session. This handles the
  late-arriving Task case where the LiveView crashed and the group was
  swept to `:abandoned` before the Task's HTTP request returned.
  """
  @spec record_search_result(
          GenServer.server(),
          String.t(),
          {:ok, [SearchResult.t()]} | {:error, term()}
        ) :: :ok
  def record_search_result(server \\ __MODULE__, term, outcome) when is_binary(term) do
    GenServer.call(server, {:record_search_result, term, outcome})
  end

  @doc "Sets `term => guid` in the selections map."
  @spec set_selection(GenServer.server(), String.t(), String.t()) :: :ok
  def set_selection(server \\ __MODULE__, term, guid) when is_binary(term) and is_binary(guid) do
    GenServer.call(server, {:set_selection, term, guid})
  end

  @doc "Removes `term` from the selections map."
  @spec clear_selection(GenServer.server(), String.t()) :: :ok
  def clear_selection(server \\ __MODULE__, term) when is_binary(term) do
    GenServer.call(server, {:clear_selection, term})
  end

  @doc "Empties the selections map."
  @spec clear_selections(GenServer.server()) :: :ok
  def clear_selections(server \\ __MODULE__) do
    GenServer.call(server, :clear_selections)
  end

  @doc "Flips `expanded?` on the group whose term matches; no-op for unknown terms."
  @spec toggle_group(GenServer.server(), String.t()) :: :ok
  def toggle_group(server \\ __MODULE__, term) when is_binary(term) do
    GenServer.call(server, {:toggle_group, term})
  end

  @doc """
  Updates `query` and `expansion_preview` from a live input value, without
  touching any other field. Used by the LiveView's `phx-change` handler so
  the user sees the brace-expanded count update as they type.
  """
  @spec set_query_preview(GenServer.server(), String.t()) :: :ok
  def set_query_preview(server \\ __MODULE__, query) when is_binary(query) do
    GenServer.call(server, {:set_query_preview, query})
  end

  @doc "Sets the boolean `grabbing?` flag."
  @spec set_grabbing(GenServer.server(), boolean()) :: :ok
  def set_grabbing(server \\ __MODULE__, value) when is_boolean(value) do
    GenServer.call(server, {:set_grabbing, value})
  end

  @doc "Sets the last-grab outcome message."
  @spec set_grab_message(
          GenServer.server(),
          {:ok | :partial | :error, String.t()}
        ) :: :ok
  def set_grab_message(server \\ __MODULE__, message) do
    GenServer.call(server, {:set_grab_message, message})
  end

  @doc "Resets the entire session to the default empty state."
  @spec clear(GenServer.server()) :: :ok
  def clear(server \\ __MODULE__) do
    GenServer.call(server, :clear)
  end

  @doc """
  Re-arms named groups: any term currently in `:abandoned` or `{:failed, _}`
  flips back to `:loading`. Other states are no-ops for that term. The
  caller's pid becomes the new monitored `searching_pid`.

  The caller is responsible for spawning Tasks for these terms after the
  call returns.
  """
  @spec retry_search_terms(GenServer.server(), [String.t()]) :: :ok
  def retry_search_terms(server \\ __MODULE__, terms) when is_list(terms) do
    GenServer.call(server, {:retry_search_terms, terms, self()})
  end

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl GenServer
  def handle_call(:current, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:start_search, query, caller_pid}, _from, state) do
    trimmed = String.trim(query)

    case QueryExpander.expand(trimmed) do
      {:ok, [_ | _] = queries} ->
        groups =
          Enum.map(queries, fn term ->
            %{term: term, status: :loading, results: [], expanded?: false}
          end)

        new_state =
          swap_monitor(
            %__MODULE__{
              query: trimmed,
              expansion_preview: {:ok, length(queries)},
              groups: groups,
              selections: %{},
              grab_message: nil,
              grabbing?: false,
              searching_pid: caller_pid
            },
            state
          )

        broadcast(new_state)
        Log.info(:acquisition, "search started — #{length(queries)} queries")
        {:reply, {:ok, %{session: new_state, queries: queries}}, new_state}

      {:ok, []} ->
        {:reply, {:error, :invalid_syntax}, state}

      {:error, _reason} ->
        {:reply, {:error, :invalid_syntax}, state}
    end
  end

  def handle_call({:record_search_result, term, outcome}, _from, state) do
    case Enum.find_index(state.groups, &(&1.term == term and &1.status == :loading)) do
      nil ->
        {:reply, :ok, state}

      index ->
        new_state = apply_search_result(state, index, outcome)
        broadcast(new_state)
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:set_selection, term, guid}, _from, state) do
    new_state = %{state | selections: Map.put(state.selections, term, guid)}
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:clear_selection, term}, _from, state) do
    new_state = %{state | selections: Map.delete(state.selections, term)}
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:clear_selections, _from, state) do
    new_state = %{state | selections: %{}}
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:toggle_group, term}, _from, state) do
    groups =
      Enum.map(state.groups, fn
        %{term: ^term} = group -> %{group | expanded?: not group.expanded?}
        group -> group
      end)

    new_state = %{state | groups: groups}
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:set_query_preview, query}, _from, state) do
    preview =
      case String.trim(query) do
        "" ->
          :idle

        trimmed ->
          case QueryExpander.expand(trimmed) do
            {:ok, queries} -> {:ok, length(queries)}
            {:error, _reason} -> {:error, :invalid_syntax}
          end
      end

    new_state = %{state | query: query, expansion_preview: preview}
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:set_grabbing, value}, _from, state) do
    new_state = %{state | grabbing?: value}
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:set_grab_message, message}, _from, state) do
    new_state = %{state | grab_message: message}
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:clear, _from, state) do
    new_state = swap_monitor(%__MODULE__{}, state)
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:retry_search_terms, terms, caller_pid}, _from, state) do
    terms_set = MapSet.new(terms)

    groups =
      Enum.map(state.groups, fn
        %{term: term, status: :abandoned} = group ->
          if MapSet.member?(terms_set, term),
            do: %{group | status: :loading, results: []},
            else: group

        %{term: term, status: {:failed, _}} = group ->
          if MapSet.member?(terms_set, term),
            do: %{group | status: :loading, results: []},
            else: group

        group ->
          group
      end)

    new_state =
      swap_monitor(%{state | groups: groups, searching_pid: caller_pid}, state)

    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_info(
        {:DOWN, ref, :process, pid, _reason},
        %__MODULE__{monitor_ref: ref, searching_pid: pid} = state
      ) do
    {groups, abandoned_count} =
      Enum.map_reduce(state.groups, 0, fn
        %{status: :loading} = group, acc -> {%{group | status: :abandoned}, acc + 1}
        group, acc -> {group, acc}
      end)

    new_state = %{state | groups: groups, searching_pid: nil, monitor_ref: nil}

    if abandoned_count > 0 do
      Log.info(
        :acquisition,
        "search abandoned — #{abandoned_count} group(s), query=#{inspect(state.query)}"
      )
    end

    broadcast(new_state)
    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp swap_monitor(%__MODULE__{searching_pid: new_pid} = new_state, %__MODULE__{monitor_ref: old_ref}) do
    if old_ref, do: Process.demonitor(old_ref, [:flush])
    new_ref = if new_pid, do: Process.monitor(new_pid)
    %{new_state | monitor_ref: new_ref}
  end

  defp broadcast(%__MODULE__{} = session) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.acquisition_search(),
      {:search_session, session}
    )
  end

  defp apply_search_result(state, index, {:ok, results}) do
    sorted = sort_results(results)
    group = Enum.at(state.groups, index)
    updated_group = %{group | status: :ready, results: sorted}
    groups = List.replace_at(state.groups, index, updated_group)

    selections =
      case sorted do
        [first | _] -> Map.put_new(state.selections, group.term, first.guid)
        [] -> state.selections
      end

    %{state | groups: groups, selections: selections}
  end

  defp apply_search_result(state, index, {:error, reason}) do
    group = Enum.at(state.groups, index)
    updated_group = %{group | status: {:failed, reason}, results: []}
    groups = List.replace_at(state.groups, index, updated_group)
    %{state | groups: groups}
  end

  defp sort_results(results) do
    Enum.sort_by(results, fn r -> {Quality.rank(r.quality), r.seeders || 0} end, :desc)
  end
end
