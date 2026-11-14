defmodule MediaCentaurWeb.Components.Detail.LogicTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.TitleProgress
  alias MediaCentaurWeb.Components.Detail.Facet
  alias MediaCentaurWeb.Components.Detail.Logic
  alias MediaCentaurWeb.ViewModel.EpisodeRow
  alias MediaCentaurWeb.ViewModel.SeasonView

  describe "facets_for/2 with :movie" do
    test "returns Director / Rating / Original language / Studio / Genres in order" do
      movie =
        build_movie(%{
          director: "F. W. Murnau",
          original_language: "de",
          studio: "Prana Film",
          genres: ["Horror", "Silent"],
          aggregate_rating_value: 7.9,
          vote_count: 1234
        })

      assert Logic.facets_for(:movie, movie) == [
               %Facet{label: "Director", kind: :text, value: "F. W. Murnau"},
               %Facet{label: "Rating", kind: :rating, value: %{rating: 7.9, vote_count: 1234}},
               %Facet{label: "Original language", kind: :text, value: "de"},
               %Facet{label: "Studio", kind: :text, value: "Prana Film"},
               %Facet{label: "Genres", kind: :chips, value: ["Horror", "Silent"]}
             ]
    end

    test "omits text facets whose value is nil" do
      movie =
        build_movie(%{
          director: "Someone",
          original_language: nil,
          studio: nil,
          genres: nil,
          aggregate_rating_value: nil,
          vote_count: nil
        })

      assert Logic.facets_for(:movie, movie) == [
               %Facet{label: "Director", kind: :text, value: "Someone"}
             ]
    end

    test "omits text facets whose value is blank string" do
      movie =
        build_movie(%{
          director: "",
          original_language: "en",
          studio: "  ",
          genres: [],
          aggregate_rating_value: nil
        })

      assert Logic.facets_for(:movie, movie) == [
               %Facet{label: "Original language", kind: :text, value: "en"}
             ]
    end

    test "omits genres facet when list is empty" do
      movie = build_movie(%{director: "X", genres: []})
      refute Enum.any?(Logic.facets_for(:movie, movie), &(&1.label == "Genres"))
    end

    test "omits genres facet when list is nil" do
      movie = build_movie(%{director: "X", genres: nil})
      refute Enum.any?(Logic.facets_for(:movie, movie), &(&1.label == "Genres"))
    end

    test "omits rating facet when rating is nil" do
      movie = build_movie(%{director: "X", aggregate_rating_value: nil})
      refute Enum.any?(Logic.facets_for(:movie, movie), &(&1.label == "Rating"))
    end

    test "omits rating facet when rating is 0.0 (TMDB unrated)" do
      movie = build_movie(%{director: "X", aggregate_rating_value: 0.0})
      refute Enum.any?(Logic.facets_for(:movie, movie), &(&1.label == "Rating"))
    end

    test "rating facet allows nil vote_count" do
      movie = build_movie(%{aggregate_rating_value: 6.4, vote_count: nil})
      facets = Logic.facets_for(:movie, movie)

      assert %Facet{label: "Rating", kind: :rating, value: %{rating: 6.4, vote_count: nil}} in facets
    end

    test "returns empty list when nothing is populated" do
      assert Logic.facets_for(:movie, build_movie()) == []
    end
  end

  describe "facets_for/2 with :tv_series" do
    test "returns Network / Rating / Original language / Genres in order" do
      tv =
        build_tv_series(%{
          network: "ABC",
          original_language: "en",
          genres: ["Drama"],
          aggregate_rating_value: 8.2,
          vote_count: 5500
        })

      assert Logic.facets_for(:tv_series, tv) == [
               %Facet{label: "Network", kind: :text, value: "ABC"},
               %Facet{label: "Rating", kind: :rating, value: %{rating: 8.2, vote_count: 5500}},
               %Facet{label: "Original language", kind: :text, value: "en"},
               %Facet{label: "Genres", kind: :chips, value: ["Drama"]}
             ]
    end

    test "does not include Country (already in metadata row)" do
      tv = build_tv_series(%{network: "HBO", country_code: "US"})
      refute Enum.any?(Logic.facets_for(:tv_series, tv), &(&1.label == "Country"))
    end

    test "does not include Status (already in metadata row)" do
      tv = build_tv_series(%{network: "HBO", status: :ended})
      refute Enum.any?(Logic.facets_for(:tv_series, tv), &(&1.label == "Status"))
    end
  end

  describe "humanize_status/1" do
    test "title-cases atom statuses" do
      assert Logic.humanize_status(:released) == "Released"
      assert Logic.humanize_status(:in_production) == "In production"
      assert Logic.humanize_status(:post_production) == "Post production"
      assert Logic.humanize_status(:returning) == "Returning"
    end

    test "passes through string statuses" do
      assert Logic.humanize_status("Released") == "Released"
    end

    test "nil → nil" do
      assert Logic.humanize_status(nil) == nil
    end
  end

  describe "completed?/1" do
    test "nil progress → false" do
      refute Logic.completed?(nil)
    end

    test "all items completed → true" do
      assert Logic.completed?(%{episodes_completed: 10, episodes_total: 10})
      assert Logic.completed?(%{episodes_completed: 1, episodes_total: 1})
    end

    test "partial progress → false" do
      refute Logic.completed?(%{episodes_completed: 0, episodes_total: 1})
      refute Logic.completed?(%{episodes_completed: 5, episodes_total: 10})
    end

    test "zero total (defensive) → false" do
      refute Logic.completed?(%{episodes_completed: 0, episodes_total: 0})
    end
  end

  describe "in_progress?/1" do
    test "nil progress → false" do
      refute Logic.in_progress?(nil)
    end

    test "any episode completed but not all → true" do
      assert Logic.in_progress?(%{
               episodes_completed: 3,
               episodes_total: 10,
               episode_position_seconds: 0.0
             })
    end

    test "no completions but current item has playback position → true" do
      assert Logic.in_progress?(%{
               episodes_completed: 0,
               episodes_total: 1,
               episode_position_seconds: 1500.0
             })
    end

    test "no completions and no position → false" do
      refute Logic.in_progress?(%{
               episodes_completed: 0,
               episodes_total: 1,
               episode_position_seconds: 0.0
             })
    end

    test "fully completed → false (it's done, not in progress)" do
      refute Logic.in_progress?(%{
               episodes_completed: 10,
               episodes_total: 10,
               episode_position_seconds: 0.0
             })
    end
  end

  describe "playback_props/2 — TV series" do
    defp tv_series do
      %{
        id: "tv-uuid",
        type: :tv_series,
        seasons: [
          %{season_number: 1, episodes: [%{id: "e3", episode_number: 3, name: "Episode 3"}]},
          %{season_number: 2, episodes: [%{id: "s2e1", episode_number: 1, name: "Episode 1"}]}
        ]
      }
    end

    defp next(item_id, offset), do: %{item_id: item_id, offset_seconds: offset, duration_seconds: 1300.0}

    defp in_progress(item_id, offset \\ 0.0),
      do: %TitleProgress{state: :in_progress, next: next(item_id, offset), before_next: 2, total: 10}

    test "complete reads Watch again and targets the title" do
      progress = %TitleProgress{state: :complete, before_next: 10, total: 10}
      assert Logic.playback_props(tv_series(), progress) == {"Watch again", "tv-uuid"}
    end

    test "in progress without an offset names next" do
      assert Logic.playback_props(tv_series(), in_progress("e3")) == {"Play Episode 3", "e3"}
    end

    test "in progress with an offset reads Resume" do
      assert Logic.playback_props(tv_series(), in_progress("e3", 600.0)) == {"Resume Episode 3", "e3"}
    end

    test "a next episode beyond season 1 carries its season" do
      assert Logic.playback_props(tv_series(), in_progress("s2e1")) == {"Play S2E1", "s2e1"}
      assert Logic.playback_props(tv_series(), in_progress("s2e1", 600.0)) == {"Resume S2E1", "s2e1"}
    end

    test "a rewatch names the next episode of the pass, though every episode is marked" do
      progress = %TitleProgress{state: :in_progress, next: next("e3", 0.0), before_next: 2, total: 2}
      assert Logic.playback_props(tv_series(), progress) == {"Play Episode 3", "e3"}
    end

    test "a next episode the entity does not list reads the bare verb and still targets it" do
      assert Logic.playback_props(tv_series(), in_progress("gone")) == {"Play", "gone"}
    end

    test "unstarted reads Play and targets the title" do
      progress = %TitleProgress{state: :unstarted, next: next("e3", 0.0), before_next: 0, total: 10}
      assert Logic.playback_props(tv_series(), progress) == {"Play", "tv-uuid"}
    end

    test "no title progress reads Play and targets the title" do
      assert Logic.playback_props(tv_series(), nil) == {"Play", "tv-uuid"}
    end
  end

  describe "playback_props/2 — movie and video object" do
    test "never watched → Play on the entity" do
      movie = %{type: :movie, id: "mv-uuid"}
      progress = %TitleProgress{state: :unstarted, next: next("mv-uuid", 0.0), before_next: 0, total: 1}

      assert Logic.playback_props(movie, progress) == {"Play", "mv-uuid"}
    end

    test "a viewing in flight → Resume, never Watch again" do
      for type <- [:movie, :video_object] do
        entity = %{type: type, id: "leaf-uuid"}

        progress = %TitleProgress{
          state: :in_progress,
          next: next("leaf-uuid", 1500.0),
          before_next: 0,
          total: 1
        }

        assert Logic.playback_props(entity, progress) == {"Resume", "leaf-uuid"}
      end
    end

    test "watched → Watch again" do
      movie = %{type: :movie, id: "mv-uuid"}
      progress = %TitleProgress{state: :complete, before_next: 1, total: 1}

      assert Logic.playback_props(movie, progress) == {"Watch again", "mv-uuid"}
    end
  end

  describe "playback_props/2 — movie collection" do
    defp collection(second_name) do
      %{
        id: "ms-uuid",
        type: :movie_series,
        movies: [
          %{
            id: "mv-1",
            name: "First Movie",
            position: 0,
            date_published: nil,
            content_url: "/movies/first.mkv"
          },
          %{
            id: "mv-2",
            name: second_name,
            position: 1,
            date_published: nil,
            content_url: "/movies/second.mkv"
          },
          %{id: "mv-3", name: "Third Movie", position: 2, date_published: nil, content_url: nil}
        ]
      }
    end

    defp at_second(offset),
      do: %TitleProgress{state: :in_progress, next: next("mv-2", offset), before_next: 1, total: 2}

    test "the next movie is named" do
      assert Logic.playback_props(collection("Second Movie"), at_second(0.0)) ==
               {"Play Second Movie", "mv-2"}

      assert Logic.playback_props(collection("Second Movie"), at_second(600.0)) ==
               {"Resume Second Movie", "mv-2"}
    end

    test "a next movie without a name reads its place among the movies with a file" do
      assert Logic.playback_props(collection("  "), at_second(600.0)) == {"Resume Movie 2", "mv-2"}
    end

    test "complete → Watch again on the collection" do
      progress = %TitleProgress{state: :complete, before_next: 2, total: 2}
      assert Logic.playback_props(collection("Second Movie"), progress) == {"Watch again", "ms-uuid"}
    end
  end

  describe "main_body?/1 — is there anything inside this title to list?" do
    # The body tab only earns a place when there is a body. This is the
    # predicate `scrollable_content?/2` was already asking inline; hoisted
    # because the tab strip and the view resolver both need the same answer.

    test "series always have a body" do
      assert Logic.main_body?(%{type: :tv_series})
      assert Logic.main_body?(%{type: :movie_series})
    end

    test "a bare movie has none" do
      refute Logic.main_body?(%{type: :movie, extras: []})
    end

    test "a movie with its own extras has one" do
      assert Logic.main_body?(%{type: :movie, extras: [build_extra(%{owner_type: :movie})]})
    end

    test "season-owned extras belong to their season, not the title" do
      refute Logic.main_body?(%{type: :movie, extras: [build_extra(%{owner_type: :season})]})
    end
  end

  describe "cast_tab?/1" do
    test "movies and series have a Cast view" do
      assert Logic.cast_tab?(%{type: :movie})
      assert Logic.cast_tab?(%{type: :tv_series})
    end

    test "collections do not — there is no collection-level cast to show" do
      refute Logic.cast_tab?(%{type: :movie_series})
    end
  end

  describe "resolve_view/2" do
    # A tab that cannot render must never be the selected one, whether it
    # was asked for by URL or landed on by default.

    test "keeps a view the entity can actually render" do
      assert Logic.resolve_view(%{type: :tv_series}, :main) == :main
      assert Logic.resolve_view(%{type: :tv_series}, :cast) == :cast
      assert Logic.resolve_view(%{type: :tv_series}, :info) == :info
    end

    test "a movie with no extras opens on its own hero page — Cast is a view you visit" do
      # The bare movie's main view is the orientation block alone (title,
      # Play, synopsis) — it fits without scrolling, and the Cast control
      # beside Play leads to the grid, same shape as TV.
      assert Logic.resolve_view(%{type: :movie, extras: []}, :main) == :main
    end

    test "a collection asked for Cast falls back to its movie list" do
      assert Logic.resolve_view(%{type: :movie_series}, :cast) == :main
    end

    test "Manage is always available, whatever the entity" do
      assert Logic.resolve_view(%{type: :movie, extras: []}, :info) == :info
      assert Logic.resolve_view(%{type: :movie_series}, :info) == :info
    end
  end

  describe "body_label/1" do
    # The name of what the title contains. Type-dependent because the body is
    # a different kind of thing per type, and there is no honest generic word
    # covering episodes, member movies and extras at once.

    test "names what the body actually holds" do
      assert Logic.body_label(%{type: :tv_series}) == "Episodes"
      assert Logic.body_label(%{type: :movie_series}) == "Movies"
      assert Logic.body_label(%{type: :movie, extras: [%{owner_type: :movie}]}) == "Extras"
    end

    test "a bare movie's root is its hero page — the return control reads Overview" do
      assert Logic.body_label(%{type: :movie, extras: []}) == "Overview"
    end
  end

  describe "secondary_view/2 — the one control beside Play" do
    # The modal's only view control, and it names its destination rather than
    # saying "Back". "Episodes" tells you where you are going; "Back" only
    # tells you it is not here.

    test "on the root view it offers the other view worth seeing" do
      assert Logic.secondary_view(%{type: :tv_series}, :main) == :cast

      assert Logic.secondary_view(%{type: :movie, extras: [%{owner_type: :movie}]}, :main) ==
               :cast

      assert Logic.secondary_view(%{type: :movie, extras: []}, :main) == :cast
    end

    test "off the root view it returns there, whichever view you are on" do
      assert Logic.secondary_view(%{type: :tv_series}, :cast) == :main
      assert Logic.secondary_view(%{type: :tv_series}, :info) == :main
      assert Logic.secondary_view(%{type: :movie, extras: []}, :cast) == :main
      assert Logic.secondary_view(%{type: :movie, extras: []}, :info) == :main
    end

    test "no control when the root view is the only content view" do
      assert Logic.secondary_view(%{type: :movie_series}, :main) == nil
    end

    test "a collection still gets back to its movie list from Manage" do
      assert Logic.secondary_view(%{type: :movie_series}, :info) == :main
    end
  end

  describe "member_playback/1 — selected collection member (UIDR-023)" do
    alias MediaCentaurWeb.ViewModel.MovieRow

    test "unwatched member plays fresh" do
      movie = build_movie(%{name: "Part One", content_url: "/m/1.mkv"})

      member = %MovieRow.Library{
        movie: movie,
        progress: nil,
        state: :unwatched,
        is_resume_target: false
      }

      assert Logic.member_playback(member) == %{
               label: "Play",
               target_id: movie.id,
               percent: 0,
               remaining_text: nil
             }
    end

    test "in-progress member resumes with percent and remaining copy" do
      # UIDR-024: percent feeds the hero hairline; remaining_text is the
      # metadata line's "left" item.
      movie = build_movie(%{name: "Part Two", content_url: "/m/2.mkv"})

      progress =
        build_progress(%{
          movie_id: movie.id,
          completed: false,
          position_seconds: 3600.0,
          duration_seconds: 7200.0
        })

      member = %MovieRow.Library{
        movie: movie,
        progress: progress,
        state: :current,
        is_resume_target: true
      }

      assert %{label: "Resume", percent: 50, remaining_text: "1h left"} =
               Logic.member_playback(member)

      assert Logic.member_playback(member).target_id == movie.id
    end

    test "watched member offers watch-again with a full hairline" do
      movie = build_movie(%{name: "Part Three", content_url: "/m/3.mkv"})
      progress = build_progress(%{movie_id: movie.id, completed: true})

      member = %MovieRow.Library{
        movie: movie,
        progress: progress,
        state: :watched,
        is_resume_target: false
      }

      # UIDR-024: a watched member's hairline fills — percent 100, like a
      # completed series — while the remaining item stays absent.
      assert %{label: "Watch again", percent: 100, remaining_text: nil} =
               Logic.member_playback(member)
    end

    test "zero-duration progress row yields percent 0, never a divide crash" do
      movie = build_movie(%{name: "Part Four", content_url: "/m/4.mkv"})

      progress =
        build_progress(%{
          movie_id: movie.id,
          completed: false,
          position_seconds: 10.0,
          duration_seconds: 0.0
        })

      member = %MovieRow.Library{
        movie: movie,
        progress: progress,
        state: :current,
        is_resume_target: false
      }

      assert %{label: "Resume", percent: 0, remaining_text: nil} = Logic.member_playback(member)
    end
  end

  describe "letterboxd_url/1" do
    test "builds the TMDB-redirect URL from a TMDB id" do
      assert Logic.letterboxd_url("603") == "https://letterboxd.com/tmdb/603"
    end

    test "nil when there is no TMDB id" do
      assert Logic.letterboxd_url(nil) == nil
    end
  end

  defp library_row(season_number, episode_number) do
    %EpisodeRow.Library{
      episode: %{id: "ep-#{season_number}-#{episode_number}", episode_number: episode_number},
      season_number: season_number,
      state: :unwatched,
      is_resume_target: false
    }
  end

  defp owned_season(season_number, items) do
    %SeasonView{
      season_number: season_number,
      kind: :library,
      items: items,
      watched_count: 0,
      total_count: length(items)
    }
  end

  describe "more_to_download?/2 — is there anything left for the picker to offer?" do
    test "no: every season the series has, every episode in them" do
      seasons = [
        owned_season(1, [library_row(1, 1), library_row(1, 2)]),
        owned_season(2, [library_row(2, 1)])
      ]

      refute Logic.more_to_download?(seasons, 2)
    end

    test "yes: an aired episode with no file" do
      seasons = [
        owned_season(1, [library_row(1, 1), %EpisodeRow.Missing{season_number: 1, episode_number: 2}])
      ]

      assert Logic.more_to_download?(seasons, 1)
    end

    test "yes: a season the library holds nothing of" do
      assert Logic.more_to_download?([owned_season(2, [library_row(2, 1)])], 2)
    end

    test "an episode already being downloaded is still an episode you do not have" do
      seasons = [
        owned_season(1, [
          library_row(1, 1),
          %EpisodeRow.InFlight{season_number: 1, episode_number: 2}
        ])
      ]

      assert Logic.more_to_download?(seasons, 1)
    end

    test "an unaired episode is not an absence you can act on" do
      seasons = [
        owned_season(1, [
          library_row(1, 1),
          %EpisodeRow.Upcoming{season_number: 1, episode_number: 2, air_date: ~D[2030-01-01]}
        ])
      ]

      refute Logic.more_to_download?(seasons, 1)
    end

    test "a future season carries no ownership — the seasons you have are the library ones" do
      seasons = [
        owned_season(1, [library_row(1, 1)]),
        %SeasonView{
          season_number: 2,
          kind: :future,
          items: [%EpisodeRow.Upcoming{season_number: 2, episode_number: 1, air_date: ~D[2030-01-01]}],
          watched_count: nil,
          total_count: 1
        }
      ]

      assert Logic.more_to_download?(seasons, 2)
    end

    test "an unknown season count cannot prove completeness, so the offer stands" do
      assert Logic.more_to_download?([owned_season(1, [library_row(1, 1)])], nil)
    end

    test "a series with no seasons at all" do
      assert Logic.more_to_download?([], 3)
    end
  end
end

defmodule MediaCentaurWeb.Components.Detail.LogicPrimaryActionTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.Library.TitleProgress
  alias MediaCentaurWeb.Components.Detail.Logic
  alias MediaCentaurWeb.Components.ReleaseTracking.TrackingDetail
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.ViewModel.LeafDetail
  alias MediaCentaurWeb.ViewModel.MovieRow

  @today ~D[2026-09-05]

  defp title(overrides \\ %{}) do
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

  defp detail(overrides \\ %{}) do
    title = Map.get(overrides, :title, title())

    struct!(
      TitleDetail,
      Map.merge(%{ref: Title.ref(title), title: title, rung: nil, acquisition_state: nil}, overrides)
    )
  end

  defp owned(entity, overrides \\ %{}) do
    Map.merge(
      %TitleDetail.Library{
        entry: %LeafDetail{entity: entity, progress: nil, progress_records: [], title_progress: nil},
        subject: entity,
        member: nil,
        files: :loading,
        available: true
      },
      overrides
    )
  end

  describe "primary_action/2 — the one honest primary action, from facts" do
    test "files win over everything: an owned title plays" do
      movie = %{type: :movie, id: "mv-uuid"}

      detail =
        detail(%{library: owned(movie), acquisition_state: :downloading, release_mode_available: true})

      assert Logic.primary_action(detail, @today) ==
               {:play, %{label: "Play", target_id: "mv-uuid", percent: 0, remaining_text: nil}}
    end

    test "an owned title mid-watch resumes, with its fraction and the time left" do
      movie = %{type: :movie, id: "mv-uuid", duration_seconds: 7200}

      progress = %{
        episodes_completed: 0,
        episodes_total: 1,
        episode_position_seconds: 3600.0,
        episode_duration_seconds: 7200.0
      }

      title_progress = %TitleProgress{
        state: :in_progress,
        next: %{item_id: "mv-uuid", offset_seconds: 3600.0, duration_seconds: 7200.0},
        before_next: 0,
        total: 1
      }

      library = owned(movie)
      library = %{library | entry: %{library.entry | progress: progress, title_progress: title_progress}}

      assert {:play, props} = Logic.primary_action(detail(%{library: library}), @today)
      assert props.label == "Resume"
      assert props.target_id == "mv-uuid"
      assert props.percent == 50
      assert props.remaining_text == "1h left"
    end

    test "a collection member plays as the member — the rail's selection" do
      member = %MovieRow.Library{
        movie: %{id: "part-2", name: "Part 2"},
        progress: nil,
        state: :unwatched,
        is_resume_target: false
      }

      library = owned(%{type: :movie, id: "part-2"}, %{member: member})

      assert Logic.primary_action(detail(%{library: library}), @today) ==
               {:play, Logic.member_playback(member)}
    end

    test "downloading, needs review and planning are states, not actions" do
      for state <- [:downloading, :needs_review, :planning] do
        assert Logic.primary_action(
                 detail(%{acquisition_state: state, release_mode_available: true}),
                 @today
               ) == {:state, state}
      end
    end

    test "released with an indexer downloads; a series carries the scope menu" do
      assert Logic.primary_action(detail(%{release_mode_available: true}), @today) == {:download, false}

      show = title(%{media_type: :tv_series, name: "Sample Show"})

      assert Logic.primary_action(detail(%{title: show, release_mode_available: true}), @today) ==
               {:download, true}
    end

    test "upcoming, or no indexer, offers no verb — the tracking-mode control arms" do
      upcoming = title(%{release_date: ~D[2027-01-01]})

      assert Logic.primary_action(detail(%{title: upcoming, release_mode_available: true}), @today) ==
               :none

      assert Logic.primary_action(detail(%{release_mode_available: false}), @today) == :none
    end
  end

  describe "tracking_card?/1 — the card under the body is the unowned title's" do
    test "a title the library does not hold always has one: Ignore unlisted, the line ignored, the switches listed" do
      assert Logic.tracking_card?(detail())
      assert Logic.tracking_card?(detail(%{rung: :ignored}))
      assert Logic.tracking_card?(detail(%{rung: :list}))
    end

    test "an owned title with nothing to say has none" do
      refute Logic.tracking_card?(detail(%{library: struct(TitleDetail.Library, [])}))
    end

    # An owned title has the Manage sheet, which is where the acceptance
    # lives (`Title.LowerQualityNote`). Counting it here too put the note
    # under the episode list as well as behind the cog.
    test "an owned title's acceptance is Manage's business, not the card's" do
      detail =
        detail(%{library: owned(%{type: :tv_series, id: "tv-uuid"}), lower_quality_accepted?: true})

      refute Logic.tracking_card?(detail)
    end

    # The modal of a title the library holds is for watching it. Tracking
    # an owned series is the Watchlist page's business (UIDR-042, amended
    # 2026-11-08): no switches, no caught-up point, no dates under it.
    test "an owned title never shows the card, whatever its rung or calendar" do
      library = owned(%{type: :tv_series, id: "tv-uuid"})

      refute Logic.tracking_card?(detail(%{library: library, rung: :list}))
      refute Logic.tracking_card?(detail(%{library: library, rung: :grab}))
      refute Logic.tracking_card?(detail(%{library: library, tracking: %TrackingDetail{}}))
    end
  end

  describe "finish prompt — whose it is, what it says, what its delete covers" do
    alias MediaCentaur.TMDB.Title
    alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
    alias MediaCentaurWeb.Components.Title.Detail.Library, as: Half
    alias MediaCentaurWeb.ViewModel.MovieRow

    @today ~D[2026-10-05]

    defp open_detail(media_type, container_id, opts \\ []) do
      title = Title.new!(%{tmdb_id: 1, media_type: media_type, name: "Sample Title"})

      member =
        case opts[:member] do
          nil -> nil
          id -> %MovieRow.Library{movie: %{id: id}, state: :watched, is_resume_target: false}
        end

      %TitleDetail{
        ref: Title.ref(title),
        title: title,
        settled?: Keyword.get(opts, :settled?, false),
        library: %Half{entry: %{entity: %{id: container_id}}, subject: %{}, member: member}
      }
    end

    defp file_info(path, movie_id),
      do: %{file: %{file_path: path, playable_item: %{container_id: movie_id}}, size: 1}

    test "subject_id/1 is the selected member, else the container, nil when unowned" do
      assert Logic.subject_id(open_detail(:movie, "movie-1")) == "movie-1"
      assert Logic.subject_id(open_detail(:movie, "collection-1", member: "movie-2")) == "movie-2"
      assert Logic.subject_id(%TitleDetail{ref: nil, title: nil}) == nil
    end

    test "finish_prompt/3 is nil unless the open subject is the finished id" do
      assert Logic.finish_prompt(open_detail(:movie, "movie-1"), nil, @today) == nil
      assert Logic.finish_prompt(open_detail(:movie, "movie-1"), "movie-2", @today) == nil

      assert Logic.finish_prompt(
               open_detail(:movie, "collection-1", member: "movie-2"),
               "movie-3",
               @today
             ) ==
               nil
    end

    test "a finished movie offers the primary delete" do
      assert Logic.finish_prompt(open_detail(:movie, "movie-1"), "movie-1", @today) ==
               %{kind: :finished, delete_target: :all}
    end

    test "a finished collection movie's delete covers that member only" do
      detail = open_detail(:movie, "collection-1", member: "movie-2")

      assert Logic.finish_prompt(detail, "movie-2", @today) ==
               %{kind: :finished, delete_target: {:member, "movie-2"}}
    end

    test "a settled series is finished; one with a release ahead is caught up" do
      assert Logic.finish_prompt(open_detail(:tv_series, "series-1", settled?: true), "series-1", @today) ==
               %{kind: :finished, delete_target: :all}

      assert Logic.finish_prompt(open_detail(:tv_series, "series-1"), "series-1", @today) ==
               %{kind: :caught_up, delete_target: nil}
    end

    test "files_for_target/2 — every file for :all, the member's own for {:member, id}" do
      files = [
        file_info("/m/a.mkv", "movie-1"),
        file_info("/m/b.mkv", "movie-2"),
        file_info("/m/b2.mkv", "movie-2")
      ]

      assert Logic.files_for_target(files, :all) == files

      assert Enum.map(Logic.files_for_target(files, {:member, "movie-2"}), & &1.file.file_path) ==
               ["/m/b.mkv", "/m/b2.mkv"]
    end
  end
end
