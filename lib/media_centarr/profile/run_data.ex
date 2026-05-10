defmodule MediaCentarr.Profile.RunData do
  @moduledoc """
  Canonical in-memory representation of a profile run (ADR-041).

  Both `MediaCentarr.Profile.JSONFormatter` and
  `MediaCentarr.Profile.MarkdownFormatter` consume this same struct.
  Keeping a single source of truth prevents the two formats from
  drifting — if you can't render it from RunData, it doesn't go in
  the report.

  ## Schema versioning

  `:schema_version` is an integer that bumps any time the JSON shape
  changes in a way that breaks downstream consumers (today: only the
  baseline-comparison logic, but future: dashboards, CI bots, etc.).
  Diff logic refuses to compare runs across different schema versions
  rather than silently mismatching fields.
  """

  @schema_version 1

  defstruct [
    :schema_version,
    :metadata,
    :microbenchmarks,
    :page_mounts,
    :ets_memory,
    :deltas
  ]

  @doc "Returns the current schema version."
  @spec schema_version() :: integer()
  def schema_version, do: @schema_version

  @doc """
  Builds a `%RunData{}` from in-memory results. ETS memory is sampled
  at build time — reflects the moment the run finished, not when the
  bench scenarios began.

  Normalises the producers' map shapes into the canonical schema
  (e.g. `:warm_cache?` from Mounts becomes `:warm_cache` so the
  JSON serialisation does not carry an Elixir-specific question mark
  into the wire format).
  """
  @spec build(map(), [map()], [map()]) :: %__MODULE__{}
  def build(metadata, bench_results, mount_results) do
    %__MODULE__{
      schema_version: @schema_version,
      metadata: serialise_metadata(metadata),
      microbenchmarks: bench_results,
      page_mounts: Enum.map(mount_results, &normalise_mount/1),
      ets_memory: sample_ets_memory(),
      deltas: nil
    }
  end

  defp normalise_mount(mount) do
    %{
      route: mount.route,
      warm_cache: Map.get(mount, :warm_cache?, false),
      runs: mount.runs,
      min_us: mount.min_us,
      p50_us: mount.p50_us,
      p95_us: mount.p95_us,
      max_us: mount.max_us
    }
  end

  @doc "Attaches a `%DeltaSet{}` (or any map) to the run's `:deltas` field."
  @spec with_deltas(%__MODULE__{}, map() | nil) :: %__MODULE__{}
  def with_deltas(%__MODULE__{} = run, deltas), do: %{run | deltas: deltas}

  defp serialise_metadata(meta) do
    %{
      run_id: meta.run_id,
      timestamp: DateTime.to_iso8601(meta.timestamp),
      scale: Atom.to_string(meta.scale),
      git_sha: meta.git_sha,
      git_branch: meta.git_branch,
      dirty: meta.dirty?,
      otp_release: meta.otp_release,
      elixir_version: meta.elixir_version,
      schedulers_online: meta.schedulers,
      cpu_count: meta.cpu_count,
      database_path: meta.database_path
    }
  end

  defp sample_ets_memory do
    :ets.all()
    |> Enum.filter(&projection_table?/1)
    |> Enum.sort_by(&table_name/1)
    |> Enum.map(fn table ->
      name = table_name(table)
      rows = :ets.info(table, :size)
      words = :ets.info(table, :memory)
      bytes = words * :erlang.system_info(:wordsize)
      %{table: name, rows: rows, bytes: bytes}
    end)
  end

  defp projection_table?(table) do
    case :ets.info(table, :name) do
      :undefined ->
        false

      name when is_atom(name) ->
        name_str = Atom.to_string(name)
        String.contains?(name_str, "_view_") or String.starts_with?(name_str, "library_view_")

      _ ->
        false
    end
  end

  defp table_name(table) do
    case :ets.info(table, :name) do
      :undefined -> ""
      name -> Atom.to_string(name)
    end
  end
end
