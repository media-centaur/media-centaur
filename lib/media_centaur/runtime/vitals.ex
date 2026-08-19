defmodule MediaCentaur.Runtime.Vitals do
  @moduledoc """
  A single cheap, all-in-VM snapshot of runtime health for the System status
  tile: uptime, memory/process/scheduler vitals, host/build facts (reused from
  `ErrorReports.EnvMetadata`), and the SQLite datastore footprint.

  ## Shape

      %{uptime_seconds: non_neg_integer(),
        memory: %{total: pos_integer(), processes: pos_integer(), ets: non_neg_integer(), binary: non_neg_integer()},
        process_count: pos_integer(), process_limit: pos_integer(),
        run_queue: non_neg_integer(), schedulers: pos_integer(),
        host: %{otp: String.t(), elixir: String.t(), os: String.t(), version: String.t()},
        db: %{size_bytes: non_neg_integer(), wal_bytes: non_neg_integer()}}
  """
  alias MediaCentaur.ErrorReports.EnvMetadata

  @spec snapshot() :: map()
  def snapshot do
    mem = :erlang.memory()

    %{
      uptime_seconds: uptime_seconds(),
      memory: %{
        total: mem[:total],
        processes: mem[:processes],
        ets: mem[:ets],
        binary: mem[:binary]
      },
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      run_queue: :erlang.statistics(:run_queue),
      schedulers: System.schedulers_online(),
      host: host_facts(),
      db: db_sizes()
    }
  end

  defp uptime_seconds do
    native = :erlang.monotonic_time() - :erlang.system_info(:start_time)
    System.convert_time_unit(native, :native, :second)
  end

  defp host_facts do
    meta = EnvMetadata.collect()
    %{otp: meta.otp_release, elixir: meta.elixir_version, os: meta.os, version: meta.app_version}
  end

  defp db_sizes do
    path = MediaCentaur.Settings.Config.get(:database_path)
    %{size_bytes: file_size(path), wal_bytes: file_size(wal_path(path))}
  end

  defp wal_path(nil), do: nil
  defp wal_path(path), do: path <> "-wal"

  defp file_size(nil), do: 0

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end
end
