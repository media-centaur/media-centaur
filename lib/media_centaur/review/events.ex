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

  ## What changed for subscribers

  Two of these messages used to be positional 3-tuples:

      # before
      {:group_error, group_key, message}
      {:group_approved, group_key, count}

      # after
      {:group_error, %GroupError{group_key: key, message: message}}
      {:group_approved, %GroupApproved{group_key: key, count: count}}

  A positional tuple gives a subscriber no way to notice that two
  same-typed arguments were swapped at the publisher. That is the class of
  bug the structs exist to prevent, so the positional forms are gone
  rather than carried alongside.

  Map-matching still works on the payload — a struct *is* a map, so
  `%{group_key: key} = payload` destructures as before.

  Pair with the `MC0026 ReviewUpdatesContract` Credo check, which flags any
  publication of these tags outside this module.
  """

  alias MediaCentaur.Topics

  defmodule FileAdded do
    @moduledoc """
    A file entered the review queue. Subscribers holding a count re-read
    it; the review page debounces a reload.
    """
    @enforce_keys [:pending_file_id]
    defstruct [:pending_file_id]

    @type t :: %__MODULE__{pending_file_id: Ecto.UUID.t()}
  end

  defmodule FileReviewed do
    @moduledoc """
    A pending file left the queue — approved, rejected or deleted. The
    record is already gone by the time this lands, so subscribers drop the
    id rather than re-fetching it.
    """
    @enforce_keys [:pending_file_id]
    defstruct [:pending_file_id]

    @type t :: %__MODULE__{pending_file_id: Ecto.UUID.t()}
  end

  defmodule GroupApproved do
    @moduledoc """
    A whole review group was approved. `count` is how many files landed —
    the group itself is gone, so subscribers remove it wholesale.
    """
    @enforce_keys [:group_key, :count]
    defstruct [:group_key, :count]

    @type t :: %__MODULE__{group_key: String.t(), count: non_neg_integer()}
  end

  defmodule GroupError do
    @moduledoc """
    At least one file in a group failed to approve. `message` is
    user-facing copy, flashed by the review page.
    """
    @enforce_keys [:group_key, :message]
    defstruct [:group_key, :message]

    @type t :: %__MODULE__{group_key: String.t(), message: String.t()}
  end

  @type t :: FileAdded.t() | FileReviewed.t() | GroupApproved.t() | GroupError.t()

  @doc """
  Broadcast a typed event on the `review:updates` topic.

  Each clause pairs a struct with the tagged tuple subscribers match
  against. This is the *only* place the topic is published to, so adding a
  message means editing this module — a deliberate, reviewable act.
  """
  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%FileAdded{} = event), do: publish({:file_added, event})
  def broadcast(%FileReviewed{} = event), do: publish({:file_reviewed, event})
  def broadcast(%GroupApproved{} = event), do: publish({:group_approved, event})
  def broadcast(%GroupError{} = event), do: publish({:group_error, event})

  defp publish(message), do: Topics.publish(Topics.review_updates(), message)
end
