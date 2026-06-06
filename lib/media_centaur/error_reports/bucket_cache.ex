defmodule MediaCentaur.ErrorReports.BucketCache do
  @moduledoc """
  Pure, process-free projection logic for the bucket cache.

  Holds the in-memory map of `fingerprint => %Bucket{}` that
  `MediaCentaur.ErrorReports.Buckets` serves, and all the grouping rules:
  fingerprinting an entry, incrementing counts, capping samples, capping the
  working set, and ordering for display. No DB, no PubSub, no GenServer — so
  every rule here is unit-tested synchronously (`async: true`), and the
  GenServer is left as thin wiring (ADR-030).

  The cache is a *projection*: the durable store is the source of truth, and
  `from_incidents/1` rebuilds the cache from it on boot. `put_entry/2` keeps the
  cache live between rebuilds as new entries arrive.
  """
  alias MediaCentaur.Console.Entry
  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaur.ErrorReports.Fingerprint

  @max_sample_entries 5
  @max_active_buckets 200

  @type t :: %{optional(binary()) => Bucket.t()}

  @doc "Most-recently-active buckets held as the working set."
  @spec max_active_buckets() :: pos_integer()
  def max_active_buckets, do: @max_active_buckets

  @doc "Redacted samples retained per bucket."
  @spec max_sample_entries() :: pos_integer()
  def max_sample_entries, do: @max_sample_entries

  @doc "An empty cache."
  @spec new() :: t()
  def new, do: %{}

  @doc """
  Builds a cache from durable incidents and their pre-fetched samples. Incidents
  without a fingerprint (`:subsystem`/`:user`) are skipped — those don't bucket.
  """
  @spec from_incidents([{struct(), [Bucket.sample_entry()]}]) :: t()
  def from_incidents(incident_samples) do
    incident_samples
    |> Enum.filter(fn {incident, _samples} -> incident.fingerprint end)
    |> Map.new(fn {incident, samples} ->
      {incident.fingerprint, Bucket.from_incident(incident, samples)}
    end)
  end

  @doc """
  Folds a captured `%Entry{}` into the cache: opens a new bucket or bumps the
  existing one for the entry's fingerprint, then enforces the working-set cap.
  """
  @spec put_entry(t(), Entry.t()) :: t()
  def put_entry(cache, %Entry{} = entry) do
    %{key: fingerprint, display_title: title, normalized_message: normalized} =
      Fingerprint.fingerprint(entry.component, entry.message)

    sample = %{timestamp: entry.timestamp, message: normalized}

    bucket =
      case Map.get(cache, fingerprint) do
        nil ->
          %Bucket{
            fingerprint: fingerprint,
            component: entry.component,
            normalized_message: normalized,
            display_title: title,
            severity: severity_for(entry.level),
            count: 1,
            first_seen: entry.timestamp,
            last_seen: entry.timestamp,
            sample_entries: [sample]
          }

        %Bucket{} = existing ->
          %{
            existing
            | count: existing.count + 1,
              last_seen: max_dt(existing.last_seen, entry.timestamp),
              first_seen: min_dt(existing.first_seen, entry.timestamp),
              sample_entries: Enum.take([sample | existing.sample_entries], @max_sample_entries)
          }
      end

    cache
    |> Map.put(fingerprint, bucket)
    |> enforce_cap()
  end

  @doc "The bucket for a fingerprint, or `nil`."
  @spec get(t(), binary()) :: Bucket.t() | nil
  def get(cache, fingerprint), do: Map.get(cache, fingerprint)

  @doc "Removes a bucket by fingerprint (the projection side of a dismiss). No-op if absent."
  @spec delete(t(), binary()) :: t()
  def delete(cache, fingerprint), do: Map.delete(cache, fingerprint)

  @doc "Buckets ordered newest-active first."
  @spec to_list(t()) :: [Bucket.t()]
  def to_list(cache) do
    cache
    |> Map.values()
    |> Enum.sort_by(& &1.last_seen, {:desc, DateTime})
  end

  # Severity tracks the captured level; `:critical` is reserved for subsystem
  # faults (not produced by `:log` capture).
  defp severity_for(:error), do: :error
  defp severity_for(:warning), do: :warning

  defp enforce_cap(cache) when map_size(cache) <= @max_active_buckets, do: cache

  defp enforce_cap(cache) do
    {drop_key, _} =
      Enum.min_by(cache, fn {_, bucket} ->
        DateTime.to_unix(bucket.last_seen, :microsecond)
      end)

    Map.delete(cache, drop_key)
  end

  defp max_dt(a, b), do: if(DateTime.after?(a, b), do: a, else: b)
  defp min_dt(a, b), do: if(DateTime.before?(a, b), do: a, else: b)
end
