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
    extra_progress: []
  ]

  @type kind :: :movie | :movie_series | :tv_series | :video_object

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          type: kind(),
          name: String.t(),
          collection: %{id: Ecto.UUID.t(), name: String.t()} | nil
        }
end
