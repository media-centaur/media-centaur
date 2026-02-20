defmodule MediaManager.Library.Image do
  use Ash.Resource,
    domain: MediaManager.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "images"
    repo MediaManager.Repo
  end

  actions do
    defaults [:create, :read, :update, :destroy]
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :string
    attribute :url, :string
    attribute :content_url, :string
    attribute :extension, :string

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :entity, MediaManager.Library.Entity
  end
end
