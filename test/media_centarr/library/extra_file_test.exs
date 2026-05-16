defmodule MediaCentarr.Library.ExtraFileTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library
  alias MediaCentarr.Library.ExtraFile

  describe "Library.create_extra_file/1" do
    test "links a file path to an Extra" do
      movie = create_entity(%{type: :movie, name: "Container Movie"})

      extra =
        create_extra(%{
          movie_id: movie.id,
          name: "Behind the Scenes",
          content_url: "/media/test/extras/bts.mkv",
          position: 1
        })

      assert {:ok, file} =
               Library.create_extra_file(%{
                 file_path: "/media/test/extras/bts.mkv",
                 watch_dir: "/media/test",
                 extra_id: extra.id
               })

      assert file.extra_id == extra.id
      assert file.file_path == "/media/test/extras/bts.mkv"
      assert file.watch_dir == "/media/test"
    end

    test "upserts on duplicate file_path" do
      movie_a = create_entity(%{type: :movie, name: "Movie A"})
      movie_b = create_entity(%{type: :movie, name: "Movie B"})

      extra_a =
        create_extra(%{movie_id: movie_a.id, name: "Extra A", content_url: "/x.mkv", position: 1})

      extra_b =
        create_extra(%{movie_id: movie_b.id, name: "Extra B", content_url: "/x.mkv", position: 1})

      {:ok, first} =
        Library.create_extra_file(%{
          file_path: "/media/test/same-extra.mkv",
          watch_dir: "/media/test",
          extra_id: extra_a.id
        })

      {:ok, second} =
        Library.create_extra_file(%{
          file_path: "/media/test/same-extra.mkv",
          watch_dir: "/media/test",
          extra_id: extra_b.id
        })

      assert first.id == second.id
      assert second.extra_id == extra_b.id
    end

    test "requires extra_id" do
      changeset =
        ExtraFile.link_file_changeset(%{
          file_path: "/media/test/orphan.mkv",
          watch_dir: "/media/test"
        })

      assert %{extra_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires file_path" do
      movie = create_entity(%{type: :movie, name: "Container Movie 2"})

      extra =
        create_extra(%{
          movie_id: movie.id,
          name: "Extra",
          content_url: "/media/test/extras/x.mkv",
          position: 1
        })

      changeset =
        ExtraFile.link_file_changeset(%{
          extra_id: extra.id,
          watch_dir: "/media/test"
        })

      assert %{file_path: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "Library.list_extra_files_for/1" do
    test "lists ExtraFile rows for an Extra" do
      movie = create_entity(%{type: :movie, name: "Lister Movie"})

      extra =
        create_extra(%{
          movie_id: movie.id,
          name: "BTS",
          content_url: "/media/test/extras/bts.mkv",
          position: 1
        })

      {:ok, _} =
        Library.create_extra_file(%{
          file_path: "/media/test/extras/bts.mkv",
          watch_dir: "/media/test",
          extra_id: extra.id
        })

      assert [%ExtraFile{file_path: "/media/test/extras/bts.mkv"}] =
               Library.list_extra_files_for(extra.id)
    end

    test "returns empty list for an extra with no files" do
      movie = create_entity(%{type: :movie, name: "Empty Movie"})

      extra =
        create_extra(%{
          movie_id: movie.id,
          name: "Empty BTS",
          content_url: "/media/test/extras/empty.mkv",
          position: 1
        })

      assert Library.list_extra_files_for(extra.id) == []
    end
  end

  describe "Library.destroy_extra_file/1" do
    test "deletes the row" do
      movie = create_entity(%{type: :movie, name: "Destroy Movie"})

      extra =
        create_extra(%{
          movie_id: movie.id,
          name: "BTS",
          content_url: "/media/test/extras/destroy.mkv",
          position: 1
        })

      {:ok, file} =
        Library.create_extra_file(%{
          file_path: "/media/test/extras/destroy.mkv",
          watch_dir: "/media/test",
          extra_id: extra.id
        })

      assert {:ok, _} = Library.destroy_extra_file(file)
      assert Library.list_extra_files_for(extra.id) == []
    end
  end
end
