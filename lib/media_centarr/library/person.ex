defmodule MediaCentarr.Library.Person do
  @moduledoc """
  Embedded schema for cast and crew members on `Movie`, `TVSeries`, and
  `MovieSeries`. One struct shape, two changesets — `cast_member_changeset/1`
  reads the cast-specific fields (`character`, `order`) and
  `crew_member_changeset/1` reads the crew-specific fields (`job`,
  `department`). Both share `name`, `tmdb_person_id`, and
  `profile_path`.

  Data originates in the TMDB mapper (`MediaCentarr.TMDB.Mapper`) and
  is read by the More info detail panel — `tmdb_person_id` is kept
  alongside `name` so the panel can link to the TMDB person page.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          name: String.t() | nil,
          character: String.t() | nil,
          order: integer() | nil,
          job: String.t() | nil,
          department: String.t() | nil,
          profile_path: String.t() | nil,
          tmdb_person_id: integer() | nil
        }

  @primary_key false
  embedded_schema do
    field :name, :string
    field :character, :string
    field :order, :integer
    field :job, :string
    field :department, :string
    field :profile_path, :string
    field :tmdb_person_id, :integer
  end

  @cast_fields [:name, :character, :order, :profile_path, :tmdb_person_id]
  @crew_fields [:name, :job, :department, :profile_path, :tmdb_person_id]

  def cast_member_changeset(person \\ %__MODULE__{}, attrs) do
    person
    |> cast(attrs, @cast_fields)
    |> validate_required([:name])
  end

  def crew_member_changeset(person \\ %__MODULE__{}, attrs) do
    person
    |> cast(attrs, @crew_fields)
    |> validate_required([:name])
  end

  @doc """
  Casts the `cast` and `crew` embeds on a parent changeset.

  IMDB ids previously rode along on this helper as a parent-schema
  cast — they now live in `Library.ExternalId` rows and are written
  separately by maintenance refresh paths (see
  `MediaCentarr.Library.ExternalIds`).
  """
  def put_credits(changeset, attrs) do
    changeset
    |> cast(attrs, [])
    |> cast_embed(:cast, with: &cast_member_changeset/2)
    |> cast_embed(:crew, with: &crew_member_changeset/2)
  end
end
