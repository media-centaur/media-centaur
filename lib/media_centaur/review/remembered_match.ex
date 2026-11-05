defmodule MediaCentaur.Review.RememberedMatch do
  @moduledoc """
  A person's answer in Review, kept for the name the files were read as:
  "a file named this way is that TMDB title". Discovery's search stage
  takes it before asking TMDB, so a release name TMDB cannot find — a
  broadcaster's tag, an odd spelling — is answered once, not once per
  episode or per week.

  ## The name

  Three parts, all required to agree:

    * `title_form` — the parsed title in `Search.TitleForm.compare/1`
      form, so punctuation, case and accents do not matter;
    * `media_type` — the type the file is searched as
      (`Parser.effective_media_type/1`: an extra is searched as its
      parent's type);
    * `parsed_year` — a name with a year is often a remake, a different
      title from the one without (owner decision, 2026-11-05).

  `parsed_title` keeps the name as it was read, for Settings → Media
  Import, where the answers are listed and forgotten.

  ## Lifecycle

  Written by `Review.match/2` and `Review.approve/1`, one row per name,
  the latest answer replacing an earlier one. Forgotten from Settings,
  or by a rematch of files carrying the name (`Review.add_files_for_review/1`)
  — left in place, it would import the released files to the same wrong
  title on the next rescan.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "review_remembered_matches" do
    field :title_form, :string
    field :media_type, :string
    field :parsed_year, :integer
    field :parsed_title, :string
    field :tmdb_id, :integer
    field :tmdb_type, :string
    field :match_title, :string
    field :match_year, :string
    field :match_poster_path, :string

    timestamps()
  end

  @fields [
    :title_form,
    :media_type,
    :parsed_year,
    :parsed_title,
    :tmdb_id,
    :tmdb_type,
    :match_title,
    :match_year,
    :match_poster_path
  ]

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required([:title_form, :media_type, :parsed_title, :tmdb_id, :tmdb_type])
    |> validate_inclusion(:tmdb_type, ["movie", "tv"])
  end
end
