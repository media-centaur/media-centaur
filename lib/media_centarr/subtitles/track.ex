defmodule MediaCentarr.Subtitles.Track do
  @moduledoc """
  A single detected subtitle track.

  Independent of where the track came from — embedded in the video
  container, a sidecar file next to the video, or any future source.
  Detector modules build `Track` values; the orchestrator dedupes and
  persists them; the UI renders them via
  `MediaCentarr.Subtitles.list_tracks_for_file/1`.

  Stored in `subtitles_tracks`, linked to the `Library.WatchedFile`
  the track was detected against. Owned by `MediaCentarr.Subtitles` —
  callers go through that context, never `Repo` directly.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  @type kind :: :embedded | :sidecar

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          kind: kind() | nil,
          language: String.t() | nil,
          source: String.t() | nil,
          watched_file_id: Ecto.UUID.t() | nil
        }

  schema "subtitles_tracks" do
    field :kind, Ecto.Enum, values: [:embedded, :sidecar]
    field :language, :string
    field :source, :string

    belongs_to :watched_file, MediaCentarr.Library.WatchedFile

    timestamps()
  end

  @doc """
  Builds an insert changeset for a new track.

  Required fields: `watched_file_id`, `kind`, `source`. `language` is
  optional — sidecars without a recognisable ISO suffix have `nil`,
  which the UI surfaces as "external".
  """
  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:watched_file_id, :kind, :language, :source])
    |> validate_required([:watched_file_id, :kind, :source])
    |> foreign_key_constraint(:watched_file_id)
  end
end
