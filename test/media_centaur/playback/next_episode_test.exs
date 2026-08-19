defmodule MediaCentaur.Playback.NextEpisodeTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Playback.NextEpisode
  alias MediaCentaur.Settings

  # NextEpisode gates on the successor's file being present on disk, so
  # fixtures write real files under a per-test temp dir.
  setup do
    dir = Path.join(System.tmp_dir!(), "next-episode-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp media_file!(dir, name) do
    path = Path.join(dir, name)
    File.write!(path, "media")
    path
  end

  defp create_series_with_two_episodes(dir) do
    tv_series = create_entity(%{type: :tv_series, name: "Sample Show"})
    season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

    episode_one =
      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        name: "First",
        content_url: media_file!(dir, "Sample.Show.S01E01.mkv")
      })

    episode_two =
      create_episode(%{
        season_id: season.id,
        episode_number: 2,
        name: "Second",
        content_url: media_file!(dir, "Sample.Show.S01E02.mkv")
      })

    %{tv_series: tv_series, season: season, episode_one: episode_one, episode_two: episode_two}
  end

  describe "resolve/1" do
    test "returns the following episode starting at zero when unwatched", %{dir: dir} do
      %{episode_one: episode_one, episode_two: episode_two} =
        create_series_with_two_episodes(dir)

      assert {:ok, item} = NextEpisode.resolve(episode_one.id)
      assert item.episode_id == episode_two.id
      assert item.season_number == 1
      assert item.episode_number == 2
      assert item.episode_name == "Second"
      assert item.content_url =~ "S01E02"
      assert item.start_position == 0.0
    end

    test "carries the successor's own resume position when partially watched", %{dir: dir} do
      %{episode_one: episode_one, episode_two: episode_two} =
        create_series_with_two_episodes(dir)

      create_watch_progress(%{
        episode_id: episode_two.id,
        position_seconds: 300.0,
        duration_seconds: 1800.0
      })

      assert {:ok, item} = NextEpisode.resolve(episode_one.id)
      assert item.episode_id == episode_two.id
      assert item.start_position == 300.0
    end

    test "starts a completed successor from zero", %{dir: dir} do
      %{episode_one: episode_one, episode_two: episode_two} =
        create_series_with_two_episodes(dir)

      progress =
        create_watch_progress(%{
          episode_id: episode_two.id,
          position_seconds: 1700.0,
          duration_seconds: 1800.0
        })

      MediaCentaur.Library.ProgressRecords.mark_completed!(progress)

      assert {:ok, item} = NextEpisode.resolve(episode_one.id)
      assert item.start_position == 0.0
    end

    test "returns :none after the final episode", %{dir: dir} do
      %{episode_two: episode_two} = create_series_with_two_episodes(dir)

      assert NextEpisode.resolve(episode_two.id) == :none
    end

    test "returns :none when auto-play is disabled", %{dir: dir} do
      %{episode_one: episode_one} = create_series_with_two_episodes(dir)

      Settings.find_or_create_entry!(%{
        key: MediaCentaur.Preferences.AutoPlayNextEpisode.setting_key(),
        value: %{"enabled" => false}
      })

      assert NextEpisode.resolve(episode_one.id) == :none
    end

    test "returns :none when the successor's file is gone from disk", %{dir: dir} do
      %{episode_one: episode_one, episode_two: episode_two} =
        create_series_with_two_episodes(dir)

      File.rm!(episode_two.content_url)

      assert NextEpisode.resolve(episode_one.id) == :none
    end

    test "returns :none for an unknown id" do
      assert NextEpisode.resolve(Ecto.UUID.generate()) == :none
    end
  end

  describe "identify/2" do
    test "maps a playing path back to its episode identity", %{dir: dir} do
      %{tv_series: tv_series, episode_two: episode_two} =
        create_series_with_two_episodes(dir)

      assert {:ok, identity} = NextEpisode.identify(tv_series.id, episode_two.content_url)
      assert identity.episode_id == episode_two.id
      assert identity.season_number == 1
      assert identity.episode_number == 2
      assert identity.episode_name == "Second"
      assert identity.content_url == episode_two.content_url
    end

    test "returns :none for a path outside the series", %{dir: dir} do
      %{tv_series: tv_series} = create_series_with_two_episodes(dir)

      assert NextEpisode.identify(tv_series.id, "/somewhere/else.mkv") == :none
    end

    test "returns :none for an unknown entity" do
      assert NextEpisode.identify(Ecto.UUID.generate(), "/a.mkv") == :none
    end
  end

  describe "loadfile_command/1" do
    test "appends without options when starting from zero" do
      assert NextEpisode.loadfile_command(%{content_url: "/shows/a.mkv", start_position: 0.0}) ==
               ["loadfile", "/shows/a.mkv", "append"]
    end

    test "carries a per-entry start option when resuming" do
      assert NextEpisode.loadfile_command(%{content_url: "/shows/a.mkv", start_position: 300.0}) ==
               ["loadfile", "/shows/a.mkv", "append", -1, "start=300.0"]
    end
  end
end
