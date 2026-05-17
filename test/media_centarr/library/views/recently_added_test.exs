defmodule MediaCentarr.Library.Views.RecentlyAddedTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Library
  alias MediaCentarr.Library.Views
  alias MediaCentarr.Library.Views.RecentlyAdded
  alias MediaCentarr.Library.Views.RecentlyAddedItem
  alias MediaCentarr.Repo
  alias MediaCentarr.Topics

  @table :library_view_recently_added

  defp seed_recently_added(name, inserted_at \\ nil) do
    movie = create_standalone_movie(%{name: name})
    record_present(create_linked_file(%{movie_id: movie.id}))

    if inserted_at do
      movie
      |> Ecto.Changeset.change(inserted_at: inserted_at)
      |> Repo.update!()
    else
      movie
    end
  end

  defp on_exit_clear_table do
    on_exit(fn ->
      case :ets.whereis(@table) do
        :undefined -> :ok
        _ref -> :ets.delete(@table)
      end
    end)
  end

  # Post-Phase-7 no-op (legacy hook from the library-presence-unification campaign).
  defp record_present(_file), do: :ok

  describe "Cache behaviour — relevant?/1" do
    test "accepts library entity-changed events" do
      assert RecentlyAdded.relevant?({:entities_changed, %{entity_ids: ["x"]}})
    end

    test "accepts availability changes (file presence flips alter the result set)" do
      assert RecentlyAdded.relevant?({:availability_changed, "/some/dir", :available})
      assert RecentlyAdded.relevant?({:availability_changed, "/some/dir", :unavailable})
    end

    test "rejects unrelated messages" do
      refute RecentlyAdded.relevant?(:something_else)
      refute RecentlyAdded.relevant?({:watch_event_created, %{}})
      refute RecentlyAdded.relevant?({:entity_progress_updated, %{}})
      refute RecentlyAdded.relevant?({:other, "payload"})
    end
  end

  describe "refresh_cache/0" do
    test "populates the ETS table with view-model structs ordered newest-first" do
      on_exit_clear_table()

      now = DateTime.utc_now(:second)
      seed_recently_added("Oldest", DateTime.add(now, -3600, :second))
      seed_recently_added("Middle", DateTime.add(now, -1800, :second))
      seed_recently_added("Newest", now)

      assert :ok = RecentlyAdded.refresh_cache()

      items = Views.recently_added(limit: 10)

      assert length(items) == 3
      assert Enum.all?(items, &is_struct(&1, RecentlyAddedItem))

      names = Enum.map(items, & &1.name)
      assert names == ["Newest", "Middle", "Oldest"]
    end

    test "broadcasts {:library_view_updated, :recently_added} after refresh" do
      on_exit_clear_table()

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_views())

      seed_recently_added("Some Movie")

      assert :ok = RecentlyAdded.refresh_cache()

      assert_receive {:library_view_updated, :recently_added}
    end

    test "is idempotent — repeat calls replace the snapshot, no leak" do
      on_exit_clear_table()

      seed_recently_added("Movie A")
      assert :ok = RecentlyAdded.refresh_cache()
      assert length(Views.recently_added(limit: 10)) == 1

      seed_recently_added("Movie B")
      assert :ok = RecentlyAdded.refresh_cache()
      assert length(Views.recently_added(limit: 10)) == 2

      assert :ok = RecentlyAdded.refresh_cache()
      assert length(Views.recently_added(limit: 10)) == 2
    end
  end

  describe "Views.recently_added/1 — ETS path vs DB fallback" do
    test "falls back to DB query when the ETS table is absent" do
      seed_recently_added("Cold Read")

      assert :undefined = :ets.whereis(@table)

      [item] = Views.recently_added(limit: 5)
      assert item.name == "Cold Read"
    end

    test "honours :limit on the ETS path" do
      on_exit_clear_table()

      Enum.each(1..5, fn i -> seed_recently_added("Movie #{i}") end)
      assert :ok = RecentlyAdded.refresh_cache()

      assert length(Views.recently_added(limit: 3)) == 3
      assert length(Views.recently_added(limit: 100)) == 5
    end

    test "honours :limit on the DB-fallback path" do
      Enum.each(1..5, fn i -> seed_recently_added("Movie #{i}") end)

      assert :undefined = :ets.whereis(@table)

      assert length(Views.recently_added(limit: 3)) == 3
    end
  end

  describe "equivalence with Library.list_recently_added/1" do
    test "ETS-cached output matches Library.list_recently_added for the same DB state" do
      on_exit_clear_table()

      seed_recently_added("Movie One")
      Process.sleep(5)
      seed_recently_added("Movie Two")

      :ok = RecentlyAdded.refresh_cache()

      legacy = Library.list_recently_added(limit: 10)
      cached = Views.recently_added(limit: 10)

      assert length(legacy) == length(cached)

      Enum.each(Enum.zip(legacy, cached), fn {legacy_row, cached_item} ->
        assert legacy_row.id == cached_item.id
        assert legacy_row.name == cached_item.name
        assert legacy_row.year == cached_item.year
        assert legacy_row.poster_url == cached_item.poster_url
      end)
    end
  end

  describe "RecentlyAddedItem struct" do
    test "enforces id and name" do
      assert_raise ArgumentError, fn ->
        struct!(RecentlyAddedItem, %{})
      end

      assert_raise ArgumentError, fn ->
        struct!(RecentlyAddedItem, %{id: "x"})
      end
    end

    test "permits nil values for the optional fields" do
      item = %RecentlyAddedItem{id: "id-1", name: "Name"}

      assert item.year == nil
      assert item.poster_url == nil
    end
  end
end
