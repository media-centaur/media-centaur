defmodule MediaCentarr.Acquisition.QueueItem do
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
  `health` is `MediaCentarr.Acquisition.Health.classify/3`'s judgement
  on whether progress is actually being made. Drivers
  (`from_qbittorrent/1`) leave it `nil` — only
  `MediaCentarr.Acquisition.QueueMonitor` sets it, because
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
    :health
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
          health: MediaCentarr.Acquisition.Health.status() | nil
        }

  @qbit_infinite_eta 8_640_000

  @doc "Builds a QueueItem from a raw qBittorrent `/api/v2/torrents/info` entry."
  @spec from_qbittorrent(map()) :: t()
  def from_qbittorrent(raw) when is_map(raw) do
    %__MODULE__{
      id: raw["hash"],
      title: raw["name"] || "",
      status: raw["state"],
      state: state_from_qbittorrent(raw["state"]),
      download_client: "qBittorrent",
      indexer: blank_to_nil(raw["category"]),
      size: raw["size"],
      size_left: raw["amount_left"],
      progress: progress_from_qbittorrent(raw["progress"]),
      timeleft: format_eta(raw["eta"])
    }
  end

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
