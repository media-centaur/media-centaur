defmodule MediaCentaur.Library.Episode do
  @moduledoc """
  A TV episode belonging to a `Season`. Stores per-episode metadata from
  TMDB.

  `duration_seconds` is the canonical integer-seconds field (Library Schema
  v2 Phase 1 Task 3). The pipeline derives it from TMDB's per-episode
  `runtime` (minutes) at ingest time via `TMDB.Mapper.episode_attrs/4`. The
  prior stringly-typed `:duration` column was dropped; any previously-stored
  values are not recoverable but are repopulated on the next TMDB refresh.

  ## `content_url` is a derived virtual field

  `content_url` no longer carries a persisted column (Library Schema v2
  Phase 2 Task I dropped it). It is materialised at read time from
  `playable_items.watched_files.file_path` by
  `MediaCentaur.Library.ContentUrls.populate/1`. Writes must go through
  `Library.Files.link/1` against the Episode's `PlayableItem`.
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
    # TMDB `air_date`. Nil for episodes scraped before the column existed
    # and for episodes TMDB has not dated yet (unaired).
    field :date_published, :date
    # Cast membership as TMDB person ids referencing the parent series'
    # aggregate-cast embeds — season regulars + this episode's guest
    # stars (`TMDB.Mapper.episode_attrs/2`). Empty for episodes scraped
    # before the column existed; backfilled by the *Refresh series
    # credits* maintenance task.
    field :cast_person_ids, {:array, :integer}, default: []
    # Virtual: populated from `playable_items.watched_files.file_path` by
    # `MediaCentaur.Library.ContentUrls.populate/1` (Library Schema v2
    # Phase 2 Task I). The persisted column was dropped; `WatchedFile` is
    # the sole source of truth.
    field :content_url, :string, virtual: true

    belongs_to :season, MediaCentaur.Library.Season

    # Polymorphic association — Image rows discriminate on
    # `(owner_type, owner_id)` (Library Schema v2 Phase 2 Task D).
    has_many :images, MediaCentaur.Library.Image,
      foreign_key: :owner_id,
      where: [owner_type: :episode]

    # Polymorphic has_many via Ecto's `where:` filter. See
    # `Library.PlayableItem` moduledoc for the discriminator design.
    has_many :playable_items, MediaCentaur.Library.PlayableItem,
      foreign_key: :container_id,
      where: [container_type: :episode]

    # WatchedFiles reach this Episode via its PlayableItems
    # (Library Schema v2 Phase 2 Task B). An episode with N
    # PlayableItems (multi-part / version variants) has up to N files.
    has_many :watched_files, through: [:playable_items, :watched_files]

    # WatchProgress is per-PlayableItem (Library Schema v2 Phase 2
    # Task C). For the canonical case (single PlayableItem per
    # Episode) `has_one :through` matches the historical semantics.
    # If an Episode ever has multiple PlayableItems each with
    # WatchProgress, `Repo.preload(episode, :watch_progress)` silently
    # returns the first PlayableItem's progress; the second cut would
    # be invisible at this preload path.
    has_one :watch_progress, through: [:playable_items, :watch_progress]

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :episode_number,
      :name,
      :description,
      :duration_seconds,
      :date_published,
      :cast_person_ids,
      :season_id
    ])
    |> validate_required([:season_id, :episode_number])
    # The episode unique index already existed; this only teaches the
    # changeset to surface a racing duplicate as `{:error, changeset}`
    # instead of raising `Ecto.ConstraintError`. The index name is
    # normalised to the Ecto default in
    # 20260523210000_restore_season_unique_index.
    |> unique_constraint([:season_id, :episode_number])
  end

  @doc """
  Changeset for refreshing an existing episode's cast membership alone —
  the *Refresh series credits* backfill path. Deliberately narrow so a
  membership refresh can never disturb episode metadata.
  """
  def cast_membership_changeset(%__MODULE__{} = episode, cast_person_ids)
      when is_list(cast_person_ids) do
    cast(episode, %{cast_person_ids: cast_person_ids}, [:cast_person_ids])
  end
end
