defmodule MediaCentaur.Library.Extra do
  @moduledoc """
  A bonus feature (featurette, behind-the-scenes, deleted scene) belonging to
  a movie `Entity`. Extras live in subdirectories like `Extras/` alongside
  the main movie file and are serialized as `hasPart` → `VideoObject` entries.
  """
  use Ash.Resource,
    domain: MediaCentaur.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "extras"
    repo MediaCentaur.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :content_url, :position, :entity_id, :season_id]
    end

    create :find_or_create do
      accept [:name, :content_url, :position, :entity_id, :season_id]
      upsert? true
      upsert_identity :unique_entity_extra
      upsert_fields []
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string
    attribute :content_url, :string
    attribute :position, :integer

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :entity, MediaCentaur.Library.Entity
    belongs_to :season, MediaCentaur.Library.Season
  end

  identities do
    identity :unique_entity_extra, [:entity_id, :content_url]
  end
end
