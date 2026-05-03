defmodule MediaCentarr.Acquisition.HealthHistory do
  @moduledoc """
  Per-poll bookkeeping for the throughput history map that
  `MediaCentarr.Acquisition.Health.classify/3` consumes.

  Pure module — no GenServer, no IO. Lives between
  `MediaCentarr.Acquisition.QueueMonitor` (which holds the map in its
  state and drives the polls) and `Health` (which classifies one item
  given its samples).

  ## Shape

      %{torrent_id => [{monotonic_us, size_left_bytes}, ...]}

  Samples are newest-first. Each call to `update/3` truncates samples
  older than `Health.max_window_us/0`, so the map is bounded by the
  active-torrent count × the longest classification window.

  ## Reset rules

  - **Item disappeared from the snapshot**: drop its key entirely. If
    it reappears later it's treated as a new entry — warm-up restarts.
    Acceptable: an item that vanished mid-download has likely been
    removed from the client and re-added.
  - **Backwards motion** (`size_left` increased poll-to-poll): qBit ran
    a recheck or restored bytes we'd already counted as downloaded. Can
    no longer reason about throughput across that boundary — reset
    history for that key to a single fresh sample.
  - **`size_left` is nil**: driver gave us no signal. Don't append a
    sample (would record garbage), but keep existing history (transient
    nil shouldn't lose all our throughput data).
  """

  alias MediaCentarr.Acquisition.Health
  alias MediaCentarr.Acquisition.QueueItem

  @type history :: %{(integer() | String.t()) => [Health.sample()]}

  @doc """
  Folds an active-items snapshot into the history map and attaches
  `:health` to each item.

  Returns `{new_history, items_with_health}`.
  """
  @spec update(history(), [QueueItem.t()], integer()) :: {history(), [QueueItem.t()]}
  def update(history, items, now) when is_map(history) and is_list(items) and is_integer(now) do
    history = drop_missing(history, items)
    max_window_us = Health.max_window_us()

    history =
      Enum.reduce(items, history, fn item, h ->
        record_sample(h, item, now, max_window_us)
      end)

    items_with_health =
      Enum.map(items, fn item ->
        %{item | health: Health.classify(item, Map.get(history, item.id, []), now)}
      end)

    {history, items_with_health}
  end

  defp drop_missing(history, items) do
    active_ids = MapSet.new(items, & &1.id)
    Map.filter(history, fn {id, _} -> MapSet.member?(active_ids, id) end)
  end

  defp record_sample(history, %QueueItem{size_left: nil}, _now, _window), do: history

  defp record_sample(history, %QueueItem{id: id, size_left: size_left}, now, window) do
    case Map.get(history, id, []) do
      [] ->
        Map.put(history, id, [{now, size_left}])

      [{_, prev_size_left} | _] when size_left > prev_size_left ->
        # Recheck / restoration — reset to a single fresh sample.
        Map.put(history, id, [{now, size_left}])

      samples ->
        cutoff = now - window
        kept = Enum.take_while([{now, size_left} | samples], fn {ts, _} -> ts >= cutoff end)
        Map.put(history, id, kept)
    end
  end
end
