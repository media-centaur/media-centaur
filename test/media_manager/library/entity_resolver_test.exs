defmodule MediaManager.Library.EntityResolverTest do
  use MediaManager.DataCase

  alias MediaManager.Library.{Entity, EntityResolver, Identifier}
  import MediaManager.TmdbStubs

  setup do
    setup_tmdb_client()
    :ok
  end

  defp find_identifier_by_tmdb_id(tmdb_id) do
    Identifier
    |> Ash.Query.for_read(:find_by_tmdb_id, %{tmdb_id: tmdb_id})
    |> Ash.read()
  end

  defp find_identifier_by_collection(collection_id) do
    Identifier
    |> Ash.Query.for_read(:find_by_tmdb_collection, %{collection_id: collection_id})
    |> Ash.read()
  end

  # ---------------------------------------------------------------------------
  # Movie resolution
  # ---------------------------------------------------------------------------

  describe "resolve/3 standalone movie" do
    test "creates entity, identifier, and images" do
      stub_routes([
        {"/movie/550", movie_detail()}
      ])

      context = %{file_path: "/media/fight_club.mkv", season_number: nil, episode_number: nil}

      assert {:ok, entity, :new} = EntityResolver.resolve("550", :movie, context)

      assert entity.type == :movie
      assert entity.name == "Fight Club"
      assert entity.content_url == "/media/fight_club.mkv"

      # Identifier created
      assert {:ok, [identifier]} = find_identifier_by_tmdb_id("550")
      assert identifier.entity_id == entity.id

      # Images created
      entity = Ash.get!(Entity, entity.id, action: :with_images)
      assert length(entity.images) >= 1
      assert Enum.any?(entity.images, &(&1.role == "poster"))
    end

    test "existing movie is reused — no duplicate entity" do
      existing = create_entity(%{type: :movie, name: "Fight Club"})
      create_identifier(%{entity_id: existing.id, property_id: "tmdb", value: "550"})

      context = %{file_path: "/media/fight_club_2.mkv", season_number: nil, episode_number: nil}

      assert {:ok, entity, :existing} = EntityResolver.resolve("550", :movie, context)
      assert entity.id == existing.id

      # content_url set on the existing entity
      reloaded = Ash.get!(Entity, entity.id)
      assert reloaded.content_url == "/media/fight_club_2.mkv"
    end

    test "existing movie with content_url already set is returned unchanged" do
      existing =
        create_entity(%{type: :movie, name: "Fight Club", content_url: "/media/original.mkv"})

      create_identifier(%{entity_id: existing.id, property_id: "tmdb", value: "550"})

      context = %{file_path: "/media/fight_club_2.mkv", season_number: nil, episode_number: nil}

      assert {:ok, entity, :existing} = EntityResolver.resolve("550", :movie, context)
      assert entity.id == existing.id

      reloaded = Ash.get!(Entity, entity.id)
      assert reloaded.content_url == "/media/original.mkv"
    end
  end

  describe "resolve/3 movie in collection" do
    test "creates movie_series entity + child movie + identifiers" do
      stub_routes([
        {"/movie/155", movie_in_collection_detail()},
        {"/collection/263", collection_detail()}
      ])

      context = %{file_path: "/media/dark_knight.mkv", season_number: nil, episode_number: nil}

      assert {:ok, entity, :new} = EntityResolver.resolve("155", :movie, context)

      assert entity.type == :movie_series
      assert entity.name == "The Shadowy Sentinel Collection"

      # Collection identifier
      assert {:ok, [collection_id]} = find_identifier_by_collection("263")
      assert collection_id.entity_id == entity.id

      # Movie-level TMDB identifier
      assert {:ok, [movie_id]} = find_identifier_by_tmdb_id("155")
      assert movie_id.entity_id == entity.id

      # Child movie
      entity = Ash.load!(entity, [:movies])
      assert length(entity.movies) == 1
      movie = hd(entity.movies)
      assert movie.name == "The Shadowy Sentinel"
      assert movie.content_url == "/media/dark_knight.mkv"
      assert movie.position == 1
    end

    test "existing movie series — adds new child movie" do
      # Pre-create the series entity and collection identifier
      series = create_entity(%{type: :movie_series, name: "The Shadowy Sentinel Collection"})
      create_identifier(%{entity_id: series.id, property_id: "tmdb_collection", value: "263"})

      stub_routes([
        {"/movie/49026",
         movie_detail(%{
           "id" => 49026,
           "title" => "The Shadowy Sentinel Rises",
           "belongs_to_collection" => %{"id" => 263, "name" => "The Shadowy Sentinel Collection"}
         })},
        {"/collection/263", collection_detail()}
      ])

      context = %{
        file_path: "/media/dark_knight_rises.mkv",
        season_number: nil,
        episode_number: nil
      }

      assert {:ok, entity, :new_child} = EntityResolver.resolve("49026", :movie, context)
      assert entity.id == series.id

      entity = Ash.load!(entity, [:movies])
      assert length(entity.movies) == 1
      movie = hd(entity.movies)
      assert movie.name == "The Shadowy Sentinel Rises"
      assert movie.position == 2
    end
  end

  # ---------------------------------------------------------------------------
  # TV resolution
  # ---------------------------------------------------------------------------

  describe "resolve/3 TV series" do
    test "creates entity, identifier, season, episode, and images" do
      stub_routes([
        {"/tv/1396/season/1", season_detail()},
        {"/tv/1396", tv_detail()}
      ])

      context = %{
        file_path: "/media/breaking_bad_s01e01.mkv",
        season_number: 1,
        episode_number: 1
      }

      assert {:ok, entity, :new} = EntityResolver.resolve("1396", :tv, context)

      assert entity.type == :tv_series
      assert entity.name == "Sample Show Eight"

      # Identifier
      assert {:ok, [identifier]} = find_identifier_by_tmdb_id("1396")
      assert identifier.entity_id == entity.id

      # Season + Episode
      entity = Ash.get!(Entity, entity.id, action: :with_associations)
      assert length(entity.seasons) == 1
      season = hd(entity.seasons)
      assert season.season_number == 1
      assert length(season.episodes) == 1
      episode = hd(season.episodes)
      assert episode.episode_number == 1
      assert episode.name == "Pilot"
      assert episode.content_url == "/media/breaking_bad_s01e01.mkv"
    end

    test "existing TV series — reuses entity, adds new episode" do
      existing = create_entity(%{type: :tv_series, name: "Sample Show Eight"})
      create_identifier(%{entity_id: existing.id, property_id: "tmdb", value: "1396"})

      stub_routes([
        {"/tv/1396/season/1",
         season_detail(%{
           "episodes" => [
             %{
               "episode_number" => 2,
               "name" => "Cat's in the Bag...",
               "overview" => "Walt and Jesse attempt to dispose of the bodies.",
               "runtime" => 48,
               "still_path" => "/tjMFMhGOFwyg8acoUMCmjMAdMf3.jpg"
             }
           ]
         })},
        {"/tv/1396", tv_detail()}
      ])

      context = %{
        file_path: "/media/breaking_bad_s01e02.mkv",
        season_number: 1,
        episode_number: 2
      }

      assert {:ok, entity, :existing} = EntityResolver.resolve("1396", :tv, context)
      assert entity.id == existing.id

      entity = Ash.get!(Entity, entity.id, action: :with_associations)
      assert length(entity.seasons) == 1
      episode = hd(hd(entity.seasons).episodes)
      assert episode.episode_number == 2
      assert episode.content_url == "/media/breaking_bad_s01e02.mkv"
    end

    test "missing season/episode numbers — no-op, returns entity" do
      stub_routes([
        {"/tv/1396", tv_detail()}
      ])

      context = %{
        file_path: "/media/breaking_bad.mkv",
        season_number: nil,
        episode_number: nil
      }

      assert {:ok, entity, :new} = EntityResolver.resolve("1396", :tv, context)
      assert entity.type == :tv_series

      # No seasons created (no season/episode numbers)
      entity = Ash.get!(Entity, entity.id, action: :with_associations)
      assert entity.seasons == []
    end
  end

  # ---------------------------------------------------------------------------
  # Extra resolution
  # ---------------------------------------------------------------------------

  describe "resolve/3 extras" do
    test "extra with season_number — creates TV parent and links extra to season" do
      stub_routes([
        {"/tv/1396/season/1", season_detail()},
        {"/tv/1396", tv_detail()}
      ])

      context = %{
        file_path: "/media/breaking_bad/Extras/making_of.mkv",
        season_number: 1,
        episode_number: nil,
        extra_title: "Making Of"
      }

      assert {:ok, entity, :new} = EntityResolver.resolve("1396", :extra, context)
      assert entity.type == :tv_series

      entity = Ash.get!(Entity, entity.id, action: :with_associations)
      assert length(entity.seasons) == 1
      season = hd(entity.seasons)
      assert length(season.extras) == 1
      extra = hd(season.extras)
      assert extra.name == "Making Of"
      assert extra.content_url == "/media/breaking_bad/Extras/making_of.mkv"
    end

    test "extra without season_number — creates movie parent and links extra" do
      stub_routes([
        {"/movie/550", movie_detail()}
      ])

      context = %{
        file_path: "/media/fight_club/Extras/behind_scenes.mkv",
        season_number: nil,
        episode_number: nil,
        extra_title: "Behind the Scenes"
      }

      assert {:ok, entity, :new} = EntityResolver.resolve("550", :extra, context)
      assert entity.type == :movie

      entity = Ash.get!(Entity, entity.id, action: :with_associations)
      assert length(entity.extras) == 1
      extra = hd(entity.extras)
      assert extra.name == "Behind the Scenes"
    end

    test "extra on existing entity — reuses parent, creates extra only" do
      existing = create_entity(%{type: :movie, name: "Fight Club"})
      create_identifier(%{entity_id: existing.id, property_id: "tmdb", value: "550"})

      context = %{
        file_path: "/media/fight_club/Extras/deleted_scenes.mkv",
        season_number: nil,
        episode_number: nil,
        extra_title: "Deleted Scenes"
      }

      assert {:ok, entity, :existing} = EntityResolver.resolve("550", :extra, context)
      assert entity.id == existing.id

      entity = Ash.get!(Entity, entity.id, action: :with_associations)
      assert length(entity.extras) == 1
      assert hd(entity.extras).name == "Deleted Scenes"
    end
  end

  # ---------------------------------------------------------------------------
  # Race-loss recovery
  # ---------------------------------------------------------------------------

  describe "race-loss recovery" do
    test "detects race loss, destroys duplicate, returns winner" do
      # Pre-create a "winner" entity with the same TMDB identifier
      winner = create_entity(%{type: :movie, name: "Fight Club (Winner)"})
      create_identifier(%{entity_id: winner.id, property_id: "tmdb", value: "550"})

      # Stub the TMDB API to return movie data
      stub_routes([
        {"/movie/550", movie_detail()}
      ])

      context = %{
        file_path: "/media/fight_club_racer.mkv",
        season_number: nil,
        episode_number: nil
      }

      # The resolver will create a new entity, then when creating the identifier
      # it'll find the existing one belongs to winner. It destroys the duplicate
      # and returns the winner via link_file_to_existing_entity.
      assert {:ok, entity, :existing} = EntityResolver.resolve("550", :movie, context)
      assert entity.id == winner.id

      # The duplicate entity was destroyed — only the winner remains
      {:ok, entities} = Ash.read(Entity)
      assert length(entities) == 1
      assert hd(entities).id == winner.id
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  describe "error handling" do
    test "TMDB returns 404 for movie — propagates error" do
      stub_tmdb_error("/movie/999999", 404)

      context = %{file_path: "/media/nonexistent.mkv", season_number: nil, episode_number: nil}

      assert {:error, _reason} = EntityResolver.resolve("999999", :movie, context)

      # No entity created
      {:ok, entities} = Ash.read(Entity)
      assert entities == []
    end

    test "TMDB returns 500 for TV — propagates error" do
      stub_tmdb_error("/tv/999999", 500)

      context = %{
        file_path: "/media/nonexistent.mkv",
        season_number: 1,
        episode_number: 1
      }

      assert {:error, _reason} = EntityResolver.resolve("999999", :tv, context)
      {:ok, entities} = Ash.read(Entity)
      assert entities == []
    end

    test "TMDB season fetch fails — propagates error for TV entity" do
      # Use a Req.Test stub with explicit path routing — more specific paths first
      Req.Test.stub(:tmdb, fn conn ->
        cond do
          String.contains?(conn.request_path, "/season/") ->
            json_resp(conn, 500, %{"status_message" => "Server Error"})

          String.contains?(conn.request_path, "/tv/1396") ->
            json_resp(conn, 200, tv_detail())

          true ->
            json_resp(conn, 404, %{"status_message" => "Not Found"})
        end
      end)

      context = %{
        file_path: "/media/bb_s01e01.mkv",
        season_number: 1,
        episode_number: 1
      }

      assert {:error, _reason} = EntityResolver.resolve("1396", :tv, context)
    end
  end

  # ---------------------------------------------------------------------------
  # Unknown type fallback
  # ---------------------------------------------------------------------------

  describe "resolve/3 unknown type" do
    test "unknown type tries movie first" do
      stub_routes([
        {"/movie/550", movie_detail()}
      ])

      context = %{file_path: "/media/fight_club.mkv", season_number: nil, episode_number: nil}

      assert {:ok, entity, :new} = EntityResolver.resolve("550", :unknown, context)
      assert entity.type == :movie
    end

    test "unknown type falls back to TV when movie returns error" do
      # Use explicit routing for ambiguous paths
      Req.Test.stub(:tmdb, fn conn ->
        cond do
          String.contains?(conn.request_path, "/movie/") ->
            json_resp(conn, 404, %{"status_message" => "Not Found"})

          String.contains?(conn.request_path, "/tv/1396/season") ->
            json_resp(conn, 200, season_detail())

          String.contains?(conn.request_path, "/tv/1396") ->
            json_resp(conn, 200, tv_detail())

          true ->
            json_resp(conn, 404, %{"status_message" => "Not Found"})
        end
      end)

      context = %{
        file_path: "/media/show.mkv",
        season_number: nil,
        episode_number: nil
      }

      assert {:ok, entity, :new} = EntityResolver.resolve("1396", :unknown, context)
      assert entity.type == :tv_series
    end
  end

  # Private helper for inline stubs
  defp json_resp(conn, status, data) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, JSON.encode!(data))
  end
end
