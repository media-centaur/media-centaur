defmodule MediaCentarr.WatchHistory.Event do
  @moduledoc """
  A single completion event. Append-only — one row per time a title is watched
  to completion (≥90%). Re-watching creates a new row.

  FKs are nilify_all so history survives entity deletion. `title` is denormalized
  for the same reason — display remains meaningful after an entity is removed.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  schema "watch_history_events" do
    field :entity_type, Ecto.Enum, values: [:movie, :episode, :video_object]
    field :title, :string
    field :duration_seconds, :float
    field :completed_at, :utc_datetime_usec

    belongs_to :movie, MediaCentarr.Library.Movie
    belongs_to :episode, MediaCentarr.Library.Episode
    belongs_to :video_object, MediaCentarr.Library.VideoObject

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :entity_type,
      :title,
      :duration_seconds,
      :completed_at,
      :movie_id,
      :episode_id,
      :video_object_id
    ])
    |> validate_required([:entity_type, :title, :duration_seconds, :completed_at])
  end
end
