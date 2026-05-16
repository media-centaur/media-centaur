defmodule MediaCentarr.Library.WatchProgress do
  @moduledoc """
  Per-playable-item playback progress. Tracks position, duration, and
  completion state keyed by a single `playable_item_id` FK pointing at
  `MediaCentarr.Library.PlayableItem`.

  Library Schema v2 Phase 2 Task C collapsed the previous three-FK
  polymorphism (`movie_id` / `episode_id` / `video_object_id`) into
  this single FK and added a DB-level `UNIQUE(playable_item_id)`
  constraint enforcing "one progress row per playable item". Type
  information now lives on the linked PlayableItem's
  `(container_type, container_id)` discriminator.
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

    belongs_to :playable_item, MediaCentarr.Library.PlayableItem

    timestamps()
  end

  @impl true
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :playable_item_id,
      :position_seconds,
      :duration_seconds,
      :completed
    ])
    |> validate_required([:playable_item_id])
    |> put_change(:last_watched_at, DateTime.utc_now(:second))
    |> unique_constraint(:playable_item_id)
  end

  @impl true
  def update_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :position_seconds,
      :duration_seconds,
      :completed,
      :playable_item_id
    ])
    |> put_change(:last_watched_at, DateTime.utc_now(:second))
    |> unique_constraint(:playable_item_id)
  end

  @impl true
  defdelegate mark_completed_changeset(record), to: MediaCentarr.Library.ProgressTracker

  @impl true
  defdelegate mark_incomplete_changeset(record), to: MediaCentarr.Library.ProgressTracker
end
