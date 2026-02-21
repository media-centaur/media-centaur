defmodule MediaManager.Library.Image do
  @moduledoc """
  An image associated with a media entity — poster, backdrop, logo, or thumb.

  Each entity has at most one image per role, enforced by the `unique_entity_role`
  identity and the `find_or_create` upsert action.
  """
  use Ash.Resource,
    domain: MediaManager.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "images"
    repo MediaManager.Repo
  end

  actions do
    defaults [:read]

    update :update do
      primary? true
      accept [:content_url]
    end

    create :create do
      primary? true
      accept [:role, :url, :content_url, :extension, :entity_id]

      validate present([:role, :entity_id])
    end

    create :find_or_create do
      accept [:role, :url, :content_url, :extension, :entity_id]
      upsert? true
      upsert_identity :unique_entity_role
      upsert_fields []
    end
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

  identities do
    identity :unique_entity_role, [:entity_id, :role]
  end
end
