defmodule MediaCentaurWeb.Components.Detail.TitlePreview do
  @moduledoc """
  A detail-page shaped preview of a TMDB title the library does not own
  — the same identity cues (backdrop, logo, tagline, metadata row,
  facets, top cast) the owned detail panel shows, built live from a full
  TMDB payload so a confirmation surface never drifts from what
  ingestion would record. Worn by the plan modal's movie confirm stage
  and the Discovery title detail modal.

  Built by `movie/3` and `tv/3` from raw TMDB payloads via `TMDB.Mapper`
  — the same derivation the import pipeline uses. Absent TMDB fields
  collapse to `nil`/empty so templates drop them.

  `year` is the title's canonical year: for a movie `TMDB.Mapper`'s
  earliest-typed-release derivation (not the primary `release_date`),
  which is the year `Plans.create_movie_plan/2` stamps on the plan so the
  indexer query matches how releases are tagged; for a series the first
  air year.

  `imdb_id` / `tvdb_id` are how TMDB spells the title elsewhere
  (`TMDB.Identifiers`) — carried so the plan the confirm stage creates
  knows the identity indexers declare on their own results.

  `upcoming?` says the title isn't out anywhere yet — its canonical date
  is missing or still ahead. It gates the *Track release* verb: watching
  for a release only makes sense while there is one to wait for.

  `facets` are `Detail.Facet` structs (rendered by `Detail.FacetStrip`),
  `cast` are `Library.Person` structs (the library's cast shape), and the
  image fields are absolute TMDB CDN URLs — a not-yet-owned title has no
  local artwork, so the preview hotlinks TMDB rather than the
  `/media-images/` path the owned detail panel serves from.
  """

  alias MediaCentaur.Format
  alias MediaCentaur.Library.Person
  alias MediaCentaur.TMDB.Identifiers
  alias MediaCentaur.TMDB.Mapper
  alias MediaCentaurWeb.Components.Detail.Facet
  alias MediaCentaurWeb.Components.Detail.Logic, as: DetailLogic

  @type t :: %__MODULE__{
          media_type: :movie | :tv_series,
          tmdb_id: String.t(),
          imdb_id: String.t() | nil,
          tvdb_id: String.t() | nil,
          title: String.t() | nil,
          year: integer() | nil,
          tagline: String.t() | nil,
          overview: String.t() | nil,
          backdrop_url: String.t() | nil,
          logo_url: String.t() | nil,
          poster_url: String.t() | nil,
          metadata_items: [String.t()],
          facets: [Facet.t()],
          cast: [Person.t()],
          in_library?: boolean(),
          upcoming?: boolean()
        }

  @enforce_keys [:media_type, :tmdb_id, :in_library?]
  defstruct media_type: :movie,
            tmdb_id: nil,
            imdb_id: nil,
            tvdb_id: nil,
            title: nil,
            year: nil,
            tagline: nil,
            overview: nil,
            backdrop_url: nil,
            logo_url: nil,
            poster_url: nil,
            metadata_items: [],
            facets: [],
            cast: [],
            in_library?: false,
            upcoming?: false

  # The top-billed few — a compact confirmation strip, not the full
  # detail-panel cast grid. Mapper already sorts by billing order.
  @cast_preview_limit 10

  @doc "The metadata row's badge word for a preview's media type."
  @spec badge_text(t()) :: String.t()
  def badge_text(%__MODULE__{media_type: :movie}), do: "Movie"
  def badge_text(%__MODULE__{media_type: :tv_series}), do: "TV series"

  @doc "Builds a movie preview from a `TMDB.Client.get_movie/2` payload."
  @spec movie(map(), boolean(), Date.t()) :: t()
  def movie(tmdb_movie, in_library?, today \\ Date.utc_today()) do
    tmdb_id = tmdb_movie["id"]
    attrs = Mapper.movie_attrs(tmdb_id, tmdb_movie, nil)
    images = Map.new(Mapper.image_list(tmdb_movie), &{&1.role, &1.url})

    %__MODULE__{
      media_type: :movie,
      tmdb_id: to_string(tmdb_id),
      imdb_id: attrs.imdb_id,
      title: attrs.name,
      year: attrs.date_published && attrs.date_published.year,
      tagline: attrs.tagline,
      overview: presence(attrs.description),
      backdrop_url: images["backdrop"],
      logo_url: images["logo"],
      poster_url: images["poster"],
      metadata_items: movie_metadata_items(attrs),
      facets: DetailLogic.facets_for(:movie, attrs),
      cast: top_cast(attrs.cast),
      in_library?: in_library?,
      upcoming?: upcoming?(attrs.date_published, today)
    }
  end

  @doc "Builds a series preview from a `TMDB.Client.get_tv/2` payload."
  @spec tv(map(), boolean(), Date.t()) :: t()
  def tv(tmdb_show, in_library?, today \\ Date.utc_today()) do
    tmdb_id = tmdb_show["id"]
    attrs = Mapper.tv_attrs(tmdb_id, tmdb_show)
    identifiers = Identifiers.from_payload(:tv, tmdb_show)
    images = Map.new(Mapper.image_list(tmdb_show), &{&1.role, &1.url})

    %__MODULE__{
      media_type: :tv_series,
      tmdb_id: to_string(tmdb_id),
      imdb_id: identifiers.imdb_id,
      tvdb_id: identifiers.tvdb_id,
      title: attrs.name,
      year: attrs.date_published && attrs.date_published.year,
      tagline: attrs.tagline,
      overview: presence(attrs.description),
      backdrop_url: images["backdrop"],
      logo_url: images["logo"],
      poster_url: images["poster"],
      metadata_items: tv_metadata_items(attrs),
      facets: DetailLogic.facets_for(:tv_series, attrs),
      cast: top_cast(attrs.cast),
      in_library?: in_library?,
      upcoming?: upcoming?(attrs.date_published, today)
    }
  end

  defp upcoming?(nil, _today), do: true
  defp upcoming?(%Date{} = release_date, today), do: Date.after?(release_date, today)

  # Non-facet row items: year and runtime plus certification and country,
  # mirroring the owned detail panel's metadata row. Rating, director,
  # language, studio, and genres live in the facet strip, never here.
  defp movie_metadata_items(attrs) do
    compact([
      Format.year(attrs.date_published),
      runtime_label(attrs.duration_seconds),
      attrs.content_rating,
      attrs.country_code
    ])
  end

  # A series: first-air year, season count and country. Network, rating,
  # language and genres live in the facet strip.
  defp tv_metadata_items(attrs) do
    compact([
      Format.year(attrs.date_published),
      seasons_label(attrs.number_of_seasons),
      attrs.country_code
    ])
  end

  defp compact(items), do: Enum.reject(items, &(is_nil(&1) or &1 == ""))

  defp seasons_label(1), do: "1 season"
  defp seasons_label(count) when is_integer(count) and count > 1, do: "#{count} seasons"
  defp seasons_label(_count), do: nil

  defp runtime_label(seconds) when is_integer(seconds) and seconds > 0,
    do: MediaCentaurWeb.LibraryFormatters.format_human_duration(seconds)

  defp runtime_label(_seconds), do: nil

  defp top_cast(cast) when is_list(cast) do
    cast
    |> Enum.take(@cast_preview_limit)
    |> Enum.map(fn person ->
      %Person{
        name: person["name"],
        character: person["character"],
        profile_path: person["profile_path"],
        tmdb_person_id: person["tmdb_person_id"],
        order: person["order"]
      }
    end)
  end

  defp top_cast(_cast), do: []

  defp presence(value) when is_binary(value) and value != "", do: value
  defp presence(_value), do: nil
end
