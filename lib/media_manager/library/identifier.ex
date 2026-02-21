defmodule MediaManager.Library.Identifier do
  @moduledoc """
  An external identifier linking an entity to a third-party service
  (TMDB, IMDB, etc.). Modelled as a schema.org `PropertyValue`.
  """
  use Ash.Resource,
    domain: MediaManager.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "identifiers"
    repo MediaManager.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:property_id, :value, :entity_id]

      validate present([:property_id, :value, :entity_id])
    end

    create :find_or_create do
      accept [:property_id, :value, :entity_id]
      upsert? true
      upsert_identity :unique_external_id
      upsert_fields []
    end

    read :find_by_tmdb_id do
      argument :tmdb_id, :string, allow_nil?: false
      filter expr(property_id == "tmdb" and value == ^arg(:tmdb_id))
      prepare build(load: [:entity], limit: 1)
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

  identities do
    identity :unique_external_id, [:property_id, :value]
  end
end
