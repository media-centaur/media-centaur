defmodule MediaCentaur.Playback.Events do
  @moduledoc """
  Typed payloads for messages broadcast on the `playback:events` topic.

  Wrapping payloads in structs (instead of raw maps or positional
  tagged tuples) gives us:

    * `@enforce_keys` — callers cannot construct a payload missing a
      required field; the failure is a `KeyError` at compile time, not a
      silent `nil` at the subscriber.
    * a single `broadcast/1` chokepoint — every message on the topic
      flows through one function whose head pattern-matches against the
      defined struct types, so adding a new variant requires updating
      this module (and is therefore a deliberate, reviewable act).
    * Dialyzer surface — the `@type t :: …` definitions feed into specs
      so consumers get type information at the destructure site.

  Subscribers continue to map-match — `%{entity_id: id} = payload` works
  on a struct because structs *are* maps. Only callers that destructured
  positional tagged tuples (`{:playback_state_changed, id, state, np, ts}`)
  need to switch to map-style matching:

      # before
      def handle_info({:playback_state_changed, id, state, _, _}, socket)

      # after
      def handle_info({:playback_state_changed, %{entity_id: id, state: state}}, socket)

  ## Why this exists

  The class of bug we'd been hitting (the v0.31.1 modal-staleness fix,
  the v0.31.0 acquisition-grab-status fix) shares one shape: a publisher
  emits a payload variant that a subscriber doesn't expect, with no
  compile-time check at the boundary. Forcing every PubSub payload
  through a struct narrows the surface where that can happen.

  Pair with the `MC0012 PlaybackEventsContract` Credo check, which flags
  any direct `Phoenix.PubSub.broadcast/3` to this topic outside this
  module — the goal is that **every** message lands here first.
  """

  alias MediaCentaur.Topics

  defmodule EntityProgressUpdated do
    @moduledoc "Persisted progress for an entity (movie / episode root) changed."
    @enforce_keys [:entity_id, :summary, :resume_target, :changed_record, :last_activity_at]
    defstruct [
      :entity_id,
      :summary,
      :resume_target,
      :changed_record,
      :last_activity_at
    ]

    @type t :: %__MODULE__{
            entity_id: String.t(),
            summary: map(),
            resume_target: map() | nil,
            changed_record: map() | nil,
            last_activity_at: DateTime.t()
          }
  end

  defmodule ExtraProgressUpdated do
    @moduledoc "Persisted progress for an extra (bonus / behind-the-scenes) changed."
    @enforce_keys [:entity_id, :extra_id, :progress]
    defstruct [:entity_id, :extra_id, :progress]

    @type t :: %__MODULE__{
            entity_id: String.t(),
            extra_id: String.t(),
            progress: map() | nil
          }
  end

  defmodule PlaybackStateChanged do
    @moduledoc "MpvSession state moved to :playing, :paused, or :stopped."
    @enforce_keys [:entity_id, :state, :now_playing, :started_at]
    defstruct [:entity_id, :state, :now_playing, :started_at]

    @type state :: :playing | :paused | :stopped
    @type t :: %__MODULE__{
            entity_id: String.t(),
            state: state(),
            now_playing: map() | nil,
            started_at: DateTime.t()
          }
  end

  defmodule PlaybackFailed do
    @moduledoc "MpvSession could not start or crashed during startup."
    @enforce_keys [:entity_id, :reason, :payload]
    defstruct [:entity_id, :reason, :payload]

    @type t :: %__MODULE__{
            entity_id: String.t(),
            reason: atom(),
            payload: map()
          }
  end

  defmodule TrackOverrideChanged do
    @moduledoc """
    The user changed audio/subtitle tracks during playback and the
    selection differs from the language policy's choice — captured as
    a per-entity override.
    """
    @enforce_keys [:owner_type, :owner_id]
    defstruct [:owner_type, :owner_id]

    @type t :: %__MODULE__{
            owner_type: :tv_series | :movie,
            owner_id: String.t()
          }
  end

  @doc """
  Broadcast a typed event on the `playback:events` topic. Each clause
  pairs a struct with the tagged-tuple shape subscribers pattern-match
  against — this is the *only* place where the topic is published to.
  """
  @spec broadcast(
          EntityProgressUpdated.t()
          | ExtraProgressUpdated.t()
          | PlaybackStateChanged.t()
          | PlaybackFailed.t()
          | TrackOverrideChanged.t()
        ) :: :ok | {:error, term()}
  def broadcast(%EntityProgressUpdated{} = event), do: do_broadcast({:entity_progress_updated, event})

  def broadcast(%ExtraProgressUpdated{} = event), do: do_broadcast({:extra_progress_updated, event})

  def broadcast(%PlaybackStateChanged{} = event), do: do_broadcast({:playback_state_changed, event})

  def broadcast(%PlaybackFailed{} = event), do: do_broadcast({:playback_failed, event})

  def broadcast(%TrackOverrideChanged{} = event), do: do_broadcast({:track_override_changed, event})

  defp do_broadcast(message) do
    Phoenix.PubSub.broadcast(MediaCentaur.PubSub, Topics.playback_events(), message)
  end
end
