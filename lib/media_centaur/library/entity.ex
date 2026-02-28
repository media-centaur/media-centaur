defmodule MediaCentaur.Library.Entity do
  @moduledoc """
  A media entity in the library — a movie, TV series, or generic video object.

  Entities are created from TMDB metadata and served to the user-interface
  via Phoenix Channels.
  """
  use Ash.Resource,
    domain: MediaCentaur.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "entities"
    repo MediaCentaur.Repo
  end

  actions do
    defaults [:read, :destroy]

    read :with_associations do
      prepare build(
                load: [
                  :images,
                  :identifiers,
                  :watch_progress,
                  :extras,
                  seasons: [:extras, episodes: [:images]],
                  movies: [:images]
                ]
              )
    end

    read :with_progress do
      prepare build(
                load: [
                  :watch_progress,
                  seasons: [:episodes],
                  movies: []
                ]
              )
    end

    read :with_images do
      prepare build(
                load: [
                  :images,
                  seasons: [episodes: [:images]],
                  movies: [:images]
                ]
              )
    end

    create :create_from_tmdb do
      accept [
        :type,
        :name,
        :description,
        :date_published,
        :genres,
        :url,
        :duration,
        :director,
        :content_rating,
        :content_url,
        :number_of_seasons,
        :aggregate_rating_value
      ]

      validate present([:type, :name])
    end

    update :set_content_url do
      accept [:content_url]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :type, MediaCentaur.Library.Types.EntityType
    attribute :name, :string
    attribute :description, :string
    attribute :date_published, :string
    attribute :genres, {:array, :string}
    attribute :content_url, :string
    attribute :url, :string
    attribute :duration, :string
    attribute :director, :string
    attribute :content_rating, :string
    attribute :number_of_seasons, :integer
    attribute :aggregate_rating_value, :float

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :images, MediaCentaur.Library.Image
    has_many :identifiers, MediaCentaur.Library.Identifier
    has_many :movies, MediaCentaur.Library.Movie
    has_many :extras, MediaCentaur.Library.Extra
    has_many :seasons, MediaCentaur.Library.Season
    has_many :watched_files, MediaCentaur.Library.WatchedFile
    has_many :watch_progress, MediaCentaur.Library.WatchProgress
  end
end
