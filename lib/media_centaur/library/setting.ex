defmodule MediaCentaur.Library.Setting do
  @moduledoc """
  Key/value settings store persisted in SQLite.

  Used by the logging system to persist enabled component toggles and
  framework log suppression across restarts.
  """
  use Ash.Resource,
    domain: MediaCentaur.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "settings"
    repo MediaCentaur.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:key, :value]
    end

    update :update do
      accept [:value]
    end

    read :by_key do
      argument :key, :string, allow_nil?: false
      filter expr(key == ^arg(:key))
    end

    create :find_or_create do
      accept [:key, :value]
      upsert? true
      upsert_identity :unique_key
      upsert_fields [:value]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string, allow_nil?: false
    attribute :value, :map

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_key, [:key]
  end
end
