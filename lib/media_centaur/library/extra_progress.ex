defmodule MediaCentaur.Library.ExtraProgress do
  @moduledoc """
  A row is one profile's progress on one extra (ADR-078) — position,
  duration and completion for bonus content (featurettes, deleted scenes,
  behind-the-scenes) — unique on `(profile_id, extra_id)`; the profile is
  a plain id, not an association — `Profiles` is another context.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour MediaCentaur.Library.ProgressTracker

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  schema "library_extra_progress" do
    field :position_seconds, :float, default: 0.0
    field :duration_seconds, :float, default: 0.0
    field :completed, :boolean, default: false
    field :last_watched_at, :utc_datetime
    field :profile_id, Ecto.UUID

    belongs_to :extra, MediaCentaur.Library.Extra

    timestamps()
  end

  @type t :: %__MODULE__{}

  @impl true
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:profile_id, :extra_id, :position_seconds, :duration_seconds])
    |> validate_required([:profile_id, :extra_id])
    |> put_change(:last_watched_at, DateTime.utc_now(:second))
    |> unique_constraint([:profile_id, :extra_id])
  end

  @impl true
  def update_changeset(record, attrs) do
    record
    |> cast(attrs, [:position_seconds, :duration_seconds])
    |> put_change(:last_watched_at, DateTime.utc_now(:second))
  end

  @impl true
  defdelegate mark_completed_changeset(record), to: MediaCentaur.Library.ProgressTracker

  @impl true
  defdelegate mark_incomplete_changeset(record), to: MediaCentaur.Library.ProgressTracker
end
