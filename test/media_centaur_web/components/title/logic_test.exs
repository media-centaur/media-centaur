defmodule MediaCentaurWeb.Components.Title.LogicTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.TestFactory, only: [build_activity: 1, build_entity: 1, build_tracking_release: 1]

  alias MediaCentaur.TMDB.ReleaseWindow
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.ViewModel.LeafDetail

  @today ~D[2026-09-05]

  defp movie(overrides \\ %{}) do
    Title.new!(
      Map.merge(
        %{
          tmdb_id: 777,
          media_type: :movie,
          name: "Sample Movie",
          year: "2010",
          release_date: ~D[2010-03-05]
        },
        overrides
      )
    )
  end

  defp facts(overrides \\ %{}) do
    Map.merge(
      %{rung: nil, acquisition_state: nil, release_mode_available: true},
      overrides
    )
  end

  describe "title_detail/2 tracking facts" do
    test "carries the release window (nil until the preview lands) and whether the title is complete" do
      detail = Logic.title_detail(movie(), facts())
      assert detail.release_window == nil
      refute detail.complete?

      window = %ReleaseWindow{stage: :theatrical}

      detail =
        Logic.title_detail(movie(), facts(%{release_window: window, complete?: true}))

      assert detail.release_window == window
      assert detail.complete?
    end
  end

  describe "title_detail/2 facts" do
    test "carries the title's rung, Off included" do
      assert Logic.title_detail(movie(), facts(%{rung: :list})).rung == :list
      assert Logic.title_detail(movie(), facts()).rung == nil
    end

    test "carries the acquisition state and the indexer's readiness as facts — the action is derived where it mounts" do
      detail =
        Logic.title_detail(
          movie(),
          facts(%{acquisition_state: :downloading, release_mode_available: false})
        )

      assert detail.acquisition_state == :downloading
      refute detail.release_mode_available
      refute Map.has_key?(detail, :primary)
    end

    test "carries the library half when the library owns the title, nil when it does not" do
      entity = %{type: :movie, id: "mv-uuid", name: "Sample Movie"}

      library = %TitleDetail.Library{
        entry: %LeafDetail{entity: entity, progress: nil, progress_records: [], resume_target: nil},
        subject: entity,
        member: nil,
        files: :loading,
        available: true
      }

      assert Logic.title_detail(movie(), facts(%{library: library})).library == library
      assert Logic.title_detail(movie(), facts()).library == nil
    end

    test "carries the activity it speaks for as one row, and the intent's note beside it" do
      row = %{activity: build_activity(%{text: "Watch it."}), nickname: "Sample Friend", own?: false}

      detail = Logic.title_detail(movie(), facts(%{activity: row, intent_note: "Mine."}))
      assert detail.activity == row
      assert detail.intent_note == "Mine."

      bare = Logic.title_detail(movie(), facts())
      assert bare.activity == nil
      assert bare.intent_note == nil
    end
  end

  describe "snapshot_from_entity/1 — the owner's entity as the title's snapshot" do
    test "a movie: name, year, release date and overview from the entity" do
      entity =
        build_entity(%{
          type: :movie,
          tmdb_id: "603",
          name: "Sample Movie",
          date_published: ~D[1999-03-31],
          description: "A sample overview."
        })

      assert %Title{
               tmdb_id: 603,
               media_type: :movie,
               name: "Sample Movie",
               year: "1999",
               release_date: ~D[1999-03-31],
               overview: "A sample overview.",
               poster_path: nil,
               backdrop_path: nil
             } = Logic.snapshot_from_entity(entity)
    end

    test "a series" do
      entity =
        build_entity(%{
          type: :tv_series,
          tmdb_id: "1399",
          name: "Sample Show",
          date_published: ~D[2011-04-17]
        })

      assert %Title{tmdb_id: 1399, media_type: :tv_series, name: "Sample Show", year: "2011"} =
               Logic.snapshot_from_entity(entity)
    end

    test "a collection member — the projection's integer id, no date" do
      subject = %{type: :movie, tmdb_id: 604, name: "Part 2", date_published: nil, description: nil}

      assert %Title{tmdb_id: 604, media_type: :movie, name: "Part 2", year: nil, release_date: nil} =
               Logic.snapshot_from_entity(subject)
    end

    test "a collection, or an entity without a TMDB identity, has no snapshot" do
      assert Logic.snapshot_from_entity(build_entity(%{type: :movie_series, tmdb_id: "10"})) == nil
      assert Logic.snapshot_from_entity(build_entity(%{type: :movie, tmdb_id: nil})) == nil
    end
  end

  describe "acquisition_marker/1" do
    test "words for each state, nil for none" do
      assert Logic.acquisition_marker(:planning) == "Planning"
      assert Logic.acquisition_marker(:downloading) == "Downloading"
      assert Logic.acquisition_marker(:needs_review) == "Needs review"
      assert Logic.acquisition_marker(nil) == nil
    end
  end

  describe "row_markers/2" do
    test "in library wins, then the acquisition state" do
      assert Logic.row_markers(%{
               in_library?: true,
               acquisition_state: :downloading,
               rung: :list
             }) == ["In library"]

      assert Logic.row_markers(%{
               in_library?: false,
               acquisition_state: :needs_review,
               rung: :list
             }) == ["Needs review", "On your list"]

      assert Logic.row_markers(%{
               in_library?: false,
               acquisition_state: nil,
               rung: nil
             }) == []
    end
  end

  describe "row_markers/2 tracking" do
    test "a followed title says Tracking, a grabbing one Auto-grab; Off and owned say nothing" do
      base = %{in_library?: false, acquisition_state: nil, rung: nil}

      assert Logic.row_markers(%{base | rung: :follow}) == ["Tracking"]
      assert Logic.row_markers(%{base | rung: :grab}) == ["Auto-grab"]
      assert Logic.row_markers(%{base | rung: :list}) == ["On your list"]
      assert Logic.row_markers(base) == []
      assert Logic.row_markers(%{base | in_library?: true, rung: :grab}) == ["In library"]
    end

    test "an ignored title says so — a search result you dismissed is still findable" do
      base = %{in_library?: false, acquisition_state: nil}
      assert Logic.row_markers(Map.put(base, :rung, :ignored)) == ["Ignored"]
      assert Logic.row_markers(Map.put(base, :rung, :ignored), true) == ["Ignored"]
    end

    test "list_implied? drops only the List marker" do
      base = %{in_library?: false, acquisition_state: nil, rung: nil}

      assert Logic.row_markers(Map.put(base, :rung, :list), true) == []
      assert Logic.row_markers(Map.put(base, :rung, :follow), true) == ["Tracking"]
    end
  end

  describe "release_ahead?/3 — whether the Track release dates row has anything to track" do
    test "a series always has a release ahead as far as the snapshot knows" do
      show = Title.new!(%{tmdb_id: 2, media_type: :tv_series, name: "Sample Show"})
      assert Logic.release_ahead?(show, nil, ~D[2026-09-14])
    end

    test "without the window, the snapshot's primary date decides" do
      assert Logic.release_ahead?(dated_movie(~D[2026-12-01]), nil, ~D[2026-09-14])
      assert Logic.release_ahead?(dated_movie(nil), nil, ~D[2026-09-14])
      refute Logic.release_ahead?(dated_movie(~D[2020-01-01]), nil, ~D[2026-09-14])
    end

    test "with the window, only a home release that has passed says no" do
      out = dated_movie(~D[2020-01-01])
      assert Logic.release_ahead?(out, %ReleaseWindow{stage: :unreleased}, ~D[2026-09-14])
      assert Logic.release_ahead?(out, %ReleaseWindow{stage: :theatrical}, ~D[2026-09-14])

      refute Logic.release_ahead?(
               dated_movie(~D[2026-12-01]),
               %ReleaseWindow{stage: :home},
               ~D[2026-09-14]
             )
    end

    test "an unknown window defers to the snapshot" do
      assert Logic.release_ahead?(
               dated_movie(~D[2026-12-01]),
               %ReleaseWindow{stage: :unknown},
               ~D[2026-09-14]
             )

      refute Logic.release_ahead?(
               dated_movie(~D[2020-01-01]),
               %ReleaseWindow{stage: :unknown},
               ~D[2026-09-14]
             )
    end

    defp dated_movie(release_date),
      do: Title.new!(%{tmdb_id: 1, media_type: :movie, name: "Movie A", release_date: release_date})
  end

  describe "row_markers/2 next release" do
    test "a watchlist row states its next date when it has one" do
      assert Logic.row_markers(%{
               in_library?: false,
               acquisition_state: nil,
               rung: nil,
               next_air_date: Date.add(@today, 1),
               today: @today
             }) == ["Next: Tomorrow"]

      assert Logic.row_markers(%{
               in_library?: false,
               acquisition_state: :planning,
               rung: nil,
               next_air_date: nil,
               today: @today
             }) == ["Planning"]
    end
  end

  describe "next_air_date/2" do
    test "the earliest dated release today or later that is not in the library" do
      releases = [
        build_tracking_release(%{air_date: Date.add(@today, 9)}),
        build_tracking_release(%{air_date: Date.add(@today, 2)}),
        build_tracking_release(%{air_date: Date.add(@today, -3)}),
        build_tracking_release(%{air_date: @today, in_library: true}),
        build_tracking_release(%{air_date: nil})
      ]

      assert Logic.next_air_date(releases, @today) == Date.add(@today, 2)
      assert Logic.next_air_date([], @today) == nil
    end
  end

  describe "planning mode and scope words" do
    test "each mode has its label" do
      assert Logic.planning_mode_label(:auto_select_best_release) == "Auto-select best release"
      assert Logic.planning_mode_label(:manually_select_release) == "Manually select release"
    end

    test "each scope choice has its label" do
      assert Logic.download_scope_label(:first_season) == "Season 1"
      assert Logic.download_scope_label(:everything) == "All seasons"
      assert Logic.download_scope_label(:choose_episodes) == "Choose episodes"
    end
  end

  describe "title_detail/2 planning mode" do
    test "carries the host's planning mode" do
      assert %{planning_mode: :auto_select_best_release} =
               Logic.title_detail(movie(), facts(%{planning_mode: :auto_select_best_release}))
    end

    test "defaults to manually selecting" do
      assert %{planning_mode: :manually_select_release} = Logic.title_detail(movie(), facts())
    end
  end
end
