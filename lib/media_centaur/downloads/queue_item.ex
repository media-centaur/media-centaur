defmodule MediaCentaur.Downloads.QueueItem do
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
  `health` is `MediaCentaur.Downloads.Health.classify/3`'s judgement
  on whether progress is actually being made. Drivers
  (`from_qbittorrent/1`) leave it `nil` — only
  `MediaCentaur.Downloads.QueueMonitor` sets it, because
  classification needs throughput history that only the monitor has.
  """

  @enforce_keys [:id, :title]
  defstruct [
    :id,
    :title,
    :status,
    :state,
    # `:torrent | :usenet` — which protocol slot's client owns this item.
    # Cancel routing and per-client queue merging key off this.
    :protocol,
    :download_client,
    :indexer,
    :size,
    :size_left,
    :progress,
    :timeleft,
    :health,
    # Terminal failure detail from the client (SABnzbd's `fail_message`,
    # e.g. "Repair failed, not enough repair blocks"). Nil for torrents —
    # qBittorrent expresses failure only as a state.
    :failure_message,
    # On-disk path the download lands at (qBittorrent's `content_path`):
    # the file for a single-file torrent, the folder for a multi-file one.
    # Captured onto the pursuit's Target so the lifecycle stage can be
    # resolved by exact path against the review / library tables.
    :content_path,
    # Memoised normalized title — computed once at construction so the
    # render-hot pairing in `QueueMatcher.match/2` reads `Map.get/2`
    # instead of running `String.downcase/1` + a regex over every queue
    # item on every render.
    :normalized_title
  ]

  @type state ::
          :downloading
          | :fetching_nzb
          | :queued
          | :stalled
          | :paused
          | :verifying
          | :repairing
          | :extracting
          | :moving
          | :completed
          | :error
          | :other

  @type t :: %__MODULE__{
          id: integer() | String.t(),
          title: String.t(),
          status: String.t() | nil,
          state: state() | nil,
          protocol: :torrent | :usenet | nil,
          download_client: String.t() | nil,
          indexer: String.t() | nil,
          size: integer() | nil,
          size_left: integer() | nil,
          progress: float() | nil,
          timeleft: String.t() | nil,
          health: MediaCentaur.Downloads.Health.status() | nil,
          failure_message: String.t() | nil,
          content_path: String.t() | nil,
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
      protocol: :torrent,
      download_client: "qBittorrent",
      indexer: blank_to_nil(raw["category"]),
      size: raw["size"],
      size_left: raw["amount_left"],
      progress: progress_from_qbittorrent(raw["progress"]),
      timeleft: format_eta(raw["eta"]),
      content_path: blank_to_nil(raw["content_path"]),
      normalized_title: normalize_title(title)
    }
  end

  @doc """
  Builds a QueueItem from a raw SABnzbd `mode=queue` slot.

  Live queue slots never carry `content_path` — the final media file
  only exists after post-processing, so the path is captured from the
  history entry's `storage` field once the job completes (see
  `from_sabnzbd_history/1`). Pinning the incomplete-dir path here would
  hand the pursuit lifecycle an obfuscated temp path.

  SABnzbd serialises `mb`/`mbleft`/`percentage` as strings; parsing is
  tolerant of both strings and numbers.
  """
  @spec from_sabnzbd_queue(map()) :: t()
  def from_sabnzbd_queue(raw) when is_map(raw) do
    title = raw["filename"] || ""

    %__MODULE__{
      id: raw["nzo_id"],
      title: title,
      status: raw["status"],
      state: state_from_sabnzbd_queue(raw["status"]),
      protocol: :usenet,
      download_client: "SABnzbd",
      indexer: blank_to_nil(raw["cat"]),
      size: megabytes_to_bytes(raw["mb"]),
      size_left: megabytes_to_bytes(raw["mbleft"]),
      progress: parse_progress_percent(raw["percentage"]),
      timeleft: blank_to_nil(raw["timeleft"]),
      normalized_title: normalize_title(title)
    }
  end

  @doc """
  Builds a QueueItem from a raw SABnzbd `mode=history` slot.

  Usenet completion is read from history, not the live queue: only a
  `Completed` entry carries a usable `storage` path (`content_path`).
  Non-terminal post-processing phases (`Verifying`/`Repairing`/
  `Extracting`) map to their own states so the UI can say "Repairing…"
  instead of looking stalled; `Failed` maps to `:error` and keeps the
  client's `fail_message` as `failure_message`.
  """
  @spec from_sabnzbd_history(map()) :: t()
  def from_sabnzbd_history(raw) when is_map(raw) do
    title = raw["name"] || ""
    state = state_from_sabnzbd_history(raw["status"])

    %__MODULE__{
      id: raw["nzo_id"],
      title: title,
      status: raw["status"],
      state: state,
      protocol: :usenet,
      download_client: "SABnzbd",
      indexer: blank_to_nil(raw["category"]),
      size: raw["bytes"],
      size_left: if(state == :completed, do: 0),
      progress: if(state == :completed, do: 100.0),
      failure_message: if(state == :error, do: blank_to_nil(raw["fail_message"])),
      content_path: if(state == :completed, do: blank_to_nil(raw["storage"])),
      normalized_title: normalize_title(title)
    }
  end

  defp state_from_sabnzbd_queue("Downloading"), do: :downloading

  # "Grabbing" is SABnzbd fetching the .nzb from the indexer — the content
  # download has not started, so it must NOT read as :downloading. Its own
  # state lets the UI say "Fetching NZB…" instead of claiming a download
  # (with a meaningless percentage) before a byte of media has moved.
  defp state_from_sabnzbd_queue("Grabbing"), do: :fetching_nzb

  # "Fetching" is SABnzbd pulling extra par2 blocks to repair a damaged
  # download — a repair-phase activity, mapped alongside the history-side
  # :repairing phase rather than looking like fresh content download.
  defp state_from_sabnzbd_queue("Fetching"), do: :repairing

  defp state_from_sabnzbd_queue(status) when status in ~w(Queued Propagating), do: :queued
  defp state_from_sabnzbd_queue("Paused"), do: :paused
  defp state_from_sabnzbd_queue(_), do: :other

  defp state_from_sabnzbd_history("Completed"), do: :completed
  defp state_from_sabnzbd_history("Failed"), do: :error
  defp state_from_sabnzbd_history("Verifying"), do: :verifying
  defp state_from_sabnzbd_history("Repairing"), do: :repairing
  defp state_from_sabnzbd_history("Extracting"), do: :extracting
  # Moving = relocating the finished job to its destination. Minutes-long
  # for a large file crossing mounts (a 58 GB remux is a full copy across
  # docker bind mounts), so it earns its own state instead of :other.
  defp state_from_sabnzbd_history("Moving"), do: :moving
  defp state_from_sabnzbd_history("Queued"), do: :queued
  defp state_from_sabnzbd_history(_), do: :other

  defp megabytes_to_bytes(mb) when is_binary(mb) do
    case Float.parse(mb) do
      {megabytes, _rest} -> round(megabytes * 1_048_576)
      :error -> nil
    end
  end

  defp megabytes_to_bytes(mb) when is_number(mb), do: round(mb * 1_048_576)
  defp megabytes_to_bytes(_), do: nil

  defp parse_progress_percent(percentage) when is_binary(percentage) do
    case Float.parse(percentage) do
      {percent, _rest} -> percent
      :error -> nil
    end
  end

  defp parse_progress_percent(percentage) when is_number(percentage), do: percentage * 1.0
  defp parse_progress_percent(_), do: nil

  # Inlined normalisation — kept verbatim against
  # `MediaCentaur.Acquisition.Pursuits.Identity.normalize_title/1` so the
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
