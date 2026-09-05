defmodule MediaCentaur.Library.ImageTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Settings.Config

  alias MediaCentaur.Library.ImageCache
  alias MediaCentaur.Library

  describe "upsert_image/2 replaced-file cleanup" do
    test "deletes the old file on disk when the content_url changes" do
      media_dir =
        Path.join(System.tmp_dir!(), "image_upsert_test_#{System.unique_integer([:positive])}")

      config = :persistent_term.get({Config, :config})
      :persistent_term.put({Config, :config}, Map.put(config, :media_dirs, [media_dir]))
      on_exit(fn -> File.rm_rf!(media_dir) end)

      movie = create_entity(%{type: :movie, name: "Test Movie"})
      images_dir = ImageCache.dir_for(media_dir)
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

      {:ok, _} = Library.Images.upsert(image_attrs, [:owner_type, :owner_id, :role])

      {:ok, _} =
        Library.Images.upsert(
          %{image_attrs | content_url: "#{movie.id}/poster.png", extension: "png"},
          [:owner_type, :owner_id, :role]
        )

      refute File.exists?(old_path)
    end

    test "keeps the file when the content_url is unchanged" do
      media_dir =
        Path.join(System.tmp_dir!(), "image_upsert_test_#{System.unique_integer([:positive])}")

      config = :persistent_term.get({Config, :config})
      :persistent_term.put({Config, :config}, Map.put(config, :media_dirs, [media_dir]))
      on_exit(fn -> File.rm_rf!(media_dir) end)

      movie = create_entity(%{type: :movie, name: "Test Movie"})
      images_dir = ImageCache.dir_for(media_dir)
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

      {:ok, _} = Library.Images.upsert(image_attrs, [:owner_type, :owner_id, :role])
      {:ok, _} = Library.Images.upsert(image_attrs, [:owner_type, :owner_id, :role])

      assert File.exists?(path)
    end
  end

  describe "image CRUD" do
    test "creates an image with content_url" do
      movie = create_entity(%{type: :movie, name: "Test Movie"})

      image =
        Library.Images.create!(%{
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
        Library.Images.upsert(
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
        Library.Images.upsert(
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
      images = Library.Images.list_all()

      movie_images =
        Enum.filter(images, &(&1.owner_id == movie.id && &1.role == "poster"))

      assert length(movie_images) == 1
    end

    test "polymorphic owner discriminator separates Movie and TVSeries images of same role" do
      movie = create_entity(%{type: :movie, name: "Sample Movie"})
      tv = create_entity(%{type: :tv_series, name: "Sample Show"})

      {:ok, _} =
        Library.Images.upsert(
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
        Library.Images.upsert(
          %{
            owner_type: :tv_series,
            owner_id: tv.id,
            role: "poster",
            content_url: "tv-poster.jpg",
            extension: "jpg"
          },
          [:owner_type, :owner_id, :role]
        )

      images = Library.Images.list_all()
      assert Enum.any?(images, &(&1.owner_type == :movie and &1.owner_id == movie.id))
      assert Enum.any?(images, &(&1.owner_type == :tv_series and &1.owner_id == tv.id))
    end
  end
end
