defmodule MediaCentarr.Library.WatchedFile do
  @moduledoc """
  Links a video file on disk to the `Library.PlayableItem` it plays back.

  A WatchedFile is a pure join between a file path (and its watch
  directory) and a single `playable_item_id`. The PlayableItem in turn
  carries the `(container_type, container_id)` discriminator pair to
  the owning Movie / Episode / VideoObject — there is no per-container
  FK on this schema anymore (Library Schema v2 Phase 2 Task B).

  Detected subtitle tracks live in the Subtitles context — call
  `MediaCentarr.Subtitles.list_tracks_for_file/1` (or
  `aggregate_languages_for_files/1`) to read them. File-on-disk
  presence is tracked via the `belongs_to :file_presence` reference
  to `Library.FilePresence`. The column is plain (no DB-level FK);
  cleanup ordering is owned by the application — see ADR-046 and
  `Library.AbsenceSweeper.purge_expired/1`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_watched_files" do
    field :file_path, :string
    field :watch_dir, :string

    belongs_to :playable_item, MediaCentarr.Library.PlayableItem
    belongs_to :file_presence, MediaCentarr.Library.FilePresence

    timestamps()
  end

  @doc """
  Insert changeset for a new WatchedFile. Requires `:file_path`,
  `:playable_item_id`, and `:file_presence_id`. `:watch_dir` is
  captured for cross-context presence lookups. Callers should go
  through `Library.link_file/1` rather than building this changeset
  directly — `link_file/1` ensures a matching FilePresence exists
  and injects its id.
  """
  def link_file_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:file_path, :watch_dir, :playable_item_id, :file_presence_id])
    |> validate_required([:file_path, :playable_item_id, :file_presence_id])
  end

  @doc """
  Update changeset for re-pointing an existing WatchedFile (used by
  `Library.link_file/1` when a file_path is re-ingested under a
  different leaf).
  """
  def link_file_changeset(watched_file, attrs) do
    watched_file
    |> cast(attrs, [:file_path, :watch_dir, :playable_item_id, :file_presence_id])
    |> validate_required([:file_path, :playable_item_id, :file_presence_id])
  end
end
