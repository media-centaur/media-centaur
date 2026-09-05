defmodule MediaCentaur.BootHeal do
  use Boundary, deps: [MediaCentaur.Library, MediaCentaur.Pipeline]

  @moduledoc """
  Boot-time self-heals — network-free, idempotent backfills the
  application runs in the background after start so a fix shipped in an
  update reaches existing records on the next restart, with no operator
  action.

  Every heal is skipped under `:test`: a boot-spawned task runs outside
  the test's sandbox-owned process, so the sweeps are tested directly
  instead (`Pipeline.ExtraRederive`, `Library.Files.backfill_extras/0`,
  `Library.MediaInfo.probe_missing/0`). The operator-run versions of the
  same sweeps live in `MediaCentaur.Maintenance`.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Pipeline.ExtraRederive

  @type outcome :: :skipped | :started

  @doc """
  Re-derives extra display names against the current parser rules, so a
  parser-rule improvement heals records already on disk.
  """
  @spec heal_extra_names(atom()) :: outcome()
  def heal_extra_names(:test), do: :skipped

  def heal_extra_names(_env) do
    run_async(fn ->
      {:ok, summary} = ExtraRederive.rederive_all()

      if summary.updated > 0 do
        Log.info(:library, "boot re-derive healed #{summary.updated} extra name(s)")
      end
    end)
  end

  @doc """
  Creates `ExtraFile` rows for extras imported before the ingest path
  wrote them, so they become linked and stop being re-emitted by
  `rescan_unlinked`.
  """
  @spec backfill_extra_files(atom()) :: outcome()
  def backfill_extra_files(:test), do: :skipped

  def backfill_extra_files(_env) do
    run_async(fn ->
      %{created: created} = Library.Files.backfill_extras()

      if created > 0 do
        Log.info(:library, "boot ExtraFile backfill linked #{created} extra file(s)")
      end
    end)
  end

  @doc """
  Probes technical metadata (`Library.MediaProbe`) for files that have no
  `FileMediaInfo` row yet — pre-feature imports and files whose earlier
  probe failed (ADR-057).
  """
  @spec probe_media_info(atom()) :: outcome()
  def probe_media_info(:test), do: :skipped

  def probe_media_info(_env) do
    run_async(fn ->
      %{probed: probed, skipped: skipped} = Library.MediaInfo.probe_missing()

      if probed > 0 or skipped > 0 do
        Log.info(:library, "boot media-info probe filled #{probed} file(s), #{skipped} skipped")
      end
    end)
  end

  defp run_async(fun) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fun)
    :started
  end
end
