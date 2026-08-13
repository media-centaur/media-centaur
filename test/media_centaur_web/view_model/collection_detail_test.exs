defmodule MediaCentaurWeb.ViewModel.CollectionDetailTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaurWeb.ViewModel.CollectionDetail
  alias MediaCentaurWeb.ViewModel.MovieListItem

  describe "build/4 — pure composition" do
    test "library items are chronological, content-bearing movies only" do
      movie_b = build_movie(%{name: "Movie B", date_published: ~D[2012-06-01], content_url: "/m/b.mkv"})
      movie_a = build_movie(%{name: "Movie A", date_published: ~D[2010-06-01], content_url: "/m/a.mkv"})
      absent = build_movie(%{name: "Absent Member", date_published: ~D[2011-06-01], content_url: nil})
      collection = build_movie_series(%{movies: [movie_b, absent, movie_a]})

      view_model =
        CollectionDetail.build(
          %{entity: collection, progress: nil, progress_records: []},
          [],
          nil,
          nil
        )

      assert [
               %MovieListItem.Library{movie: %{name: "Movie A"}},
               %MovieListItem.Library{movie: %{name: "Movie B"}}
             ] = view_model.movies
    end

    test "library item state reflects watch progress" do
      movie_1 = build_movie(%{date_published: ~D[2010-01-01], content_url: "/m/1.mkv"})
      movie_2 = build_movie(%{date_published: ~D[2012-01-01], content_url: "/m/2.mkv"})
      movie_3 = build_movie(%{date_published: ~D[2014-01-01], content_url: "/m/3.mkv"})
      collection = build_movie_series(%{movies: [movie_1, movie_2, movie_3]})

      progress_records = [
        build_progress(%{movie_id: movie_1.id, completed: true}),
        build_progress(%{
          movie_id: movie_2.id,
          completed: false,
          position_seconds: 300.0,
          duration_seconds: 5400.0
        })
      ]

      view_model =
        CollectionDetail.build(
          %{entity: collection, progress: nil, progress_records: progress_records},
          [],
          nil,
          nil
        )

      assert [
               %MovieListItem.Library{state: :watched},
               %MovieListItem.Library{state: :current, progress: %{position_seconds: 300.0}},
               %MovieListItem.Library{state: :unwatched, progress: nil}
             ] = view_model.movies
    end

    test "is_resume_target marks the movie named by the resume hint's targetId" do
      movie_1 = build_movie(%{date_published: ~D[2010-01-01], content_url: "/m/1.mkv"})
      movie_2 = build_movie(%{date_published: ~D[2012-01-01], content_url: "/m/2.mkv"})
      collection = build_movie_series(%{movies: [movie_1, movie_2]})

      resume_target = %{"action" => "resume", "targetId" => movie_2.id}

      view_model =
        CollectionDetail.build(
          %{entity: collection, progress: nil, progress_records: []},
          [],
          nil,
          resume_target
        )

      assert [
               %MovieListItem.Library{is_resume_target: false},
               %MovieListItem.Library{is_resume_target: true}
             ] = view_model.movies
    end

    test "upcoming releases append after library movies, sorted by air date" do
      movie = build_movie(%{date_published: ~D[2010-01-01], content_url: "/m/1.mkv"})
      collection = build_movie_series(%{movies: [movie]})

      releases = [
        release_map(%{part_tmdb_id: 22, title: "Part Later", air_date: Date.add(Date.utc_today(), 90)}),
        release_map(%{part_tmdb_id: 11, title: "Part Sooner", air_date: Date.add(Date.utc_today(), 30)})
      ]

      view_model =
        CollectionDetail.build(
          %{entity: collection, progress: nil, progress_records: []},
          releases,
          :watching,
          nil
        )

      assert [
               %MovieListItem.Library{},
               %MovieListItem.Upcoming{title: "Part Sooner", sub_status: :unaired},
               %MovieListItem.Upcoming{title: "Part Later", sub_status: :unaired}
             ] = view_model.movies
    end

    test "one upcoming row per part: dated rows beat undated, earliest date wins" do
      collection = build_movie_series(%{movies: []})

      releases = [
        release_map(%{part_tmdb_id: 33, title: "The Part", air_date: nil}),
        release_map(%{part_tmdb_id: 33, title: "The Part", air_date: Date.add(Date.utc_today(), 200)}),
        release_map(%{part_tmdb_id: 33, title: "The Part", air_date: Date.add(Date.utc_today(), 60)})
      ]

      view_model =
        CollectionDetail.build(
          %{entity: collection, progress: nil, progress_records: []},
          releases,
          :watching,
          nil
        )

      expected_date = Date.add(Date.utc_today(), 60)
      assert [%MovieListItem.Upcoming{part_tmdb_id: 33, air_date: ^expected_date}] = view_model.movies
    end

    test "a release matching a library movie's tmdb id is not listed as upcoming" do
      owned = %{
        id: Ecto.UUID.generate(),
        name: "Owned Part",
        date_published: ~D[2020-01-01],
        position: 1,
        content_url: "/m/owned.mkv",
        tmdb_id: 900_010
      }

      collection = build_movie_series(%{movies: [owned]})

      releases = [
        release_map(%{part_tmdb_id: 900_010, title: "Owned Part"}),
        release_map(%{part_tmdb_id: 900_011, title: "Missing Part"})
      ]

      view_model =
        CollectionDetail.build(
          %{entity: collection, progress: nil, progress_records: []},
          releases,
          :watching,
          nil
        )

      assert [
               %MovieListItem.Library{},
               %MovieListItem.Upcoming{part_tmdb_id: 900_011}
             ] = view_model.movies
    end

    test "aired-but-not-in-library release reads :aired_not_in_library" do
      collection = build_movie_series(%{movies: []})

      releases = [
        release_map(%{part_tmdb_id: 44, title: "Aired Part", air_date: ~D[2026-04-01]})
      ]

      view_model =
        CollectionDetail.build(
          %{entity: collection, progress: nil, progress_records: []},
          releases,
          :watching,
          nil
        )

      assert [%MovieListItem.Upcoming{sub_status: :aired_not_in_library}] = view_model.movies
    end

    test "tracking_status passes through unchanged" do
      collection = build_movie_series(%{movies: []})

      view_model =
        CollectionDetail.build(
          %{entity: collection, progress: nil, progress_records: []},
          [],
          :ignored,
          nil
        )

      assert view_model.tracking_status == :ignored
    end

    test "no movies and no releases produce an empty item list" do
      collection = build_movie_series(%{movies: []})

      view_model =
        CollectionDetail.build(%{entity: collection, progress: nil, progress_records: []}, [], nil, nil)

      assert view_model.movies == []
    end
  end

  describe "with_progress/4" do
    test "rebuilds item states from the merged records without re-supplying releases" do
      movie_1 = build_movie(%{date_published: ~D[2010-01-01], content_url: "/m/1.mkv"})
      movie_2 = build_movie(%{date_published: ~D[2012-01-01], content_url: "/m/2.mkv"})
      collection = build_movie_series(%{movies: [movie_1, movie_2]})

      releases = [release_map(%{part_tmdb_id: 55, title: "Next Part"})]

      view_model =
        CollectionDetail.build(
          %{entity: collection, progress: nil, progress_records: []},
          releases,
          :watching,
          nil
        )

      assert [
               %MovieListItem.Library{state: :unwatched},
               %MovieListItem.Library{state: :unwatched},
               %MovieListItem.Upcoming{}
             ] = view_model.movies

      records = [build_progress(%{movie_id: movie_1.id, completed: true})]
      updated = CollectionDetail.with_progress(view_model, nil, records, nil)

      assert [
               %MovieListItem.Library{state: :watched},
               %MovieListItem.Library{state: :unwatched},
               %MovieListItem.Upcoming{title: "Next Part"}
             ] = updated.movies

      assert updated.tracking_status == :watching
    end
  end

  describe "compose/1 — DB-backed assembly" do
    test "returns :not_found when the id matches no movie_series projection" do
      assert :not_found == CollectionDetail.compose(Ecto.UUID.generate())
    end

    test "collection with two present movies composes Library items" do
      collection = create_movie_series(%{name: "Sample Collection"})

      create_present_member(collection, "Member One", ~D[2010-01-01])
      create_present_member(collection, "Member Two", ~D[2012-01-01])

      assert {:ok, view_model} = CollectionDetail.compose(collection.id)
      assert view_model.tracking_status == nil

      assert [
               %MovieListItem.Library{movie: %{name: "Member One"}},
               %MovieListItem.Library{movie: %{name: "Member Two"}}
             ] = view_model.movies
    end

    test "tracked collection with a future part appends an Upcoming row" do
      collection = create_movie_series(%{name: "Tracked Collection", tmdb_id: "777001"})

      create_present_member(collection, "Member One", ~D[2010-01-01])
      create_present_member(collection, "Member Two", ~D[2012-01-01])

      item =
        create_tracking_item(%{
          tmdb_id: 777_001,
          media_type: :movie,
          name: "Tracked Collection",
          library_container_type: :movie_series,
          library_container_id: collection.id
        })

      create_tracking_release(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), 45),
        title: "Member Three",
        part_tmdb_id: 900_003
      })

      assert {:ok, view_model} = CollectionDetail.compose(collection.id)
      assert view_model.tracking_status == :watching

      assert [
               %MovieListItem.Library{},
               %MovieListItem.Library{},
               %MovieListItem.Upcoming{title: "Member Three", sub_status: :unaired}
             ] = view_model.movies
    end
  end

  describe "member selection — movie-first modal (UIDR-023)" do
    setup do
      movie_1 = build_movie(%{name: "Part One", date_published: ~D[2010-01-01], content_url: "/m/1.mkv"})
      movie_2 = build_movie(%{name: "Part Two", date_published: ~D[2012-01-01], content_url: "/m/2.mkv"})

      movie_3 =
        build_movie(%{name: "Part Three", date_published: ~D[2014-01-01], content_url: "/m/3.mkv"})

      collection = build_movie_series(%{movies: [movie_1, movie_2, movie_3]})

      resume_target = %{"action" => "resume", "targetId" => movie_2.id}

      view_model =
        CollectionDetail.build(
          %{entity: collection, progress: nil, progress_records: []},
          [
            release_map(%{
              part_tmdb_id: 44,
              title: "Part Four",
              air_date: Date.add(Date.utc_today(), 90)
            })
          ],
          :watching,
          resume_target
        )

      %{view_model: view_model, movie_1: movie_1, movie_2: movie_2, movie_3: movie_3}
    end

    test "select_member/2 returns the explicitly-selected library member", %{
      view_model: view_model,
      movie_3: movie_3
    } do
      assert %MovieListItem.Library{movie: %{name: "Part Three"}} =
               CollectionDetail.select_member(view_model, movie_3.id)
    end

    test "select_member/2 falls back to the resume target for nil or unknown ids", %{
      view_model: view_model
    } do
      assert %MovieListItem.Library{movie: %{name: "Part Two"}} =
               CollectionDetail.select_member(view_model, nil)

      assert %MovieListItem.Library{movie: %{name: "Part Two"}} =
               CollectionDetail.select_member(view_model, Ecto.UUID.generate())
    end

    test "select_member/2 falls back to the first library member without a resume target" do
      movie = build_movie(%{name: "Only Part", date_published: ~D[2010-01-01], content_url: "/m/1.mkv"})
      collection = build_movie_series(%{movies: [movie]})

      view_model =
        CollectionDetail.build(%{entity: collection, progress: nil, progress_records: []}, [], nil, nil)

      assert %MovieListItem.Library{movie: %{name: "Only Part"}} =
               CollectionDetail.select_member(view_model, nil)
    end

    test "select_member/2 returns nil for a collection with no playable members" do
      collection = build_movie_series(%{movies: []})

      view_model =
        CollectionDetail.build(%{entity: collection, progress: nil, progress_records: []}, [], nil, nil)

      assert CollectionDetail.select_member(view_model, nil) == nil
    end

    test "member_subject/1 composes a :movie-shaped map from the member", %{
      view_model: view_model,
      movie_2: movie_2
    } do
      member = CollectionDetail.select_member(view_model, movie_2.id)
      subject = CollectionDetail.member_subject(member)

      assert subject.type == :movie
      assert subject.id == movie_2.id
      assert subject.name == "Part Two"
      assert subject.date_published == ~D[2012-01-01]
      assert subject.extras == []
      assert is_list(subject.cast)
      assert is_list(subject.images)
    end
  end

  # --- Test helpers ---

  defp release_map(overrides) do
    Map.merge(
      %{
        part_tmdb_id: 1,
        title: "Untitled Part",
        air_date: Date.add(Date.utc_today(), 30),
        season_number: nil,
        episode_number: nil,
        in_library: false
      },
      overrides
    )
  end

  defp create_present_member(collection, name, date_published) do
    movie =
      create_movie(%{
        name: name,
        movie_series_id: collection.id,
        date_published: date_published,
        content_url:
          "/media/collection-test/#{name |> String.downcase() |> String.replace(" ", "-")}.mkv"
      })

    movie
  end
end
