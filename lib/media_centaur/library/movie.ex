defmodule MediaCentaur.Library.Movie do
  @moduledoc """
  A child movie belonging to a `MovieSeries` entity. Parallel to `Episode`
  belonging to a `Season` — stores per-movie metadata from TMDB and the
  local `content_url` linking to the video file.
  """
  use Ash.Resource,
    domain: MediaCentaur.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "movies"
    repo MediaCentaur.Repo
  end

  actions do
    defaults [:read, :destroy]

    read :by_entity do
      argument :entity_id, :uuid, allow_nil?: false
      filter expr(entity_id == ^arg(:entity_id))
    end

    create :create do
      primary? true

      accept [
        :name,
        :description,
        :date_published,
        :duration,
        :director,
        :content_rating,
        :content_url,
        :url,
        :aggregate_rating_value,
        :tmdb_id,
        :position,
        :entity_id
      ]
    end

    create :find_or_create do
      accept [
        :name,
        :description,
        :date_published,
        :duration,
        :director,
        :content_rating,
        :content_url,
        :url,
        :aggregate_rating_value,
        :tmdb_id,
        :position,
        :entity_id
      ]

      upsert? true
      upsert_identity :unique_entity_movie
      upsert_fields []
    end

    update :set_content_url do
      accept [:content_url]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string
    attribute :description, :string
    attribute :date_published, :string
    attribute :duration, :string
    attribute :director, :string
    attribute :content_rating, :string
    attribute :content_url, :string
    attribute :url, :string
    attribute :aggregate_rating_value, :float
    attribute :tmdb_id, :string
    attribute :position, :integer

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :entity, MediaCentaur.Library.Entity
    has_many :images, MediaCentaur.Library.Image
  end

  identities do
    identity :unique_entity_movie, [:entity_id, :tmdb_id]
  end
end
