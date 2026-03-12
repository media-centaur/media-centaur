defmodule MediaCentaur.Library.Entity do
  @moduledoc """
  A media entity in the library — a movie, TV series, or generic video object.

  Entities are created from TMDB metadata and served to the user-interface
  via Phoenix Channels.
  """
  use Ash.Resource,
    domain: MediaCentaur.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "entities"
    repo MediaCentaur.Repo
  end

  actions do
    defaults [:read, :destroy]

    read :with_associations do
      prepare build(
                load: [
                  :images,
                  :identifiers,
                  :watch_progress,
                  :extras,
                  seasons: [:extras, episodes: [:images]],
                  movies: [:images]
                ]
              )
    end

    read :with_progress do
      prepare build(
                load: [
                  :watch_progress,
                  seasons: [:episodes],
                  movies: []
                ]
              )
    end

    read :with_images do
      prepare build(
                load: [
                  :images,
                  seasons: [episodes: [:images]],
                  movies: [:images]
                ]
              )
    end

    create :create do
      accept [
        :type,
        :name,
        :description,
        :date_published,
        :genres,
        :url,
        :duration,
        :director,
        :content_rating,
        :content_url,
        :number_of_seasons,
        :aggregate_rating_value
      ]

      validate present([:type, :name])
    end

    read :by_ids do
      argument :ids, {:array, :uuid_v7}, allow_nil?: false
      filter expr(id in ^arg(:ids))

      prepare build(
                load: [
                  :images,
                  :identifiers,
                  :watch_progress,
                  :extras,
                  seasons: [:extras, episodes: [:images]],
                  movies: [:images]
                ]
              )
    end

    read :all_files_absent do
      filter expr(
               exists(watched_files, true) and
                 not exists(watched_files, state == :complete)
             )
    end

    update :set_content_url do
      accept [:content_url]
    end

    # --- Generic actions (MCP tools) ---

    action :parse_filename, :map do
      description "Parse a video filename into structured metadata (title, year, type, season, episode)"
      argument :file_path, :string, allow_nil?: false

      run fn input, _context ->
        result = MediaCentaur.Parser.parse(input.arguments.file_path)
        {:ok, Map.from_struct(result)}
      end
    end

    action :resolve_playback, :map do
      description "Resolve a UUID into playback parameters (content URL, resume position, episode info)"
      argument :uuid, :string, allow_nil?: false

      run fn input, _context ->
        case MediaCentaur.Playback.Resolver.resolve(input.arguments.uuid) do
          {:ok, params} -> {:ok, params}
          {:error, reason} -> {:error, Ash.Error.Unknown.exception(error: "#{reason}")}
        end
      end
    end

    action :trigger_scan, :map do
      description "Trigger a file system scan across all watched directories"

      run fn _input, _context ->
        MediaCentaur.Watcher.Supervisor.scan()
        {:ok, %{status: :triggered}}
      end
    end

    action :measure_storage, {:array, :map} do
      description "Measure disk usage for watch directories, images, and database"

      run fn _input, _context ->
        {:ok, MediaCentaur.Storage.measure_all()}
      end
    end

    action :watcher_statuses, {:array, :map} do
      description "Get the current status of all file system watchers"

      run fn _input, _context ->
        statuses =
          MediaCentaur.Watcher.Supervisor.statuses()
          |> Enum.map(fn {dir, status} -> %{directory: dir, status: status} end)

        {:ok, statuses}
      end
    end

    action :serialize_entity, :map do
      description "Load and serialize an entity to its schema.org JSON-LD representation"
      argument :entity_id, :uuid_v7, allow_nil?: false

      run fn input, _context ->
        case MediaCentaur.Library.Helpers.load_entity(input.arguments.entity_id) do
          {:ok, entity} -> {:ok, MediaCentaur.Serializer.serialize_entity(entity)}
          {:error, _} = error -> error
        end
      end
    end

    action :clear_database, :map do
      description "Destroy all library records and clear image files from disk (destructive!)"

      run fn _input, _context ->
        case MediaCentaur.Admin.clear_database() do
          :ok -> {:ok, %{status: :cleared}}
          {:error, _} = error -> error
        end
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :type, MediaCentaur.Library.Types.EntityType
    attribute :name, :string
    attribute :description, :string
    attribute :date_published, :string
    attribute :genres, {:array, :string}
    attribute :content_url, :string
    attribute :url, :string
    attribute :duration, :string
    attribute :director, :string
    attribute :content_rating, :string
    attribute :number_of_seasons, :integer
    attribute :aggregate_rating_value, :float

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :images, MediaCentaur.Library.Image
    has_many :identifiers, MediaCentaur.Library.Identifier
    has_many :movies, MediaCentaur.Library.Movie
    has_many :extras, MediaCentaur.Library.Extra
    has_many :seasons, MediaCentaur.Library.Season
    has_many :watched_files, MediaCentaur.Library.WatchedFile
    has_many :watch_progress, MediaCentaur.Library.WatchProgress
  end
end
