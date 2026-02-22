defmodule MediaManager.Library.Season do
  @moduledoc """
  A TV season belonging to a `TVSeries` entity. Created from TMDB season data
  when a file for that season is first ingested.
  """
  use Ash.Resource,
    domain: MediaManager.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "seasons"
    repo MediaManager.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:season_number, :number_of_episodes, :name, :entity_id]
    end

    create :find_or_create do
      accept [:season_number, :number_of_episodes, :name, :entity_id]
      upsert? true
      upsert_identity :unique_entity_season
      upsert_fields []
    end
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
    has_many :extras, MediaManager.Library.Extra
  end

  identities do
    identity :unique_entity_season, [:entity_id, :season_number]
  end
end
