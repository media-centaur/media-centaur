defmodule MediaCentaur.ReleaseTracking.SetRungTest do
  @moduledoc """
  `set_rung/3` is the only way a title moves on the ladder, and the only
  thing that creates or destroys a tracked title. The machinery is
  derived, so these tests are about one question: given a rung, does the
  right machinery exist?
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
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

  describe "the rung is recorded at once; its tracking follows in a job (ADR-077)" do
    # Regression: the title detail set the rung on a fire-and-forget task,
    # so a crash lost the person's choice, or stored Follow with no tracked
    # title — which nothing ever derived afterwards.
    test "a following rung owes its derivation in the same transaction, and asks TMDB nothing yet" do
      Req.Test.stub(:tmdb, fn _conn -> flunk("setting the rung must not ask TMDB") end)

      {{:ok, intent}, inserts} =
        MediaCentaur.JobRuns.capture_inserts(fn -> ReleaseTracking.set_rung(show(), :follow) end)

      assert intent.rung == :follow
      refute tracked?()

      assert [%{in_transaction?: true}] =
               Enum.filter(inserts, &(&1.worker == "MediaCentaur.ReleaseTracking.DeriveJob"))
    end

    test "the derivation reads the rung when it runs: a later change wins" do
      {:ok, _} = ReleaseTracking.set_rung(show(), :follow)
      {:ok, _} = ReleaseTracking.set_rung(show(), :list)

      MediaCentaur.JobRuns.run_enqueued_jobs()

      refute tracked?()
    end
  end

  describe "raising onto the ladder" do
    test "List puts the title on the list and follows nothing" do
      assert {:ok, intent} = ReleaseTracking.set_rung(show(), :list)
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert intent.rung == :list
      assert Discovery.listed?(@tmdb_id, :tv_series)
      refute tracked?()

      await_supervised_tasks()
    end

    test "Follow and above derive a tracked title, and list it as part of the act" do
      for rung <- [:follow, :grab] do
        assert {:ok, intent} = ReleaseTracking.set_rung(show(), rung)
        MediaCentaur.JobRuns.run_enqueued_jobs()
        assert intent.rung == rung
        assert Discovery.listed?(@tmdb_id, :tv_series)
        assert tracked?(), "#{rung} must derive a tracked title"
      end

      await_supervised_tasks()
    end

    test "the calendar is fetched once, not on every raise" do
      {:ok, _} = ReleaseTracking.set_rung(show(), :follow)
      MediaCentaur.JobRuns.run_enqueued_jobs()
      item = ReleaseTracking.get_item_by_tmdb(@tmdb_id, :tv_series)

      {:ok, _} = ReleaseTracking.set_rung(show(), :grab)
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert ReleaseTracking.get_item_by_tmdb(@tmdb_id, :tv_series).id == item.id

      await_supervised_tasks()
    end

    test "provenance is carried onto a record that did not exist" do
      activity_id = Ecto.UUID.generate()

      {:ok, intent} =
        ReleaseTracking.set_rung(show(), :list, %{
          source: :friend,
          activity_id: activity_id,
          note: "you'll like this"
        })

      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert intent.source == :friend
      assert intent.activity_id == activity_id
      assert intent.note == "you'll like this"

      await_supervised_tasks()
    end
  end

  describe "lowering the ladder" do
    test "dropping below Follow destroys the tracked title but keeps the listing" do
      {:ok, _} = ReleaseTracking.set_rung(show(), :grab)
      MediaCentaur.JobRuns.run_enqueued_jobs()
      assert tracked?()

      assert {:ok, intent} = ReleaseTracking.set_rung(show(), :list)
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert intent.rung == :list
      assert Discovery.listed?(@tmdb_id, :tv_series)
      refute tracked?()

      await_supervised_tasks()
    end

    test "Off deletes the record and everything derived from it" do
      {:ok, _} = ReleaseTracking.set_rung(show(), :grab)
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert {:ok, nil} = ReleaseTracking.set_rung(show(), :off)
      MediaCentaur.JobRuns.run_enqueued_jobs()

      refute Discovery.listed?(@tmdb_id, :tv_series)
      refute tracked?()
      assert Discovery.rung(@tmdb_id, :tv_series) == nil

      await_supervised_tasks()
    end

    test "Off on a title that was never on the ladder is a no-op" do
      assert {:ok, nil} = ReleaseTracking.set_rung(show(), :off)
      MediaCentaur.JobRuns.run_enqueued_jobs()
      refute tracked?()

      await_supervised_tasks()
    end

    test "re-raising after Off starts fresh — there is no disarmed row to remember" do
      {:ok, _} = ReleaseTracking.set_rung(show(), :grab)
      MediaCentaur.JobRuns.run_enqueued_jobs()
      {:ok, nil} = ReleaseTracking.set_rung(show(), :off)
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert {:ok, intent} = ReleaseTracking.set_rung(show(), :follow)
      MediaCentaur.JobRuns.run_enqueued_jobs()
      assert intent.rung == :follow
      assert tracked?()

      await_supervised_tasks()
    end
  end

  describe "a film you already own" do
    test "complete?/2 is the one spelling of the rule: an owned film, never a series" do
      movie = create_movie(%{name: "Owned Movie"})
      create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
      create_linked_file(%{movie_id: movie.id})

      assert ReleaseTracking.complete?(777, :movie)
      refute ReleaseTracking.complete?(778, :movie)
      refute ReleaseTracking.complete?(@tmdb_id, :tv_series)
    end

    test "is complete: the rung stands, the machinery does not" do
      movie = create_standalone_movie(%{name: "Owned Film"})
      create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
      create_linked_file(%{movie_id: movie.id})

      stub_routes([{"/movie/777", %{"id" => 777, "title" => "Owned Film"}}])

      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Owned Film"})

      assert {:ok, intent} = ReleaseTracking.set_rung(title, :grab)
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert intent.rung == :grab

      refute ReleaseTracking.get_item_by_tmdb(777, :movie),
             "an owned film has no future release to follow"

      # Listing fetches artwork on a supervised task; drive it home (ADR-049).
      await_supervised_tasks()
    end
  end
end
