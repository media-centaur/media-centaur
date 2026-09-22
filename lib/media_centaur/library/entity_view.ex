defmodule MediaCentaur.Library.EntityView do
  @moduledoc """
  The container-level read model of one library entity — what the detail
  components, the modal view models and playback resolution consume as
  `entity`.

  Two adapters produce it, one per source, and both must fill every
  field (`struct!/2` refuses anything else):

    * `MediaCentaur.Library.Views.DetailItem.to_entity_view/1` — from the
      detail projection (read side: the detail modal, progress broadcasts).
    * `MediaCentaur.Library.EntityShape.to_entity_view/2` — from a
      preloaded container record (write-adjacent side: playback resolution
      and the Browse projection's rebuild, which read the database).

  The two sources differ in what they can know, so a field a source
  cannot fill is empty rather than absent: the projection carries no
  `:watch_progress` (progress is an overlay, see `Library.ProgressRecords`)
  and no timestamps; a record carries no probed `:subtitle_tracks`.
  Child lists (`:seasons`, `:movies`, `:watched_files`, `:extras`) hold the
  source's own child shapes — projection maps or Ecto records — which
  consumers read with dot access.

  `:type` is the presented kind (`:movie | :movie_series | :tv_series |
  :video_object`, ADR-050); `:collection` is the `%{id, name}` of the
  collection a hoisted movie belongs to, else nil; `:track_override` is
  attached by `Library.MediaTrackOverrides.put_on_entity/1`.
  `:available?` is whether the entity's media directory is reachable
  right now — the projection adapter carries it from `DetailItem`, and
  `MediaCentaurWeb.LiveHelpers.image_url/2` withholds every artwork URL
  while it is false; the record adapter has no availability to report
  and leaves the default, since nothing renders a record-built view.
  `title_ref/1` is the entity's TMDB title identity, when it has one.
  """

  @enforce_keys [:id, :type, :name]
  defstruct [
    :id,
    :type,
    :name,
    :collection,
    :description,
    :date_published,
    :content_url,
    :url,
    :tagline,
    :genres,
    :studio,
    :country_code,
    :original_language,
    :network,
    :status,
    :duration_seconds,
    :content_rating,
    :aggregate_rating_value,
    :vote_count,
    :number_of_seasons,
    :director,
    :imdb_id,
    :tmdb_id,
    :inserted_at,
    :updated_at,
    :track_override,
    cast: [],
    crew: [],
    extras: [],
    external_ids: [],
    images: [],
    seasons: [],
    movies: [],
    watched_files: [],
    subtitle_tracks: [],
    watch_progress: [],
    extra_progress: [],
    available?: true
  ]

  @type kind :: :movie | :movie_series | :tv_series | :video_object

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          type: kind(),
          name: String.t(),
          collection: %{id: Ecto.UUID.t(), name: String.t()} | nil,
          available?: boolean()
        }

  @doc """
  The TMDB title identity a library entity answers to — `{tmdb_id,
  media_type}` for a movie or a series with a TMDB id, nil for a
  collection (its collection id is not a title id), a video object, or
  an unmatched entity. Reads the `:tmdb_id` the projection carries (a
  string on an `EntityView`, an integer on a collection member's
  projection map), so a `:movie`-shaped member subject answers too.
  """
  @spec title_ref(map()) :: {integer(), :movie | :tv_series} | nil
  def title_ref(%{type: type, tmdb_id: tmdb_id}) when type in [:movie, :tv_series] do
    case tmdb_id do
      id when is_integer(id) -> {id, type}
      id when is_binary(id) and id != "" -> {String.to_integer(id), type}
      _none -> nil
    end
  end

  def title_ref(_entity), do: nil
end
