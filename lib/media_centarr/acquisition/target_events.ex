defmodule MediaCentarr.Acquisition.TargetEvents do
  @moduledoc """
  Typed PubSub broadcast structs for transient target lifecycle signals.

  These structs ride the `acquisition:updates` topic alongside the
  persisted `Pursuits.Events.*` structs. Unlike pursuit events,
  TargetEvents are NOT persisted — they're pure LiveView-refresh
  signals carrying the affected `%Target{}` so subscribers can
  re-render without an extra DB round-trip.

  ## Why typed structs instead of tuples

  Through v0.60.x the lifecycle broadcasts rode the topic as raw
  tuples (`{:target_acquired, target}`, `{:target_snoozed, target}`,
  …). LiveView subscribers had to pattern-match both shapes — typed
  pursuit events AND legacy tuples — on the same `handle_info`
  function. Phase 5 of the pursuits-maturation campaign collapsed that
  to a single dialect: every broadcast on `acquisition:updates` is now
  a struct, and subscribers do `event?/1` to recognise the family.

  ## Why not persist these too?

  Snooze events fire on every retry attempt (up to ~12 per target).
  Persisting them would clutter the per-pursuit timeline with
  heartbeats. The story-beat events (`search_started`,
  `release_no_match`, `release_picked`, `target_changed`,
  `pursuit_exhausted`) already cover the meaningful moments via
  `Pursuits.Events.*` — these supplement with the precise lifecycle
  edges the LV needs to refresh on.
  """

  defmodule Acquired do
    @moduledoc "Broadcast when Prowlarr accepts a release for a target (transitions seeking → acquired)."
    @enforce_keys [:target]
    defstruct [:target]
    @type t :: %__MODULE__{target: MediaCentarr.Acquisition.Target.t()}
  end

  defmodule Snoozed do
    @moduledoc "Broadcast when a search wake yielded no acceptable result and the worker rescheduled."
    @enforce_keys [:target]
    defstruct [:target]
    @type t :: %__MODULE__{target: MediaCentarr.Acquisition.Target.t()}
  end

  defmodule Failed do
    @moduledoc "Broadcast when a target exhausts its attempt budget without an acceptable result."
    @enforce_keys [:target]
    defstruct [:target]
    @type t :: %__MODULE__{target: MediaCentarr.Acquisition.Target.t()}
  end

  defmodule Armed do
    @moduledoc "Broadcast when a terminal target is re-armed back into seeking."
    @enforce_keys [:target]
    defstruct [:target]
    @type t :: %__MODULE__{target: MediaCentarr.Acquisition.Target.t()}
  end

  defmodule Cancelled do
    @moduledoc "Broadcast when a target is cancelled (user or system)."
    @enforce_keys [:target]
    defstruct [:target]
    @type t :: %__MODULE__{target: MediaCentarr.Acquisition.Target.t()}
  end

  defmodule Picked do
    @moduledoc "Broadcast when a user submits a manual pick or decision-card choice."
    @enforce_keys [:target]
    defstruct [:target]
    @type t :: %__MODULE__{target: MediaCentarr.Acquisition.Target.t()}
  end

  @event_modules [Acquired, Snoozed, Failed, Armed, Cancelled, Picked]

  @doc """
  True when `module` is one of the registered TargetEvents structs.
  Subscribers use this in a catch-all `handle_info(%struct{}, socket)`
  to identify lifecycle broadcasts without enumerating every kind.
  """
  @spec event?(module()) :: boolean()
  def event?(module) when is_atom(module), do: module in @event_modules
end
