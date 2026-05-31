defmodule MediaCentaur.ErrorReports.ContextSnapshot do
  @moduledoc """
  Assembles the **frozen context snapshot** captured at incident time — the
  cross-subsystem evidence a report is built from (D11).

  The returned map is JSON-safe (string keys, primitive values, ISO8601
  timestamps) so it round-trips cleanly through an incident's `first_context` /
  `latest_context` `:map` column. It contains:

  - `lead_up` — the tail of the volatile Console buffer at this instant, every
    line re-run through the `Redactor`, with lines that share a triggering id
    flagged `correlated` (the causal chain, D13).
  - `vitals` — every registered subsystem's `vitals/0`, gathered concurrently
    and defensively (a dead subsystem records `"unavailable"`).
  - `contributor` — the firing subsystem's `gather/1` for the triggering ids.
  - `triggering_ids` — the ids the incident fired with (kept; the Redactor
    strips titles/paths from the surrounding text, not these).
  - `crash_reason` — when present in metadata.

  Pure given its inputs: the Console buffer slice and the contributor registry
  are injectable, so assembly is unit-tested without booting anything.

  > Contributor and vitals maps must be JSON-serialisable — that is the
  > `IncidentContext` implementer's contract.
  """
  alias MediaCentaur.Console.Buffer
  alias MediaCentaur.Console.Entry
  alias MediaCentaur.ErrorReports.Contributors
  alias MediaCentaur.ErrorReports.Redactor

  @lead_up_lines 50

  @doc """
  Builds the snapshot for `component` and `triggering_ids`.

  Options (all injectable for testing):
    - `:buffer_entries` — the lead-up `%Console.Entry{}` list (default: the live
      buffer tail).
    - `:registry` — the contributor registry (default: configured).
    - `:crash_reason` — crash reason string, if any.
  """
  @spec assemble(atom(), map(), keyword()) :: map()
  def assemble(component, triggering_ids, opts \\ []) do
    buffer_entries = Keyword.get_lazy(opts, :buffer_entries, fn -> Buffer.recent(@lead_up_lines) end)
    registry = Keyword.get_lazy(opts, :registry, &Contributors.registry/0)
    id_values = triggering_ids |> Map.values() |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == ""))

    %{
      "lead_up" => Enum.map(buffer_entries, &lead_up_line(&1, id_values)),
      "vitals" => Contributors.all_vitals(registry),
      "contributor" => Contributors.gather(component, triggering_ids, registry),
      "triggering_ids" => Map.new(triggering_ids, fn {key, value} -> {to_string(key), value} end),
      "crash_reason" => Keyword.get(opts, :crash_reason)
    }
  end

  defp lead_up_line(%Entry{} = entry, id_values) do
    %{
      "ts" => DateTime.to_iso8601(entry.timestamp),
      "level" => to_string(entry.level),
      "component" => to_string(entry.component),
      "message" => Redactor.normalize(entry.message),
      "correlated" => Enum.any?(id_values, &String.contains?(entry.message, &1))
    }
  end
end
