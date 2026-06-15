defmodule MediaCentaur.TMDB.MetadataStats do
  @moduledoc """
  Retains recent TMDB metadata-enrichment activity for the Status page.

  Fetching metadata is the pipeline's job; remembering what was just enriched —
  so the Status page can show *"Last enriched 3m ago"* and a short feed of
  recent titles — is a separate concern, so it lives here. Attaches to the
  `[:media_centaur, :metadata, :enriched]` event emitted by
  `MediaCentaur.Pipeline.Stages.FetchMetadata` on a successful fetch, receives
  updates via `GenServer.cast`, and serves a snapshot via `GenServer.call`.

  Mirrors `MediaCentaur.Pipeline.Image.Stats` and `MediaCentaur.Watcher.ScanStats`.
  The handler id is derived from the registered name so multiple instances (the
  app singleton plus per-test instances) attach independently without detaching
  one another, and each detaches its own handler on terminate.

  ## Snapshot shape

      %{last_enriched_at: DateTime.t() | nil,
        total: non_neg_integer(),
        recent: [%{kind: atom(), title: String.t() | nil, year: integer() | nil, at: DateTime.t()}]}

  `recent` is newest-first and bounded to the last #{8} entries.
  """
  use GenServer

  @enriched_event [:media_centaur, :metadata, :enriched]
  @max_recent 8

  # --- Public API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the current metadata-activity snapshot, or the empty snapshot if the
  server is briefly down (reads degrade rather than crash the Status render).
  """
  @spec snapshot(GenServer.server()) :: map()
  def snapshot(server \\ __MODULE__) do
    GenServer.call(server, :snapshot)
  catch
    :exit, _ -> empty_snapshot()
  end

  @doc "Empty snapshot for the disconnected LiveView mount, before any enrichment."
  @spec empty_snapshot() :: map()
  def empty_snapshot, do: %{last_enriched_at: nil, total: 0, recent: []}

  # --- GenServer callbacks ---

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    handler_id = handler_id(name)
    attach_telemetry(handler_id)
    {:ok, %{snapshot: empty_snapshot(), handler_id: handler_id}}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.snapshot, state}

  @impl true
  def handle_cast({:enriched, entry}, %{snapshot: snapshot} = state) do
    updated = %{
      snapshot
      | last_enriched_at: entry.at,
        total: snapshot.total + 1,
        recent: Enum.take([entry | snapshot.recent], @max_recent)
    }

    {:noreply, %{state | snapshot: updated}}
  end

  @impl true
  def terminate(_reason, state) do
    :telemetry.detach(state.handler_id)
    :ok
  end

  # --- Telemetry wiring ---

  defp attach_telemetry(handler_id) do
    :telemetry.detach(handler_id)
    :telemetry.attach(handler_id, @enriched_event, &__MODULE__.handle_telemetry/4, %{stats: self()})
  end

  defp handler_id(name), do: "metadata-stats-#{inspect(name)}"

  @doc false
  def handle_telemetry(@enriched_event, _measurements, metadata, config) do
    entry = %{
      kind: metadata.kind,
      title: metadata.title,
      year: metadata[:year],
      at: DateTime.utc_now()
    }

    GenServer.cast(config.stats, {:enriched, entry})
  end
end
