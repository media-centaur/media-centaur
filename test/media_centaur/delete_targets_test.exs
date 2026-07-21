defmodule MediaCentaur.DeleteTargetsTest do
  @moduledoc """
  Shared safety-check module used by both the entity detail page delete
  flow and the Review page delete flow, so a folder is never `rm -rf`'d
  unless it demonstrably contains nothing but the files being deleted.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Config
  alias MediaCentaur.DeleteTargets

  setup do
    stored = :persistent_term.get({Config, :config})
    :persistent_term.put({Config, :config}, Map.put(stored, :media_dirs, ["/media/movies", "/media/tv"]))
    on_exit(fn -> :persistent_term.put({Config, :config}, stored) end)
    :ok
  end

  describe "safe_to_delete_folder?/2" do
    test "false for a configured media directory root" do
      refute DeleteTargets.safe_to_delete_folder?("/media/movies", ["/media/movies/a.mkv"])
    end

    test "true when every file under the folder is in the given set" do
      movie = create_movie(%{name: "Solo Release"})

      create_linked_file(%{
        movie_id: movie.id,
        file_path: "/media/movies/Solo.Release/movie.mkv",
        media_dir: "/media/movies"
      })

      assert DeleteTargets.safe_to_delete_folder?("/media/movies/Solo.Release", [
               "/media/movies/Solo.Release/movie.mkv"
             ])
    end

    test "false when the folder also contains an already-imported file outside the given set" do
      movie = create_movie(%{name: "Shared Folder Movie"})

      create_linked_file(%{
        movie_id: movie.id,
        file_path: "/media/tv/ShowName/Season 1/e01.mkv",
        media_dir: "/media/tv"
      })

      # Pretend we're about to delete a different file that happens to live
      # in the same top-level "ShowName" folder — must refuse, since
      # deleting the folder would destroy the already-imported episode too.
      refute DeleteTargets.safe_to_delete_folder?("/media/tv/ShowName", [
               "/media/tv/ShowName/Season 3/e01.mkv"
             ])
    end

    test "true for an empty/never-imported folder" do
      assert DeleteTargets.safe_to_delete_folder?("/media/movies/Brand.New.Release", [
               "/media/movies/Brand.New.Release/movie.mkv"
             ])
    end
  end

  describe "resolve_folder_target/1" do
    test "resolves via Target.content_path when every file falls under it" do
      create_target(%{content_path: "/media/tv/Show.S03.WEBRip"})

      assert DeleteTargets.resolve_folder_target([
               "/media/tv/Show.S03.WEBRip/e01.mkv",
               "/media/tv/Show.S03.WEBRip/e02.mkv"
             ]) == {:folder, "/media/tv/Show.S03.WEBRip"}
    end

    test "does not use content_path if it's a stale single-file path, not the files' real folder" do
      create_target(%{content_path: "/media/movies/Old.Location/movie.mkv"})

      # The file has since moved elsewhere — content_path no longer relates,
      # so this must fall back to the common-parent heuristic instead of a
      # nonsensical folder result.
      assert DeleteTargets.resolve_folder_target(["/media/movies/New.Location/movie.mkv"]) ==
               {:folder, "/media/movies/New.Location"}
    end

    test "falls back to the files' common parent directory when no Target matches" do
      assert DeleteTargets.resolve_folder_target([
               "/media/movies/Some.Release/movie.mkv"
             ]) == {:folder, "/media/movies/Some.Release"}
    end

    test "returns :file_only when the files don't share one folder" do
      assert DeleteTargets.resolve_folder_target([
               "/media/tv/ShowName/Season 1/e01.mkv",
               "/media/tv/ShowName/Season 2/e01.mkv"
             ]) == :file_only
    end

    test "returns :file_only when the candidate folder also holds other already-imported files" do
      movie = create_movie(%{name: "Coexisting Movie"})

      create_linked_file(%{
        movie_id: movie.id,
        file_path: "/media/tv/ShowName/e_already_here.mkv",
        media_dir: "/media/tv"
      })

      assert DeleteTargets.resolve_folder_target([
               "/media/tv/ShowName/e_pending.mkv"
             ]) == :file_only
    end

    test "returns :file_only for an empty list" do
      assert DeleteTargets.resolve_folder_target([]) == :file_only
    end
  end
end
