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
    defaults [:read, :destroy]

    create :link_file do
      accept [:file_path, :watch_dir, :entity_id]
      change set_attribute(:state, :complete)

      upsert? true
      upsert_identity :unique_file_path
    end

    create :detect do
      accept [:file_path, :watch_dir]

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

    read :claimable_files do
      argument :limit, :integer, default: 10
      argument :stale_threshold, :utc_datetime_usec, allow_nil?: false

      filter expr(
               state == :detected or
                 (state == :queued and updated_at < ^arg(:stale_threshold))
             )

      prepare build(sort: [inserted_at: :asc], limit: arg(:limit))
    end

    update :claim do
      require_atomic? false
      validate attribute_in(:state, [:detected, :queued])
      change set_attribute(:state, :queued)
    end

    update :approve do
      require_atomic? false
      validate attribute_equals(:state, :pending_review)
      change set_attribute(:state, :approved)
    end

    update :dismiss do
      require_atomic? false
      validate attribute_equals(:state, :pending_review)
      change set_attribute(:state, :dismissed)
    end

    update :retry do
      require_atomic? false
      validate attribute_equals(:state, :pending_review)

      change set_attribute(:state, :detected)
      change set_attribute(:tmdb_id, nil)
      change set_attribute(:confidence_score, nil)
      change set_attribute(:match_title, nil)
      change set_attribute(:match_year, nil)
      change set_attribute(:match_poster_path, nil)
      change set_attribute(:error_message, nil)
    end

    update :set_tmdb_match do
      require_atomic? false
      accept [:tmdb_id, :match_title, :match_year, :match_poster_path, :confidence_score]
      validate attribute_equals(:state, :pending_review)
    end

    update :update_state do
      accept [
        :state,
        :tmdb_id,
        :confidence_score,
        :match_title,
        :match_year,
        :match_poster_path,
        :error_message,
        :entity_id,
        :search_title,
        :parsed_type,
        :parsed_title,
        :season_number,
        :episode_number
      ]
    end

    read :pending_review_files do
      filter expr(state == :pending_review)
      prepare build(sort: [inserted_at: :asc])
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
    attribute :watch_dir, :string
    attribute :match_title, :string
    attribute :match_year, :string
    attribute :match_poster_path, :string

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
