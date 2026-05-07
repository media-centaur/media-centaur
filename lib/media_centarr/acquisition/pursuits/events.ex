defmodule MediaCentarr.Acquisition.Pursuits.Events do
  @moduledoc """
  Persistence + broadcast chokepoint for typed pursuit events.

  Subscribers always receive the typed struct, never a map; cold replays
  from the DB also rebuild the struct. The kind ↔ struct module mapping
  is exhaustive (asserted by `EventsTest`) — every entry in
  `Event.kinds/0` has exactly one struct module here.
  """

  alias MediaCentarr.Acquisition.Pursuits.Event

  alias MediaCentarr.Acquisition.Pursuits.Events.{
    AutoCancelled,
    DownloadStarted,
    FallbackInitiated,
    HealthChanged,
    IdentityMismatch,
    IdentityVerified,
    PursuitCancelled,
    PursuitExhausted,
    PursuitSatisfied,
    PursuitStarted,
    ReleaseNoMatch,
    ReleasePicked,
    SearchStarted,
    StallConfirmed,
    UserDecisionRecorded,
    UserDecisionRequested,
    ZeroSeedersConfirmed
  }

  alias MediaCentarr.Repo
  alias MediaCentarr.Topics

  @kind_modules %{
    "pursuit_started" => PursuitStarted,
    "search_started" => SearchStarted,
    "release_picked" => ReleasePicked,
    "release_no_match" => ReleaseNoMatch,
    "download_started" => DownloadStarted,
    "health_changed" => HealthChanged,
    "stall_confirmed" => StallConfirmed,
    "zero_seeders_confirmed" => ZeroSeedersConfirmed,
    "auto_cancelled" => AutoCancelled,
    "fallback_initiated" => FallbackInitiated,
    "user_decision_requested" => UserDecisionRequested,
    "user_decision_recorded" => UserDecisionRecorded,
    "identity_mismatch" => IdentityMismatch,
    "identity_verified" => IdentityVerified,
    "pursuit_satisfied" => PursuitSatisfied,
    "pursuit_exhausted" => PursuitExhausted,
    "pursuit_cancelled" => PursuitCancelled
  }

  @doc """
  Persists the event row and broadcasts the struct on `acquisition:updates`.
  Returns `{:ok, struct}` on success, `{:error, changeset}` on validation
  failure. The struct is broadcast unchanged so subscribers can pattern-match
  by module.
  """
  @spec record(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def record(%mod{} = event) do
    kind = mod.kind()
    payload = mod.to_payload(event)

    attrs = %{
      pursuit_id: event.pursuit_id,
      denormalized_pursuit_title: event.pursuit_title,
      kind: kind,
      payload: payload,
      occurred_at: event.occurred_at
    }

    case Repo.insert(Event.create_changeset(attrs)) do
      {:ok, _row} ->
        Phoenix.PubSub.broadcast(MediaCentarr.PubSub, Topics.acquisition_updates(), event)
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc "Rebuilds a typed event struct from a persisted row."
  @spec deserialize(Event.t()) :: struct()
  def deserialize(%Event{} = row) do
    module = module_for_kind!(row.kind)

    base = %{
      pursuit_id: row.pursuit_id,
      pursuit_title: row.denormalized_pursuit_title,
      occurred_at: row.occurred_at
    }

    payload_struct = module.from_payload(row.payload || %{})
    struct(payload_struct, base)
  end

  @doc "Returns the struct module that owns the given kind, raising on unknown."
  @spec module_for_kind!(String.t()) :: module()
  def module_for_kind!(kind) do
    case Map.fetch(@kind_modules, kind) do
      {:ok, module} -> module
      :error -> raise ArgumentError, "no struct module registered for kind: #{inspect(kind)}"
    end
  end

  @doc "Lists every kind that has a registered struct module."
  @spec all_kinds() :: [String.t()]
  def all_kinds, do: Map.keys(@kind_modules)
end
