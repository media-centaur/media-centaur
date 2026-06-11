defmodule MediaCentaur.Library.ImageTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Config
  alias MediaCentaur.Library

  describe "upsert_image/2 replaced-file cleanup" do
    test "deletes the old file on disk when the content_url changes" do
      watch_dir =
        Path.join(System.tmp_dir!(), "image_upsert_test_#{System.unique_integer([:positive])}")

      config = :persistent_term.get({Config, :config})
      :persistent_term.put({Config, :config}, Map.put(config, :watch_dirs, [watch_dir]))
      on_exit(fn -> File.rm_rf!(watch_dir) end)

      movie = create_entity(%{type: :movie, name: "Test Movie"})
      images_dir = Config.images_dir_for(watch_dir)
      old_relative_url = "#{movie.id}/poster.jpg"
      old_path = Path.join(images_dir, old_relative_url)
      File.mkdir_p!(Path.dirname(old_path))
      File.write!(old_path, "jpg")

      image_attrs = %{
        owner_type: :movie,
        owner_id: movie.id,
        role: "poster",
        content_url: old_relative_url,
        extension: "jpg"
      }

      {:ok, _} = Library.upsert_image(image_attrs, [:owner_type, :owner_id, :role])

      {:ok, _} =
        Library.upsert_image(
          %{image_attrs | content_url: "#{movie.id}/poster.png", extension: "png"},
          [:owner_type, :owner_id, :role]
        )

      refute File.exists?(old_path)
    end

    test "keeps the file when the content_url is unchanged" do
      watch_dir =
        Path.join(System.tmp_dir!(), "image_upsert_test_#{System.unique_integer([:positive])}")

      config = :persistent_term.get({Config, :config})
      :persistent_term.put({Config, :config}, Map.put(config, :watch_dirs, [watch_dir]))
      on_exit(fn -> File.rm_rf!(watch_dir) end)

      movie = create_entity(%{type: :movie, name: "Test Movie"})
      images_dir = Config.images_dir_for(watch_dir)
      relative_url = "#{movie.id}/poster.jpg"
      path = Path.join(images_dir, relative_url)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "jpg")

      image_attrs = %{
        owner_type: :movie,
        owner_id: movie.id,
        role: "poster",
        content_url: relative_url,
        extension: "jpg"
      }

      {:ok, _} = Library.upsert_image(image_attrs, [:owner_type, :owner_id, :role])
      {:ok, _} = Library.upsert_image(image_attrs, [:owner_type, :owner_id, :role])

      assert File.exists?(path)
    end
  end

  describe "image CRUD" do
    test "creates an image with content_url" do
      movie = create_entity(%{type: :movie, name: "Test Movie"})

      image =
        Library.create_image!(%{
          owner_type: :movie,
          owner_id: movie.id,
          role: "poster",
          content_url: "#{movie.id}/poster.jpg",
          extension: "jpg"
        })

      assert image.role == "poster"
      assert image.content_url == "#{movie.id}/poster.jpg"
      assert image.extension == "jpg"
      assert image.owner_type == :movie
      assert image.owner_id == movie.id
    end

    test "upserts image on conflict" do
      movie = create_entity(%{type: :movie, name: "Test Movie"})

      {:ok, first} =
        Library.upsert_image(
          %{
            owner_type: :movie,
            owner_id: movie.id,
            role: "poster",
            content_url: "old.jpg",
            extension: "jpg"
          },
          [:owner_type, :owner_id, :role]
        )

      {:ok, second} =
        Library.upsert_image(
          %{
            owner_type: :movie,
            owner_id: movie.id,
            role: "poster",
            content_url: "new.jpg",
            extension: "jpg"
          },
          [:owner_type, :owner_id, :role]
        )

      # Same image, updated content_url
      assert first.id == second.id || first.owner_id == second.owner_id
      images = Library.list_all_images()

      movie_images =
        Enum.filter(images, &(&1.owner_id == movie.id && &1.role == "poster"))

      assert length(movie_images) == 1
    end

    test "polymorphic owner discriminator separates Movie and TVSeries images of same role" do
      movie = create_entity(%{type: :movie, name: "Sample Movie"})
      tv = create_entity(%{type: :tv_series, name: "Sample Show"})

      {:ok, _} =
        Library.upsert_image(
          %{
            owner_type: :movie,
            owner_id: movie.id,
            role: "poster",
            content_url: "movie-poster.jpg",
            extension: "jpg"
          },
          [:owner_type, :owner_id, :role]
        )

      {:ok, _} =
        Library.upsert_image(
          %{
            owner_type: :tv_series,
            owner_id: tv.id,
            role: "poster",
            content_url: "tv-poster.jpg",
            extension: "jpg"
          },
          [:owner_type, :owner_id, :role]
        )

      images = Library.list_all_images()
      assert Enum.any?(images, &(&1.owner_type == :movie and &1.owner_id == movie.id))
      assert Enum.any?(images, &(&1.owner_type == :tv_series and &1.owner_id == tv.id))
    end
  end
end
