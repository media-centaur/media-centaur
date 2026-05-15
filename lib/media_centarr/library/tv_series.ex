defmodule MediaCentarr.Library.TVSeries do
  @moduledoc """
  A TV series in the library. Top-level container for seasons and episodes,
  with metadata from TMDB.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MediaCentarr.Library.Person

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_tv_series" do
    field :name, :string
    field :description, :string
    field :date_published, :string
    field :genres, {:array, :string}
    field :url, :string
    field :aggregate_rating_value, :float
    field :vote_count, :integer
    field :tagline, :string
    field :original_language, :string
    field :studio, :string
    field :country_code, :string
    field :network, :string
    field :number_of_seasons, :integer
    field :tmdb_id, :string
    field :imdb_id, :string
    field :status, Ecto.Enum, values: [:returning, :ended, :canceled, :in_production, :planned]

    embeds_many :cast, Person, on_replace: :delete
    embeds_many :crew, Person, on_replace: :delete

    has_many :seasons, MediaCentarr.Library.Season, foreign_key: :tv_series_id
    has_many :images, MediaCentarr.Library.Image, foreign_key: :tv_series_id
    has_many :extras, MediaCentarr.Library.Extra, foreign_key: :tv_series_id
    has_many :external_ids, MediaCentarr.Library.ExternalId, foreign_key: :tv_series_id
    has_many :watched_files, MediaCentarr.Library.WatchedFile, foreign_key: :tv_series_id

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :id,
      :name,
      :description,
      :date_published,
      :genres,
      :url,
      :aggregate_rating_value,
      :vote_count,
      :tagline,
      :original_language,
      :studio,
      :country_code,
      :network,
      :number_of_seasons,
      :tmdb_id,
      :imdb_id,
      :status
    ])
    |> cast_embed(:cast, with: &Person.cast_member_changeset/2)
    |> cast_embed(:crew, with: &Person.crew_member_changeset/2)
    |> validate_required([:name])
    |> unique_constraint(:tmdb_id, name: :library_tv_series_tmdb_id_index)
  end

  def update_changeset(tv_series, attrs) do
    tv_series
    |> cast(attrs, [
      :name,
      :description,
      :date_published,
      :genres,
      :url,
      :aggregate_rating_value,
      :vote_count,
      :tagline,
      :original_language,
      :studio,
      :country_code,
      :network,
      :number_of_seasons,
      :tmdb_id,
      :imdb_id,
      :status
    ])
    |> cast_embed(:cast, with: &Person.cast_member_changeset/2)
    |> cast_embed(:crew, with: &Person.crew_member_changeset/2)
  end

  @doc """
  Replaces the credits embeds in place — used by
  `MediaCentarr.Maintenance.refresh_series_credits/0` to backfill
  cast, crew (creators), and `imdb_id` from a fresh TMDB fetch.
  `cast_embed` is required here because `Ecto.Changeset.change/2`
  cannot coerce maps into `embeds_many` entries.
  """
  def update_credits_changeset(tv_series, attrs) do
    tv_series
    |> change()
    |> Person.put_credits(attrs)
  end
end
