defmodule MediaCentaurWeb.DownloadsLive.SearchSession do
  @moduledoc """
  Singleton GenServer holding the user's current acquisition search session
  and owning the searches it shows.

  Decouples the search workflow from `MediaCentaurWeb.DownloadsLive`'s
  process lifetime so search state — query, brace-expanded groups, results,
  user selections, grab feedback — survives navigation, reconnect, and
  browser refresh. The per-term Prowlarr searches are this process's own
  tasks (`Acquisition.search_async/1`: started on the context's task
  supervisor, owned by the caller), so a LiveView that goes away mid-search
  loses nothing: the outcome lands here and the next mount reads it. Lost
  on BEAM restart.

  This is web-layer UI infrastructure, not a domain concept: it holds
  transient workflow state for one surface. Search execution and corpus
  citizenship stay in the contexts; no context module references this
  GenServer.

  A group is `:loading` while its search runs, then `:ready` or
  `{:failed, reason}` — a crashed search is `{:failed, {:crashed, reason}}`.
  Retry re-runs a failed term. Replacing or clearing the session shuts its
  searches down; a late outcome for a term that is no longer `:loading` is
  dropped.
  """

  use GenServer

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Search.QueryExpander
  alias MediaCentaur.Search.Quality
  alias MediaCentaur.Search.SearchResult
  alias MediaCentaur.Topics

  require MediaCentaur.Log, as: Log

  @type group_status :: :loading | :ready | {:failed, term()}

  @type group :: %{
          term: String.t(),
          status: group_status(),
          results: [SearchResult.t()],
          expanded?: boolean(),
          featured: SearchResult.t() | nil
        }

  @type t :: %__MODULE__{
          query: String.t(),
          expansion_preview: :idle | {:ok, pos_integer()} | {:error, atom()},
          groups: [group()],
          selections: %{String.t() => String.t()},
          grab_message: nil | {:ok | :partial | :error, String.t()},
          grabbing?: boolean()
        }

  defstruct query: "",
            expansion_preview: :idle,
            groups: [],
            selections: %{},
            grab_message: nil,
            grabbing?: false

  # The process state: the session every reader sees, the running searches
  # by task ref, and the function that starts one (a test's stand-in).
  @typep state :: %{
           session: t(),
           searches: %{reference() => {String.t(), Task.t()}},
           search: (String.t() -> Task.t())
         }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  `name:` the registered name (`#{inspect(__MODULE__)}` by default);
  `search:` the one-arity function that starts a term's search and returns
  the task this process owns (`Acquisition.search_async/1` by default; a
  test hands in its own).
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Subscribes the caller to `{:search_session, t()}` broadcasts."
  @spec subscribe() :: :ok
  def subscribe do
    Topics.subscribe(Topics.acquisition_search())
  end

  @doc "Returns the current session struct."
  @spec current(GenServer.server()) :: t()
  def current(server \\ __MODULE__) do
    GenServer.call(server, :current)
  end

  @doc """
  Starts a new search session, replacing any existing one and shutting down
  the searches it was running: one `:loading` group and one search per
  expanded query.

  Returns `{:ok, %{session: session, queries: queries}}`, or
  `{:error, :invalid_syntax}` for malformed brace expansion, leaving the
  existing session unchanged.
  """
  @spec start_search(GenServer.server(), String.t()) ::
          {:ok, %{session: t(), queries: [String.t()]}}
          | {:error, :invalid_syntax}
  def start_search(server \\ __MODULE__, query) when is_binary(query) do
    GenServer.call(server, {:start_search, query})
  end

  @doc """
  Records the outcome of a per-query Prowlarr search — how this process's
  own searches land, and the seam a test lands one through.

  Idempotent: a result for a term whose group is already in a terminal
  state (`:ready`, `{:failed, _}`) is silently dropped, as is a result for
  a term not in the current session.
  """
  @spec record_search_result(
          GenServer.server(),
          String.t(),
          {:ok, [SearchResult.t()]} | {:error, term()}
        ) :: :ok
  def record_search_result(server \\ __MODULE__, term, outcome) when is_binary(term) do
    GenServer.call(server, {:record_search_result, term, outcome})
  end

  @doc """
  Mutators return the new `%SearchSession{}` so the caller can assign it
  directly without a follow-up `current/0` call. The same struct is also
  broadcast on `Topics.acquisition_search/0` for any other subscribers.
  """
  @spec set_selection(GenServer.server(), String.t(), String.t()) :: t()
  def set_selection(server \\ __MODULE__, term, guid) when is_binary(term) and is_binary(guid) do
    GenServer.call(server, {:set_selection, term, guid})
  end

  @doc "Removes `term` from the selections map. Returns the new session."
  @spec clear_selection(GenServer.server(), String.t()) :: t()
  def clear_selection(server \\ __MODULE__, term) when is_binary(term) do
    GenServer.call(server, {:clear_selection, term})
  end

  @doc "Empties the selections map. Returns the new session."
  @spec clear_selections(GenServer.server()) :: t()
  def clear_selections(server \\ __MODULE__) do
    GenServer.call(server, :clear_selections)
  end

  @doc """
  Flips `expanded?` on the group whose term matches; no-op for unknown
  terms. Returns the new session.
  """
  @spec toggle_group(GenServer.server(), String.t()) :: t()
  def toggle_group(server \\ __MODULE__, term) when is_binary(term) do
    GenServer.call(server, {:toggle_group, term})
  end

  @doc """
  Updates `query` and `expansion_preview` from a live input value, without
  touching any other field. Used by the LiveView's `phx-change` handler so
  the user sees the brace-expanded count update as they type. Returns the
  new session.
  """
  @spec set_query_preview(GenServer.server(), String.t()) :: t()
  def set_query_preview(server \\ __MODULE__, query) when is_binary(query) do
    GenServer.call(server, {:set_query_preview, query})
  end

  @doc "Sets the boolean `grabbing?` flag. Returns the new session."
  @spec set_grabbing(GenServer.server(), boolean()) :: t()
  def set_grabbing(server \\ __MODULE__, value) when is_boolean(value) do
    GenServer.call(server, {:set_grabbing, value})
  end

  @doc "Sets the last-grab outcome message. Returns the new session."
  @spec set_grab_message(
          GenServer.server(),
          {:ok | :partial | :error, String.t()}
        ) :: t()
  def set_grab_message(server \\ __MODULE__, message) do
    GenServer.call(server, {:set_grab_message, message})
  end

  @doc "Resets the entire session to the default empty state, shutting down its searches. Returns the new session."
  @spec clear(GenServer.server()) :: t()
  def clear(server \\ __MODULE__) do
    GenServer.call(server, :clear)
  end

  @doc """
  Clears search results (groups + selections) but keeps the user's
  query and expansion preview. Used after a grab batch completes so the
  results disappear without losing what the user typed in the search
  bar. Any in-flight search is shut down. Returns the new session.
  """
  @spec clear_results(GenServer.server()) :: t()
  def clear_results(server \\ __MODULE__) do
    GenServer.call(server, :clear_results)
  end

  @doc """
  Re-runs the named groups' searches: any term currently `{:failed, _}`
  flips back to `:loading` and a new search starts for it. Other states
  are no-ops for that term. Returns the new session.
  """
  @spec retry_search_terms(GenServer.server(), [String.t()]) :: t()
  def retry_search_terms(server \\ __MODULE__, terms) when is_list(terms) do
    GenServer.call(server, {:retry_search_terms, terms})
  end

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    # Trapped so `terminate/2` runs on an orderly stop and shuts the
    # searches down; nothing else reads their outcome.
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       session: %__MODULE__{},
       searches: %{},
       search: Keyword.get(opts, :search, &Acquisition.search_async/1)
     }}
  end

  @impl GenServer
  def terminate(_reason, state) do
    shutdown_searches(state)
    :ok
  end

  @impl GenServer
  def handle_call(:current, _from, state) do
    {:reply, state.session, state}
  end

  def handle_call({:start_search, query}, _from, state) do
    trimmed = String.trim(query)

    case QueryExpander.expand(trimmed) do
      {:ok, [_ | _] = queries} ->
        groups =
          Enum.map(queries, fn term ->
            %{term: term, status: :loading, results: [], expanded?: false, featured: nil}
          end)

        session = %__MODULE__{
          query: trimmed,
          expansion_preview: {:ok, length(queries)},
          groups: groups,
          selections: %{},
          grab_message: nil,
          grabbing?: false
        }

        state = state |> shutdown_searches() |> put_session(session) |> start_searches(queries)
        Log.info(:acquisition, "search started — #{length(queries)} queries")
        {:reply, {:ok, %{session: session, queries: queries}}, state}

      {:ok, []} ->
        {:reply, {:error, :invalid_syntax}, state}

      {:error, _reason} ->
        {:reply, {:error, :invalid_syntax}, state}
    end
  end

  def handle_call({:record_search_result, term, outcome}, _from, state) do
    {:reply, :ok, land(state, term, outcome)}
  end

  def handle_call({:set_selection, term, guid}, _from, state) do
    # Choosing a release for a term implies the user is done browsing it —
    # collapse the group so the surface stays compact while they pick the
    # rest of their selections.
    groups =
      Enum.map(state.session.groups, fn
        %{term: ^term} = group -> %{group | expanded?: false}
        group -> group
      end)

    session =
      stamp_featured(%{
        state.session
        | selections: Map.put(state.session.selections, term, guid),
          groups: groups
      })

    reply_session(state, session)
  end

  def handle_call({:clear_selection, term}, _from, state) do
    session = stamp_featured(%{state.session | selections: Map.delete(state.session.selections, term)})
    reply_session(state, session)
  end

  def handle_call(:clear_selections, _from, state) do
    reply_session(state, stamp_featured(%{state.session | selections: %{}}))
  end

  def handle_call({:toggle_group, term}, _from, state) do
    groups =
      Enum.map(state.session.groups, fn
        %{term: ^term} = group -> %{group | expanded?: not group.expanded?}
        group -> group
      end)

    reply_session(state, %{state.session | groups: groups})
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

    reply_session(state, %{state.session | query: query, expansion_preview: preview})
  end

  def handle_call({:set_grabbing, value}, _from, state) do
    reply_session(state, %{state.session | grabbing?: value})
  end

  def handle_call({:set_grab_message, message}, _from, state) do
    reply_session(state, %{state.session | grab_message: message})
  end

  def handle_call(:clear, _from, state) do
    state = shutdown_searches(state)
    reply_session(state, %__MODULE__{})
  end

  def handle_call(:clear_results, _from, state) do
    # Only the groups + selections go — the user's query, expansion
    # preview, last grab message, and grabbing flag are preserved so the
    # surface keeps the shape the user expects after a successful grab.
    state = shutdown_searches(state)
    reply_session(state, %{state.session | groups: [], selections: %{}})
  end

  def handle_call({:retry_search_terms, terms}, _from, state) do
    retried =
      for term <- terms,
          group = Enum.find(state.session.groups, &(&1.term == term)),
          match?({:failed, _}, group.status),
          do: term

    groups =
      Enum.map(state.session.groups, fn group ->
        if group.term in retried,
          do: %{group | status: :loading, results: [], featured: nil},
          else: group
      end)

    state = state |> put_session(%{state.session | groups: groups}) |> start_searches(retried)
    broadcast(state.session)
    {:reply, state.session, state}
  end

  # A search's outcome, from the task this process owns.
  @impl GenServer
  def handle_info({ref, outcome}, %{searches: searches} = state) when is_map_key(searches, ref) do
    Process.demonitor(ref, [:flush])
    {{term, _task}, searches} = Map.pop(searches, ref)
    {:noreply, land(%{state | searches: searches}, term, outcome)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{searches: searches} = state)
      when is_map_key(searches, ref) do
    {{term, _task}, searches} = Map.pop(searches, ref)
    {:noreply, land(%{state | searches: searches}, term, {:error, {:crashed, reason}})}
  end

  def handle_info(_other, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec start_searches(state(), [String.t()]) :: state()
  defp start_searches(state, terms) do
    Enum.reduce(terms, state, fn term, acc ->
      task = acc.search.(term)
      put_in(acc.searches[task.ref], {term, task})
    end)
  end

  defp shutdown_searches(state) do
    Enum.each(state.searches, fn {_ref, {_term, task}} -> Task.shutdown(task, :brutal_kill) end)
    %{state | searches: %{}}
  end

  defp put_session(state, session) do
    broadcast(session)
    %{state | session: session}
  end

  defp reply_session(state, session) do
    broadcast(session)
    {:reply, session, %{state | session: session}}
  end

  defp land(state, term, outcome) do
    case apply_search_result(state.session, term, outcome) do
      :not_loading -> state
      session -> put_session(state, session)
    end
  end

  defp broadcast(%__MODULE__{} = session) do
    Topics.publish(
      Topics.acquisition_search(),
      {:search_session, session}
    )
  end

  # Single-pass over groups: locate the matching loading group, update
  # it in place, and accumulate the new selection (success outcomes
  # only). Returns `:not_loading` when no group matches the term in
  # `:loading` — the caller maps that to a no-op.
  defp apply_search_result(session, term, outcome) do
    {groups, found?, selection_update} =
      Enum.reduce(session.groups, {[], false, :unchanged}, fn group, {acc, found?, selection} ->
        if not found? and group.term == term and group.status == :loading do
          {updated_group, selection} = update_group_with_outcome(group, outcome)
          {[updated_group | acc], true, selection}
        else
          {[group | acc], found?, selection}
        end
      end)

    if found? do
      groups = Enum.reverse(groups)

      selections =
        case selection_update do
          {:put_new, key, guid} -> Map.put_new(session.selections, key, guid)
          :unchanged -> session.selections
        end

      stamp_featured(%{session | groups: groups, selections: selections})
    else
      :not_loading
    end
  end

  defp update_group_with_outcome(group, {:ok, results}) do
    sorted = sort_results(results)
    updated = %{group | status: :ready, results: sorted}

    selection =
      case sorted do
        [first | _] -> {:put_new, group.term, first.guid}
        [] -> :unchanged
      end

    {updated, selection}
  end

  defp update_group_with_outcome(group, {:error, reason}) do
    {%{group | status: {:failed, reason}, results: [], featured: nil}, :unchanged}
  end

  defp sort_results(results) do
    Enum.sort_by(results, fn r -> {Quality.rank(r.quality), r.seeders || 0} end, :desc)
  end

  # Stamp `:featured` onto every group based on the current `selections` map.
  # The featured result is the user's selected guid (when present and still in
  # the result list); otherwise the top-ranked result. Computed server-side so
  # the LiveView reads it as data instead of recomputing on every render.
  @spec stamp_featured(t()) :: t()
  defp stamp_featured(%__MODULE__{groups: groups, selections: selections} = session) do
    %{session | groups: Enum.map(groups, &stamp_featured_group(&1, selections))}
  end

  defp stamp_featured_group(%{results: []} = group, _selections), do: %{group | featured: nil}

  defp stamp_featured_group(%{term: term, results: [first | _] = results} = group, selections) do
    featured =
      case Map.get(selections, term) do
        nil -> first
        guid -> Enum.find(results, first, &(&1.guid == guid))
      end

    %{group | featured: featured}
  end
end
