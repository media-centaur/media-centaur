defmodule MediaCentaur.Library.ExtraProgress do
  @moduledoc """
  Per-extra playback progress. Tracks position, duration, and completion state
  for bonus content (featurettes, deleted scenes, behind-the-scenes).

  Keyed by `extra_id` — each extra gets at most one progress record.
  The `entity_id` is denormalized for efficient queries (list all extra progress
  for an entity without joining through extras).
  """
  use Ash.Resource,
    domain: MediaCentaur.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "extra_progress"
    repo MediaCentaur.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :find_or_create do
      accept [:extra_id, :entity_id, :position_seconds, :duration_seconds]
      upsert? true
      upsert_identity :unique_extra

      upsert_fields [
        :position_seconds,
        :duration_seconds,
        :last_watched_at,
        :updated_at
      ]

      change set_attribute(:last_watched_at, &DateTime.utc_now/0)
    end

    read :for_entity do
      argument :entity_id, :uuid, allow_nil?: false
      filter expr(entity_id == ^arg(:entity_id))
    end

    read :by_extra do
      argument :extra_id, :uuid, allow_nil?: false
      filter expr(extra_id == ^arg(:extra_id))
    end

    update :mark_completed do
      accept []
      change set_attribute(:completed, true)
      change set_attribute(:last_watched_at, &DateTime.utc_now/0)
    end

    update :mark_incomplete do
      accept []
      change set_attribute(:completed, false)
      change set_attribute(:last_watched_at, &DateTime.utc_now/0)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :position_seconds, :float, default: 0.0
    attribute :duration_seconds, :float, default: 0.0
    attribute :completed, :boolean, default: false
    attribute :last_watched_at, :utc_datetime

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :extra, MediaCentaur.Library.Extra, allow_nil?: false
    belongs_to :entity, MediaCentaur.Library.Entity, allow_nil?: false
  end

  identities do
    identity :unique_extra, [:extra_id]
  end
end
