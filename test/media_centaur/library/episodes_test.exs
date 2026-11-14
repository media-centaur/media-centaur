defmodule MediaCentaur.Library.EpisodesTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library.EpisodeOrder
  alias MediaCentaur.Library.Episodes

  import MediaCentaur.TestFactory

  describe "ids_by_season_episode/1" do
    test "maps every episode of the series by its {season, episode} pair" do
      series = create_tv_series(%{name: "Sample Show"})
      season_one = create_season(%{tv_series_id: series.id, season_number: 1})
      season_two = create_season(%{tv_series_id: series.id, season_number: 2})
      first = create_episode(%{season_id: season_one.id, episode_number: 1, name: "One"})
      second = create_episode(%{season_id: season_two.id, episode_number: 3, name: "Three"})

      other = create_tv_series(%{name: "Other Show"})
      other_season = create_season(%{tv_series_id: other.id, season_number: 1})
      create_episode(%{season_id: other_season.id, episode_number: 1, name: "Elsewhere"})

      assert Episodes.ids_by_season_episode(series.id) == %{
               {1, 1} => first.id,
               {2, 3} => second.id
             }
    end

    test "is empty for a series with no episodes" do
      series = create_tv_series(%{name: "Sample Show"})
      assert Episodes.ids_by_season_episode(series.id) == %{}
    end
  end

  describe "last_season_episode/1" do
    test "returns the highest {season, episode} pair the series has" do
      series = create_tv_series(%{name: "Sample Show"})
      season_one = create_season(%{tv_series_id: series.id, season_number: 1})
      season_two = create_season(%{tv_series_id: series.id, season_number: 2})
      create_episode(%{season_id: season_one.id, episode_number: 9, name: "Nine"})
      create_episode(%{season_id: season_two.id, episode_number: 2, name: "Two"})
      create_episode(%{season_id: season_two.id, episode_number: 1, name: "One"})

      assert Episodes.last_season_episode(series.id) == {2, 2}
    end

    test "is nil for a series with no episodes" do
      series = create_tv_series(%{name: "Sample Show"})
      assert Episodes.last_season_episode(series.id) == nil
    end
  end

  describe "ordered_items_by_tv_series/1" do
    test "each series' episodes with a file, in story order, with their order keys" do
      series = create_tv_series(%{name: "Sample Show"})
      season_one = create_season(%{tv_series_id: series.id, season_number: 1})
      season_two = create_season(%{tv_series_id: series.id, season_number: 2})

      later =
        create_episode(%{
          season_id: season_two.id,
          episode_number: 1,
          name: "Later",
          content_url: "/media/test/sample-show-s02e01.mkv"
        })

      tenth =
        create_episode(%{
          season_id: season_one.id,
          episode_number: 10,
          name: "Tenth",
          content_url: "/media/test/sample-show-s01e10.mkv"
        })

      second =
        create_episode(%{
          season_id: season_one.id,
          episode_number: 2,
          name: "Second",
          content_url: "/media/test/sample-show-s01e02.mkv"
        })

      create_episode(%{season_id: season_one.id, episode_number: 3, name: "No file"})

      other = create_tv_series(%{name: "Other Show"})
      other_season = create_season(%{tv_series_id: other.id, season_number: 1})

      elsewhere =
        create_episode(%{
          season_id: other_season.id,
          episode_number: 1,
          name: "Elsewhere",
          content_url: "/media/test/other-show-s01e01.mkv"
        })

      assert Episodes.ordered_items_by_tv_series([series.id, other.id]) == %{
               series.id => [
                 %{id: second.id, key: EpisodeOrder.order_key(1, 2)},
                 %{id: tenth.id, key: EpisodeOrder.order_key(1, 10)},
                 %{id: later.id, key: EpisodeOrder.order_key(2, 1)}
               ],
               other.id => [%{id: elsewhere.id, key: EpisodeOrder.order_key(1, 1)}]
             }
    end

    test "a season or an episode with no number is not in the ordered set" do
      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})
      unnumbered_season = create_season(%{tv_series_id: series.id, name: "Specials"})

      numbered =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "One",
          content_url: "/media/test/sample-show-s01e01.mkv"
        })

      %{
        season_id: season.id,
        episode_number: 2,
        name: "No number",
        content_url: "/media/test/sample-show-extra.mkv"
      }
      |> create_episode()
      |> force_attrs(episode_number: nil)

      create_episode(%{
        season_id: unnumbered_season.id,
        episode_number: 1,
        name: "Special",
        content_url: "/media/test/sample-show-special.mkv"
      })

      assert Episodes.ordered_items_by_tv_series([series.id]) == %{
               series.id => [%{id: numbered.id, key: EpisodeOrder.order_key(1, 1)}]
             }
    end

    test "a series with no episode on file is absent; no ids, no query" do
      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})
      create_episode(%{season_id: season.id, episode_number: 1, name: "No file"})

      assert Episodes.ordered_items_by_tv_series([series.id]) == %{}
      assert Episodes.ordered_items_by_tv_series([]) == %{}
    end
  end
end
