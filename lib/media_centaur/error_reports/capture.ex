defmodule MediaCentaur.ErrorReports.Capture do
  @moduledoc """
  Turns a volatile Console `%Entry{}` into durable rows.

  This is the synchronous heart of `:log`-origin capture, kept as a plain
  function (not a process) so it runs in — and is tested in — the caller's
  process under the SQLite sandbox. The subscribing GenServer (`Buckets`) is a
  thin wrapper that hands each `warning`/`error` entry here; a slow or failing
  write is the wrapper's problem to rescue, never the logger's.

  Capture only persists `warning`/`error` (debug/info are volatile-only). The
  stored `message` is the `Redactor`-normalized form — never the raw line — and
  `metadata` is pruned to scalar values, so a persisted event carries no file
  names, titles, or non-serialisable terms.
  """
  alias MediaCentaur.Console.Entry
  alias MediaCentaur.ErrorReports.EnvMetadata
  alias MediaCentaur.ErrorReports.Fingerprint
  alias MediaCentaur.ErrorReports.Store
  alias MediaCentaur.Repo

  @captured_levels [:warning, :error]

  @doc """
  Persists `entry` as a diagnostic event and opens/bumps its `:log` incident,
  in a single transaction.

  Returns `{:ok, incident}` when captured, `:ignored` for non-captured levels,
  or `{:error, reason}` if persistence fails.
  """
  @spec persist_entry(Entry.t()) :: {:ok, map()} | :ignored | {:error, term()}
  def persist_entry(%Entry{level: level} = entry) when level in @captured_levels do
    %{key: fingerprint, normalized_message: message, display_title: display_title} =
      Fingerprint.fingerprint(entry.component, entry.message)

    event_attrs = %{
      fingerprint: fingerprint,
      component: to_string(entry.component),
      level: level,
      message: message,
      module: entry.module && to_string(entry.module),
      metadata: scalar_metadata(entry.metadata),
      occurred_at: entry.timestamp
    }

    incident_attrs = %{
      fingerprint: fingerprint,
      component: to_string(entry.component),
      message: message,
      display_title: display_title,
      severity: severity_for(level),
      occurred_at: entry.timestamp,
      app_version_at_first: EnvMetadata.app_version()
    }

    Repo.transact(fn ->
      with {:ok, _event} <- Store.insert_event(event_attrs) do
        Store.upsert_log_incident(incident_attrs)
      end
    end)
  end

  def persist_entry(%Entry{}), do: :ignored

  # Severity tracks the log level; `:critical` is reserved for subsystem faults.
  defp severity_for(:error), do: :error
  defp severity_for(:warning), do: :warning

  # Keep only scalar metadata (ids, counts, flags); drop pids, refs, tuples, and
  # nested terms that can't be serialised or might leak detail. Keys stringified
  # for stable JSON round-tripping.
  defp scalar_metadata(metadata) when is_map(metadata) do
    metadata
    |> Enum.filter(fn {_key, value} -> scalar?(value) end)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp scalar_metadata(_), do: %{}

  defp scalar?(value) when is_binary(value) or is_number(value) or is_boolean(value), do: true
  defp scalar?(value) when is_atom(value), do: not is_nil(value)
  defp scalar?(_), do: false
end
