defmodule MediaCentaur.Review.Events do
  @moduledoc """
  Typed payloads for messages broadcast on the `review:updates` topic.

  The worked example for [ADR-060](../../../decisions/architecture/2026-08-06-060-event-publication-idiom.md):
  a topic with a closed message set gets one `events.ex` in the owning
  context, a struct per message with `@enforce_keys`, and a single
  `broadcast/1` whose heads enumerate the set. Same shape as
  `MediaCentaur.Library.Events` and `MediaCentaur.Playback.Events` — and
  deliberately *not* the shape of `Acquisition.Pursuits.Events`, whose 20
  files buy database persistence and replay, not payload typing.

  One message per way an item changes:

    * `FileAdded` — entered the queue, or returned to it as `:pending`;
    * `FilesApproved` — approved, now importing;
    * `FileReviewed` — left the queue.

  Pair with the `MC0026 ReviewUpdatesContract` Credo check, which flags any
  publication of these tags outside this module.
  """

  alias MediaCentaur.Topics

  defmodule FileAdded do
    @moduledoc """
    A file entered the review queue, or returned to it as `:pending` (the
    library did not link it, or startup recovery reopened it). Subscribers
    holding a count re-read it; the review page debounces a reload.
    """
    @enforce_keys [:pending_file_id]
    defstruct [:pending_file_id]

    @type t :: %__MODULE__{pending_file_id: Ecto.UUID.t()}
  end

  defmodule FilesApproved do
    @moduledoc """
    Files were approved and their matches sent to Import. They stay in the
    queue, importing, until the library reports each one's link outcome.
    """
    @enforce_keys [:pending_file_ids]
    defstruct [:pending_file_ids]

    @type t :: %__MODULE__{pending_file_ids: [Ecto.UUID.t()]}
  end

  defmodule FileReviewed do
    @moduledoc """
    A pending file left the queue — linked, parked for episode mapping,
    dismissed, deleted or removed from disk. The record may already be gone
    by the time this lands, so subscribers drop the id rather than
    re-fetching it.
    """
    @enforce_keys [:pending_file_id]
    defstruct [:pending_file_id]

    @type t :: %__MODULE__{pending_file_id: Ecto.UUID.t()}
  end

  @type t :: FileAdded.t() | FilesApproved.t() | FileReviewed.t()

  @doc """
  Broadcast a typed event on the `review:updates` topic.

  Each clause pairs a struct with the tagged tuple subscribers match
  against. This is the *only* place the topic is published to, so adding a
  message means editing this module — a deliberate, reviewable act.
  """
  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%FileAdded{} = event), do: publish({:file_added, event})
  def broadcast(%FilesApproved{} = event), do: publish({:files_approved, event})
  def broadcast(%FileReviewed{} = event), do: publish({:file_reviewed, event})

  defp publish(message), do: Topics.publish(Topics.review_updates(), message)
end
