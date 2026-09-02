defmodule MediaCentaur.DiscoveryTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]

  alias MediaCentaur.Discovery
  alias MediaCentaur.Discovery.WatchlistItem
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.TMDB.Title

  describe "WatchlistItem.create_changeset/2" do
    test "embeds the title and derives the identity columns from it" do
      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie", year: "2010"})
      changeset = WatchlistItem.create_changeset(title, %{note: "why"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :tmdb_id) == 777
      assert Ecto.Changeset.get_change(changeset, :media_type) == :movie
      assert Ecto.Changeset.get_change(changeset, :note) == "why"
      assert %Title{name: "Sample Movie"} = Ecto.Changeset.get_embed(changeset, :title, :struct)
    end

    test "rejects an unknown source" do
      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})
      changeset = WatchlistItem.create_changeset(title, %{source: :carrier_pigeon})
      refute changeset.valid?
      assert %{source: _} = errors_on(changeset)
    end
  end

  describe "watchlist" do
    @title Title.new!(%{
             tmdb_id: 777,
             media_type: :movie,
             name: "Sample Movie",
             year: "2010",
             poster_path: "/p.jpg"
           })

    setup do
      TmdbStubs.setup_tmdb_client()
    end

    test "add_to_watchlist is idempotent" do
      assert {:ok, item} = Discovery.add_to_watchlist(@title)
      assert {:ok, ^item} = Discovery.add_to_watchlist(@title)
      assert [_] = Repo.all(WatchlistItem)
      await_supervised_tasks()
    end

    test "add broadcasts a typed event" do
      Discovery.subscribe()
      {:ok, item} = Discovery.add_to_watchlist(@title)
      item_id = item.id

      assert_receive {:watchlist_item_added,
                      %Discovery.Events.ItemAdded{item_id: ^item_id, tmdb_id: 777, media_type: :movie}}

      await_supervised_tasks()
    end

    test "remove_from_watchlist deletes and broadcasts; absent is a no-op" do
      {:ok, _} = Discovery.add_to_watchlist(@title)
      Discovery.subscribe()
      assert :ok = Discovery.remove_from_watchlist(777, :movie)

      assert_receive {:watchlist_item_removed,
                      %Discovery.Events.ItemRemoved{tmdb_id: 777, media_type: :movie}}

      assert :ok = Discovery.remove_from_watchlist(777, :movie)
      refute Discovery.on_watchlist?(777, :movie)
      await_supervised_tasks()
    end

    test "watchlisted_refs returns the ref set" do
      {:ok, _} = Discovery.add_to_watchlist(@title)

      {:ok, _} =
        Discovery.add_to_watchlist(
          Title.new!(%{tmdb_id: 42, media_type: :tv_series, name: "Sample Show"})
        )

      assert Discovery.watchlisted_refs() == MapSet.new([{777, :movie}, {42, :tv_series}])
      await_supervised_tasks()
    end

    test "list_watchlist returns newest-first with nil library owner when absent" do
      {:ok, _} = Discovery.add_to_watchlist(@title)
      assert [%{item: %WatchlistItem{tmdb_id: 777}, library_owner_id: nil}] = Discovery.list_watchlist()
      await_supervised_tasks()
    end

    test "list_watchlist resolves the library owner when a presentable container exists" do
      {:ok, _} = Discovery.add_to_watchlist(@title)
      movie = create_standalone_movie(%{name: "Sample Movie"})
      create_external_id(%{source: "tmdb", external_id: "777", movie_id: movie.id})
      create_linked_file(%{movie_id: movie.id})
      assert [%{library_owner_id: owner_id}] = Discovery.list_watchlist()
      assert owner_id == movie.id
      await_supervised_tasks()
    end

    test "TmdbArtworkHolds holds every watchlist ref" do
      {:ok, _} = Discovery.add_to_watchlist(@title)
      assert MediaCentaur.Discovery.TmdbArtworkHolds.holds() == MapSet.new([{:movie, 777}])
      await_supervised_tasks()
    end

    test "duplicate insert at the changeset level returns an error, not a raise" do
      {:ok, _} = Discovery.add_to_watchlist(@title)
      # This insert is the operation under test, not setup: it pins that the
      # unique constraint surfaces as {:error, changeset} rather than raising —
      # the branch add_to_watchlist's concurrent-race recovery matches on.
      # credo:disable-for-next-line MediaCentaur.Credo.Checks.NoRepoSetupInTests
      assert {:error, changeset} = @title |> WatchlistItem.create_changeset() |> Repo.insert()
      assert %{tmdb_id: _} = errors_on(changeset)
      await_supervised_tasks()
    end

    test "the stored row reads back its title snapshot" do
      {:ok, item} = Discovery.add_to_watchlist(@title, %{note: "why"})

      assert %WatchlistItem{
               title: %Title{tmdb_id: 777, name: "Sample Movie", year: "2010", poster_path: "/p.jpg"},
               note: "why"
             } = Repo.get!(WatchlistItem, item.id)

      await_supervised_tasks()
    end
  end
end
