defmodule MediaCentaur.Library.SeasonTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library.EpisodeListEntry
  alias MediaCentaur.Library.Season

  describe "create_changeset/1 with an episode list" do
    test "casts entries, coercing ISO air dates" do
      changeset =
        Season.create_changeset(%{
          season_number: 2,
          name: "Season 2",
          tv_series_id: Ecto.UUID.generate(),
          episode_list: [
            %{episode_number: 1, name: "First Sample", air_date: "2002-10-01"},
            %{episode_number: 2, name: "Second Sample", air_date: nil}
          ]
        })

      assert changeset.valid?
      [first, second] = Ecto.Changeset.apply_changes(changeset).episode_list
      assert first.episode_number == 1
      assert first.name == "First Sample"
      assert first.air_date == ~D[2002-10-01]
      assert second.air_date == nil
    end

    test "an entry without an episode number is invalid" do
      changeset =
        Season.create_changeset(%{
          season_number: 1,
          tv_series_id: Ecto.UUID.generate(),
          episode_list: [%{name: "Untitled"}]
        })

      refute changeset.valid?
    end
  end

  describe "episode_list_changeset/2" do
    test "replaces the whole list" do
      season = %Season{
        season_number: 1,
        episode_list: [%EpisodeListEntry{episode_number: 1}]
      }

      changeset =
        Season.episode_list_changeset(season, [
          %{episode_number: 1, name: "One", air_date: "2020-01-01"},
          %{episode_number: 2, name: "Two", air_date: "2020-01-08"}
        ])

      assert length(Ecto.Changeset.apply_changes(changeset).episode_list) == 2
    end
  end
end
