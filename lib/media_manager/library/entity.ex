defmodule MediaManager.Library.Entity do
  use Ash.Resource,
    domain: MediaManager.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "entities"
    repo MediaManager.Repo
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :with_associations do
      prepare build(load: [:images, :identifiers, :watched_files, seasons: [:episodes]])
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
    end

    update :set_content_url do
      accept [:content_url]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :type, :atom do
      constraints one_of: [:movie, :tv_series, :video_object]
    end

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

    attribute :pending_write, :boolean do
      default false
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :images, MediaManager.Library.Image
    has_many :identifiers, MediaManager.Library.Identifier
    has_many :seasons, MediaManager.Library.Season
    has_many :watched_files, MediaManager.Library.WatchedFile
  end
end
