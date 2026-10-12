defmodule MediaCentaur.Downloads.Phase do
  @moduledoc """
  Where a download-client job is on its protocol's ladder — the projection
  every surface draws a job from.

  A job moves through a short, protocol-specific ladder of steps:

    * usenet — `:fetch` (the client is pulling the NZB), `:download`,
      `:verify`, `:repair` (only while it happens; SABnzbd does not say
      afterwards whether it did), `:unpack`, `:move`, `:done`
    * torrent — `:metadata`, `:download`, `:done`

  `current` is the step under way, or nil when the job has no position
  (failed, or a state the driver could not place). `condition` qualifies
  the step — `:queued`, `:paused`, `:stalled`, `:failed` — and is not a
  step. `figure` is how far through the current step the job is, 0..1,
  or nil when the client gives no figure: the client's percentage during
  `:download`, parsed from the SABnzbd stage line in post-processing
  ("Unpacking: 45%", "Verifying: 14/56"), nil while fetching.

  Pure: derived from `QueueItem.state`, `status`, `protocol`, `progress`
  and `stage_line`, never stored. `QueueItem.state` stays the client's
  word for cancel routing, health and the status sentence; this module is
  the one place the ladder is known. A SABnzbd history "Queued" (the
  post-processing queue) and a live-queue "Queued" both arrive as
  `:queued`; both draw as the queued condition on `:download`, which
  misplaces the lit step for the seconds a job waits for post-processing
  and is accepted.
  """

  alias MediaCentaur.Downloads.QueueItem

  @type step :: :fetch | :metadata | :download | :verify | :repair | :unpack | :move | :done
  @type condition :: nil | :queued | :paused | :stalled | :failed

  @type t :: %__MODULE__{
          ladder: [step()],
          current: step() | nil,
          condition: condition(),
          figure: float() | nil
        }

  @enforce_keys [:ladder, :current, :condition, :figure]
  defstruct [:ladder, :current, :condition, :figure]

  @usenet [:fetch, :download, :verify, :unpack, :move, :done]
  @usenet_repairing [:fetch, :download, :verify, :repair, :unpack, :move, :done]
  @torrent [:metadata, :download, :done]

  @doc "Projects a queue item onto its ladder."
  @spec of(QueueItem.t()) :: t()
  def of(%QueueItem{protocol: :usenet} = item) do
    {current, condition} = usenet_position(item.state)

    %__MODULE__{
      ladder: if(current == :repair, do: @usenet_repairing, else: @usenet),
      current: current,
      condition: condition,
      figure: figure(current, item)
    }
  end

  # Both drivers set protocol; anything not usenet is a torrent.
  def of(%QueueItem{} = item) do
    {current, condition} = torrent_position(item.state, item.status)

    %__MODULE__{
      ladder: @torrent,
      current: current,
      condition: condition,
      figure: figure(current, item)
    }
  end

  defp usenet_position(:fetching_nzb), do: {:fetch, nil}
  defp usenet_position(:downloading), do: {:download, nil}
  defp usenet_position(:queued), do: {:download, :queued}
  defp usenet_position(:paused), do: {:download, :paused}
  defp usenet_position(:stalled), do: {:download, :stalled}
  defp usenet_position(:verifying), do: {:verify, nil}
  defp usenet_position(:repairing), do: {:repair, nil}
  defp usenet_position(:extracting), do: {:unpack, nil}
  defp usenet_position(:moving), do: {:move, nil}
  defp usenet_position(:completed), do: {:done, nil}
  defp usenet_position(:error), do: {nil, :failed}
  defp usenet_position(_other), do: {nil, nil}

  # qBittorrent folds the metadata fetch into `:downloading`; the raw
  # status still says which it is.
  defp torrent_position(:downloading, "metaDL"), do: {:metadata, nil}
  defp torrent_position(:downloading, _status), do: {:download, nil}
  defp torrent_position(:queued, _status), do: {:download, :queued}
  defp torrent_position(:paused, _status), do: {:download, :paused}
  defp torrent_position(:stalled, _status), do: {:download, :stalled}
  defp torrent_position(:completed, _status), do: {:done, nil}
  defp torrent_position(:error, _status), do: {nil, :failed}
  defp torrent_position(_state, _status), do: {nil, nil}

  defp figure(:download, %QueueItem{progress: pct}) when is_number(pct), do: clamp(pct / 100)
  defp figure(:done, _item), do: 1.0

  defp figure(step, %QueueItem{stage_line: line}) when step in [:verify, :repair, :unpack, :move],
    do: stage_figure(line)

  defp figure(_step, _item), do: nil

  # "Unpacking: 45%" → 0.45; "Verifying: 14/56" → 0.25; anything else → nil.
  defp stage_figure(line) when is_binary(line) do
    case Regex.run(~r/(\d+(?:\.\d+)?)\s*%\s*$/, line) do
      [_, pct] ->
        {value, _rest} = Float.parse(pct)
        clamp(value / 100)

      nil ->
        ratio_figure(line)
    end
  end

  defp stage_figure(_line), do: nil

  defp ratio_figure(line) do
    case Regex.run(~r/(\d+)\s*\/\s*(\d+)\s*$/, line) do
      [_, done, total] ->
        total = String.to_integer(total)
        if total > 0, do: clamp(String.to_integer(done) / total)

      nil ->
        nil
    end
  end

  defp clamp(value), do: value |> max(0.0) |> min(1.0)

  @doc "The word the strip shows: the condition when there is one, else the step."
  @spec word(t()) :: String.t()
  def word(%__MODULE__{condition: :queued}), do: "Queued"
  def word(%__MODULE__{condition: :paused}), do: "Paused"
  def word(%__MODULE__{condition: :stalled}), do: "Stalled"
  def word(%__MODULE__{condition: :failed}), do: "Failed"
  def word(%__MODULE__{current: :fetch}), do: "Fetching NZB"
  def word(%__MODULE__{current: :metadata}), do: "Fetching metadata"
  def word(%__MODULE__{current: :download}), do: "Downloading"
  def word(%__MODULE__{current: :verify}), do: "Verifying"
  def word(%__MODULE__{current: :repair}), do: "Repairing"
  def word(%__MODULE__{current: :unpack}), do: "Unpacking"
  def word(%__MODULE__{current: :move}), do: "Moving"
  def word(%__MODULE__{current: :done}), do: "Done"
  def word(%__MODULE__{current: nil}), do: "Unknown"

  @doc "A ladder step's name, for the hover label on its segment."
  @spec step_word(step()) :: String.t()
  def step_word(:fetch), do: "Fetch NZB"
  def step_word(:metadata), do: "Fetch metadata"
  def step_word(:download), do: "Download"
  def step_word(:verify), do: "Verify"
  def step_word(:repair), do: "Repair"
  def step_word(:unpack), do: "Unpack"
  def step_word(:move), do: "Move"
  def step_word(:done), do: "Done"

  @doc """
  Text-color class for the word (status labels are plain colored text,
  never a badge). Calm info while the client works, success when done,
  warning for a held job, error for a failed one.
  """
  @spec text_class(t()) :: String.t()
  def text_class(%__MODULE__{condition: :failed}), do: "text-error/80"
  def text_class(%__MODULE__{condition: :paused}), do: "text-warning/80"
  def text_class(%__MODULE__{condition: :stalled}), do: "text-warning/80"
  def text_class(%__MODULE__{condition: :queued}), do: "text-base-content/55"
  def text_class(%__MODULE__{current: :done}), do: "text-success/80"
  def text_class(%__MODULE__{current: nil}), do: "text-base-content/60"
  def text_class(%__MODULE__{}), do: "text-info/80"

  @doc """
  Whether the client is actively working the job: positioned, not held by
  a condition, not done. A working job with no figure earns an
  indeterminate bar so the row still reads alive.
  """
  @spec working?(t()) :: boolean()
  def working?(%__MODULE__{current: nil}), do: false
  def working?(%__MODULE__{current: :done}), do: false
  def working?(%__MODULE__{condition: nil}), do: true
  def working?(%__MODULE__{}), do: false
end
