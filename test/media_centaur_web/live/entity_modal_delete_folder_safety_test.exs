defmodule MediaCentaurWeb.Live.EntityModalDeleteFolderSafetyTest do
  @moduledoc """
  `EntityModal.run_delete/1`'s `{:folder, path}` and `:all` branches now
  gate the recursive folder delete on
  `MediaCentaur.DeleteTargets.safe_to_delete_folder?/2` before calling
  `FileEventHandler.delete_folder/2` — closing the gap where a folder
  shared with another already-imported entity's files could be wiped
  wholesale. Split from `entity_modal_test.exs` (which is a plain
  `ExUnit.Case, async: true` for pure-function tests) because this needs
  DataCase for real `WatchedFile` rows and real files on disk.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library
  alias MediaCentaurWeb.Live.EntityModal

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
               EntityModal.run_delete(%{
                 delete_confirm: {:folder, folder},
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
               EntityModal.run_delete(%{
                 delete_confirm: {:folder, folder},
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
               EntityModal.run_delete(%{
                 delete_confirm: :all,
                 detail_files: detail_files,
                 media_dirs: [media_dir]
               })

      refute File.exists?(path)
      assert File.exists?(other_path), "the shared folder itself must not be wiped"
      assert Library.Files.list_by_entity_id(movie.id) == []
    end
  end
end
