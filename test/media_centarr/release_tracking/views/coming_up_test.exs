defmodule MediaCentarr.ReleaseTracking.Views.ComingUpTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.ReleaseTracking
  alias MediaCentarr.ReleaseTracking.Views
  alias MediaCentarr.ReleaseTracking.Views.ComingUp
  alias MediaCentarr.ReleaseTracking.Views.ComingUpItem
  alias MediaCentarr.Topics

  @table :release_tracking_view_coming_up

  defp seed_release(name, air_date, opts \\ []) do
    item = create_tracking_item(%{name: name, status: :watching})

    create_tracking_release(
      Map.merge(
        %{
          item_id: item.id,
          air_date: air_date,
          season_number: Keyword.get(opts, :season, 1),
          episode_number: Keyword.get(opts, :episode, 1),
          released: false
        },
        Map.new(Keyword.drop(opts, [:season, :episode]))
      )
    )

    item
  end

  defp on_exit_clear_table do
    on_exit(fn ->
      case :ets.whereis(@table) do
        :undefined -> :ok
        _ref -> :ets.delete(@table)
      end
    end)
  end

  describe "Cache behaviour — relevant?/1" do
    test "accepts release-tracking update events" do
      assert ComingUp.relevant?({:releases_updated, [1, 2]})
      assert ComingUp.relevant?({:item_removed, 123, "tv"})
      assert ComingUp.relevant?({:release_ready, %{}, %{}})
    end

    test "rejects unrelated messages" do
      refute ComingUp.relevant?(:something_else)
      refute ComingUp.relevant?({:entities_changed, %{}})
      refute ComingUp.relevant?({:other, "payload"})
    end
  end

  describe "refresh_cache/0" do
    test "populates the ETS table with view-model structs ordered by air date" do
      on_exit_clear_table()

      today = Date.utc_today()
      seed_release("Late Show", Date.add(today, 30))
      seed_release("Mid Show", Date.add(today, 14))
      seed_release("Soon Show", Date.add(today, 3))

      assert :ok = ComingUp.refresh_cache()

      items = Views.coming_up(today, Date.add(today, 90), limit: 10)

      assert length(items) == 3
      assert Enum.all?(items, &is_struct(&1, ComingUpItem))

      names = Enum.map(items, & &1.item.name)
      assert names == ["Soon Show", "Mid Show", "Late Show"]
    end

    test "broadcasts {:release_tracking_view_updated, :coming_up} after refresh" do
      on_exit_clear_table()

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.release_tracking_views())

      today = Date.utc_today()
      seed_release("Some Show", Date.add(today, 10))

      assert :ok = ComingUp.refresh_cache()

      assert_receive {:release_tracking_view_updated, :coming_up}
    end

    test "is idempotent — repeat calls replace the snapshot, no leak" do
      on_exit_clear_table()

      today = Date.utc_today()
      seed_release("Show A", Date.add(today, 5))
      assert :ok = ComingUp.refresh_cache()
      assert length(Views.coming_up(today, Date.add(today, 90), limit: 10)) == 1

      seed_release("Show B", Date.add(today, 10))
      assert :ok = ComingUp.refresh_cache()
      assert length(Views.coming_up(today, Date.add(today, 90), limit: 10)) == 2

      assert :ok = ComingUp.refresh_cache()
      assert length(Views.coming_up(today, Date.add(today, 90), limit: 10)) == 2
    end
  end

  describe "Views.coming_up/3 — ETS path vs DB fallback" do
    test "falls back to DB query when the ETS table is absent" do
      today = Date.utc_today()
      seed_release("Cold Read", Date.add(today, 10))

      assert :undefined = :ets.whereis(@table)

      [item] = Views.coming_up(today, Date.add(today, 90), limit: 5)
      assert item.item.name == "Cold Read"
    end

    test "filters by the requested date window at read time" do
      on_exit_clear_table()

      today = Date.utc_today()
      seed_release("Within Window", Date.add(today, 5))
      seed_release("Past Window", Date.add(today, 200))

      assert :ok = ComingUp.refresh_cache()

      items = Views.coming_up(today, Date.add(today, 90), limit: 10)
      names = Enum.map(items, & &1.item.name)
      assert names == ["Within Window"]
    end

    test "honours :limit on the ETS path" do
      on_exit_clear_table()

      today = Date.utc_today()

      Enum.each(1..5, fn i ->
        seed_release("Show #{i}", Date.add(today, i * 2))
      end)

      assert :ok = ComingUp.refresh_cache()

      assert length(Views.coming_up(today, Date.add(today, 90), limit: 3)) == 3
      assert length(Views.coming_up(today, Date.add(today, 90), limit: 100)) == 5
    end
  end

  describe "equivalence with ReleaseTracking.list_releases_between/3" do
    test "ETS-cached output matches list_releases_between for the same DB state" do
      on_exit_clear_table()

      today = Date.utc_today()
      to_date = Date.add(today, 90)

      seed_release("Show One", Date.add(today, 3))
      seed_release("Show Two", Date.add(today, 15))

      :ok = ComingUp.refresh_cache()

      legacy = ReleaseTracking.list_releases_between(today, to_date, limit: 10)
      cached = Views.coming_up(today, to_date, limit: 10)

      assert length(legacy) == length(cached)

      Enum.each(Enum.zip(legacy, cached), fn {legacy_row, cached_item} ->
        assert legacy_row.item.id == cached_item.item.id
        assert legacy_row.item.name == cached_item.item.name
        assert legacy_row.air_date == cached_item.air_date
        assert legacy_row.season_number == cached_item.season_number
        assert legacy_row.episode_number == cached_item.episode_number
      end)
    end
  end

  describe "ComingUpItem struct" do
    test "enforces item and air_date" do
      assert_raise ArgumentError, fn ->
        struct!(ComingUpItem, %{})
      end
    end

    test "permits nil values for the optional fields" do
      ref = %MediaCentarr.ReleaseTracking.Views.ComingUpItemRef{
        id: "abc",
        name: "X",
        tmdb_id: 1,
        media_type: :movie
      }

      item = %ComingUpItem{item: ref, air_date: ~D[2026-05-10]}

      assert item.status == :scheduled
      assert item.backdrop_url == nil
      assert item.logo_url == nil
      assert item.season_number == nil
      assert item.episode_number == nil
    end
  end
end
