defmodule MediaCentarr.Library.VideoObject do
  @moduledoc """
  A standalone video object in the library. Represents a single video file
  that doesn't belong to a TV series or movie series — e.g. a concert,
  documentary, or home video.

  TMDB ids live in `Library.ExternalId` rows reachable via the
  `:external_ids` association — no longer a column on this schema
  (Library Schema v2 Phase 1 Task 6).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_video_objects" do
    field :name, :string
    field :description, :string
    field :date_published, :date
    field :content_url, :string
    field :url, :string

    # Polymorphic associations — Image / ExternalId rows discriminate on
    # `(owner_type, owner_id)` (Library Schema v2 Phase 2 Tasks D, F).
    # VideoObject has no Extras association — Extra owner_type does not
    # include :video_object.
    has_many :images, MediaCentarr.Library.Image,
      foreign_key: :owner_id,
      where: [owner_type: :video_object]

    has_many :external_ids, MediaCentarr.Library.ExternalId,
      foreign_key: :owner_id,
      where: [owner_type: :video_object]

    # Polymorphic has_many via Ecto's `where:` filter. See
    # `Library.PlayableItem` moduledoc for the discriminator design.
    has_many :playable_items, MediaCentarr.Library.PlayableItem,
      foreign_key: :container_id,
      where: [container_type: :video_object]

    # WatchedFiles reach this VideoObject via its PlayableItems
    # (Library Schema v2 Phase 2 Task B).
    has_many :watched_files, through: [:playable_items, :watched_files]

    # WatchProgress is per-PlayableItem (Library Schema v2 Phase 2
    # Task C). A VideoObject has at most one PlayableItem in current
    # schema, so this preserves the historical `has_one` shape. If a
    # VideoObject ever has multiple PlayableItems each with
    # WatchProgress, `Repo.preload(video_object, :watch_progress)`
    # silently returns the first PlayableItem's progress; the second
    # cut would be invisible at this preload path.
    has_one :watch_progress, through: [:playable_items, :watch_progress]

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :id,
      :name,
      :description,
      :date_published,
      :content_url,
      :url
    ])
    |> validate_required([:name])
  end

  def update_changeset(video_object, attrs) do
    cast(video_object, attrs, [:name, :description, :date_published, :content_url, :url])
  end
end
