defmodule MediaCentaur.Library.Image do
  @moduledoc """
  An image associated with a media entity — poster, backdrop, logo, or thumb.

  Each entity has at most one image per role, enforced by the `unique_entity_role`
  identity and the `find_or_create` upsert action.
  """
  use Ash.Resource,
    domain: MediaCentaur.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "images"
    repo MediaCentaur.Repo
  end

  actions do
    defaults [:read, :destroy]

    read :by_entity do
      argument :entity_id, :uuid, allow_nil?: false
      filter expr(entity_id == ^arg(:entity_id))
    end

    read :by_episode do
      argument :episode_id, :uuid, allow_nil?: false
      filter expr(episode_id == ^arg(:episode_id))
    end

    read :by_movie do
      argument :movie_id, :uuid, allow_nil?: false
      filter expr(movie_id == ^arg(:movie_id))
    end

    read :incomplete do
      filter expr(not is_nil(url) and is_nil(content_url))
      prepare build(load: [:entity])
    end

    update :update do
      primary? true
      accept [:content_url]
    end

    update :clear_content_url do
      change set_attribute(:content_url, nil)
    end

    create :create do
      primary? true
      accept [:role, :url, :content_url, :extension, :entity_id, :movie_id, :episode_id]

      validate present([:role])
    end

    create :find_or_create do
      accept [:role, :url, :content_url, :extension, :entity_id]
      upsert? true
      upsert_identity :unique_entity_role
      upsert_fields []
    end

    create :find_or_create_for_movie do
      accept [:role, :url, :content_url, :extension, :movie_id]
      upsert? true
      upsert_identity :unique_movie_role
      upsert_fields []
    end

    create :find_or_create_for_episode do
      accept [:role, :url, :content_url, :extension, :episode_id]
      upsert? true
      upsert_identity :unique_episode_role
      upsert_fields []
    end

    # --- Generic actions (MCP tools) ---

    action :refresh_cache, :map do
      description "Clear all cached artwork from disk and re-download images for all entities"

      run fn _input, _context ->
        case MediaCentaur.Admin.refresh_image_cache() do
          {:ok, count} -> {:ok, %{status: :refreshed, entity_count: count}}
          {:error, _} = error -> error
        end
      end
    end

    action :retry_incomplete, :map do
      description "Re-download images that have a TMDB URL but no local content"

      run fn _input, _context ->
        case MediaCentaur.Admin.retry_incomplete_images() do
          {:ok, result} -> {:ok, result}
          {:error, _} = error -> error
        end
      end
    end

    action :dismiss_incomplete, :map do
      description "Delete all image records that have a TMDB URL but no local content"

      run fn _input, _context ->
        case MediaCentaur.Admin.dismiss_incomplete_images() do
          {:ok, count} -> {:ok, %{status: :dismissed, count: count}}
          {:error, _} = error -> error
        end
      end
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
    belongs_to :entity, MediaCentaur.Library.Entity do
      allow_nil? true
    end

    belongs_to :movie, MediaCentaur.Library.Movie do
      allow_nil? true
    end

    belongs_to :episode, MediaCentaur.Library.Episode do
      allow_nil? true
    end
  end

  identities do
    identity :unique_entity_role, [:entity_id, :role]
    identity :unique_movie_role, [:movie_id, :role]
    identity :unique_episode_role, [:episode_id, :role]
  end
end
