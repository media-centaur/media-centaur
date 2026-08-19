defmodule MediaCentaur.Status.Views.Storage do
  @moduledoc """
  ETS-backed projection of the Status page's storage picture — drive
  capacity, at-risk absence summary, and media-dir reachability — as a
  `StorageSnapshot`.

  The underlying probes (`Storage.measure_all/0` → `df`, `File.dir?/1`
  per media dir) can block for seconds on sleeping or disconnected
  drives, so they must never run on a boot or navigation path. The
  projection's Worker is registered with `prime: :async` (a blocked
  probe never blocks application boot) and a periodic refresh interval;
  the page reads the last completed measurement instantly.

  ## Refresh triggers

    * `library:availability` — drive mount / unmount events.
    * `watcher:state` — per-dir watcher state transitions.
    * `config:updates` — only `:media_dirs` changes (the set of paths
      to measure changed).
    * Periodic tick (registered in `application.ex`) — measurements
      drift without events; this preserves the page's previous 5-minute
      re-measure cadence.

  ## Storage

  `:status_view_storage` — `:set`, `:public`, `:named_table`,
  `:read_concurrency, true`, single `:snapshot` row, replaced
  atomically per refresh.
  """
  @behaviour MediaCentaur.Cache

  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Library.AbsenceSweeper
  alias MediaCentaur.Library.Availability
  alias MediaCentaur.Status.Views.StorageSnapshot
  alias MediaCentaur.Storage
  alias MediaCentaur.Topics

  @table :status_view_storage

  @impl MediaCentaur.Cache
  def subscribe do
    Availability.subscribe()
    Topics.subscribe(Topics.dir_state())
    Topics.subscribe(Topics.config_updates())
    :ok
  end

  @impl MediaCentaur.Cache
  def relevant?({:availability_changed, _dir, _state}), do: true
  def relevant?({:dir_state_changed, _dir, _role, _state}), do: true
  def relevant?({:config_updated, :media_dirs, _entries}), do: true
  def relevant?(_message), do: false

  @impl MediaCentaur.Cache
  def refresh_cache do
    ensure_table()

    :ets.insert(@table, {:snapshot, measure()})

    Topics.publish(
      Topics.status_views(),
      {:status_view_updated, :storage}
    )

    :ok
  end

  @doc """
  Read the cached snapshot. Falls back to a live measurement when the
  table is absent (test mode) or not yet primed (async-prime boot
  window with a blocked drive probe).
  """
  @spec read() :: StorageSnapshot.t()
  def read do
    case :ets.whereis(@table) do
      :undefined -> measure()
      _ref -> read_from_ets()
    end
  end

  defp read_from_ets do
    case :ets.lookup(@table, :snapshot) do
      [{:snapshot, snapshot}] -> snapshot
      [] -> measure()
    end
  end

  defp measure do
    %StorageSnapshot{
      drives: Storage.measure_all(),
      at_risk: AbsenceSweeper.at_risk_summary(),
      dir_health: check_dir_health(),
      measured_at: DateTime.utc_now()
    }
  end

  defp check_dir_health do
    media_dirs = Config.get(:media_dirs) || []

    Enum.map(media_dirs, fn dir ->
      image_dir = Config.images_dir_for(dir)

      %{
        dir: dir,
        dir_exists: File.dir?(dir),
        image_dir: image_dir,
        image_dir_exists: File.dir?(image_dir)
      }
    end)
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
      _ref -> :ok
    end
  end
end
