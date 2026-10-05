defmodule MediaCentaurWeb.Live.TitleDetailHost.LibraryEventsDeleteFolderSafetyTest do
  @moduledoc """
  `LibraryEvents.run_delete/1`'s `{:folder, path}`, `:all` and
  `{:member, movie_id}` branches
  gate the recursive folder delete on
  `MediaCentaur.DeleteTargets.safe_to_delete_folder?/2` before calling
  `Deletion.delete_folder/2` — closing the gap where a folder
  shared with another already-imported entity's files could be wiped
  wholesale. Needs DataCase for real `WatchedFile` rows and real files
  on disk.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library
  alias MediaCentaurWeb.Live.TitleDetailHost.LibraryEvents

  setup do
    media_dir =
      Path.join(System.tmp_dir!(), "entity_modal_delete_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(media_dir)
    on_exit(fn -> File.rm_rf!(media_dir) end)

    %{media_dir: media_dir}
  end

  defp write_file!(media_dir, relative_path) do
    path = Path.join(media_dir, relative_path)
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, "x")
    path
  end

  describe "run_delete/1 — {:folder, path}" do
    test "deletes the folder wholesale when this entity is the only thing in it", %{
      media_dir: media_dir
    } do
      movie = create_movie(%{name: "Solo Folder Movie"})
      path = write_file!(media_dir, "Solo.Release/movie.mkv")
      create_linked_file(%{movie_id: movie.id, file_path: path, media_dir: media_dir})

      detail_files = [%{file: %{file_path: path}, size: 1}]
      folder = Path.join(media_dir, "Solo.Release")

      assert {:ok, _} =
               LibraryEvents.run_delete(%{
                 target: {:folder, folder},
                 detail_files: detail_files,
                 media_dirs: [media_dir]
               })

      refute File.exists?(folder)
      assert Library.Files.list_by_entity_id(movie.id) == []
    end

    test "refuses to wipe a folder that also holds a different already-imported entity's file",
         %{media_dir: media_dir} do
      other_movie = create_movie(%{name: "Other Movie In Shared Folder"})
      other_path = write_file!(media_dir, "ShowName/other_entity_file.mkv")

      create_linked_file(%{
        movie_id: other_movie.id,
        file_path: other_path,
        media_dir: media_dir
      })

      # This entity's own file lives in the SAME "ShowName" folder.
      movie = create_movie(%{name: "This Movie"})
      path = write_file!(media_dir, "ShowName/this_entity_file.mkv")
      create_linked_file(%{movie_id: movie.id, file_path: path, media_dir: media_dir})

      detail_files = [%{file: %{file_path: path}, size: 1}]
      folder = Path.join(media_dir, "ShowName")

      assert {:error, _reason} =
               LibraryEvents.run_delete(%{
                 target: {:folder, folder},
                 detail_files: detail_files,
                 media_dirs: [media_dir]
               })

      assert File.exists?(folder)
      assert File.exists?(other_path), "the other entity's file must survive the refusal"
      assert File.exists?(path), "this entity's own file must survive too — nothing ran"
    end
  end

  describe "run_delete/1 — :all" do
    test "falls back to per-file deletion for a group whose folder is shared, still deletes the entity's own files",
         %{media_dir: media_dir} do
      other_movie = create_movie(%{name: "Other Movie"})
      other_path = write_file!(media_dir, "SharedFolder/other.mkv")
      create_linked_file(%{movie_id: other_movie.id, file_path: other_path, media_dir: media_dir})

      movie = create_movie(%{name: "This Movie All"})
      path = write_file!(media_dir, "SharedFolder/mine.mkv")
      create_linked_file(%{movie_id: movie.id, file_path: path, media_dir: media_dir})

      detail_files = [%{file: %{file_path: path}, size: 1}]

      assert {:ok, []} =
               LibraryEvents.run_delete(%{
                 target: :all,
                 detail_files: detail_files,
                 media_dirs: [media_dir]
               })

      refute File.exists?(path)
      assert File.exists?(other_path), "the shared folder itself must not be wiped"
      assert Library.Files.list_by_entity_id(movie.id) == []
    end
  end

  describe "run_delete/1 — {:member, movie_id}" do
    test "deletes one collection movie's files and leaves the other members", %{media_dir: media_dir} do
      collection = create_movie_series(%{name: "Sample Collection"})
      finished = create_movie(%{movie_series_id: collection.id, name: "Movie A", position: 1})
      other = create_movie(%{movie_series_id: collection.id, name: "Movie B", position: 2})
      finished_path = write_file!(media_dir, "Collection/Movie A.mkv")
      other_path = write_file!(media_dir, "Collection/Movie B.mkv")
      create_linked_file(%{movie_id: finished.id, file_path: finished_path, media_dir: media_dir})
      create_linked_file(%{movie_id: other.id, file_path: other_path, media_dir: media_dir})

      detail_files = Enum.map(Library.Files.list_by_entity_id(collection.id), &%{file: &1, size: 1})

      assert {:ok, _} =
               LibraryEvents.run_delete(%{
                 target: {:member, finished.id},
                 detail_files: detail_files,
                 media_dirs: [media_dir]
               })

      refute File.exists?(finished_path)
      assert File.exists?(other_path)
      assert Library.Files.list_by_entity_id(finished.id) == []
      assert [_] = Library.Files.list_by_entity_id(other.id)
    end
  end
end
