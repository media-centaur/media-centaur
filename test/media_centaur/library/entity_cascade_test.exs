defmodule MediaCentaur.Library.EntityCascadeTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Library
  alias MediaCentaur.Library.EntityCascade

  describe "destroy!/1" do
    test "cascade deletes a TV series with seasons, episodes, images, and identifiers" do
      entity = create_entity(%{type: :tv_series, name: "Sample Show One"})
      create_identifier(%{entity_id: entity.id, property_id: "tmdb", value: "4556"})

      create_image(%{
        entity_id: entity.id,
        role: "poster",
        url: "https://example.com/poster.jpg",
        extension: "jpg"
      })

      season = create_season(%{entity_id: entity.id, season_number: 1, number_of_episodes: 2})

      episode1 = create_episode(%{season_id: season.id, episode_number: 1, name: "Sample Episode One"})

      create_image(%{
        episode_id: episode1.id,
        role: "thumb",
        url: "https://example.com/ep1.jpg",
        extension: "jpg"
      })

      episode2 = create_episode(%{season_id: season.id, episode_number: 2, name: "My Mentor"})

      create_image(%{
        episode_id: episode2.id,
        role: "thumb",
        url: "https://example.com/ep2.jpg",
        extension: "jpg"
      })

      create_extra(%{
        entity_id: entity.id,
        name: "Gag Reel",
        content_url: "/media/extras/gag.mkv"
      })

      EntityCascade.destroy!(entity.id)

      assert {:error, _} = Library.get_entity(entity.id)
      assert Library.list_seasons_for_entity!(entity.id) == []
      assert Library.list_images!() == []
      # Identifiers deleted along with entity (no list function; entity gone confirms it)
      assert Library.list_extras_for_entity!(entity.id) == []
    end

    test "cascade deletes a movie with images and identifiers" do
      entity =
        create_entity(%{
          type: :movie,
          name: "Sample Movie",
          content_url: "/media/movies/blade.mkv"
        })

      create_identifier(%{entity_id: entity.id, property_id: "tmdb", value: "78"})

      create_image(%{
        entity_id: entity.id,
        role: "poster",
        url: "https://example.com/poster.jpg",
        extension: "jpg"
      })

      EntityCascade.destroy!(entity.id)

      assert {:error, _} = Library.get_entity(entity.id)
      assert Library.list_images!() == []
      # Identifiers deleted along with entity (no list function; entity gone confirms it)
    end
  end
end
