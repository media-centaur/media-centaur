defmodule MediaCentarr.Library.Events do
  @moduledoc """
  Typed payloads for messages broadcast on the `library:updates` topic.

  Same rationale as `MediaCentarr.Playback.Events` — wrap each message
  in a struct with `@enforce_keys` so callers can't construct an invalid
  payload, and route every broadcast through a single `broadcast/1`
  chokepoint so adding a new variant requires updating one file.

  Subscribers continue to map-match (`%{entity_ids: ids} = payload` works
  on a struct because structs are maps), so this migration is additive
  for receivers — only the broadcast call site changes shape.

  Pair with the `MC0013 LibraryUpdatesContract` Credo check, which flags
  any direct `Phoenix.PubSub.broadcast/3` to this topic outside this
  module.
  """

  alias MediaCentarr.Topics

  defmodule EntitiesChanged do
    @moduledoc """
    One or more library entities (movie / tv_series / movie_series /
    video_object) were created, mutated, or deleted. Subscribers re-fetch
    the listed ids to reconcile their in-memory caches.
    """
    @enforce_keys [:entity_ids]
    defstruct [:entity_ids]

    @type t :: %__MODULE__{entity_ids: [String.t()]}
  end

  @doc """
  Broadcast a typed event on the `library:updates` topic. Each clause
  pairs a struct with the tagged-tuple shape subscribers pattern-match
  against — this is the *only* place the topic is published to.

  An empty `entity_ids` list is a no-op (nothing to reconcile).
  """
  @spec broadcast(EntitiesChanged.t()) :: :ok | {:error, term()}
  def broadcast(%EntitiesChanged{entity_ids: []}), do: :ok

  def broadcast(%EntitiesChanged{} = event), do: do_broadcast({:entities_changed, event})

  defp do_broadcast(message) do
    Phoenix.PubSub.broadcast(MediaCentarr.PubSub, Topics.library_updates(), message)
  end
end
