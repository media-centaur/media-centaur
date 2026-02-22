defmodule MediaManager.Library.WatchedFile do
  @moduledoc """
  Tracks a video file through the ingestion pipeline — from detection through
  TMDB search, metadata fetch, image download, and final completion.
  """
  use Ash.Resource,
    domain: MediaManager.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "watched_files"
    repo MediaManager.Repo

    custom_indexes do
      index [:state, :inserted_at], name: "watched_files_state_inserted_index"
    end
  end

  actions do
    defaults [:read]

    create :detect do
      accept [:file_path]

      change set_attribute(:state, :detected)
      change MediaManager.Library.WatchedFile.Changes.ParseFileName
    end

    update :search do
      require_atomic? false
      change set_attribute(:state, :searching)
      change MediaManager.Library.WatchedFile.Changes.SearchTmdb
    end

    update :fetch_metadata do
      require_atomic? false
      change set_attribute(:state, :fetching_metadata)
      change MediaManager.Library.WatchedFile.Changes.FetchMetadata
    end

    update :download_images do
      require_atomic? false
      change MediaManager.Library.WatchedFile.Changes.DownloadImages
    end

    read :detected_files do
      argument :limit, :integer, default: 10
      filter expr(state == :detected)
      prepare build(sort: [inserted_at: :asc], limit: arg(:limit))
    end

    update :claim do
      validate attribute_equals(:state, :detected)
      change set_attribute(:state, :queued)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :file_path, :string do
      allow_nil? false
    end

    attribute :parsed_title, :string
    attribute :parsed_year, :integer
    attribute :parsed_type, MediaManager.Library.Types.MediaType
    attribute :season_number, :integer
    attribute :episode_number, :integer
    attribute :tmdb_id, :string
    attribute :confidence_score, :float

    attribute :state, MediaManager.Library.Types.WatchedFileState do
      default :detected
    end

    attribute :search_title, :string
    attribute :error_message, :string

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :entity, MediaManager.Library.Entity
  end

  identities do
    identity :unique_file_path, [:file_path]
  end
end
