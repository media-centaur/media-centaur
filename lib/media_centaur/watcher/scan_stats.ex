defmodule MediaCentaur.Watcher.ScanStats do
  @moduledoc """
  Retains the most recent scan result per watch directory for the Status page.

  The watcher's job is *detection*; remembering what its last scan found is a
  separate concern, so it lives here rather than in the per-dir
  `MediaCentaur.Watcher` GenServer. This module attaches to the
  `[:media_centaur, :watcher, :scan, :stop]` telemetry event that every scan
  already emits (see `MediaCentaur.Watcher` `scan_directory_with_paths/4`),
  receives updates via `GenServer.cast`, and serves the retained map via
  `GenServer.call`.

  ## Why a GenServer (not ETS)

  Writes happen at most once per scan (startup, config change, FSEvents
  dropped-event rescan) and reads happen a handful of times per Status-page
  load — there is no throughput pressure, so the serialized GenServer is not a
  bottleneck and avoids the ETS-table-dies-with-owner and raising-handler
  footguns. The handler `cast`s, which is dropped (never raises) if the server
  is briefly down, so telemetry never auto-detaches it.

  ## Retained shape

  `last_scan/1` and `all/0` return summaries shaped as:

      %{at: DateTime.t(), total: non_neg_integer(), new: non_neg_integer(),
        relinked: non_neg_integer()}

  - `at` — wall-clock time the scan completed (stamped here, the retention
    layer, since the telemetry metadata carries no timestamp)
  - `total` — video files seen on disk this scan
  - `new` — files dispatched to the pipeline (genuinely new arrivals)
  - `relinked` — files recognised as moved and re-pointed instead of re-imported
  """
  use GenServer

  @handler_id "watcher-scan-stats"
  @scan_stop_event [:media_centaur, :watcher, :scan, :stop]

  # --- Public API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Returns the most recent scan summary for `dir`, or nil if never scanned."
  @spec last_scan(String.t(), GenServer.server()) :: map() | nil
  def last_scan(dir, server \\ __MODULE__) do
    GenServer.call(server, {:last_scan, dir})
  end

  @doc "Returns the full `%{dir => summary}` map of retained scans."
  @spec all(GenServer.server()) :: %{optional(String.t()) => map()}
  def all(server \\ __MODULE__) do
    GenServer.call(server, :all)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    attach_telemetry()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:last_scan, dir}, _from, scans) do
    {:reply, Map.get(scans, dir), scans}
  end

  def handle_call(:all, _from, scans) do
    {:reply, scans, scans}
  end

  @impl true
  def handle_cast({:record, dir, summary}, scans) do
    {:noreply, Map.put(scans, dir, summary)}
  end

  # --- Telemetry wiring ---

  defp attach_telemetry do
    :telemetry.detach(@handler_id)

    :telemetry.attach(
      @handler_id,
      @scan_stop_event,
      &__MODULE__.handle_telemetry/4,
      %{stats: self()}
    )
  end

  @doc false
  def handle_telemetry(@scan_stop_event, _measurements, metadata, config) do
    summary = %{
      at: DateTime.utc_now(),
      total: metadata.total_video_files,
      new: metadata.dispatched,
      relinked: metadata.relinked
    }

    GenServer.cast(config.stats, {:record, metadata.dir, summary})
  end
end
