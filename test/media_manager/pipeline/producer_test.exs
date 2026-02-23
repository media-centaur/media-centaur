defmodule MediaManager.Pipeline.ProducerTest do
  use MediaManager.DataCase

  alias MediaManager.Library.WatchedFile

  # These tests exercise the claiming query and bulk update logic
  # extracted from the Producer module, without starting the GenStage process.

  defp claim_files(limit) do
    stale_threshold = DateTime.utc_now() |> DateTime.add(-5, :minute)

    query =
      Ash.Query.for_read(WatchedFile, :claimable_files, %{
        limit: limit,
        stale_threshold: stale_threshold
      })

    case Ash.read(query) do
      {:ok, []} ->
        []

      {:ok, files} ->
        result =
          Ash.bulk_update(files, :claim, %{},
            strategy: :stream,
            return_records?: true,
            return_errors?: true
          )

        result.records || []
    end
  end

  describe "claiming files" do
    test "detected files become :queued after claim" do
      for _ <- 1..5, do: create_watched_file()

      claimed = claim_files(10)

      assert length(claimed) == 5
      assert Enum.all?(claimed, &(&1.state == :queued))
    end

    test "no files — claim returns empty list" do
      claimed = claim_files(10)
      assert claimed == []
    end

    test "partial demand — claims only available count" do
      for _ <- 1..3, do: create_watched_file()

      claimed = claim_files(10)
      assert length(claimed) == 3
    end

    test "already queued (fresh) files are not re-claimed" do
      create_queued_file()

      claimed = claim_files(10)
      assert claimed == []
    end

    test "stale queued files are re-claimed" do
      file = create_queued_file()

      # Backdate the updated_at to simulate a stale file (> 5 minutes old)
      stale_time = DateTime.utc_now() |> DateTime.add(-10, :minute)

      MediaManager.Repo.query!(
        "UPDATE watched_files SET updated_at = ?1 WHERE id = ?2",
        [DateTime.to_iso8601(stale_time), file.id]
      )

      claimed = claim_files(10)
      assert length(claimed) == 1
      assert hd(claimed).id == file.id
    end

    test "mixed states — only detected and stale queued are claimed" do
      # Detected files
      create_watched_file()
      create_watched_file()

      # Fresh queued (should not be claimed)
      create_queued_file()

      # Completed/error files (should not be claimed)
      completed = create_watched_file()

      completed
      |> Ash.Changeset.for_update(:update_state, %{state: :complete})
      |> Ash.update!()

      claimed = claim_files(10)
      assert length(claimed) == 2
      assert Enum.all?(claimed, &(&1.state == :queued))
    end

    test "limit is respected — claims at most N files" do
      for _ <- 1..5, do: create_watched_file()

      claimed = claim_files(2)
      assert length(claimed) == 2
    end
  end
end
