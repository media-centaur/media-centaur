defmodule MediaCentaur.Playback.EpisodeListTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Playback.EpisodeList

  import MediaCentaur.TestFactory

  describe "list_available/1" do
    test "returns sorted {season, episode, url} tuples for episodes with content_url" do
      entity =
        build_entity(%{
          seasons: [
            build_season(%{
              season_number: 1,
              episodes: [
                build_episode(%{episode_number: 2, content_url: "/ep2.mkv"}),
                build_episode(%{episode_number: 1, content_url: "/ep1.mkv"})
              ]
            })
          ]
        })

      assert EpisodeList.list_available(entity) == [
               {1, 1, "/ep1.mkv"},
               {1, 2, "/ep2.mkv"}
             ]
    end

    test "skips episodes without content_url" do
      entity =
        build_entity(%{
          seasons: [
            build_season(%{
              season_number: 1,
              episodes: [
                build_episode(%{episode_number: 1, content_url: "/ep1.mkv"}),
                build_episode(%{episode_number: 2, content_url: nil})
              ]
            })
          ]
        })

      assert EpisodeList.list_available(entity) == [{1, 1, "/ep1.mkv"}]
    end

    test "handles empty seasons list" do
      entity = build_entity(%{seasons: []})
      assert EpisodeList.list_available(entity) == []
    end

    test "sorts across multiple seasons" do
      entity =
        build_entity(%{
          seasons: [
            build_season(%{
              season_number: 2,
              episodes: [
                build_episode(%{episode_number: 1, content_url: "/s2e1.mkv"})
              ]
            }),
            build_season(%{
              season_number: 1,
              episodes: [
                build_episode(%{episode_number: 3, content_url: "/s1e3.mkv"}),
                build_episode(%{episode_number: 1, content_url: "/s1e1.mkv"})
              ]
            })
          ]
        })

      assert EpisodeList.list_available(entity) == [
               {1, 1, "/s1e1.mkv"},
               {1, 3, "/s1e3.mkv"},
               {2, 1, "/s2e1.mkv"}
             ]
    end
  end

  describe "index_progress_by_key/1" do
    test "indexes by {season_number, episode_number} tuple" do
      progress_a = build_progress(%{season_number: 1, episode_number: 1, position_seconds: 30.0})
      progress_b = build_progress(%{season_number: 1, episode_number: 2, position_seconds: 60.0})

      index = EpisodeList.index_progress_by_key([progress_a, progress_b])

      assert index[{1, 1}] == progress_a
      assert index[{1, 2}] == progress_b
      assert map_size(index) == 2
    end
  end

  describe "find_content_url/3" do
    setup do
      entity =
        build_entity(%{
          seasons: [
            build_season(%{
              season_number: 1,
              episodes: [
                build_episode(%{episode_number: 1, content_url: "/s1e1.mkv"}),
                build_episode(%{episode_number: 2, content_url: "/s1e2.mkv"})
              ]
            })
          ]
        })

      %{entity: entity}
    end

    test "returns {:ok, url} for valid season/episode", %{entity: entity} do
      assert EpisodeList.find_content_url(entity, 1, 1) == {:ok, "/s1e1.mkv"}
      assert EpisodeList.find_content_url(entity, 1, 2) == {:ok, "/s1e2.mkv"}
    end

    test "returns {:error, :invalid_episode} for missing season", %{entity: entity} do
      assert EpisodeList.find_content_url(entity, 99, 1) == {:error, :invalid_episode}
    end

    test "returns {:error, :invalid_episode} for missing episode", %{entity: entity} do
      assert EpisodeList.find_content_url(entity, 1, 99) == {:error, :invalid_episode}
    end
  end

  describe "find_episode_name/3" do
    setup do
      entity =
        build_entity(%{
          seasons: [
            build_season(%{
              season_number: 1,
              episodes: [
                build_episode(%{episode_number: 1, name: "Pilot"}),
                build_episode(%{episode_number: 2, name: "The Cat's in the Bag..."})
              ]
            })
          ]
        })

      %{entity: entity}
    end

    test "returns name for valid season/episode", %{entity: entity} do
      assert EpisodeList.find_episode_name(entity, 1, 1) == "Pilot"
      assert EpisodeList.find_episode_name(entity, 1, 2) == "The Cat's in the Bag..."
    end

    test "returns nil for missing season", %{entity: entity} do
      assert EpisodeList.find_episode_name(entity, 99, 1) == nil
    end

    test "returns nil when season_number is nil", %{entity: entity} do
      assert EpisodeList.find_episode_name(entity, nil, 1) == nil
    end

    test "returns nil when episode_number is nil", %{entity: entity} do
      assert EpisodeList.find_episode_name(entity, 1, nil) == nil
    end
  end

  describe "find_by_content_url/2" do
    setup do
      entity =
        build_entity(%{
          seasons: [
            build_season(%{
              season_number: 1,
              episodes: [
                build_episode(%{episode_number: 1, content_url: "/s1e1.mkv"}),
                build_episode(%{episode_number: 2, content_url: "/s1e2.mkv"})
              ]
            }),
            build_season(%{
              season_number: 2,
              episodes: [
                build_episode(%{episode_number: 1, content_url: "/s2e1.mkv"})
              ]
            })
          ]
        })

      %{entity: entity}
    end

    test "returns {season_number, episode_number} for matching url", %{entity: entity} do
      assert EpisodeList.find_by_content_url(entity, "/s1e2.mkv") == {1, 2}
      assert EpisodeList.find_by_content_url(entity, "/s2e1.mkv") == {2, 1}
    end

    test "returns nil when no match", %{entity: entity} do
      assert EpisodeList.find_by_content_url(entity, "/nonexistent.mkv") == nil
    end
  end
end
