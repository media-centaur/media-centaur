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

  alias MediaCentaur.Profiles.Actor
  alias MediaCentaur.Watchlist
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
        MediaCentaur.JobRuns.capture_inserts(fn -> ReleaseTracking.set_rung(show(), :follow, nil) end)

      assert intent.rung == :follow
      refute tracked?()

      assert [%{in_transaction?: true}] =
               Enum.filter(inserts, &(&1.worker == "MediaCentaur.ReleaseTracking.DeriveJob"))
    end

    test "the derivation reads the rung when it runs: a later change wins" do
      {:ok, _} = ReleaseTracking.set_rung(show(), :follow, nil)
      {:ok, _} = ReleaseTracking.set_rung(show(), :list, nil)

      MediaCentaur.JobRuns.run_enqueued_jobs()

      refute tracked?()
    end
  end

  describe "raising onto the ladder" do
    test "List puts the title on the list and follows nothing" do
      assert {:ok, intent} = ReleaseTracking.set_rung(show(), :list, nil)
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert intent.rung == :list
      assert Watchlist.listed?(@tmdb_id, :tv_series)
      refute tracked?()

      await_supervised_tasks()
    end

    test "Follow and above derive a tracked title, and list it as part of the act" do
      for rung <- [:follow, :grab] do
        assert {:ok, intent} = ReleaseTracking.set_rung(show(), rung, nil)
        MediaCentaur.JobRuns.run_enqueued_jobs()
        assert intent.rung == rung
        assert Watchlist.listed?(@tmdb_id, :tv_series)
        assert tracked?(), "#{rung} must derive a tracked title"
      end

      await_supervised_tasks()
    end

    test "the calendar is fetched once, not on every raise" do
      {:ok, _} = ReleaseTracking.set_rung(show(), :follow, nil)
      MediaCentaur.JobRuns.run_enqueued_jobs()
      item = ReleaseTracking.get_item_by_tmdb(@tmdb_id, :tv_series)

      {:ok, _} = ReleaseTracking.set_rung(show(), :grab, nil)
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert ReleaseTracking.get_item_by_tmdb(@tmdb_id, :tv_series).id == item.id

      await_supervised_tasks()
    end

    test "provenance is carried onto a record that did not exist" do
      activity_id = Ecto.UUID.generate()

      {:ok, intent} =
        ReleaseTracking.set_rung(show(), :list, nil, %{
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

  describe "a series the library already holds" do
    # The library holds S01E01–S01E02; TMDB has aired S01E01–S02E01.
    defp owned_show do
      tv = create_tv_series(%{name: "Sample Show"})

      create_external_id(%{
        tv_series_id: tv.id,
        source: "tmdb",
        external_id: Integer.to_string(@tmdb_id)
      })

      season = create_season(%{tv_series_id: tv.id, season_number: 1})

      episodes =
        for number <- [1, 2] do
          episode =
            create_episode(%{season_id: season.id, episode_number: number, name: "Episode #{number}"})

          create_playable_item_for_episode(episode)
          episode
        end

      {tv, episodes}
    end

    defp wanted do
      @tmdb_id
      |> ReleaseTracking.get_item_by_tmdb(:tv_series)
      |> Map.fetch!(:id)
      |> ReleaseTracking.open_wants_for_item()
      |> Enum.map(&{&1.season_number, &1.episode_number})
    end

    # Regression: following a series the library already held never linked
    # it (the link was made only when the library changed), so the library
    # half of "had" read nothing and a point behind the library wanted
    # episodes the person owns.
    test "following links the tracked title to its library series, to the last episode held" do
      {tv, _episodes} = owned_show()

      {:ok, _} = ReleaseTracking.set_rung(show(), :follow, nil)
      MediaCentaur.JobRuns.run_enqueued_jobs()

      item = ReleaseTracking.get_item_by_tmdb(@tmdb_id, :tv_series)
      assert item.library_container_id == tv.id
      assert {item.last_library_season, item.last_library_episode} == {1, 2}

      await_supervised_tasks()
    end

    test "the point starts at the last episode the acting profile finished; owned episodes are never wanted" do
      {_tv, [first, _second]} = owned_show()
      create_watch_progress(%{episode_id: first.id, completed: true})

      {:ok, _} = ReleaseTracking.set_rung(show(), :follow, Actor.new(owner_profile_id()))
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert Watchlist.caught_up(@tmdb_id, :tv_series) == {1, 1}
      # Seen through S01E01, held through S01E02: only S02E01 is wanted.
      assert wanted() == [{2, 1}]

      await_supervised_tasks()
    end

    test "raising a listed series to Follow starts the point from the profile's viewing too" do
      {_tv, [first, _second]} = owned_show()
      create_watch_progress(%{episode_id: first.id, completed: true})

      {:ok, _} = ReleaseTracking.set_rung(show(), :list, nil)
      {:ok, _} = ReleaseTracking.set_rung(show(), :follow, Actor.new(owner_profile_id()))
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert Watchlist.caught_up(@tmdb_id, :tv_series) == {1, 1}
      await_supervised_tasks()
    end

    test "with no viewing to go on, the point is TMDB's latest aired episode" do
      owned_show()

      {:ok, _} = ReleaseTracking.set_rung(show(), :follow, Actor.new(owner_profile_id()))
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert Watchlist.caught_up(@tmdb_id, :tv_series) == {2, 1}
      assert wanted() == []
      await_supervised_tasks()
    end

    test "a point already set is kept when the rung rises" do
      {_tv, [first, _second]} = owned_show()
      {:ok, _} = ReleaseTracking.set_rung(show(), :follow, nil)
      MediaCentaur.JobRuns.run_enqueued_jobs()
      assert Watchlist.caught_up(@tmdb_id, :tv_series) == {2, 1}

      create_watch_progress(%{episode_id: first.id, completed: true})
      {:ok, _} = ReleaseTracking.set_rung(show(), :grab, Actor.new(owner_profile_id()))
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert Watchlist.caught_up(@tmdb_id, :tv_series) == {2, 1}
      await_supervised_tasks()
    end

    test "the sweep links a followed series that the library already held but was never linked" do
      {:ok, _} = ReleaseTracking.set_rung(show(), :follow, nil)
      MediaCentaur.JobRuns.run_enqueued_jobs()
      {tv, _episodes} = owned_show()
      assert ReleaseTracking.get_item_by_tmdb(@tmdb_id, :tv_series).library_container_id == nil

      :ok = MediaCentaur.ReleaseTracking.SweepJob.perform(%Oban.Job{args: %{}})

      assert ReleaseTracking.get_item_by_tmdb(@tmdb_id, :tv_series).library_container_id == tv.id
      await_supervised_tasks()
    end
  end

  describe "lowering the ladder" do
    test "dropping below Follow destroys the tracked title but keeps the listing" do
      {:ok, _} = ReleaseTracking.set_rung(show(), :grab, nil)
      MediaCentaur.JobRuns.run_enqueued_jobs()
      assert tracked?()

      assert {:ok, intent} = ReleaseTracking.set_rung(show(), :list, nil)
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert intent.rung == :list
      assert Watchlist.listed?(@tmdb_id, :tv_series)
      refute tracked?()

      await_supervised_tasks()
    end

    test "Off deletes the record and everything derived from it" do
      {:ok, _} = ReleaseTracking.set_rung(show(), :grab, nil)
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert {:ok, nil} = ReleaseTracking.set_rung(show(), :off, nil)
      MediaCentaur.JobRuns.run_enqueued_jobs()

      refute Watchlist.listed?(@tmdb_id, :tv_series)
      refute tracked?()
      assert Watchlist.rung(@tmdb_id, :tv_series) == nil

      await_supervised_tasks()
    end

    test "Off on a title that was never on the ladder is a no-op" do
      assert {:ok, nil} = ReleaseTracking.set_rung(show(), :off, nil)
      MediaCentaur.JobRuns.run_enqueued_jobs()
      refute tracked?()

      await_supervised_tasks()
    end

    test "re-raising after Off starts fresh — there is no disarmed row to remember" do
      {:ok, _} = ReleaseTracking.set_rung(show(), :grab, nil)
      MediaCentaur.JobRuns.run_enqueued_jobs()
      {:ok, nil} = ReleaseTracking.set_rung(show(), :off, nil)
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert {:ok, intent} = ReleaseTracking.set_rung(show(), :follow, nil)
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

      assert {:ok, intent} = ReleaseTracking.set_rung(title, :grab, nil)
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert intent.rung == :grab

      refute ReleaseTracking.get_item_by_tmdb(777, :movie),
             "an owned film has no future release to follow"

      # Listing fetches artwork on a supervised task; drive it home (ADR-049).
      await_supervised_tasks()
    end
  end
end
