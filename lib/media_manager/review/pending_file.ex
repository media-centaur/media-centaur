defmodule MediaManager.Review.PendingFile do
  @moduledoc """
  A file awaiting human review before library ingestion.

  Created when the pipeline's Search stage returns `{:needs_review, payload}`
  (low confidence or no TMDB match). Stores everything the reviewer needs to
  make a decision — parsed file info, best TMDB match, and all scored candidates.
  """
  use Ash.Resource,
    domain: MediaManager.Review,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "review_pending_files"
    repo MediaManager.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :file_path,
        :watch_directory,
        :parsed_title,
        :parsed_year,
        :parsed_type,
        :season_number,
        :episode_number,
        :tmdb_id,
        :tmdb_type,
        :confidence,
        :match_title,
        :match_year,
        :match_poster_path,
        :candidates,
        :error_message
      ]
    end

    create :find_or_create do
      accept [
        :file_path,
        :watch_directory,
        :parsed_title,
        :parsed_year,
        :parsed_type,
        :season_number,
        :episode_number,
        :tmdb_id,
        :tmdb_type,
        :confidence,
        :match_title,
        :match_year,
        :match_poster_path,
        :candidates,
        :error_message
      ]

      upsert? true
      upsert_identity :unique_file_path
    end

    update :approve do
      require_atomic? false
      validate attribute_equals(:status, :pending)
      change set_attribute(:status, :approved)
    end

    update :dismiss do
      require_atomic? false
      validate attribute_equals(:status, :pending)
      change set_attribute(:status, :dismissed)
    end

    update :set_tmdb_match do
      require_atomic? false
      accept [:tmdb_id, :tmdb_type, :confidence, :match_title, :match_year, :match_poster_path]
      validate attribute_equals(:status, :pending)
    end

    read :pending do
      filter expr(status == :pending)
      prepare build(sort: [inserted_at: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    # File info
    attribute :file_path, :string, allow_nil?: false
    attribute :watch_directory, :string

    # Parsed info (from Parser.Result)
    attribute :parsed_title, :string
    attribute :parsed_year, :integer
    attribute :parsed_type, :string
    attribute :season_number, :integer
    attribute :episode_number, :integer

    # Best TMDB match (from Search stage)
    attribute :tmdb_id, :integer
    attribute :tmdb_type, :string
    attribute :confidence, :float
    attribute :match_title, :string
    attribute :match_year, :string
    attribute :match_poster_path, :string

    # All scored candidates (JSON array of maps)
    attribute :candidates, {:array, :map}

    # Error if search failed
    attribute :error_message, :string

    # Workflow status
    attribute :status, :atom do
      constraints one_of: [:pending, :approved, :dismissed]
      default :pending
    end

    timestamps()
  end

  identities do
    identity :unique_file_path, [:file_path]
  end
end
