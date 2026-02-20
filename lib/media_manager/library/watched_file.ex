defmodule MediaManager.Library.WatchedFile do
  use Ash.Resource,
    domain: MediaManager.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "watched_files"
    repo MediaManager.Repo
  end

  actions do
    defaults [:create, :read, :update, :destroy]

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
  end

  attributes do
    uuid_primary_key :id

    attribute :file_path, :string do
      allow_nil? false
    end

    attribute :parsed_title, :string
    attribute :parsed_year, :integer

    attribute :parsed_type, :atom do
      constraints one_of: [:movie, :tv, :unknown]
    end

    attribute :season_number, :integer
    attribute :episode_number, :integer
    attribute :tmdb_id, :string
    attribute :confidence_score, :float

    attribute :state, :atom do
      constraints one_of: [
                    :detected,
                    :searching,
                    :pending_review,
                    :approved,
                    :fetching_metadata,
                    :fetching_images,
                    :complete,
                    :error,
                    :removed
                  ]

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
