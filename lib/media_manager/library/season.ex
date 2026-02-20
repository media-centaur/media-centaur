defmodule MediaManager.Library.Season do
  use Ash.Resource,
    domain: MediaManager.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "seasons"
    repo MediaManager.Repo
  end

  actions do
    defaults [:create, :read, :update, :destroy]
  end

  attributes do
    uuid_primary_key :id

    attribute :season_number, :integer
    attribute :number_of_episodes, :integer
    attribute :name, :string

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :entity, MediaManager.Library.Entity
    has_many :episodes, MediaManager.Library.Episode
  end
end
