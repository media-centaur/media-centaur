defmodule MediaManager.Library.Identifier do
  use Ash.Resource,
    domain: MediaManager.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "identifiers"
    repo MediaManager.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:property_id, :value, :entity_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :property_id, :string
    attribute :value, :string

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :entity, MediaManager.Library.Entity
  end
end
