defmodule MediaCentaur.Reconciliation.AwaitingFilesTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Reconciliation
  alias MediaCentaur.Reconciliation.AwaitingFile

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
      assert {:ok, %AwaitingFile{} = file} = Reconciliation.divert(attrs())

      assert file.status == :pending
      assert file.tmdb_id == 4242
      assert file.claimed_season == 2
      assert file.claimed_episode == 1
      assert file.claimed_title == "Shall We Go, Then"
    end

    test "requires file_path, media_dir and tmdb_id" do
      assert {:error, changeset} = Reconciliation.divert(%{claimed_season: 2})

      assert %{file_path: _, media_dir: _, tmdb_id: _} = errors_on(changeset)
    end

    test "is idempotent on file_path — re-diverting returns the same record" do
      assert {:ok, first} = Reconciliation.divert(attrs())
      assert {:ok, second} = Reconciliation.divert(attrs(%{claimed_title: "Updated"}))

      assert first.id == second.id
      assert Enum.count(Reconciliation.list_awaiting()) == 1
    end
  end

  describe "listing" do
    test "list_awaiting/0 returns only pending records" do
      {:ok, pending} = Reconciliation.divert(attrs())
      {:ok, other} = Reconciliation.divert(attrs(%{file_path: "/media/Sample Show/S02E02.mkv"}))
      {:ok, _} = Reconciliation.resolve_awaiting(other)

      ids = Enum.map(Reconciliation.list_awaiting(), & &1.id)

      assert ids == [pending.id]
    end

    test "awaiting_for_tmdb/1 scopes to one show" do
      {:ok, mine} = Reconciliation.divert(attrs())
      {:ok, _theirs} = Reconciliation.divert(attrs(%{file_path: "/media/Other/S02E01.mkv", tmdb_id: 99}))

      ids = Enum.map(Reconciliation.awaiting_for_tmdb(4242), & &1.id)

      assert ids == [mine.id]
    end
  end

  describe "resolve_awaiting/1 and dismiss_awaiting/1" do
    test "resolve marks the record resolved and drops it from the pending list" do
      {:ok, file} = Reconciliation.divert(attrs())

      assert {:ok, resolved} = Reconciliation.resolve_awaiting(file)
      assert resolved.status == :resolved
      assert Reconciliation.list_awaiting() == []
    end

    test "dismiss marks the record dismissed and drops it from the pending list" do
      {:ok, file} = Reconciliation.divert(attrs())

      assert {:ok, dismissed} = Reconciliation.dismiss_awaiting(file)
      assert dismissed.status == :dismissed
      assert Reconciliation.list_awaiting() == []
    end
  end
end
