defmodule MediaCentaur.DiscoveryTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory

  alias MediaCentaur.Discovery
  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.TMDB.Title

  describe "TitleIntent.create_changeset/3" do
    test "takes the identity columns from the title and copies nothing else (ADR-071)" do
      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie", year: "2010"})
      changeset = TitleIntent.create_changeset(title, :list, %{note: "why"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :tmdb_id) == 777
      assert Ecto.Changeset.get_change(changeset, :media_type) == :movie
      assert Ecto.Changeset.get_change(changeset, :note) == "why"
      assert Ecto.Changeset.get_change(changeset, :title) == nil
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
      assert {:ok, %{rung: :list}} = Discovery.put_rung(@title, :list)
      assert {:ok, %{rung: :grab}} = Discovery.put_rung(@title, :grab)
      assert [_] = Repo.all(TitleIntent)
      await_supervised_tasks()
    end

    test "a rung change broadcasts the transition: both rungs and the title" do
      Discovery.subscribe()
      {:ok, _intent} = Discovery.put_rung(@title, :list)

      assert_receive {:title_intent_changed,
                      %Discovery.Events.RungChanged{
                        tmdb_id: 777,
                        media_type: :movie,
                        previous_rung: nil,
                        rung: :list,
                        title: %Title{tmdb_id: 777}
                      }}

      {:ok, _intent} = Discovery.put_rung(@title, :follow)

      assert_receive {:title_intent_changed,
                      %Discovery.Events.RungChanged{previous_rung: :list, rung: :follow}}

      await_supervised_tasks()
    end

    test "leaving Ignored for the list is a transition from :ignored" do
      {:ok, _intent} = Discovery.put_rung(@title, :ignored)
      Discovery.subscribe()
      {:ok, _intent} = Discovery.put_rung(@title, :list)

      assert_receive {:title_intent_changed,
                      %Discovery.Events.RungChanged{previous_rung: :ignored, rung: :list}}

      await_supervised_tasks()
    end

    test "forget deletes and broadcasts nil — Off is the absence of a record; absent is a no-op" do
      {:ok, _} = Discovery.put_rung(@title, :grab)
      Discovery.subscribe()
      assert :ok = Discovery.forget(777, :movie)

      assert_receive {:title_intent_changed,
                      %Discovery.Events.RungChanged{
                        tmdb_id: 777,
                        media_type: :movie,
                        previous_rung: :grab,
                        rung: nil,
                        title: %Title{tmdb_id: 777}
                      }}

      assert :ok = Discovery.forget(777, :movie)
      refute Discovery.listed?(777, :movie)
      assert Discovery.rung(777, :movie) == nil
      await_supervised_tasks()
    end

    test "rungs/0 returns every listed title's rung" do
      {:ok, _} = Discovery.put_rung(@title, :list)

      {:ok, _} =
        Discovery.put_rung(
          Title.new!(%{tmdb_id: 42, media_type: :tv_series, name: "Sample Show"}),
          :grab
        )

      assert Discovery.rungs() == %{{777, :movie} => :list, {42, :tv_series} => :grab}
      await_supervised_tasks()
    end

    test "list_watchlist returns newest-first with nil library owner when absent" do
      {:ok, _} = Discovery.put_rung(@title, :list)
      assert [%{intent: %TitleIntent{tmdb_id: 777}, library_owner_id: nil}] = Discovery.list_watchlist()
      await_supervised_tasks()
    end

    test "list_watchlist resolves the library owner when a presentable container exists" do
      {:ok, _} = Discovery.put_rung(@title, :list)
      movie = create_standalone_movie(%{name: "Sample Movie"})
      create_external_id(%{source: "tmdb", external_id: "777", movie_id: movie.id})
      create_linked_file(%{movie_id: movie.id})
      assert [%{library_owner_id: owner_id}] = Discovery.list_watchlist()
      assert owner_id == movie.id
      await_supervised_tasks()
    end

    test "an ignored title is a record below the list: not listed, off the watchlist, in rungs/0" do
      {:ok, %{rung: :ignored}} = Discovery.put_rung(@title, :ignored)

      refute Discovery.listed?(777, :movie)
      assert Discovery.rung(777, :movie) == :ignored
      assert Discovery.list_watchlist() == []
      assert Discovery.rungs() == %{{777, :movie} => :ignored}
      # No artwork is promoted or held for a title the person has dismissed.
      assert MediaCentaur.Discovery.TmdbReferences.references() == MapSet.new()

      # Wanting it again supersedes having dismissed it — one record, moved.
      {:ok, %{rung: :list}} = Discovery.put_rung(@title, :list)
      assert Discovery.listed?(777, :movie)
      assert [_] = Discovery.list_watchlist()
      await_supervised_tasks()
    end

    test "TmdbArtworkHolds holds every listed ref" do
      {:ok, _} = Discovery.put_rung(@title, :list)
      assert MediaCentaur.Discovery.TmdbReferences.references() == MapSet.new([{777, :movie}])
      await_supervised_tasks()
    end

    test "duplicate insert at the changeset level returns an error, not a raise" do
      {:ok, _} = Discovery.put_rung(@title, :list)
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
        Discovery.put_rung(@title, :list, %{note: "why"})

      # The record copies nothing from the title it was listed with.
      assert %TitleIntent{
               title: %Title{
                 tmdb_id: 777,
                 name: "Stored Movie",
                 year: "2011",
                 poster_path: "/stored.jpg"
               },
               note: "why"
             } = Discovery.get_intent(777, :movie)

      assert [%{intent: %TitleIntent{title: %Title{name: "Stored Movie"}}}] = Discovery.list_watchlist()
      await_supervised_tasks()
    end

    test "a listed title the store lacks carries a bare identity until first contact lands" do
      {:ok, _intent} = Discovery.put_rung(@title, :list)

      assert %TitleIntent{title: %Title{tmdb_id: 777, media_type: :movie, name: nil, poster_path: nil}} =
               Discovery.get_intent(777, :movie)

      await_supervised_tasks()
    end

    test "forgetting a title the store never held still broadcasts the move to Off" do
      Discovery.subscribe()
      {:ok, _intent} = Discovery.put_rung(@title, :list)
      assert_receive {:title_intent_changed, %{rung: :list}}

      :ok = Discovery.forget(777, :movie)

      assert_receive {:title_intent_changed,
                      %{previous_rung: :list, rung: nil, title: %Title{tmdb_id: 777, name: nil}}}

      await_supervised_tasks()
    end
  end
end
