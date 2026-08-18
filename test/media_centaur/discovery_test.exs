defmodule MediaCentaur.DiscoveryTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Discovery
  alias MediaCentaur.Discovery.WatchlistItem
  alias MediaCentaur.TmdbStubs

  describe "WatchlistItem.create_changeset/1" do
    test "valid with identity + name" do
      changeset =
        WatchlistItem.create_changeset(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})

      assert changeset.valid?
    end

    test "requires tmdb_id, media_type, name" do
      changeset = WatchlistItem.create_changeset(%{})
      refute changeset.valid?
      assert %{tmdb_id: _, media_type: _, name: _} = errors_on(changeset)
    end

    test "rejects unknown media_type" do
      changeset =
        WatchlistItem.create_changeset(%{tmdb_id: 777, media_type: :book, name: "Sample"})

      refute changeset.valid?
      assert %{media_type: _} = errors_on(changeset)
    end
  end

  describe "watchlist" do
    @attrs %{tmdb_id: 777, media_type: :movie, name: "Sample Movie", year: "2010", poster_path: "/p.jpg"}

    setup do
      TmdbStubs.setup_tmdb_client()
    end

    test "add_to_watchlist is idempotent" do
      assert {:ok, item} = Discovery.add_to_watchlist(@attrs)
      assert {:ok, ^item} = Discovery.add_to_watchlist(@attrs)
      assert [_] = Repo.all(WatchlistItem)
      await_artwork_tasks()
    end

    test "add broadcasts a typed event" do
      Discovery.subscribe()
      {:ok, item} = Discovery.add_to_watchlist(@attrs)
      item_id = item.id

      assert_receive {:watchlist_item_added,
                      %Discovery.Events.ItemAdded{item_id: ^item_id, tmdb_id: 777, media_type: :movie}}

      await_artwork_tasks()
    end

    test "remove_from_watchlist deletes and broadcasts; absent is a no-op" do
      {:ok, _} = Discovery.add_to_watchlist(@attrs)
      Discovery.subscribe()
      assert :ok = Discovery.remove_from_watchlist(777, :movie)

      assert_receive {:watchlist_item_removed,
                      %Discovery.Events.ItemRemoved{tmdb_id: 777, media_type: :movie}}

      assert :ok = Discovery.remove_from_watchlist(777, :movie)
      refute Discovery.on_watchlist?(777, :movie)
      await_artwork_tasks()
    end

    test "watchlisted_refs returns the ref set" do
      {:ok, _} = Discovery.add_to_watchlist(@attrs)
      {:ok, _} = Discovery.add_to_watchlist(%{tmdb_id: 42, media_type: :tv_series, name: "Sample Show"})
      assert Discovery.watchlisted_refs() == MapSet.new([{777, :movie}, {42, :tv_series}])
      await_artwork_tasks()
    end

    test "list_watchlist returns newest-first with nil library owner when absent" do
      {:ok, _} = Discovery.add_to_watchlist(@attrs)
      assert [%{item: %WatchlistItem{tmdb_id: 777}, library_owner_id: nil}] = Discovery.list_watchlist()
      await_artwork_tasks()
    end

    test "list_watchlist resolves the library owner when a container exists" do
      {:ok, _} = Discovery.add_to_watchlist(@attrs)
      movie = create_standalone_movie(%{name: "Sample Movie"})
      create_external_id(%{source: "tmdb", external_id: "777", movie_id: movie.id})
      assert [%{library_owner_id: owner_id}] = Discovery.list_watchlist()
      assert owner_id == movie.id
      await_artwork_tasks()
    end

    test "duplicate insert at the changeset level returns an error, not a raise" do
      {:ok, _} = Discovery.add_to_watchlist(@attrs)
      # This insert is the operation under test, not setup: it pins that the
      # unique constraint surfaces as {:error, changeset} rather than raising —
      # the branch add_to_watchlist's concurrent-race recovery matches on.
      # credo:disable-for-next-line MediaCentaur.Credo.Checks.NoRepoSetupInTests
      assert {:error, changeset} = @attrs |> WatchlistItem.create_changeset() |> Repo.insert()
      assert %{tmdb_id: _} = errors_on(changeset)
      await_artwork_tasks()
    end
  end

  # `add_to_watchlist/1` fires an artwork task under the global
  # TaskSupervisor. Its Req.Test stub dies with this (owner) process, so
  # the test drives the task to completion before exiting (ADR-049) —
  # otherwise a task losing the race logs a "cannot find mock/stub" crash.
  defp await_artwork_tasks do
    MediaCentaur.TaskSupervisor
    |> Task.Supervisor.children()
    |> Enum.each(fn pid ->
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, _, _, _} -> :ok
      after
        1_000 -> raise "artwork task did not finish within 1s"
      end
    end)
  end
end
