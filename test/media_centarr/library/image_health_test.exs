defmodule MediaCentarr.Library.ImageHealthTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Config
  alias MediaCentarr.Library
  alias MediaCentarr.Library.ImageHealth

  setup do
    tmp = Path.join(System.tmp_dir!(), "image_health_#{Ecto.UUID.generate()}")
    images_dir = Path.join(tmp, ".media-centarr/images")
    File.mkdir_p!(images_dir)

    original = :persistent_term.get({Config, :config}, %{})

    :persistent_term.put({Config, :config}, %{
      watch_dirs: [tmp],
      watch_dir_images: %{tmp => images_dir}
    })

    on_exit(fn ->
      File.rm_rf!(tmp)
      :persistent_term.put({Config, :config}, original)
    end)

    %{tmp: tmp, images_dir: images_dir}
  end

  describe "count_missing/0" do
    test "returns 0 when library has no images" do
      assert ImageHealth.count_missing() == 0
    end

    test "returns 0 when all image files are present on disk", %{images_dir: images_dir} do
      movie = create_entity(%{type: :movie, name: "Present"})
      put_image_with_file(movie.id, :movie_id, "poster", "jpg", images_dir)

      assert ImageHealth.count_missing() == 0
    end

    test "counts image rows whose files are absent" do
      movie = create_entity(%{type: :movie, name: "Absent"})

      Library.create_image!(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      assert ImageHealth.count_missing() == 1
    end

    test "distinguishes missing from present within the same entity", %{images_dir: images_dir} do
      movie = create_entity(%{type: :movie, name: "Partial"})
      put_image_with_file(movie.id, :movie_id, "poster", "jpg", images_dir)

      Library.create_image!(%{
        movie_id: movie.id,
        role: "backdrop",
        content_url: "#{movie.id}/backdrop.jpg",
        extension: "jpg"
      })

      assert ImageHealth.count_missing() == 1
    end

    test "excludes rows with nil content_url (mid-refresh)" do
      movie = create_entity(%{type: :movie, name: "Refreshing"})

      Library.create_image!(%{
        movie_id: movie.id,
        role: "poster",
        content_url: nil,
        extension: "jpg"
      })

      assert ImageHealth.count_missing() == 0
    end
  end

  describe "list_missing/0" do
    test "returns image rows annotated with entity_id and entity_type" do
      movie = create_entity(%{type: :movie, name: "M"})

      image =
        Library.create_image!(%{
          movie_id: movie.id,
          role: "poster",
          content_url: "#{movie.id}/poster.jpg",
          extension: "jpg"
        })

      assert [entry] = ImageHealth.list_missing()
      assert entry.image.id == image.id
      assert entry.entity_id == movie.id
      assert entry.entity_type == :movie
    end

    test "resolves entity_type for each top-level FK" do
      movie = create_entity(%{type: :movie, name: "M"})

      Library.create_image!(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      tv_series = create_tv_series()

      Library.create_image!(%{
        tv_series_id: tv_series.id,
        role: "poster",
        content_url: "#{tv_series.id}/poster.jpg",
        extension: "jpg"
      })

      movie_series = create_movie_series()

      Library.create_image!(%{
        movie_series_id: movie_series.id,
        role: "poster",
        content_url: "#{movie_series.id}/poster.jpg",
        extension: "jpg"
      })

      video_object = create_video_object()

      Library.create_image!(%{
        video_object_id: video_object.id,
        role: "poster",
        content_url: "#{video_object.id}/poster.jpg",
        extension: "jpg"
      })

      types = ImageHealth.list_missing() |> Enum.map(& &1.entity_type) |> Enum.sort()
      assert types == [:movie, :movie_series, :tv_series, :video_object]
    end

    test "resolves episode entity_type via episode_id FK" do
      tv_series = create_tv_series()
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1, number_of_episodes: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 1, name: "Pilot"})

      Library.create_image!(%{
        episode_id: episode.id,
        role: "thumb",
        content_url: "#{episode.id}/thumb.jpg",
        extension: "jpg"
      })

      assert [entry] = ImageHealth.list_missing()
      assert entry.entity_type == :episode
      assert entry.entity_id == episode.id
    end
  end

  describe "summary/0" do
    test "reports zero totals on an empty library" do
      assert ImageHealth.summary() == %{total: 0, missing: 0, by_role: %{}}
    end

    test "aggregates total, missing, and per-role missing counts", %{images_dir: images_dir} do
      movie = create_entity(%{type: :movie, name: "Mixed"})

      put_image_with_file(movie.id, :movie_id, "poster", "jpg", images_dir)

      Library.create_image!(%{
        movie_id: movie.id,
        role: "backdrop",
        content_url: "#{movie.id}/backdrop.jpg",
        extension: "jpg"
      })

      Library.create_image!(%{
        movie_id: movie.id,
        role: "logo",
        content_url: "#{movie.id}/logo.png",
        extension: "png"
      })

      assert %{total: 3, missing: 2, by_role: %{"backdrop" => 1, "logo" => 1}} =
               ImageHealth.summary()
    end
  end

  defp put_image_with_file(entity_id, fk, role, extension, images_dir) do
    entity_dir = Path.join(images_dir, entity_id)
    File.mkdir_p!(entity_dir)
    File.write!(Path.join(entity_dir, "#{role}.#{extension}"), "fake image bytes")

    Library.create_image!(%{
      fk => entity_id,
      :role => role,
      :content_url => "#{entity_id}/#{role}.#{extension}",
      :extension => extension
    })
  end
end
