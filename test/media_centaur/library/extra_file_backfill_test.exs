defmodule MediaCentaur.Library.ExtraFileBackfillTest do
  @moduledoc """
  Backfill of `ExtraFile` rows for extras imported before the ingest path wrote
  them (ExtraFile-unification / Schema v2 "Task G"). Network-free, deterministic,
  idempotent — runs on boot so existing extras become "linked" and stop being
  re-emitted by `rescan_unlinked`.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library
  alias MediaCentaur.Library.{ExtraFile, FilePresence}

  setup do
    movie = create_movie(%{name: "Sample Movie"})
    %{movie: movie}
  end

  test "creates an ExtraFile for an extra that has a FilePresence but no ExtraFile", %{movie: movie} do
    extra =
      create_extra(%{movie_id: movie.id, name: "Clip", content_url: "/media/extras/clip.mkv"})

    FilePresence.stamp("/media/extras/clip.mkv", "/media")

    assert %{created: 1} = Library.Files.backfill_extras()

    extra = Repo.preload(extra, :files)
    assert [extra_file] = extra.files
    assert extra_file.file_path == "/media/extras/clip.mkv"
    assert extra_file.media_dir == "/media"
  end

  test "skips an extra whose path has no FilePresence (can't resolve media dir)", %{movie: movie} do
    extra =
      create_extra(%{movie_id: movie.id, name: "Orphan", content_url: "/media/extras/orphan.mkv"})

    assert %{created: 0} = Library.Files.backfill_extras()
    assert Repo.preload(extra, :files).files == []
  end

  test "is idempotent — a second run creates nothing", %{movie: movie} do
    create_extra(%{movie_id: movie.id, name: "Clip", content_url: "/media/extras/clip.mkv"})
    FilePresence.stamp("/media/extras/clip.mkv", "/media")

    assert %{created: 1} = Library.Files.backfill_extras()
    assert %{created: 0} = Library.Files.backfill_extras()

    assert Repo.aggregate(ExtraFile, :count) == 1
  end

  test "ignores extras with no content_url", %{movie: movie} do
    create_extra(%{movie_id: movie.id, name: "No file", content_url: nil})

    assert %{created: 0} = Library.Files.backfill_extras()
  end
end
