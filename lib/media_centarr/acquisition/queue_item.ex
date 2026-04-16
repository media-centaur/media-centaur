defmodule MediaCentarr.Acquisition.QueueItem do
  @moduledoc """
  A single entry in the Prowlarr download queue.

  Built from the raw `/api/v1/queue` response. `progress` is derived from
  `size` and `size_left` at construction time so the UI does not have to
  recompute on every render.

  `status` is kept as the raw string from Prowlarr (e.g. `"downloading"`,
  `"queued"`, `"completed"`, `"warning"`, `"failed"`, `"paused"`). The UI
  decides how to present each value; we deliberately do not whitelist or
  atomize the set so a new Prowlarr status surfaces verbatim instead of
  being silently dropped.
  """

  @enforce_keys [:id, :title]
  defstruct [
    :id,
    :title,
    :status,
    :download_client,
    :indexer,
    :size,
    :size_left,
    :progress,
    :timeleft
  ]

  @type t :: %__MODULE__{
          id: integer() | String.t(),
          title: String.t(),
          status: String.t() | nil,
          download_client: String.t() | nil,
          indexer: String.t() | nil,
          size: integer() | nil,
          size_left: integer() | nil,
          progress: float() | nil,
          timeleft: String.t() | nil
        }

  @doc "Builds a QueueItem from a raw Prowlarr API queue entry."
  @spec from_prowlarr(map()) :: t()
  def from_prowlarr(raw) when is_map(raw) do
    size = raw["size"]
    size_left = raw["sizeleft"]

    %__MODULE__{
      id: raw["id"],
      title: raw["title"] || "",
      status: raw["status"],
      download_client: raw["downloadClient"],
      indexer: raw["indexer"],
      size: size,
      size_left: size_left,
      progress: compute_progress(size, size_left),
      timeleft: raw["timeleft"]
    }
  end

  defp compute_progress(nil, _), do: nil
  defp compute_progress(_, nil), do: nil
  defp compute_progress(size, _) when not is_integer(size) or size <= 0, do: nil
  defp compute_progress(_size, size_left) when not is_integer(size_left), do: nil

  defp compute_progress(size, size_left) do
    Float.round((size - size_left) / size * 100, 1)
  end
end
