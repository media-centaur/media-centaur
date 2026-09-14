defmodule MediaCentaur.TMDB.Title do
  @moduledoc """
  The app-wide TMDB title value — a movie or show referenced by TMDB
  identity, whether or not the library owns it: search hits, tracked
  items, watchlist items, reviews.

  Identity is `(tmdb_id, media_type)`; TMDB's movie and TV id spaces
  overlap, so neither half is enough alone. The remaining fields are a
  *render snapshot* cached at build time so any surface can paint the
  title without a TMDB call. `poster_path`/`backdrop_path` are TMDB
  paths, not URLs — `MediaCentaurWeb.LiveHelpers.title_poster_url/1`
  resolves them.

  No per-surface decoration lives here (tracked, on the watchlist, in
  the library); surfaces derive those from ref sets at render time.

  An embedded schema so rows can carry it verbatim (`embeds_one :title`)
  with one serialization; in-memory it is a plain struct built by
  `new!/1` or `changeset/2`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.DateUtil

  @type media_type :: :movie | :tv_series

  @type t :: %__MODULE__{
          tmdb_id: integer(),
          media_type: media_type(),
          name: String.t(),
          year: String.t() | nil,
          release_date: Date.t() | nil,
          poster_path: String.t() | nil,
          backdrop_path: String.t() | nil,
          overview: String.t() | nil
        }

  @primary_key false
  embedded_schema do
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    field :name, :string
    field :year, :string
    field :release_date, :date
    field :poster_path, :string
    field :backdrop_path, :string
    field :overview, :string
  end

  @fields [:tmdb_id, :media_type, :name, :year, :release_date, :poster_path, :backdrop_path, :overview]

  @doc "Casts a title from plain attrs; identity and name are required."
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(title \\ %__MODULE__{}, attrs) do
    title
    |> cast(attrs, @fields)
    |> validate_required([:tmdb_id, :media_type, :name])
  end

  @doc """
  Builds the snapshot from a TMDB payload — a search hit or a detail
  response, which share the fields the snapshot keeps. TMDB names a
  movie's title `title` and dates it by `release_date`; a series is
  `name` and `first_air_date`. The media type is the caller's: a multi
  search hit carries one, a per-type hit or a detail response does not.
  A missing or partial date is nil, and its year survives when the string
  starts with one. A payload without an identity or a name is an error
  rather than a title. The one field mapping every TMDB-fed builder
  shares.
  """
  @spec from_tmdb(map(), media_type()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def from_tmdb(%{} = tmdb, :movie), do: from_fields(tmdb, :movie, tmdb["title"], tmdb["release_date"])

  def from_tmdb(%{} = tmdb, :tv_series),
    do: from_fields(tmdb, :tv_series, tmdb["name"], tmdb["first_air_date"])

  defp from_fields(tmdb, media_type, name, date_string) do
    %{
      tmdb_id: tmdb["id"],
      media_type: media_type,
      name: name,
      year: DateUtil.extract_year(date_string),
      release_date: parse_date(date_string),
      poster_path: tmdb["poster_path"],
      backdrop_path: tmdb["backdrop_path"],
      overview: tmdb["overview"]
    }
    |> changeset()
    |> apply_action(:insert)
  end

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_date(_missing), do: nil

  @doc """
  Builds a title from plain attrs, raising `ArgumentError` when the
  identity or name is missing or the media type is unknown — the
  enforced constructor every in-app builder uses.
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case apply_action(changeset(attrs), :insert) do
      {:ok, title} -> title
      {:error, changeset} -> raise ArgumentError, "invalid TMDB title: #{inspect(changeset.errors)}"
    end
  end

  @doc "The `{tmdb_id, media_type}` identity pair — the key every ref set uses."
  @spec ref(t()) :: {integer(), media_type()}
  def ref(%__MODULE__{tmdb_id: tmdb_id, media_type: media_type}), do: {tmdb_id, media_type}
end
