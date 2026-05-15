defmodule MediaCentarr.Library.Person do
  @moduledoc """
  Embedded schema for cast and crew members on `Movie` and `TVSeries`.
  One struct shape, two changesets — `cast_member_changeset/1` reads
  the cast-specific fields (`character`, `order`) and
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
  Casts cast/crew embeds plus `:imdb_id` on a parent changeset.

  The `imdb_id` field is the only non-credits field that the credits
  refresh path touches; keeping it here keeps all credit-update knowledge
  in one place rather than duplicated across every container schema.

  When the parent schema does not declare `imdb_id` (e.g. `MovieSeries`,
  whose TMDB collection payload has no top-level IMDB id), the field is
  silently skipped — the helper composes cleanly across schemas with and
  without the column.
  """
  def put_credits(changeset, attrs) do
    changeset
    # `cast/3` is what attaches `attrs` to the changeset params; without
    # it the downstream `cast_embed/2` calls have nothing to read. We
    # include `:imdb_id` only on parent schemas that declare it (Movie,
    # TVSeries); for schemas without it (MovieSeries) we pass an empty
    # field list — the cast still brings the params in.
    |> cast(attrs, imdb_id_fields(changeset))
    |> cast_embed(:cast, with: &cast_member_changeset/2)
    |> cast_embed(:crew, with: &crew_member_changeset/2)
  end

  defp imdb_id_fields(changeset) do
    schema = changeset.data.__struct__

    if :imdb_id in schema.__schema__(:fields) do
      [:imdb_id]
    else
      []
    end
  end
end
