defmodule MediaCentaur.ReleaseTracking.SetRungTest do
  @moduledoc """
  `set_rung/3` is the only way a title moves on the ladder, and the only
  thing that creates or destroys a tracked title. The machinery is
  derived, so these tests are about one question: given a rung, does the
  right machinery exist?
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmdbStubs

  alias MediaCentaur.Discovery
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TMDB.Title

  @tmdb_id 246_810

  setup do
    setup_tmdb_client()
    stub_series_universe_for_targeting()
    :ok
  end

  defp show, do: Title.new!(%{tmdb_id: @tmdb_id, media_type: :tv_series, name: "Sample Show"})

  defp tracked?, do: ReleaseTracking.get_item_by_tmdb(@tmdb_id, :tv_series) != nil

  describe "raising onto the ladder" do
    test "List puts the title on the list and follows nothing" do
      assert {:ok, intent} = ReleaseTracking.set_rung(show(), :list)

      assert intent.rung == :list
      assert Discovery.listed?(@tmdb_id, :tv_series)
      refute tracked?()
    end

    test "Follow and above derive a tracked title, and list it as part of the act" do
      for rung <- [:follow, :ask, :grab, :default] do
        assert {:ok, intent} = ReleaseTracking.set_rung(show(), rung)
        assert intent.rung == rung
        assert Discovery.listed?(@tmdb_id, :tv_series)
        assert tracked?(), "#{rung} must derive a tracked title"
      end
    end

    test "the calendar is fetched once, not on every raise" do
      {:ok, _} = ReleaseTracking.set_rung(show(), :follow)
      item = ReleaseTracking.get_item_by_tmdb(@tmdb_id, :tv_series)

      {:ok, _} = ReleaseTracking.set_rung(show(), :grab)

      assert ReleaseTracking.get_item_by_tmdb(@tmdb_id, :tv_series).id == item.id
    end

    test "provenance is carried onto a record that did not exist" do
      activity_id = Ecto.UUID.generate()

      {:ok, intent} =
        ReleaseTracking.set_rung(show(), :list, %{
          source: :friend,
          activity_id: activity_id,
          note: "you'll like this"
        })

      assert intent.source == :friend
      assert intent.activity_id == activity_id
      assert intent.note == "you'll like this"
    end
  end

  describe "lowering the ladder" do
    test "dropping below Follow destroys the tracked title but keeps the listing" do
      {:ok, _} = ReleaseTracking.set_rung(show(), :grab)
      assert tracked?()

      assert {:ok, intent} = ReleaseTracking.set_rung(show(), :list)

      assert intent.rung == :list
      assert Discovery.listed?(@tmdb_id, :tv_series)
      refute tracked?()
    end

    test "Off deletes the record and everything derived from it" do
      {:ok, _} = ReleaseTracking.set_rung(show(), :grab)

      assert {:ok, nil} = ReleaseTracking.set_rung(show(), :off)

      refute Discovery.listed?(@tmdb_id, :tv_series)
      refute tracked?()
      assert Discovery.rung(@tmdb_id, :tv_series) == nil
    end

    test "Off on a title that was never on the ladder is a no-op" do
      assert {:ok, nil} = ReleaseTracking.set_rung(show(), :off)
      refute tracked?()
    end

    test "re-raising after Off starts fresh — there is no disarmed row to remember" do
      {:ok, _} = ReleaseTracking.set_rung(show(), :grab)
      {:ok, nil} = ReleaseTracking.set_rung(show(), :off)

      assert {:ok, intent} = ReleaseTracking.set_rung(show(), :follow)
      assert intent.rung == :follow
      assert tracked?()
    end
  end

  describe "a film you already own" do
    test "is complete: the rung stands, the machinery does not" do
      movie = create_standalone_movie(%{name: "Owned Film"})
      create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
      create_linked_file(%{movie_id: movie.id})

      stub_routes([{"/movie/777", %{"id" => 777, "title" => "Owned Film"}}])

      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Owned Film"})

      assert {:ok, intent} = ReleaseTracking.set_rung(title, :grab)

      assert intent.rung == :grab

      refute ReleaseTracking.get_item_by_tmdb(777, :movie),
             "an owned film has no future release to follow"
    end
  end
end
