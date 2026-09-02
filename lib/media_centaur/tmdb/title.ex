defmodule MediaCentaur.TMDB.Title do
  @moduledoc """
  The app-wide TMDB title value — a movie or show referenced by TMDB
  identity, whether or not the library owns it: search hits, tracked
  items, watchlist items, recommendations.

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
