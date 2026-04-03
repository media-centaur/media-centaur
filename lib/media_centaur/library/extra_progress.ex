defmodule MediaCentaur.Library.ExtraProgress do
  @moduledoc """
  Per-extra playback progress. Tracks position, duration, and completion state
  for bonus content (featurettes, deleted scenes, behind-the-scenes).

  Keyed by `extra_id` — each extra gets at most one progress record.
  The `entity_id` is denormalized for efficient queries (list all extra progress
  for an entity without joining through extras).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_extra_progress" do
    field :position_seconds, :float, default: 0.0
    field :duration_seconds, :float, default: 0.0
    field :completed, :boolean, default: false
    field :last_watched_at, :utc_datetime

    belongs_to :extra, MediaCentaur.Library.Extra

    timestamps()
  end

  def upsert_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:extra_id, :position_seconds, :duration_seconds])
    |> validate_required([:extra_id])
    |> put_change(:last_watched_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  def upsert_changeset(record, attrs) do
    record
    |> cast(attrs, [:position_seconds, :duration_seconds])
    |> put_change(:last_watched_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  def mark_completed_changeset(record) do
    record
    |> change(completed: true, last_watched_at: DateTime.truncate(DateTime.utc_now(), :second))
  end

  def mark_incomplete_changeset(record) do
    record
    |> change(completed: false, last_watched_at: DateTime.truncate(DateTime.utc_now(), :second))
  end
end
