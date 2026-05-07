defmodule MediaCentarr.Acquisition.Pursuits.Event do
  @moduledoc """
  Schema for one persisted lifecycle event.

  Append-only. FK to `acquisition_pursuits` is `nilify_all` so events
  survive pursuit deletion (the pattern used by `WatchHistory.Event`).
  `denormalized_pursuit_title` is preserved on the row for the same reason —
  the timeline UI remains meaningful even after the pursuit is gone.

  The `kind` field is a string with a closed enum enforced in the
  changeset. Each kind has a corresponding struct module under
  `Acquisition.Pursuits.Events.*` that handles serialization to/from the
  `payload` map (the typed-events contract).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  @kinds ~w(
    pursuit_started
    search_started
    release_picked
    release_no_match
    download_started
    health_changed
    stall_confirmed
    zero_seeders_confirmed
    auto_cancelled
    fallback_initiated
    user_decision_requested
    user_decision_recorded
    identity_mismatch
    identity_verified
    pursuit_satisfied
    pursuit_exhausted
    pursuit_cancelled
  )

  schema "acquisition_pursuit_events" do
    field :pursuit_id, Ecto.UUID
    field :denormalized_pursuit_title, :string
    field :kind, :string
    field :payload, :map, default: %{}
    field :occurred_at, :utc_datetime

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Returns every valid kind string."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:pursuit_id, :denormalized_pursuit_title, :kind, :payload, :occurred_at])
    |> validate_required([:denormalized_pursuit_title, :kind, :occurred_at])
    |> validate_inclusion(:kind, @kinds)
  end
end
