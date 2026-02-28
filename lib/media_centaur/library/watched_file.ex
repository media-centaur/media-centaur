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
  end

  actions do
    defaults [:read, :destroy]

    create :link_file do
      accept [:file_path, :watch_dir, :entity_id]
      change set_attribute(:state, :complete)

      upsert? true
      upsert_identity :unique_file_path
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
