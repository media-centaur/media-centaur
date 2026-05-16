defmodule MediaCentarr.Library.PlayableItem do
  @moduledoc """
  The user-visible playable leaf — the thing pressed Play on. One container
  (`Movie` / `Episode` / `VideoObject`) can host multiple PlayableItems for
  director's cuts, multi-part episodes, or other version variants.

  ## Fields

    * `container_type` / `container_id` — discriminator pair identifying the
      owning entity (see *Discriminator design* below).
    * `position` — 1-based ordering within the container; combined with
      `(container_type, container_id)` it is unique (DB-enforced) so that
      multiple version-variants don't collide.
    * `duration_seconds` — playback duration of this specific leaf.
    * `name` — the version label (e.g. `"Director's Cut"`, `"Part 2"`); `nil`
      for the canonical/sole leaf of a container.

  ## Discriminator design

  The container is identified by a `(container_type, container_id)` pair
  rather than three nullable per-type foreign keys. This is the cross-cutting
  polymorphism decision from the Library Schema v2 campaign (2026-05-15):
  adding a new container type means one new enum value rather than one new
  nullable FK column on every supporting table.

  The tradeoff is no DB-level FK enforcement on `container_id`. Integrity is
  enforced at the write seam (`MediaCentarr.Library.Inbound` and the
  `Library` context's `create_playable_item/1`); orphan rows would only
  appear if writes skip the boundary.

  See `campaigns/library-schema-v2.md` for the full target shape.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  @type container_type :: :movie | :episode | :video_object

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          container_type: container_type() | nil,
          container_id: Ecto.UUID.t() | nil,
          position: integer() | nil,
          duration_seconds: integer() | nil,
          name: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "library_playable_items" do
    field :container_type, Ecto.Enum, values: [:movie, :episode, :video_object]
    field :container_id, Ecto.UUID
    field :position, :integer
    field :duration_seconds, :integer
    field :name, :string

    has_many :watched_files, MediaCentarr.Library.WatchedFile
    # `UNIQUE(playable_item_id)` on `library_watch_progress` guarantees
    # the cardinality (Library Schema v2 Phase 2 Task C).
    has_one :watch_progress, MediaCentarr.Library.WatchProgress

    timestamps()
  end

  @doc """
  Builds the canonical insert changeset. Validates the discriminator pair
  `(container_type, container_id)`; `position`, `duration_seconds`, and
  `name` are optional version-label fields.
  """
  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:container_type, :container_id, :position, :duration_seconds, :name])
    |> validate_required([:container_type, :container_id])
    # The SQLite Ecto adapter doesn't propagate the index name from the
    # constraint error; it synthesises `<table>_<col1>_<col2>_..._index`
    # from the offending columns. We declare the constraint by its
    # default Ecto-derived name so the violation surfaces as a changeset
    # error (enabling race-loss recovery in Task B/G) rather than as
    # `Ecto.ConstraintError`. See `MediaCentarr.Library.ExternalId` for
    # the same pattern.
    |> unique_constraint([:container_type, :container_id, :position])
  end
end
