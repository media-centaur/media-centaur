defmodule MediaManager.Library.Entity do
  @moduledoc """
  A media entity in the library — a movie, TV series, or generic video object.

  Entities are created from TMDB metadata and served to the user-interface
  via Phoenix Channels.
  """
  use Ash.Resource,
    domain: MediaManager.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "entities"
    repo MediaManager.Repo
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

    attribute :type, MediaManager.Library.Types.EntityType
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
    has_many :images, MediaManager.Library.Image
    has_many :identifiers, MediaManager.Library.Identifier
    has_many :movies, MediaManager.Library.Movie
    has_many :extras, MediaManager.Library.Extra
    has_many :seasons, MediaManager.Library.Season
    has_many :watched_files, MediaManager.Library.WatchedFile
    has_many :watch_progress, MediaManager.Library.WatchProgress
  end
end
