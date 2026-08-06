defmodule MediaCentaur.SelfUpdate.History do
  @moduledoc """
  Durable log of the versions this install has run, for the Status → Updates
  drill-in's history list.

  Captured by boot-time version detection: `record_boot_version/1` appends the
  running version only when it differs from the newest recorded entry, so the
  log gains one row per actual upgrade regardless of how that upgrade happened
  (in-app "Update now", manual reinstall, or installer script). `recorded_at`
  is the boot-observation time — effectively the upgrade moment.

  Persisted via `MediaCentaur.Settings.Entry` under `update.history`, mirroring
  the rest of the SelfUpdate subsystem (no dedicated table). The list is kept
  newest-first and capped at 50 entries — a small, append-only display log.
  """

  alias MediaCentaur.Settings

  @key "update.history"
  # Keep the @moduledoc's "capped at 50 entries" in sync when changing this.
  @max_entries 50

  @type entry :: %{version: String.t(), recorded_at: DateTime.t()}

  @doc """
  Records the currently running version. Appends a new newest-first entry only
  when it differs from the most recent recorded version (or the log is empty).
  Defaults to `MediaCentaur.Version.current_version/0`; the arity-1 form exists
  for tests to drive version transitions.
  """
  @spec record_boot_version() :: :ok
  def record_boot_version, do: record_boot_version(MediaCentaur.Version.current_version())

  @spec record_boot_version(String.t()) :: :ok
  def record_boot_version(version) when is_binary(version) do
    raw = read_entries()

    case raw do
      [%{"version" => ^version} | _] ->
        :ok

      _ ->
        new_entry = %{"version" => version, "recorded_at" => DateTime.to_iso8601(DateTime.utc_now())}
        entries = Enum.take([new_entry | raw], @max_entries)
        Settings.find_or_create_entry!(%{key: @key, value: %{"entries" => entries}})
        :ok
    end
  end

  @doc "Returns the recorded versions newest-first, as `%{version, recorded_at}` maps."
  @spec list() :: [entry()]
  def list do
    read_entries()
    |> Enum.map(&decode/1)
    |> Enum.reject(&is_nil/1)
  end

  defp read_entries do
    case Settings.get_by_key(@key) do
      %{value: %{"entries" => entries}} when is_list(entries) -> entries
      _ -> []
    end
  end

  defp decode(%{"version" => version, "recorded_at" => iso})
       when is_binary(version) and is_binary(iso) do
    case MediaCentaur.Iso8601.parse(iso) do
      nil -> nil
      at -> %{version: version, recorded_at: at}
    end
  end

  defp decode(_), do: nil
end
