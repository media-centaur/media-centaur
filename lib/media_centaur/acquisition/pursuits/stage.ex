defmodule MediaCentaur.Acquisition.Pursuits.Stage do
  @moduledoc """
  How far a target's download has got — the single definition of a pursuit's
  lifecycle position.

  A download moves through an ordered sequence: handed off to the download
  client, at the client, left the client, in review, in the library. The stage
  it has reached is a **durable observed fact** on the target
  (`first_seen_in_queue_at`); the live queue item only says what it is doing
  *right now*, at whatever stage it is in. Telemetry decorates a stage, it
  never defines one.

  That distinction is the whole point of this module. Absence from the queue
  snapshot is not evidence: a target the client has never shown us and one the
  client finished and dropped look identical from the snapshot alone. Before
  `first_seen_in_queue_at` existed, both read as "Finished downloading" — so a
  release flashed as complete the instant it was grabbed, and a grab that
  never arrived at the client claimed completion forever.

  ## Stages

  | Stage | Meaning |
  |---|---|
  | `:no_target` | the unit has no current target at all |
  | `:seeking` | no release picked yet |
  | `:handed_off` | Prowlarr accepted the grab (or the user picked); the client has not shown it yet |
  | `:missing` | handed off, never seen at the client, and the hand-off window has elapsed |
  | `:at_client` | visible in the client's queue right now |
  | `:in_review` | the downloaded file is waiting in the review queue |
  | `:left_client` | seen at the client before, gone now, not yet in review |
  | `:done` | the file landed and identity was verified |
  | `:failed` | the attempt gave up |
  | `:cancelled` | the attempt was cancelled |

  `:at_client` deliberately does not distinguish downloading from queued,
  stalled or post-processing — those are telemetry, read off the queue item by
  the caller.

  ## Precedence

  Evidence beats inference, strongest first: a live queue item proves
  `:at_client`; a file in review proves `:in_review`; only then does the
  first-sighting stamp separate `:left_client` from `:handed_off` /
  `:missing`. So a download fast enough to appear and vanish between two
  observation passes still reads as `:in_review` rather than falling back to
  the hand-off stages.

  `:missing` is an accusation, and it is only made when the client actually
  answered: `StatusContext.client_reachable?/1` gates it. An unreachable
  client means the snapshot's silence says nothing, so the target stays at
  `:handed_off` however long the wait.
  """

  alias MediaCentaur.Acquisition.Pursuits.StatusContext
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Downloads.QueueItem

  @type t ::
          :no_target
          | :seeking
          | :handed_off
          | :missing
          | :at_client
          | :in_review
          | :left_client
          | :done
          | :failed
          | :cancelled

  @typedoc """
  Where the target's downloaded file sits after the client is done with it.
  Resolved by `Pursuits.download_location/2` as a batched membership test, so
  it arrives here already decided.
  """
  @type location :: :in_review | :none

  @doc """
  Resolves the stage of a target.

  `queue_item` is the target's live pairing from the current queue snapshot
  (`QueueMatcher.find_item/4`), or `nil`. `location` is the post-download file
  position. The context supplies the clock, the hand-off window and whether
  the client answered — all three are consulted only for a target that has
  never been seen at the client.
  """
  @spec of(Target.t() | nil, QueueItem.t() | nil, location(), StatusContext.t()) :: t()
  def of(target, queue_item, location, context)

  def of(nil, _queue_item, _location, _context), do: :no_target

  def of(%Target{status: "seeking"}, _queue_item, _location, _context), do: :seeking
  def of(%Target{status: "succeeded"}, _queue_item, _location, _context), do: :done
  def of(%Target{status: "failed"}, _queue_item, _location, _context), do: :failed
  def of(%Target{status: "cancelled"}, _queue_item, _location, _context), do: :cancelled

  def of(%Target{status: "acquired"} = target, queue_item, location, %StatusContext{} = context) do
    cond do
      match?(%QueueItem{}, queue_item) -> :at_client
      location == :in_review -> :in_review
      match?(%DateTime{}, target.first_seen_in_queue_at) -> :left_client
      never_arrived?(target, context) -> :missing
      true -> :handed_off
    end
  end

  # Measured from the hand-off, which is what `acquired_at` stamps. A target
  # with no stamp (only reachable by a hand-written row) is treated as still
  # within the window rather than accused of never arriving, and so is every
  # target while the client is not answering.
  defp never_arrived?(_target, %StatusContext{client_reachable?: false}), do: false
  defp never_arrived?(%Target{acquired_at: nil}, _context), do: false

  defp never_arrived?(%Target{acquired_at: %DateTime{} = acquired_at}, %StatusContext{} = context),
    do: DateTime.diff(context.now, acquired_at, :second) >= context.handoff_window_minutes * 60
end
