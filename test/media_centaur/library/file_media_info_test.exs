defmodule MediaCentaur.Library.FileMediaInfoTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library

  # Canned ffprobe output — probing "succeeds" for every path.
  defmodule StubRunner do
    def run(_executable, _args) do
      json =
        Jason.encode!(%{
          "streams" => [
            %{
              "codec_type" => "video",
              "codec_name" => "hevc",
              "width" => 3840,
              "height" => 2160,
              "disposition" => %{"attached_pic" => 0}
            },
            %{
              "codec_type" => "audio",
              "codec_name" => "truehd",
              "channels" => 8,
              "channel_layout" => "7.1"
            }
          ],
          "format" => %{
            "duration" => "6073.6",
            "tags" => %{"title" => "Sample.Movie.2024.2160p-GRP"}
          }
        })

      {json, 0}
    end
  end

  defp with_stub_runner do
    previous = Application.get_env(:media_centaur, :media_probe_runner)
    Application.put_env(:media_centaur, :media_probe_runner, StubRunner)
    on_exit(fn -> Application.put_env(:media_centaur, :media_probe_runner, previous) end)
  end

  describe "refresh_file_media_info/2 + file_media_info_by_paths/1" do
    test "probes and upserts, keyed by presence; re-probing updates in place" do
      with_stub_runner()
      file = create_linked_file(%{movie_id: create_movie(%{name: "Sample Movie"}).id})

      assert :ok = Library.refresh_file_media_info(file.file_presence_id, file.file_path)
      assert :ok = Library.refresh_file_media_info(file.file_presence_id, file.file_path)

      infos = Library.file_media_info_by_paths([file.file_path])
      assert info = infos[file.file_path]

      assert info.container_title == "Sample.Movie.2024.2160p-GRP"
      assert info.duration_seconds == 6074
      assert info.video_codec == "HEVC"
      assert info.audio_summary == "TrueHD 7.1"
    end

    test "a failed probe is :skipped and stores nothing" do
      file = create_linked_file(%{movie_id: create_movie(%{name: "Sample Movie"}).id})

      assert :skipped = Library.refresh_file_media_info(file.file_presence_id, file.file_path)
      assert Library.file_media_info_by_paths([file.file_path]) == %{}
    end
  end

  describe "link_file/1 hook" do
    test "linking a file probes it in the same gesture" do
      with_stub_runner()
      file = create_linked_file(%{movie_id: create_movie(%{name: "Sample Movie"}).id})

      assert %{} = infos = Library.file_media_info_by_paths([file.file_path])
      assert infos[file.file_path].video_codec == "HEVC"
    end
  end

  describe "probe_missing_media_info/0" do
    test "a sweep that filled rows broadcasts entities_changed so cached projections rebuild" do
      # The boot sweep runs AFTER the detail projection's boot build —
      # without this broadcast the More-info pane shows nothing until an
      # unrelated library event rebuilds the cache (the "I don't see it"
      # incident).
      _file = create_linked_file(%{movie_id: create_movie(%{name: "Sample Movie"}).id})
      with_stub_runner()
      :ok = Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_updates())

      assert %{probed: 1} = Library.probe_missing_media_info()
      assert_receive {:entities_changed, _ids}, 500

      # An all-caught-up sweep stays silent — no rebuild churn at boot.
      assert %{probed: 0} = Library.probe_missing_media_info()
      refute_receive {:entities_changed, _ids}, 100
    end

    test "fills only files without a row" do
      first = create_linked_file(%{movie_id: create_movie(%{name: "Sample Movie"}).id})
      second = create_linked_file(%{movie_id: create_movie(%{name: "Sample Movie"}).id})

      with_stub_runner()
      assert :ok = Library.refresh_file_media_info(first.file_presence_id, first.file_path)

      assert %{probed: 1, skipped: 0} = Library.probe_missing_media_info()

      infos = Library.file_media_info_by_paths([first.file_path, second.file_path])
      assert map_size(infos) == 2
    end
  end
end
