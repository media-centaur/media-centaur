defmodule MediaCentaur.Library.WatchedFile do
  @moduledoc """
  Links a video file to its resolved library entity.
  """
  use Ash.Resource,
    domain: MediaCentaur.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "watched_files"
    repo MediaCentaur.Repo

    custom_indexes do
      index [:entity_id], name: "watched_files_entity_id_index"
      index [:watch_dir, :state], name: "watched_files_watch_dir_state_index"
    end
  end

  actions do
    defaults [:read, :destroy]

    create :link_file do
      accept [:file_path, :watch_dir, :entity_id]
      change set_attribute(:state, :complete)

      upsert? true
      upsert_identity :unique_file_path
    end

    update :mark_absent do
      change set_attribute(:state, :absent)
      change set_attribute(:absent_since, &DateTime.utc_now/0)
    end

    update :mark_present do
      change set_attribute(:state, :complete)
      change set_attribute(:absent_since, nil)
    end

    update :set_absent_since do
      accept [:absent_since]
    end

    read :expired_absent do
      argument :cutoff, :utc_datetime_usec, allow_nil?: false
      filter expr(state == :absent and absent_since < ^arg(:cutoff))
    end

    read :by_watch_dir do
      argument :watch_dir, :string, allow_nil?: false
      argument :state, MediaCentaur.Library.Types.WatchedFileState, allow_nil?: false
      filter expr(watch_dir == ^arg(:watch_dir) and state == ^arg(:state))
    end

    read :by_entity do
      argument :entity_id, :uuid, allow_nil?: false
      filter expr(entity_id == ^arg(:entity_id))
    end

    read :by_file_paths do
      argument :file_paths, {:array, :string}, allow_nil?: false
      filter expr(file_path in ^arg(:file_paths))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :file_path, :string do
      allow_nil? false
    end

    attribute :state, MediaCentaur.Library.Types.WatchedFileState do
      default :complete
    end

    attribute :watch_dir, :string
    attribute :absent_since, :utc_datetime_usec

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :entity, MediaCentaur.Library.Entity
  end

  identities do
    identity :unique_file_path, [:file_path]
  end
end
