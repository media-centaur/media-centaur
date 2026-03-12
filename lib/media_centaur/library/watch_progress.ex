defmodule MediaCentaur.Library.WatchProgress do
  @moduledoc """
  Per-item playback progress. Tracks position, duration, and completion state
  for each playable item (movie, episode, or video object).
  """
  use Ash.Resource,
    domain: MediaCentaur.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "watch_progress"
    repo MediaCentaur.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :upsert_progress do
      accept [:entity_id, :season_number, :episode_number, :position_seconds, :duration_seconds]
      upsert? true
      upsert_identity :unique_playable_item

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
      prepare build(sort: [season_number: :asc, episode_number: :asc])
    end

    read :recently_watched do
      argument :limit, :integer, default: 5
      filter expr(not is_nil(last_watched_at))
      prepare build(sort: [last_watched_at: :desc], limit: arg(:limit), load: [:entity])
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

    attribute :season_number, :integer, allow_nil?: false, default: 0
    attribute :episode_number, :integer, allow_nil?: false, default: 0
    attribute :position_seconds, :float, default: 0.0
    attribute :duration_seconds, :float, default: 0.0
    attribute :completed, :boolean, default: false
    attribute :last_watched_at, :utc_datetime

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :entity, MediaCentaur.Library.Entity
  end

  identities do
    identity :unique_playable_item, [:entity_id, :season_number, :episode_number]
  end
end
