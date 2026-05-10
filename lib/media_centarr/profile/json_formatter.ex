defmodule MediaCentarr.Profile.JSONFormatter do
  @moduledoc """
  Encodes a `MediaCentarr.Profile.RunData` to canonical JSON.

  This is the machine-readable counterpart of
  `MediaCentarr.Profile.MarkdownFormatter`. The shape is stable:
  bumping `RunData.schema_version/0` is the contract for any
  field rename, removal, or type change.

  ## Shape

      {
        "schema_version": 1,
        "metadata": { run_id, timestamp, scale, git_sha, ... },
        "microbenchmarks": [ { suite, runs: [ { input, scenarios: [...] } ] } ],
        "page_mounts":     [ { route, warm_cache, runs, min_us, p50_us, p95_us, max_us } ],
        "ets_memory":      [ { table, rows, bytes } ],
        "deltas":          null | { compared_against, thresholds, metrics: [...], summary }
      }

  Atom values (e.g. `:small`, `:stable`, `:REGRESSION`) are
  serialised as strings; classification atoms keep their case so
  the JSON consumer can split on uppercase = highlighted.
  """

  alias MediaCentarr.Profile.RunData

  # Mirrored at compile time so we can pattern-match on the schema
  # version in a guard. RunData is the source of truth — bump there
  # and recompile this module.
  @schema_version RunData.schema_version()

  @doc "Encodes a RunData snapshot as pretty-printed JSON iodata."
  @spec encode(%RunData{}) :: iodata()
  def encode(%RunData{} = run) do
    run
    |> to_jsonable()
    |> Jason.encode_to_iodata!(pretty: true)
  end

  @doc "Encodes as JSON and returns the binary string."
  @spec encode!(%RunData{}) :: String.t()
  def encode!(%RunData{} = run), do: run |> encode() |> IO.iodata_to_binary()

  @doc """
  Decodes a JSON binary or iodata back into a `%RunData{}`.
  Used by the Mix task to load a baseline file before diffing.
  Returns `{:error, reason}` on malformed input or schema drift.
  """
  @spec decode(binary() | iodata()) :: {:ok, %RunData{}} | {:error, term()}
  def decode(json) do
    with {:ok, decoded} <- Jason.decode(json) do
      from_jsonable(decoded)
    end
  end

  # ---- Encoding -----------------------------------------------------------

  defp to_jsonable(%RunData{} = run) do
    %{
      schema_version: run.schema_version,
      metadata: run.metadata,
      microbenchmarks: Enum.map(run.microbenchmarks, &serialise_suite/1),
      page_mounts: run.page_mounts,
      ets_memory: run.ets_memory,
      deltas: serialise_deltas(run.deltas)
    }
  end

  defp serialise_suite(%{suite: name, runs: runs}) do
    %{suite: name, runs: Enum.map(runs, &serialise_input_run/1)}
  end

  defp serialise_input_run(%{input: input, scenarios: scenarios}) do
    %{input: input, scenarios: Enum.map(scenarios, &serialise_scenario/1)}
  end

  defp serialise_scenario(%{name: name, stats: stats, memory: memory}) do
    %{name: name, stats: stats, memory_bytes: memory}
  end

  defp serialise_deltas(nil), do: nil

  defp serialise_deltas(%{} = deltas) do
    %{
      compared_against: deltas.compared_against,
      thresholds: deltas.thresholds,
      metrics: Enum.map(deltas.metrics, &serialise_metric/1),
      summary: serialise_summary(deltas.summary)
    }
  end

  defp serialise_metric(metric) do
    Map.update(metric, :classification, nil, &Atom.to_string/1)
  end

  defp serialise_summary(summary) do
    Map.new(summary, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end

  # ---- Decoding -----------------------------------------------------------

  defp from_jsonable(%{"schema_version" => version} = map) when version == @schema_version do
    {:ok,
     %RunData{
       schema_version: version,
       metadata: atomize_metadata(map["metadata"]),
       microbenchmarks: Enum.map(map["microbenchmarks"], &deserialise_suite/1),
       page_mounts: Enum.map(map["page_mounts"], &atomize_mount/1),
       ets_memory: Enum.map(map["ets_memory"], &atomize_ets_row/1),
       deltas: deserialise_deltas(map["deltas"])
     }}
  end

  defp from_jsonable(%{"schema_version" => version}),
    do: {:error, {:schema_mismatch, found: version, expected: @schema_version}}

  defp from_jsonable(_), do: {:error, :malformed_json}

  defp atomize_metadata(meta) do
    %{
      run_id: meta["run_id"],
      timestamp: meta["timestamp"],
      scale: meta["scale"],
      git_sha: meta["git_sha"],
      git_branch: meta["git_branch"],
      dirty: meta["dirty"],
      otp_release: meta["otp_release"],
      elixir_version: meta["elixir_version"],
      schedulers_online: meta["schedulers_online"],
      cpu_count: meta["cpu_count"],
      database_path: meta["database_path"]
    }
  end

  defp deserialise_suite(%{"suite" => name, "runs" => runs}) do
    %{
      suite: name,
      runs:
        Enum.map(runs, fn %{"input" => input, "scenarios" => scenarios} ->
          %{input: input, scenarios: Enum.map(scenarios, &deserialise_scenario/1)}
        end)
    }
  end

  defp deserialise_scenario(%{"name" => name, "stats" => stats} = scenario) do
    %{
      name: name,
      stats: atomize_stats(stats),
      memory: scenario["memory_bytes"]
    }
  end

  defp atomize_stats(stats) do
    %{
      ips: stats["ips"],
      average_ns: stats["average_ns"],
      median_ns: stats["median_ns"],
      p99_ns: stats["p99_ns"],
      min_ns: stats["min_ns"],
      max_ns: stats["max_ns"],
      sample_size: stats["sample_size"]
    }
  end

  defp atomize_mount(mount) do
    %{
      route: mount["route"],
      warm_cache: mount["warm_cache"],
      runs: mount["runs"],
      min_us: mount["min_us"],
      p50_us: mount["p50_us"],
      p95_us: mount["p95_us"],
      max_us: mount["max_us"]
    }
  end

  defp atomize_ets_row(row) do
    %{table: row["table"], rows: row["rows"], bytes: row["bytes"]}
  end

  defp deserialise_deltas(nil), do: nil

  defp deserialise_deltas(deltas) do
    %{
      compared_against: deltas["compared_against"],
      thresholds: deltas["thresholds"],
      metrics: Enum.map(deltas["metrics"], &deserialise_metric/1),
      summary: deltas["summary"]
    }
  end

  defp deserialise_metric(metric) do
    metric
    |> Map.update("classification", nil, &String.to_existing_atom/1)
    |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
  end
end
