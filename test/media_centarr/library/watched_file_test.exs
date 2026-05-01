defmodule MediaCentarr.Library.WatchedFileTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library
  alias MediaCentarr.Library.WatchedFile

  describe "WatchedFile :link_file action" do
    test "creates record with movie_id" do
      movie = create_entity(%{type: :movie, name: "Test Movie"})

      assert {:ok, file} =
               Library.link_file(%{
                 file_path: "/media/test/linked.mkv",
                 watch_dir: "/media/test",
                 movie_id: movie.id
               })

      assert file.movie_id == movie.id
      assert file.file_path == "/media/test/linked.mkv"
      assert file.watch_dir == "/media/test"
    end

    test "upserts on duplicate file_path" do
      movie1 = create_entity(%{type: :movie, name: "First Movie"})
      movie2 = create_entity(%{type: :movie, name: "Second Movie"})

      {:ok, first} =
        Library.link_file(%{
          file_path: "/media/test/same.mkv",
          watch_dir: "/media/test",
          movie_id: movie1.id
        })

      {:ok, second} =
        Library.link_file(%{
          file_path: "/media/test/same.mkv",
          watch_dir: "/media/test",
          movie_id: movie2.id
        })

      assert first.id == second.id

      # Only one record exists
      all = Library.list_watched_files()
      assert length(all) == 1
    end
  end

  describe "owner_id/1" do
    test "returns tv_series_id when set" do
      file = %WatchedFile{
        tv_series_id: "tv-1",
        movie_series_id: nil,
        movie_id: nil,
        video_object_id: nil
      }

      assert WatchedFile.owner_id(file) == "tv-1"
    end

    test "returns movie_series_id when set" do
      file = %WatchedFile{
        tv_series_id: nil,
        movie_series_id: "ms-1",
        movie_id: nil,
        video_object_id: nil
      }

      assert WatchedFile.owner_id(file) == "ms-1"
    end

    test "returns movie_id when set" do
      file = %WatchedFile{
        tv_series_id: nil,
        movie_series_id: nil,
        movie_id: "m-1",
        video_object_id: nil
      }

      assert WatchedFile.owner_id(file) == "m-1"
    end

    test "returns video_object_id when set" do
      file = %WatchedFile{
        tv_series_id: nil,
        movie_series_id: nil,
        movie_id: nil,
        video_object_id: "v-1"
      }

      assert WatchedFile.owner_id(file) == "v-1"
    end

    test "returns nil when no FK is set" do
      file = %WatchedFile{
        tv_series_id: nil,
        movie_series_id: nil,
        movie_id: nil,
        video_object_id: nil
      }

      assert WatchedFile.owner_id(file) == nil
    end

    test "tv_series_id wins over movie_id when both somehow set" do
      file = %WatchedFile{
        tv_series_id: "tv-1",
        movie_series_id: nil,
        movie_id: "m-1",
        video_object_id: nil
      }

      assert WatchedFile.owner_id(file) == "tv-1"
    end
  end
end
