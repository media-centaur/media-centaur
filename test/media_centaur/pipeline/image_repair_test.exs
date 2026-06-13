defmodule MediaCentaur.Pipeline.ImageRepairTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmdbStubs

  alias MediaCentaur.Config
  alias MediaCentaur.Library
  alias MediaCentaur.Pipeline.ImageQueue
  alias MediaCentaur.Pipeline.ImageQueueEntry
  alias MediaCentaur.Pipeline.ImageRepair
  alias MediaCentaur.Topics

  setup :setup_tmdb_client

  setup do
    tmp = Path.join(System.tmp_dir!(), "image_repair_#{Ecto.UUID.generate()}")
    images_dir = Path.join(tmp, ".media-centaur/images")
    File.mkdir_p!(images_dir)

    original = :persistent_term.get({Config, :config}, %{})

    :persistent_term.put({Config, :config}, %{
      media_dirs: [tmp],
      media_dir_images: %{tmp => images_dir}
    })

    :ok = Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.pipeline_images())

    on_exit(fn ->
      File.rm_rf!(tmp)
      :persistent_term.put({Config, :config}, original)
    end)

    %{tmp: tmp, images_dir: images_dir}
  end

  describe "repair_all/0 empty state" do
    test "reports zero counts and broadcasts nothing when nothing is missing" do
      assert {:ok, result} = ImageRepair.repair_all()

      assert result == %{
               enqueued: 0,
               queue_reused: 0,
               queue_rebuilt: 0,
               skipped: 0
             }

      refute_receive {:images_pending, _}, 50
    end
  end

  describe "repair_all/0 queue-row reuse" do
    test "reuses an existing queue entry and resets it to pending", %{tmp: tmp} do
      movie = create_movie_with_watched_file(tmp)

      Library.create_image!(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      {:ok, entry} =
        ImageQueue.create(%{
          owner_id: movie.id,
          owner_type: "movie",
          role: "poster",
          source_url: "https://image.tmdb.org/t/p/original/stored.jpg",
          entity_id: movie.id,
          media_dir: tmp,
          status: "complete"
        })

      assert {:ok, result} = ImageRepair.repair_all()
      assert result.enqueued == 1
      assert result.queue_reused == 1
      assert result.queue_rebuilt == 0

      reloaded = Repo.get(ImageQueueEntry, entry.id)
      assert reloaded.status == "pending"
      assert reloaded.retry_count == 0

      assert_receive {:images_pending, %{entity_id: entity_id, media_dir: ^tmp}}
      assert entity_id == movie.id
    end
  end

  describe "refetch_role/1" do
    test "re-enqueues every image of the role and purges its derivatives",
         %{tmp: tmp, images_dir: images_dir} do
      Process.put(:image_derivative_root, Path.join(tmp, "derivatives"))

      movie = create_movie_with_watched_file(tmp)

      entity_dir = Path.join(images_dir, movie.id)
      File.mkdir_p!(entity_dir)
      master = Path.join(entity_dir, "backdrop.jpg")
      {:ok, img} = Image.new(1200, 675, color: :red)
      {:ok, _} = Image.write(img, master, suffix: ".jpg", quality: 90)

      Library.create_image!(%{
        movie_id: movie.id,
        role: "backdrop",
        content_url: "#{movie.id}/backdrop.jpg",
        extension: "jpg"
      })

      {:ok, entry} =
        ImageQueue.create(%{
          owner_id: movie.id,
          owner_type: "movie",
          role: "backdrop",
          source_url: "https://image.tmdb.org/t/p/original/stored.jpg",
          entity_id: movie.id,
          media_dir: tmp,
          status: "complete"
        })

      # A derivative exists for the present master — it must be purged so the
      # re-downloaded (new-resolution) master regenerates a fresh one.
      {:ok, derivative} = MediaCentaur.Images.derivative(master, 480)
      assert File.exists?(derivative)

      assert {:ok, result} = ImageRepair.refetch_role("backdrop")
      assert result.enqueued == 1
      assert result.queue_reused == 1

      reloaded = Repo.get(ImageQueueEntry, entry.id)
      assert reloaded.status == "pending"
      refute File.exists?(derivative)

      assert_receive {:images_pending, %{entity_id: _id, media_dir: ^tmp}}
    end

    test "is a no-op when no images of the role exist" do
      assert {:ok, result} = ImageRepair.refetch_role("backdrop")
      assert result.enqueued == 0
      refute_receive {:images_pending, _}, 50
    end
  end

  describe "repair_all/0 queue-row rebuild via TMDB" do
    test "creates a new queue row for a movie with a direct tmdb_id", %{tmp: tmp} do
      movie = create_movie_with_watched_file(tmp, %{tmdb_id: "550"})

      Library.create_image!(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      stub_get_movie("550", movie_detail(%{"poster_path" => "/fresh.jpg"}))

      assert {:ok, result} = ImageRepair.repair_all()
      assert result.queue_rebuilt == 1
      assert result.enqueued == 1

      assert [entry] = Repo.all(ImageQueueEntry)
      assert entry.owner_id == movie.id
      assert entry.role == "poster"
      assert entry.source_url == "https://image.tmdb.org/t/p/original/fresh.jpg"
      assert entry.status == "pending"
      assert entry.owner_type == "movie"
      assert entry.media_dir == tmp
    end

    test "creates a new queue row for a tv_series via tmdb_id", %{tmp: tmp} do
      tv = create_tv_series_with_watched_file(tmp, %{tmdb_id: "1396"})

      Library.create_image!(%{
        tv_series_id: tv.id,
        role: "backdrop",
        content_url: "#{tv.id}/backdrop.jpg",
        extension: "jpg"
      })

      stub_get_tv("1396", tv_detail(%{"backdrop_path" => "/fresh_bd.jpg"}))

      assert {:ok, result} = ImageRepair.repair_all()
      assert result.queue_rebuilt == 1

      assert [entry] = Repo.all(ImageQueueEntry)
      assert entry.owner_id == tv.id
      assert entry.owner_type == "tv_series"
      assert entry.source_url == "https://image.tmdb.org/t/p/original/fresh_bd.jpg"
    end

    test "creates a new queue row for a movie_series via tmdb_id", %{tmp: tmp} do
      movie_series = create_movie_series_with_watched_file(tmp, %{tmdb_id: "263"})

      Library.create_image!(%{
        movie_series_id: movie_series.id,
        role: "poster",
        content_url: "#{movie_series.id}/poster.jpg",
        extension: "jpg"
      })

      stub_get_collection("263", collection_detail(%{"poster_path" => "/ms_poster.jpg"}))

      assert {:ok, result} = ImageRepair.repair_all()
      assert result.queue_rebuilt == 1

      assert [entry] = Repo.all(ImageQueueEntry)
      assert entry.owner_type == "movie_series"
      assert entry.source_url == "https://image.tmdb.org/t/p/original/ms_poster.jpg"
    end

    test "skips when TMDB returns no path for the requested role", %{tmp: tmp} do
      movie = create_movie_with_watched_file(tmp, %{tmdb_id: "550"})

      Library.create_image!(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      stub_get_movie("550", movie_detail(%{"poster_path" => nil}))

      assert {:ok, result} = ImageRepair.repair_all()
      assert result.skipped == 1
      assert result.queue_rebuilt == 0
      assert [] = Repo.all(ImageQueueEntry)

      refute_receive {:images_pending, _}, 50
    end

    test "skips when TMDB returns an error", %{tmp: tmp} do
      movie = create_movie_with_watched_file(tmp, %{tmdb_id: "550"})

      Library.create_image!(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      stub_routes([{"/movie/550", {:error, 500}}])

      assert {:ok, result} = ImageRepair.repair_all()
      assert result.skipped == 1
      assert result.queue_rebuilt == 0
    end

    test "skips when entity has no tmdb_id and no external_ids", %{tmp: tmp} do
      tv = create_tv_series_with_watched_file(tmp)

      Library.create_image!(%{
        tv_series_id: tv.id,
        role: "poster",
        content_url: "#{tv.id}/poster.jpg",
        extension: "jpg"
      })

      assert {:ok, result} = ImageRepair.repair_all()
      assert result.skipped == 1
    end

    test "skips entity with no watched_files (cannot determine media_dir)", %{tmp: _tmp} do
      movie = create_standalone_movie(%{name: "Orphan", position: 0, tmdb_id: "550"})

      Library.create_image!(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      assert {:ok, result} = ImageRepair.repair_all()
      assert result.skipped == 1
    end
  end

  describe "repair_all/0 broadcast dedup" do
    test "broadcasts once per entity even with multiple missing roles", %{tmp: tmp} do
      movie = create_movie_with_watched_file(tmp, %{tmdb_id: "550"})

      Library.create_image!(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      Library.create_image!(%{
        movie_id: movie.id,
        role: "backdrop",
        content_url: "#{movie.id}/backdrop.jpg",
        extension: "jpg"
      })

      stub_get_movie("550", movie_detail())

      assert {:ok, result} = ImageRepair.repair_all()
      assert result.enqueued == 2

      assert_receive {:images_pending, %{entity_id: id}}
      assert id == movie.id

      refute_receive {:images_pending, _}, 50
    end
  end

  describe "repair_all/0 episode via parent series" do
    test "rebuilds queue row for an episode thumb via get_season", %{tmp: tmp} do
      tv = create_tv_series_with_watched_file(tmp, %{tmdb_id: "1396"})

      season = create_season(%{tv_series_id: tv.id, season_number: 1, number_of_episodes: 1})

      episode =
        create_episode(%{season_id: season.id, episode_number: 3, name: "Sample Episode 3"})

      Library.create_image!(%{
        episode_id: episode.id,
        role: "thumb",
        content_url: "#{episode.id}/thumb.jpg",
        extension: "jpg"
      })

      stub_get_season("1396", 1, %{
        "season_number" => 1,
        "episodes" => [
          %{"episode_number" => 1, "still_path" => "/ep1.jpg"},
          %{"episode_number" => 3, "still_path" => "/ep3.jpg"}
        ]
      })

      assert {:ok, result} = ImageRepair.repair_all()
      assert result.queue_rebuilt == 1

      assert [entry] = Repo.all(ImageQueueEntry)
      assert entry.owner_id == episode.id
      assert entry.owner_type == "episode"
      assert entry.entity_id == tv.id
      assert entry.source_url == "https://image.tmdb.org/t/p/original/ep3.jpg"
    end
  end

  # --- helpers ---

  defp create_movie_with_watched_file(tmp, attrs \\ %{}) do
    defaults = %{name: "Test Movie", position: 0}
    movie = create_standalone_movie(Map.merge(defaults, attrs))
    file_path = Path.join(tmp, "movie-#{movie.id}.mkv")
    create_linked_file(%{movie_id: movie.id, file_path: file_path, media_dir: tmp})
    movie
  end

  defp create_tv_series_with_watched_file(tmp, attrs \\ %{}) do
    tv = create_tv_series(attrs)
    file_path = Path.join(tmp, "tv-#{tv.id}.mkv")
    create_linked_file(%{tv_series_id: tv.id, file_path: file_path, media_dir: tmp})
    tv
  end

  defp create_movie_series_with_watched_file(tmp, attrs) do
    ms = create_movie_series(attrs)
    file_path = Path.join(tmp, "ms-#{ms.id}.mkv")
    create_linked_file(%{movie_series_id: ms.id, file_path: file_path, media_dir: tmp})
    ms
  end
end
