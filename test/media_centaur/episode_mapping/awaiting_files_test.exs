defmodule MediaCentaur.EpisodeMapping.AwaitingFilesTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.EpisodeMapping
  alias MediaCentaur.EpisodeMapping.AwaitingFile

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        file_path: "/media/Sample Show/S02E01.mkv",
        media_dir: "/media",
        tmdb_id: 4242,
        series_title: "Sample Show",
        claimed_season: 2,
        claimed_episode: 1,
        claimed_title: "Shall We Go, Then"
      },
      overrides
    )
  end

  describe "divert/1" do
    test "parks a diverted file as a pending awaiting record" do
      assert {:ok, %AwaitingFile{} = file} = EpisodeMapping.divert(attrs())

      assert file.status == :pending
      assert file.tmdb_id == 4242
      assert file.claimed_season == 2
      assert file.claimed_episode == 1
      assert file.claimed_title == "Shall We Go, Then"
    end

    test "keeps the year the file's name claims" do
      assert {:ok, file} =
               EpisodeMapping.divert(
                 attrs(%{
                   claimed_season: nil,
                   claimed_episode: nil,
                   claimed_title: nil,
                   claimed_year: 2025
                 })
               )

      assert file.claimed_year == 2025
    end

    test "requires file_path, media_dir and tmdb_id" do
      assert {:error, changeset} = EpisodeMapping.divert(%{claimed_season: 2})

      assert %{file_path: _, media_dir: _, tmdb_id: _} = errors_on(changeset)
    end

    test "is idempotent on file_path — re-diverting returns the same record" do
      assert {:ok, first} = EpisodeMapping.divert(attrs())
      assert {:ok, second} = EpisodeMapping.divert(attrs(%{claimed_title: "Updated"}))

      assert first.id == second.id
      assert Enum.count(EpisodeMapping.list_awaiting()) == 1
    end
  end

  # Changed 2026-09-29 (campaign `review-coherence`): these used a
  # `:resolved` status that confirm set after linking. Being linked is the
  # answer, read from the library, so the status is gone: a confirmed row is
  # deleted, and one whose file is linked any other way is not listed.
  defp link!(file_path) do
    movie = create_movie(%{name: "Sample Movie"})
    create_linked_file(%{file_path: file_path, media_dir: "/media", movie_id: movie.id})
  end

  describe "count_awaiting/0" do
    test "counts only files still awaiting a mapping decision" do
      assert EpisodeMapping.count_awaiting() == 0

      {:ok, _pending} = EpisodeMapping.divert(attrs())
      {:ok, _linked} = EpisodeMapping.divert(attrs(%{file_path: "/media/Sample Show/S02E02.mkv"}))
      {:ok, dismissed} = EpisodeMapping.divert(attrs(%{file_path: "/media/Sample Show/S02E03.mkv"}))

      link!("/media/Sample Show/S02E02.mkv")
      {:ok, _} = EpisodeMapping.dismiss_awaiting(dismissed)

      assert EpisodeMapping.count_awaiting() == 1
    end
  end

  describe "listing" do
    test "list_awaiting/0 returns only files still awaiting a decision" do
      {:ok, pending} = EpisodeMapping.divert(attrs())
      {:ok, _other} = EpisodeMapping.divert(attrs(%{file_path: "/media/Sample Show/S02E02.mkv"}))
      link!("/media/Sample Show/S02E02.mkv")

      ids = Enum.map(EpisodeMapping.list_awaiting(), & &1.id)

      assert ids == [pending.id]
    end

    test "awaiting_for_tmdb/1 scopes to one show, and leaves out a linked file" do
      {:ok, mine} = EpisodeMapping.divert(attrs())
      {:ok, _linked} = EpisodeMapping.divert(attrs(%{file_path: "/media/Sample Show/S02E02.mkv"}))
      {:ok, _theirs} = EpisodeMapping.divert(attrs(%{file_path: "/media/Other/S02E01.mkv", tmdb_id: 99}))
      link!("/media/Sample Show/S02E02.mkv")

      ids = Enum.map(EpisodeMapping.awaiting_for_tmdb(4242), & &1.id)

      assert ids == [mine.id]
    end
  end

  describe "dismiss_awaiting/1" do
    test "dismiss marks the record dismissed and drops it from the pending list" do
      {:ok, file} = EpisodeMapping.divert(attrs())

      assert {:ok, dismissed} = EpisodeMapping.dismiss_awaiting(file)
      assert dismissed.status == :dismissed
      assert EpisodeMapping.list_awaiting() == []
    end
  end
end
