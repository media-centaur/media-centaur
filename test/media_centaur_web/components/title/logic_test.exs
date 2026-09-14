defmodule MediaCentaurWeb.Components.Title.LogicTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.TestFactory, only: [build_tracking_release: 1]

  alias MediaCentaur.TMDB.ReleaseWindow
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Components.Title.Logic

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
      %{
        library_owner_id: nil,
        rung: nil,
        acquisition_state: nil,
        release_mode_available: true,
        today: @today
      },
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

  describe "title_detail/2 primary action" do
    test "in library wins over everything" do
      detail =
        Logic.title_detail(movie(), facts(%{library_owner_id: "owner", acquisition_state: :downloading}))

      assert detail.primary == {:in_library, "owner"}
    end

    test "downloading, needs review and planning are states, not actions" do
      assert Logic.title_detail(movie(), facts(%{acquisition_state: :downloading})).primary ==
               {:state, :downloading}

      assert Logic.title_detail(movie(), facts(%{acquisition_state: :needs_review})).primary ==
               {:state, :needs_review}

      assert Logic.title_detail(movie(), facts(%{acquisition_state: :planning})).primary ==
               {:state, :planning}
    end

    test "released with an indexer downloads; a series carries the scope menu" do
      assert Logic.title_detail(movie(), facts()).primary == :download

      show =
        Title.new!(%{
          tmdb_id: 42,
          media_type: :tv_series,
          name: "Sample Show",
          release_date: ~D[2010-01-01]
        })

      detail = Logic.title_detail(show, facts())
      assert detail.primary == :download
      assert detail.scoped?
    end

    test "upcoming, or no indexer, offers no verb — the tracking-mode control arms" do
      assert Logic.title_detail(movie(%{release_date: ~D[2999-01-01]}), facts()).primary == nil
      assert Logic.title_detail(movie(), facts(%{release_mode_available: false})).primary == nil
    end
  end

  describe "title_detail/2 secondary and provenance" do
    test "the detail carries the title's rung, Off included" do
      assert Logic.title_detail(movie(), facts()).rung == nil
      assert Logic.title_detail(movie(), facts(%{rung: :grab})).rung == :grab
    end

    test "carries the feed provenance when given" do
      detail =
        Logic.title_detail(
          movie(),
          facts(%{
            sender: "Sample Friend",
            note: "Watch it",
            acted_at: ~U[2026-09-01 10:00:00Z],
            own?: false
          })
        )

      assert %TitleDetail{sender: "Sample Friend", note: "Watch it", own?: false} = detail
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

    test "each scope has its label" do
      assert Logic.download_scope_label(:first_season) == "Season 1"
      assert Logic.download_scope_label(:everything) == "All seasons"
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
