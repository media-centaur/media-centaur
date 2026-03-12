defmodule MediaCentaur.Library.ChangeEntry do
  @moduledoc """
  A log entry recording a library change — an entity being added or removed.

  Stores a snapshot of the entity's name and type so removals remain visible
  after the entity is deleted. References entities only by UUID (no foreign key),
  so cascade deletes don't affect the log.
  """
  use Ash.Resource,
    domain: MediaCentaur.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "change_entries"
    repo MediaCentaur.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:entity_id, :entity_name, :entity_type, :kind]
      validate present([:entity_id, :entity_name, :entity_type, :kind])
    end

    create :backfill do
      accept [:entity_id, :entity_name, :entity_type, :kind, :inserted_at]
      validate present([:entity_id, :entity_name, :entity_type, :kind, :inserted_at])
    end

    read :recent do
      argument :limit, :integer, default: 10
      argument :since, :utc_datetime_usec

      filter expr(
               if not is_nil(^arg(:since)) do
                 inserted_at >= ^arg(:since)
               else
                 true
               end
             )

      prepare build(sort: [inserted_at: :desc], limit: arg(:limit))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :entity_id, :uuid_v7, allow_nil?: false, public?: true
    attribute :entity_name, :string, allow_nil?: false, public?: true

    attribute :entity_type, MediaCentaur.Library.Types.EntityType,
      allow_nil?: false,
      public?: true

    attribute :kind, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:added, :removed]]

    create_timestamp :inserted_at, writable?: true
  end
end
