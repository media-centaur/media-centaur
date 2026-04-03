defmodule MediaCentaur.Library.WatchProgress do
  @moduledoc """
  Per-item playback progress. Tracks position, duration, and completion state
  for each playable item (movie, episode, or video object).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_watch_progress" do
    field :season_number, :integer, default: 0
    field :episode_number, :integer, default: 0
    field :position_seconds, :float, default: 0.0
    field :duration_seconds, :float, default: 0.0
    field :completed, :boolean, default: false
    field :last_watched_at, :utc_datetime

    belongs_to :entity, MediaCentaur.Library.Entity
    belongs_to :movie, MediaCentaur.Library.Movie
    belongs_to :episode, MediaCentaur.Library.Episode
    belongs_to :video_object, MediaCentaur.Library.VideoObject

    timestamps()
  end

  def upsert_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :entity_id,
      :movie_id,
      :episode_id,
      :video_object_id,
      :season_number,
      :episode_number,
      :position_seconds,
      :duration_seconds
    ])
    |> validate_required([:entity_id])
    |> put_change(:last_watched_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  def upsert_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :position_seconds,
      :duration_seconds,
      :movie_id,
      :episode_id,
      :video_object_id
    ])
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
