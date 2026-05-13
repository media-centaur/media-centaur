defmodule MediaCentarr.Downloads.QueueItem do
  @moduledoc """
  A single entry in a download client's queue.

  `status` is the raw client-supplied string (e.g. qBittorrent's
  `"downloading"`, `"pausedDL"`, `"stalledUP"`). It is kept verbatim so
  unknown values surface in the UI rather than being silently dropped.

  `state` is a normalized atom for UI grouping. Drivers map their
  client-specific status strings to one of `:downloading | :queued |
  :stalled | :paused | :completed | :error | :other`. The UI groups by
  `state` and shows the raw `status` as a tooltip / detail.

  `:queued` (qBittorrent's `queuedDL`) and `:stalled` (qBittorrent's
  `stalledDL`) are intentionally separate. `:queued` means the
  download is waiting in the client's internal queue for a slot to
  open and has not started — passive waiting. `:stalled` means the
  download is active but cannot make progress (no peers, no source) —
  needs attention.

  ## `:health`

  Orthogonal to `state`. `state` is what the download client says;
  `health` is `MediaCentarr.Downloads.Health.classify/3`'s judgement
  on whether progress is actually being made. Drivers
  (`from_qbittorrent/1`) leave it `nil` — only
  `MediaCentarr.Downloads.QueueMonitor` sets it, because
  classification needs throughput history that only the monitor has.
  """

  @enforce_keys [:id, :title]
  defstruct [
    :id,
    :title,
    :status,
    :state,
    :download_client,
    :indexer,
    :size,
    :size_left,
    :progress,
    :timeleft,
    :health,
    # Memoised normalized title — computed once at construction so the
    # render-hot pairing in `QueueMatcher.match/2` reads `Map.get/2`
    # instead of running `String.downcase/1` + a regex over every queue
    # item on every render.
    :normalized_title
  ]

  @type state :: :downloading | :queued | :stalled | :paused | :completed | :error | :other

  @type t :: %__MODULE__{
          id: integer() | String.t(),
          title: String.t(),
          status: String.t() | nil,
          state: state() | nil,
          download_client: String.t() | nil,
          indexer: String.t() | nil,
          size: integer() | nil,
          size_left: integer() | nil,
          progress: float() | nil,
          timeleft: String.t() | nil,
          health: MediaCentarr.Downloads.Health.status() | nil,
          normalized_title: String.t() | nil
        }

  @qbit_infinite_eta 8_640_000

  @doc "Builds a QueueItem from a raw qBittorrent `/api/v2/torrents/info` entry."
  @spec from_qbittorrent(map()) :: t()
  def from_qbittorrent(raw) when is_map(raw) do
    title = title_from_qbittorrent(raw["name"], raw["hash"])

    %__MODULE__{
      id: raw["hash"],
      title: title,
      status: raw["state"],
      state: state_from_qbittorrent(raw["state"]),
      download_client: "qBittorrent",
      indexer: blank_to_nil(raw["category"]),
      size: raw["size"],
      size_left: raw["amount_left"],
      progress: progress_from_qbittorrent(raw["progress"]),
      timeleft: format_eta(raw["eta"]),
      normalized_title: normalize_title(title)
    }
  end

  # Inlined normalisation — kept verbatim against
  # `MediaCentarr.Acquisition.QueueMatcher.normalize_title/1` so the
  # cached value is the same one the matcher would compute. Asserted by
  # `QueueItemTest`.
  defp normalize_title(nil), do: ""

  defp normalize_title(title) when is_binary(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "")
  end

  # qBittorrent reports `name` as the info-hash itself until torrent
  # metadata is downloaded (typically the `metaDL` state). The bare
  # hex string is meaningless to end users, so swap in a placeholder
  # until a real name arrives.
  defp title_from_qbittorrent(name, hash) when is_binary(name) and name == hash,
    do: "Fetching torrent details…"

  defp title_from_qbittorrent(name, _hash) when is_binary(name), do: name
  defp title_from_qbittorrent(_name, _hash), do: ""

  defp state_from_qbittorrent(state)
       when state in ~w(downloading metaDL forcedDL allocating checkingResumeData checkingDL),
       do: :downloading

  defp state_from_qbittorrent(state)
       when state in ~w(uploading forcedUP pausedUP queuedUP stalledUP checkingUP), do: :completed

  defp state_from_qbittorrent("pausedDL"), do: :paused
  defp state_from_qbittorrent("queuedDL"), do: :queued
  defp state_from_qbittorrent("stalledDL"), do: :stalled
  defp state_from_qbittorrent(state) when state in ~w(error missingFiles), do: :error
  defp state_from_qbittorrent(_), do: :other

  defp progress_from_qbittorrent(nil), do: nil
  # qBittorrent sometimes serialises progress as a JSON integer (0 or 1)
  # rather than a float. Coerce to float before `Float.round/2`, which
  # rejects integers in Elixir 1.19+.
  defp progress_from_qbittorrent(p) when is_number(p), do: Float.round(p * 100.0, 1)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp format_eta(nil), do: nil
  defp format_eta(@qbit_infinite_eta), do: nil
  defp format_eta(seconds) when is_integer(seconds) and seconds < 0, do: nil
  defp format_eta(seconds) when is_integer(seconds) and seconds < 60, do: "#{seconds}s"

  defp format_eta(seconds) when is_integer(seconds) and seconds < 3600 do
    "#{div(seconds, 60)}m"
  end

  defp format_eta(seconds) when is_integer(seconds) and seconds < 86_400 do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{minutes}m"
  end

  defp format_eta(seconds) when is_integer(seconds), do: "#{div(seconds, 86_400)}d"
end
