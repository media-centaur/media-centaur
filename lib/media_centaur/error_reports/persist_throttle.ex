defmodule MediaCentaur.ErrorReports.PersistThrottle do
  @moduledoc """
  Per-fingerprint debounce for durable writes — pure data structure, no process.

  Under an error storm, the same fingerprint can fire hundreds of times a
  second. Persisting each occurrence would flood the single SQLite writer (and,
  if the DB itself is the failing subsystem, pile writes onto a struggling
  connection). This throttle collapses a burst of one fingerprint into roughly
  one durable write per window: the first occurrence persists immediately; the
  rest are coalesced into a pending count that `flush_due/3` emits later as a
  single write bumping the incident by the accumulated `occurrences`.

  Count stays accurate — the live in-memory cache still counts every occurrence,
  and the durable incident converges to it on each flush (it only lags by up to
  one window). The raw event log becomes *sampled* under load (one row per
  window per fingerprint), which is the desirable behaviour — not a thousand
  identical rows.
  """
  alias MediaCentaur.Console.Entry

  @type t :: %{
          last: %{optional(binary()) => integer()},
          pending: %{optional(binary()) => {Entry.t(), pos_integer()}}
        }

  @spec new() :: t()
  def new, do: %{last: %{}, pending: %{}}

  @doc """
  Records an occurrence of `fingerprint` at `now_ms`.

  Returns `{:persist_now, state}` when the fingerprint hasn't been durably
  written within `window_ms` (the caller should persist it immediately), or
  `{:defer, state}` when it has — the occurrence is coalesced into a pending
  count for the next `flush_due/3`.
  """
  @spec record(t(), binary(), Entry.t(), integer(), pos_integer()) :: {:persist_now | :defer, t()}
  def record(state, fingerprint, entry, now_ms, window_ms) do
    last = Map.get(state.last, fingerprint)

    if is_nil(last) or now_ms - last >= window_ms do
      {:persist_now, %{state | last: Map.put(state.last, fingerprint, now_ms)}}
    else
      pending =
        Map.update(state.pending, fingerprint, {entry, 1}, fn {_entry, delta} -> {entry, delta + 1} end)

      {:defer, %{state | pending: pending}}
    end
  end

  @doc """
  Returns the deferred writes due now — `{entry, occurrences}` per fingerprint —
  paired with a reset state: pending cleared, `last` advanced for the flushed
  fingerprints, and `last` pruned of any fingerprint idle longer than
  `window_ms` (so the map stays bounded by recently-active fingerprints).
  """
  @spec flush_due(t(), integer(), pos_integer()) :: {[{Entry.t(), pos_integer()}], t()}
  def flush_due(state, now_ms, window_ms) do
    writes = Enum.map(state.pending, fn {_fingerprint, {entry, delta}} -> {entry, delta} end)

    flushed_at = Map.new(state.pending, fn {fingerprint, _} -> {fingerprint, now_ms} end)

    last =
      state.last
      |> Map.merge(flushed_at)
      |> Map.reject(fn {_fingerprint, ts} -> now_ms - ts >= window_ms end)

    {writes, %{state | pending: %{}, last: last}}
  end
end
