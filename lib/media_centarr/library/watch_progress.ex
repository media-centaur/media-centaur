defmodule MediaCentarr.Library.WatchProgress do
  @moduledoc """
  Per-item playback progress. Tracks position, duration, and completion state
  for each playable item (movie, episode, or video object).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour MediaCentarr.Library.ProgressTracker

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_watch_progress" do
    field :position_seconds, :float, default: 0.0
    field :duration_seconds, :float, default: 0.0
    field :completed, :boolean, default: false
    field :last_watched_at, :utc_datetime

    belongs_to :movie, MediaCentarr.Library.Movie
    belongs_to :episode, MediaCentarr.Library.Episode
    belongs_to :video_object, MediaCentarr.Library.VideoObject

    timestamps()
  end

  @impl true
  def upsert_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :movie_id,
      :episode_id,
      :video_object_id,
      :position_seconds,
      :duration_seconds,
      :completed
    ])
    |> put_change(:last_watched_at, DateTime.utc_now(:second))
  end

  @impl true
  def update_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :position_seconds,
      :duration_seconds,
      :completed,
      :movie_id,
      :episode_id,
      :video_object_id
    ])
    |> put_change(:last_watched_at, DateTime.utc_now(:second))
  end

  @impl true
  defdelegate mark_completed_changeset(record), to: MediaCentarr.Library.ProgressTracker

  @impl true
  defdelegate mark_incomplete_changeset(record), to: MediaCentarr.Library.ProgressTracker
end
