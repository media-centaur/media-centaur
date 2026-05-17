defmodule MediaCentarr.Library.ExtraFile do
  @moduledoc """
  Tracks file-on-disk presence for an `Library.Extra` (a bonus feature —
  featurette, behind-the-scenes, deleted scene).

  Parallel to `Library.WatchedFile` (which tracks file presence for
  `PlayableItem`s — Movies, Episodes, VideoObjects). Extras get their
  own table because they are **not** playable leaves in the PlayableItem
  sense: an Extra is a metadata-and-file pair owned by its parent
  container (Movie / TVSeries / MovieSeries / Season), not a standalone
  playable item with watch progress and a position within a container.

  The duplication with `WatchedFile` is intentional. They track different
  owners (PlayableItem vs Extra) with different polymorphism stories
  (discriminator pair vs four-FK), and collapsing them into a shared
  abstraction would re-introduce the polymorphism the campaign just
  removed from WatchedFile.

  ## Uniqueness

  `file_path` is unique — one file on disk maps to at most one Extra.
  Mirrors `WatchedFile.file_path` semantics so the Watcher / Inbound
  contract is consistent across both presence tables.

  ## Why not extend `Library.Extra` with the file column?

  `Extra.content_url` already names the canonical playable path. The
  separation here is about *presence tracking* — has the file been
  observed on disk, in which watch directory — distinct from the Extra
  metadata. Same separation that exists between `Movie.content_url` and
  `WatchedFile`.

  Follow-up: Wire `Library.Inbound` to write ExtraFiles when ingesting
  bonus-feature paths (Task G or a successor). Today the only writer is
  the Phase 2 Task B migration that backfills orphans from legacy
  `library_watched_files.movie_series_id` rows that pointed at Extras.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          file_path: String.t() | nil,
          watch_dir: String.t() | nil,
          extra_id: Ecto.UUID.t() | nil,
          file_presence_id: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "library_extra_files" do
    field :file_path, :string
    field :watch_dir, :string

    belongs_to :extra, MediaCentarr.Library.Extra
    belongs_to :file_presence, MediaCentarr.Library.FilePresence

    timestamps()
  end

  @doc """
  Insert / update changeset for an ExtraFile. Requires `:file_path`,
  `:extra_id`, and `:file_presence_id`; `:watch_dir` is captured for
  cross-context presence lookups (mirrors WatchedFile). Callers
  should go through `Library.create_extra_file/1` rather than
  building this changeset directly — that wrapper ensures a matching
  FilePresence exists and injects its id.
  """
  def link_file_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:file_path, :watch_dir, :extra_id, :file_presence_id])
    |> validate_required([:file_path, :extra_id, :file_presence_id])
    |> unique_constraint(:file_path)
  end

  def link_file_changeset(extra_file, attrs) do
    extra_file
    |> cast(attrs, [:file_path, :watch_dir, :extra_id, :file_presence_id])
    |> validate_required([:file_path, :extra_id, :file_presence_id])
    |> unique_constraint(:file_path)
  end
end
