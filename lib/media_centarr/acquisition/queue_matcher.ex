defmodule MediaCentarr.Acquisition.QueueMatcher do
  @moduledoc """
  Pairs pursuit rows with their currently-matched download-client queue
  items by normalized title.

  The Downloads index renders pursuits with their live download nested
  inside each card. `@pursuit_rows` (DB-backed, refreshed on pursuit
  PubSub) and `@active_queue` (PubSub-backed, refreshed on every
  `QueueMonitor` snapshot) are independent assigns; `match/2` is a pure
  per-render helper that joins them without a DB roundtrip.

  Matching key is `PursuitRow.release_title` against `QueueItem.title`,
  both passed through `normalize_title/1` (lowercase, non-alphanumeric
  stripped). On duplicate normalized titles across rows, the first row
  in the input list wins — deterministic in `list_active_rows/0`'s
  `updated_at desc` order.
  """

  alias MediaCentarr.Acquisition.ViewModels.{DownloadProgress, PursuitRow, PursuitWithDownload}
  alias MediaCentarr.Downloads.QueueItem

  @doc """
  Pairs rows with queue items by normalized title.

  Returns `{paired, orphans}` where `paired` preserves the input row
  order with `download` and `queue_item_id` filled in when a match
  exists, and `orphans` is the list of queue items no row claimed.
  """
  @spec match([PursuitRow.t()], [QueueItem.t()]) ::
          {[PursuitWithDownload.t()], [QueueItem.t()]}
  def match(rows, queue) when is_list(rows) and is_list(queue) do
    queue_by_norm =
      Enum.reduce(queue, %{}, fn %QueueItem{} = qi, acc ->
        Map.put_new(acc, normalize_title(qi.title), qi)
      end)

    {paired_rev, claimed_ids} =
      Enum.reduce(rows, {[], MapSet.new()}, fn %PursuitRow{} = row, {acc, claimed} ->
        case match_for_row(row, queue_by_norm, claimed) do
          {qi, claimed} ->
            entry = %PursuitWithDownload{
              row: row,
              download: to_download(qi),
              queue_item_id: qi && qi.id
            }

            {[entry | acc], claimed}
        end
      end)

    orphans = Enum.reject(queue, fn %QueueItem{id: id} -> MapSet.member?(claimed_ids, id) end)

    {Enum.reverse(paired_rev), orphans}
  end

  defp match_for_row(%PursuitRow{release_title: nil}, _by_norm, claimed), do: {nil, claimed}

  defp match_for_row(%PursuitRow{release_title: title}, by_norm, claimed) do
    normalized = normalize_title(title)

    case Map.get(by_norm, normalized) do
      %QueueItem{id: id} = qi ->
        if MapSet.member?(claimed, id) do
          {nil, claimed}
        else
          {qi, MapSet.put(claimed, id)}
        end

      nil ->
        {nil, claimed}
    end
  end

  @doc "Normalizes a title for matching — lowercased, non-alphanumeric stripped."
  @spec normalize_title(String.t() | nil) :: String.t()
  def normalize_title(nil), do: ""

  def normalize_title(title) when is_binary(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "")
  end

  @doc "Wraps a `QueueItem` into the `DownloadProgress` VM consumed by the row footer."
  @spec to_download(QueueItem.t() | nil) :: DownloadProgress.t() | nil
  def to_download(nil), do: nil

  def to_download(%QueueItem{} = qi) do
    %DownloadProgress{
      state: qi.state,
      progress_pct: progress_pct(qi.progress),
      size_bytes: qi.size,
      size_left_bytes: qi.size_left,
      eta: qi.timeleft,
      client: qi.download_client
    }
  end

  defp progress_pct(nil), do: nil
  defp progress_pct(p) when is_number(p), do: p * 100.0
end
