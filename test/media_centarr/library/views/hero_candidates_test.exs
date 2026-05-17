defmodule MediaCentarr.Library.Views.HeroCandidatesTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Library
  alias MediaCentarr.Library.Views
  alias MediaCentarr.Library.Views.HeroCandidates
  alias MediaCentarr.Library.Views.HeroCandidatesItem
  alias MediaCentarr.Topics

  @table :library_view_hero_candidates

  defp seed_hero_candidate(name) do
    movie = create_standalone_movie(%{name: name, description: "A synopsis for #{name}"})
    record_present(create_linked_file(%{movie_id: movie.id}))

    create_image(%{
      movie_id: movie.id,
      role: "backdrop",
      content_url: "#{movie.id}/backdrop.jpg",
      extension: "jpg"
    })

    movie
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
      assert HeroCandidates.relevant?({:entities_changed, %{entity_ids: ["x"]}})
    end

    test "accepts availability changes (file presence flips alter the result set)" do
      assert HeroCandidates.relevant?({:availability_changed, "/some/dir", :available})
      assert HeroCandidates.relevant?({:availability_changed, "/some/dir", :unavailable})
    end

    test "rejects unrelated messages" do
      refute HeroCandidates.relevant?(:something_else)
      refute HeroCandidates.relevant?({:watch_event_created, %{}})
      refute HeroCandidates.relevant?({:entity_progress_updated, %{}})
      refute HeroCandidates.relevant?({:other, "payload"})
    end
  end

  describe "refresh_cache/0" do
    test "populates the ETS table with view-model structs in candidate order" do
      on_exit_clear_table()

      seed_hero_candidate("Hero One")
      seed_hero_candidate("Hero Two")
      seed_hero_candidate("Hero Three")

      assert :ok = HeroCandidates.refresh_cache()

      items = Views.hero_candidates(limit: 10)

      assert length(items) == 3
      assert Enum.all?(items, &is_struct(&1, HeroCandidatesItem))
      assert Enum.all?(items, &(&1.backdrop_url != nil))
    end

    test "broadcasts {:library_view_updated, :hero_candidates} after refresh" do
      on_exit_clear_table()

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_views())

      seed_hero_candidate("Some Movie")

      assert :ok = HeroCandidates.refresh_cache()

      assert_receive {:library_view_updated, :hero_candidates}
    end

    test "is idempotent — repeat calls replace the snapshot, no leak" do
      on_exit_clear_table()

      seed_hero_candidate("Movie A")
      assert :ok = HeroCandidates.refresh_cache()
      assert length(Views.hero_candidates(limit: 10)) == 1

      seed_hero_candidate("Movie B")
      assert :ok = HeroCandidates.refresh_cache()
      assert length(Views.hero_candidates(limit: 10)) == 2

      assert :ok = HeroCandidates.refresh_cache()
      assert length(Views.hero_candidates(limit: 10)) == 2
    end
  end

  describe "Views.hero_candidates/1 — ETS path vs DB fallback" do
    test "falls back to DB query when the ETS table is absent" do
      seed_hero_candidate("Cold Read")

      assert :undefined = :ets.whereis(@table)

      [item] = Views.hero_candidates(limit: 5)
      assert item.name == "Cold Read"
      assert item.backdrop_url != nil
    end

    test "honours :limit on the ETS path" do
      on_exit_clear_table()

      Enum.each(1..5, fn i -> seed_hero_candidate("Movie #{i}") end)
      assert :ok = HeroCandidates.refresh_cache()

      assert length(Views.hero_candidates(limit: 3)) == 3
      assert length(Views.hero_candidates(limit: 100)) == 5
    end

    test "honours :limit on the DB-fallback path" do
      Enum.each(1..5, fn i -> seed_hero_candidate("Movie #{i}") end)

      assert :undefined = :ets.whereis(@table)

      assert length(Views.hero_candidates(limit: 3)) == 3
    end
  end

  describe "equivalence with Library.list_hero_candidates/1" do
    test "ETS-cached output matches Library.list_hero_candidates for the same DB state" do
      on_exit_clear_table()

      seed_hero_candidate("Movie One")
      seed_hero_candidate("Movie Two")

      :ok = HeroCandidates.refresh_cache()

      legacy = Library.list_hero_candidates(limit: 10)
      cached = Views.hero_candidates(limit: 10)

      assert length(legacy) == length(cached)

      legacy_ids = Enum.sort(Enum.map(legacy, & &1.id))
      cached_ids = Enum.sort(Enum.map(cached, & &1.id))
      assert legacy_ids == cached_ids

      Enum.each(Enum.zip(legacy, cached), fn {legacy_row, cached_item} ->
        assert legacy_row.id == cached_item.id
        assert legacy_row.name == cached_item.name
        assert legacy_row.backdrop_url == cached_item.backdrop_url
        assert legacy_row.overview == cached_item.overview
      end)
    end
  end

  describe "HeroCandidatesItem struct" do
    test "enforces id and name" do
      assert_raise ArgumentError, fn ->
        struct!(HeroCandidatesItem, %{})
      end

      assert_raise ArgumentError, fn ->
        struct!(HeroCandidatesItem, %{id: "x"})
      end
    end

    test "permits nil values for the optional fields" do
      item = %HeroCandidatesItem{id: "id-1", name: "Name"}

      assert item.year == nil
      assert item.runtime_minutes == nil
      assert item.genres == nil
      assert item.overview == nil
      assert item.backdrop_url == nil
      assert item.logo_url == nil
    end
  end
end
