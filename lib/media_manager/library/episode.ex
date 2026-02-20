defmodule MediaManager.Library.Episode do
  use Ash.Resource,
    domain: MediaManager.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "episodes"
    repo MediaManager.Repo
  end

  actions do
    defaults [:create, :read, :update, :destroy]
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
  end
end
