defmodule MediaManager.Library.Episode do
  @moduledoc """
  A TV episode belonging to a `Season`. Stores per-episode metadata from TMDB
  and the local `content_url` linking to the video file.
  """
  use Ash.Resource,
    domain: MediaManager.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "episodes"
    repo MediaManager.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:episode_number, :name, :description, :duration, :content_url, :season_id]
    end

    create :find_or_create do
      accept [:episode_number, :name, :description, :duration, :content_url, :season_id]
      upsert? true
      upsert_identity :unique_season_episode
      upsert_fields []
    end

    update :set_content_url do
      accept [:content_url]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :episode_number, :integer
    attribute :name, :string
    attribute :description, :string
    attribute :duration, :string
    attribute :content_url, :string

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :season, MediaManager.Library.Season
    has_many :images, MediaManager.Library.Image
  end

  identities do
    identity :unique_season_episode, [:season_id, :episode_number]
  end
end
