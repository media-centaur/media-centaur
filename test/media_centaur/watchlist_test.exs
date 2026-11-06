defmodule MediaCentaur.WatchlistTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory

  alias MediaCentaur.Watchlist
  alias MediaCentaur.Watchlist.TitleIntent
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.TMDB.Title

  describe "TitleIntent.create_changeset/3" do
    test "takes the identity columns and the label from the title and copies nothing else (ADR-071)" do
      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie", year: "2010"})
      changeset = TitleIntent.create_changeset(title, :list, %{note: "why"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :tmdb_id) == 777
      assert Ecto.Changeset.get_change(changeset, :media_type) == :movie
      assert Ecto.Changeset.get_change(changeset, :note) == "why"
      assert Ecto.Changeset.get_change(changeset, :title_name) == "Sample Movie"
      assert Ecto.Changeset.get_change(changeset, :title_year) == "2010"
      assert Ecto.Changeset.get_change(changeset, :title) == nil
    end

    test "a bare identity writes no label, so a move from one keeps what the record had" do
      bare = %Title{tmdb_id: 777, media_type: :movie}
      assert Ecto.Changeset.get_change(TitleIntent.create_changeset(bare, :list), :title_name) == nil

      intent = %TitleIntent{tmdb_id: 777, media_type: :movie, rung: :list, title_name: "Sample Movie"}
      changeset = TitleIntent.rung_changeset(intent, :follow, bare)
      assert Ecto.Changeset.get_field(changeset, :title_name) == "Sample Movie"
    end

    test "a friend-sourced record carries its review id; the pairing is enforced" do
      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})
      id = Ecto.UUID.generate()
      assert TitleIntent.create_changeset(title, :list, %{source: :friend, activity_id: id}).valid?
      refute TitleIntent.create_changeset(title, :list, %{source: :friend}).valid?
      refute TitleIntent.create_changeset(title, :list, %{source: :manual, activity_id: id}).valid?
    end

    test "rejects an unknown source" do
      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})
      changeset = TitleIntent.create_changeset(title, :list, %{source: :carrier_pigeon})
      refute changeset.valid?
      assert %{source: _} = errors_on(changeset)
    end
  end

  describe "title intents" do
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

    test "put_rung writes one record and moves it, never duplicates it" do
      assert {:ok, %{rung: :list}} = Watchlist.put_rung(@title, :list, nil)
      assert {:ok, %{rung: :grab}} = Watchlist.put_rung(@title, :grab, nil)
      assert [_] = Repo.all(TitleIntent)
      await_supervised_tasks()
    end

    test "a rung change broadcasts the transition: both rungs and the title" do
      Watchlist.subscribe()
      {:ok, _intent} = Watchlist.put_rung(@title, :list, nil)

      assert_receive {:title_intent_changed,
                      %Watchlist.Events.RungChanged{
                        tmdb_id: 777,
                        media_type: :movie,
                        previous_rung: nil,
                        rung: :list,
                        title: %Title{tmdb_id: 777}
                      }}

      {:ok, _intent} = Watchlist.put_rung(@title, :follow, nil)

      assert_receive {:title_intent_changed,
                      %Watchlist.Events.RungChanged{previous_rung: :list, rung: :follow}}

      await_supervised_tasks()
    end

    test "the event names the actor who moved the rung, or nil when no person did" do
      Watchlist.subscribe()
      actor = build_actor()
      {:ok, _intent} = Watchlist.put_rung(@title, :list, actor)
      assert_receive {:title_intent_changed, %Watchlist.Events.RungChanged{actor: ^actor}}

      :ok = Watchlist.forget(777, :movie, nil)
      assert_receive {:title_intent_changed, %Watchlist.Events.RungChanged{rung: nil, actor: nil}}

      await_supervised_tasks()
    end

    test "leaving Ignored for the list is a transition from :ignored" do
      {:ok, _intent} = Watchlist.put_rung(@title, :ignored, nil)
      Watchlist.subscribe()
      {:ok, _intent} = Watchlist.put_rung(@title, :list, nil)

      assert_receive {:title_intent_changed,
                      %Watchlist.Events.RungChanged{previous_rung: :ignored, rung: :list}}

      await_supervised_tasks()
    end

    test "forget deletes and broadcasts nil — Off is the absence of a record; absent is a no-op" do
      {:ok, _} = Watchlist.put_rung(@title, :grab, nil)
      Watchlist.subscribe()
      assert :ok = Watchlist.forget(777, :movie, nil)

      assert_receive {:title_intent_changed,
                      %Watchlist.Events.RungChanged{
                        tmdb_id: 777,
                        media_type: :movie,
                        previous_rung: :grab,
                        rung: nil,
                        title: %Title{tmdb_id: 777}
                      }}

      assert :ok = Watchlist.forget(777, :movie, nil)
      refute Watchlist.listed?(777, :movie)
      assert Watchlist.rung(777, :movie) == nil
      await_supervised_tasks()
    end

    test "every rung write refreshes the label, and the label paints a record the store does not hold" do
      {:ok, intent} = Watchlist.put_rung(@title, :list, nil)
      assert {intent.title_name, intent.title_year} == {"Sample Movie", "2010"}

      renamed = %{@title | name: "Sample Movie: Director's Cut"}
      {:ok, moved} = Watchlist.put_rung(renamed, :ignored, nil)
      assert moved.title_name == "Sample Movie: Director's Cut"

      # Nothing in the store for this title: the row is painted from the label.
      assert [%{intent: %TitleIntent{title: %Title{name: "Sample Movie: Director's Cut", year: "2010"}}}] =
               Watchlist.list_intents()

      await_supervised_tasks()
    end

    test "catch_up/3 sets a series' point and broadcasts it under the same tuple; a movie and Off are refused" do
      show = Title.new!(%{tmdb_id: 42, media_type: :tv_series, name: "Sample Show"})
      {:ok, _} = Watchlist.put_rung(show, :follow, nil)
      Watchlist.subscribe()

      assert {:ok, %TitleIntent{caught_up_season: 2, caught_up_episode: 5}} =
               Watchlist.catch_up(42, :tv_series, {2, 5})

      assert_receive {:title_intent_changed,
                      %Watchlist.Events.CaughtUp{
                        tmdb_id: 42,
                        media_type: :tv_series,
                        season: 2,
                        episode: 5
                      }}

      assert Watchlist.caught_up(42, :tv_series) == {2, 5}

      {:ok, _} = Watchlist.put_rung(@title, :follow, nil)
      assert {:error, %Ecto.Changeset{}} = Watchlist.catch_up(777, :movie, {1, 1})
      assert Watchlist.catch_up(999, :tv_series, {1, 1}) == {:error, :not_listed}
      assert Watchlist.caught_up(999, :tv_series) == nil

      await_supervised_tasks()
    end

    test "rungs/0 returns every listed title's rung" do
      {:ok, _} = Watchlist.put_rung(@title, :list, nil)

      {:ok, _} =
        Watchlist.put_rung(
          Title.new!(%{tmdb_id: 42, media_type: :tv_series, name: "Sample Show"}),
          :grab,
          nil
        )

      assert Watchlist.rungs() == %{{777, :movie} => :list, {42, :tv_series} => :grab}
      await_supervised_tasks()
    end

    test "list_watchlist returns newest-first with nil library owner when absent" do
      {:ok, _} = Watchlist.put_rung(@title, :list, nil)
      assert [%{intent: %TitleIntent{tmdb_id: 777}, library_owner_id: nil}] = Watchlist.list_watchlist()
      await_supervised_tasks()
    end

    test "list_watchlist resolves the library owner when a presentable container exists" do
      {:ok, _} = Watchlist.put_rung(@title, :list, nil)
      movie = create_standalone_movie(%{name: "Sample Movie"})
      create_external_id(%{source: "tmdb", external_id: "777", movie_id: movie.id})
      create_linked_file(%{movie_id: movie.id})
      assert [%{library_owner_id: owner_id}] = Watchlist.list_watchlist()
      assert owner_id == movie.id
      await_supervised_tasks()
    end

    test "an ignored title is a record below the list: not listed, off the watchlist, in rungs/0" do
      {:ok, %{rung: :ignored}} = Watchlist.put_rung(@title, :ignored, nil)

      refute Watchlist.listed?(777, :movie)
      assert Watchlist.rung(777, :movie) == :ignored
      assert Watchlist.list_watchlist() == []
      assert Watchlist.rungs() == %{{777, :movie} => :ignored}
      # No artwork is promoted or held for a title the person has dismissed.
      assert MediaCentaur.Watchlist.TmdbReferences.references() == MapSet.new()

      # Wanting it again supersedes having dismissed it — one record, moved.
      {:ok, %{rung: :list}} = Watchlist.put_rung(@title, :list, nil)
      assert Watchlist.listed?(777, :movie)
      assert [_] = Watchlist.list_watchlist()
      await_supervised_tasks()
    end

    test "list_intents/0 is every record, Ignored included, with its owner; list_watchlist/0 is its List-or-above filter" do
      {:ok, _} = Watchlist.put_rung(@title, :ignored, nil)
      show = Title.new!(%{tmdb_id: 42, media_type: :tv_series, name: "Sample Show"})
      {:ok, _} = Watchlist.put_rung(show, :follow, nil)
      movie = create_standalone_movie(%{name: "Sample Movie"})
      create_external_id(%{source: "tmdb", external_id: "777", movie_id: movie.id})
      create_linked_file(%{movie_id: movie.id})

      # Two records written in one second tie on inserted_at; the read's
      # order is newest first, asserted elsewhere — here the set.
      assert [
               %{intent: %TitleIntent{tmdb_id: 42, rung: :follow}, library_owner_id: nil},
               %{intent: %TitleIntent{tmdb_id: 777, rung: :ignored}, library_owner_id: owner}
             ] = Enum.sort_by(Watchlist.list_intents(), & &1.intent.tmdb_id)

      assert owner == movie.id
      assert [%{intent: %TitleIntent{tmdb_id: 42}}] = Watchlist.list_watchlist()
      await_supervised_tasks()
    end

    test "TmdbArtworkHolds holds every listed ref" do
      {:ok, _} = Watchlist.put_rung(@title, :list, nil)
      assert MediaCentaur.Watchlist.TmdbReferences.references() == MapSet.new([{777, :movie}])
      await_supervised_tasks()
    end

    test "duplicate insert at the changeset level returns an error, not a raise" do
      {:ok, _} = Watchlist.put_rung(@title, :list, nil)
      title = @title
      # This insert is the operation under test, not setup: it pins that the
      # unique constraint surfaces as {:error, changeset} rather than raising —
      # the branch put_rung's concurrent-race recovery matches on.
      # credo:disable-for-next-line MediaCentaur.Credo.Checks.NoRepoSetupInTests
      assert {:error, changeset} = title |> TitleIntent.create_changeset(:list) |> Repo.insert()
      assert %{tmdb_id: _} = errors_on(changeset)
      await_supervised_tasks()
    end

    test "a listed title reads its snapshot from the store (ADR-071)" do
      create_title_record(%{
        tmdb_id: 777,
        media_type: :movie,
        payload:
          TmdbStubs.movie_detail(%{
            "id" => 777,
            "title" => "Stored Movie",
            "release_date" => "2011-05-01",
            "poster_path" => "/stored.jpg"
          })
      })

      {:ok, %TitleIntent{title: %Title{name: "Stored Movie"}}} =
        Watchlist.put_rung(@title, :list, nil, %{note: "why"})

      # The record copies nothing from the title it was listed with.
      assert %TitleIntent{
               title: %Title{
                 tmdb_id: 777,
                 name: "Stored Movie",
                 year: "2011",
                 poster_path: "/stored.jpg"
               },
               note: "why"
             } = Watchlist.get_intent(777, :movie)

      assert [%{intent: %TitleIntent{title: %Title{name: "Stored Movie"}}}] = Watchlist.list_watchlist()
      await_supervised_tasks()
    end

    test "a listed title the store lacks is painted from its label: name and year, no artwork" do
      {:ok, _intent} = Watchlist.put_rung(@title, :list, nil)

      assert %TitleIntent{
               title: %Title{
                 tmdb_id: 777,
                 media_type: :movie,
                 name: "Sample Movie",
                 year: "2010",
                 poster_path: nil
               }
             } = Watchlist.get_intent(777, :movie)

      await_supervised_tasks()
    end

    test "forgetting a title the store never held broadcasts the move to Off with the label" do
      Watchlist.subscribe()
      {:ok, _intent} = Watchlist.put_rung(@title, :list, nil)
      assert_receive {:title_intent_changed, %{rung: :list}}

      :ok = Watchlist.forget(777, :movie, nil)

      assert_receive {:title_intent_changed,
                      %{
                        previous_rung: :list,
                        rung: nil,
                        title: %Title{tmdb_id: 777, name: "Sample Movie"}
                      }}

      await_supervised_tasks()
    end
  end
end
