defmodule MediaCentarr.Library.Episode do
  @moduledoc """
  A TV episode belonging to a `Season`. Stores per-episode metadata from TMDB
  and the local `content_url` linking to the video file.

  `duration_seconds` is the canonical integer-seconds field (Library Schema
  v2 Phase 1 Task 3). The pipeline derives it from TMDB's per-episode
  `runtime` (minutes) at ingest time via `TMDB.Mapper.episode_attrs/4`. The
  prior stringly-typed `:duration` column was dropped; any previously-stored
  values are not recoverable but are repopulated on the next TMDB refresh.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_episodes" do
    field :episode_number, :integer
    field :name, :string
    field :description, :string
    field :duration_seconds, :integer
    field :content_url, :string

    belongs_to :season, MediaCentarr.Library.Season
    has_many :images, MediaCentarr.Library.Image
    has_one :watch_progress, MediaCentarr.Library.WatchProgress

    # Polymorphic has_many via Ecto's `where:` filter. See
    # `Library.PlayableItem` moduledoc for the discriminator design.
    has_many :playable_items, MediaCentarr.Library.PlayableItem,
      foreign_key: :container_id,
      where: [container_type: :episode]

    # WatchedFiles reach this Episode via its PlayableItems
    # (Library Schema v2 Phase 2 Task B). An episode with N
    # PlayableItems (multi-part / version variants) has up to N files.
    has_many :watched_files, through: [:playable_items, :watched_files]

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :episode_number,
      :name,
      :description,
      :duration_seconds,
      :content_url,
      :season_id
    ])
    |> validate_required([:season_id, :episode_number])
  end

  def set_content_url_changeset(episode, attrs) do
    cast(episode, attrs, [:content_url])
  end
end
