defmodule MediaCentaurWeb.Components.Detail.LogicTest do
  use ExUnit.Case, async: true

  import MediaCentaur.TestFactory

  alias MediaCentaurWeb.Components.Detail.Facet
  alias MediaCentaurWeb.Components.Detail.Logic

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

  describe "facets_for/3 with :movie_series" do
    test "returns Movies / First released / Latest derived from member movies, plus Genres / Rating" do
      movies = [
        build_movie(%{date_published: ~D[1977-05-25], position: 1}),
        build_movie(%{date_published: ~D[1980-05-21], position: 2}),
        build_movie(%{date_published: ~D[1983-05-25], position: 3})
      ]

      movie_series =
        build_movie_series(%{
          movies: movies,
          genres: ["Sci-Fi"],
          aggregate_rating_value: 8.5
        })

      facets = Logic.facets_for(:movie_series, movie_series, movies)

      refute Enum.any?(facets, &(&1.label == "Movies"))
      assert %Facet{label: "First released", kind: :text, value: "1977"} in facets
      assert %Facet{label: "Latest", kind: :text, value: "1983"} in facets
      assert %Facet{label: "Genres", kind: :chips, value: ["Sci-Fi"]} in facets
      assert %Facet{label: "Rating", kind: :rating, value: %{rating: 8.5, vote_count: nil}} in facets
    end

    test "tolerates movies missing date_published" do
      movies = [
        build_movie(%{date_published: nil}),
        build_movie(%{date_published: ~D[1999-12-31]})
      ]

      facets = Logic.facets_for(:movie_series, build_movie_series(), movies)

      assert %Facet{label: "First released", kind: :text, value: "1999"} in facets
      assert %Facet{label: "Latest", kind: :text, value: "1999"} in facets
    end

    test "no Movies facet — the metadata row already counts them" do
      movies = [build_movie(%{date_published: nil}), build_movie(%{date_published: nil})]
      facets = Logic.facets_for(:movie_series, build_movie_series(), movies)

      refute Enum.any?(facets, &(&1.label == "Movies"))
      refute Enum.any?(facets, &(&1.label == "First released"))
      refute Enum.any?(facets, &(&1.label == "Latest"))
    end

    test "returns empty list when there are no movies and no metadata" do
      assert Logic.facets_for(:movie_series, build_movie_series(), []) == []
    end
  end

  describe "year_from_date/1" do
    test "extracts year from a Date struct" do
      assert Logic.year_from_date(~D[2008-07-18]) == "2008"
    end

    test "extracts year from an ISO date string (transition tolerance)" do
      assert Logic.year_from_date("2008-07-18") == "2008"
    end

    test "returns nil for nil input" do
      assert Logic.year_from_date(nil) == nil
    end

    test "returns nil for empty string" do
      assert Logic.year_from_date("") == nil
    end

    test "returns nil for malformed date" do
      assert Logic.year_from_date("not-a-date") == nil
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

  describe "play_label/1" do
    test "returns 'Play' and entity id" do
      assert Logic.play_label(%{type: :movie, id: "mv-uuid"}) == {"Play", "mv-uuid"}
      assert Logic.play_label(%{type: :tv_series, id: "tv-uuid"}) == {"Play", "tv-uuid"}
    end
  end

  describe "watch_again_label/1" do
    test "returns 'Watch again' and entity id" do
      assert Logic.watch_again_label(%{type: :movie, id: "mv-uuid"}) ==
               {"Watch again", "mv-uuid"}

      assert Logic.watch_again_label(%{type: :tv_series, id: "tv-uuid"}) ==
               {"Watch again", "tv-uuid"}
    end
  end

  describe "resume_label_from_hint/2" do
    test "TV series, season 1 episode N → 'Resume Episode N' with hint targetId" do
      tv = %{type: :tv_series, id: "tv-uuid"}
      hint = %{"action" => "resume", "targetId" => "ep-3", "seasonNumber" => 1, "episodeNumber" => 3}
      assert Logic.resume_label_from_hint(tv, hint) == {"Resume Episode 3", "ep-3"}
    end

    test "TV series, season 2 episode N → 'Resume S2E5'" do
      tv = %{type: :tv_series, id: "tv-uuid"}
      hint = %{"action" => "resume", "targetId" => "ep-x", "seasonNumber" => 2, "episodeNumber" => 5}
      assert Logic.resume_label_from_hint(tv, hint) == {"Resume S2E5", "ep-x"}
    end

    test "movie series with name → 'Resume <name>' and movie id" do
      ms = %{type: :movie_series, id: "ms-uuid"}
      hint = %{"action" => "resume", "targetId" => "mv-2", "ordinal" => 2, "name" => "Second Movie"}
      assert Logic.resume_label_from_hint(ms, hint) == {"Resume Second Movie", "mv-2"}
    end

    test "movie series with blank name and ordinal → 'Resume Movie N'" do
      ms = %{type: :movie_series, id: "ms-uuid"}
      hint = %{"action" => "resume", "targetId" => "mv-3", "ordinal" => 3, "name" => "  "}
      assert Logic.resume_label_from_hint(ms, hint) == {"Resume Movie 3", "mv-3"}
    end

    test "movie / video object hint without targetId → 'Resume' on entity id" do
      movie = %{type: :movie, id: "mv-uuid"}
      assert Logic.resume_label_from_hint(movie, %{"action" => "resume"}) == {"Resume", "mv-uuid"}

      vo = %{type: :video_object, id: "vo-uuid"}
      assert Logic.resume_label_from_hint(vo, %{"action" => "resume"}) == {"Resume", "vo-uuid"}
    end
  end

  describe "advance_label_from_hint/2" do
    test "TV series, season 1 episode N → 'Play Episode N'" do
      tv = %{type: :tv_series, id: "tv-uuid"}
      hint = %{"action" => "begin", "targetId" => "ep-1", "seasonNumber" => 1, "episodeNumber" => 1}
      assert Logic.advance_label_from_hint(tv, hint) == {"Play Episode 1", "ep-1"}
    end

    test "TV series, later season → 'Play S2E1'" do
      tv = %{type: :tv_series, id: "tv-uuid"}
      hint = %{"action" => "begin", "targetId" => "ep-s2e1", "seasonNumber" => 2, "episodeNumber" => 1}
      assert Logic.advance_label_from_hint(tv, hint) == {"Play S2E1", "ep-s2e1"}
    end

    test "movie series with name → 'Play <name>'" do
      ms = %{type: :movie_series, id: "ms-uuid"}
      hint = %{"action" => "begin", "targetId" => "mv-2", "ordinal" => 2, "name" => "Second Movie"}
      assert Logic.advance_label_from_hint(ms, hint) == {"Play Second Movie", "mv-2"}
    end

    test "TV series with no season/episode info → bare 'Play' on entity id" do
      tv = %{type: :tv_series, id: "tv-uuid"}
      assert Logic.advance_label_from_hint(tv, %{"action" => "begin"}) == {"Play", "tv-uuid"}
    end
  end

  describe "resume_label_from_progress/2" do
    test "TV series in season 1 → 'Resume Episode N' on entity id" do
      tv = %{type: :tv_series, id: "tv-uuid"}
      progress = %{current_episode: %{season: 1, episode: 4}}
      assert Logic.resume_label_from_progress(tv, progress) == {"Resume Episode 4", "tv-uuid"}
    end

    test "TV series in later season → 'Resume S2E3'" do
      tv = %{type: :tv_series, id: "tv-uuid"}
      progress = %{current_episode: %{season: 2, episode: 3}}
      assert Logic.resume_label_from_progress(tv, progress) == {"Resume S2E3", "tv-uuid"}
    end

    test "movie series with current ordinal → 'Resume Movie N'" do
      ms = %{type: :movie_series, id: "ms-uuid"}
      progress = %{current_episode: %{season: 0, episode: 2}}
      assert Logic.resume_label_from_progress(ms, progress) == {"Resume Movie 2", "ms-uuid"}
    end

    test "movie / video object → bare 'Resume' on entity id" do
      movie = %{type: :movie, id: "mv-uuid"}
      progress = %{current_episode: nil, episodes_completed: 0, episodes_total: 1}
      assert Logic.resume_label_from_progress(movie, progress) == {"Resume", "mv-uuid"}

      vo = %{type: :video_object, id: "vo-uuid"}
      assert Logic.resume_label_from_progress(vo, progress) == {"Resume", "vo-uuid"}
    end
  end

  # ---- Dispatcher: integrates all the per-case functions above ----

  describe "playback_props/3 — TV series (dispatcher)" do
    test "never watched (begin S01E01) → advance label with episode targetId" do
      tv = %{type: :tv_series, id: "tv-uuid"}
      hint = %{"action" => "begin", "targetId" => "ep-1", "seasonNumber" => 1, "episodeNumber" => 1}

      assert Logic.playback_props(tv, hint, nil) == {"Play Episode 1", "ep-1"}
    end

    test "advance crosses into season 2 → 'Play S2E1'" do
      tv = %{type: :tv_series, id: "tv-uuid"}
      hint = %{"action" => "begin", "targetId" => "ep-s2e1", "seasonNumber" => 2, "episodeNumber" => 1}
      progress = %{episodes_completed: 10, episodes_total: 20, episode_position_seconds: 0.0}

      assert Logic.playback_props(tv, hint, progress) == {"Play S2E1", "ep-s2e1"}
    end

    test "partially watched with hint → 'Resume Episode N' from hint" do
      tv = %{type: :tv_series, id: "tv-uuid"}

      hint = %{
        "action" => "resume",
        "targetId" => "ep-3",
        "seasonNumber" => 1,
        "episodeNumber" => 3
      }

      progress = %{episodes_completed: 2, episodes_total: 10, episode_position_seconds: 120.0}

      assert Logic.playback_props(tv, hint, progress) == {"Resume Episode 3", "ep-3"}
    end

    test "in-progress with NO hint → falls back to progress.current_episode" do
      # Bug-fix coverage: home_live never populates resume_targets, so the
      # modal sees `nil` here — we must still produce a Resume label, not
      # Watch again, when progress shows the user is mid-watch.
      tv = %{type: :tv_series, id: "tv-uuid"}

      progress = %{
        episodes_completed: 2,
        episodes_total: 10,
        episode_position_seconds: 600.0,
        current_episode: %{season: 1, episode: 3}
      }

      assert Logic.playback_props(tv, nil, progress) == {"Resume Episode 3", "tv-uuid"}
    end

    test "fully completed (any hint shape) → 'Watch again'" do
      tv = %{type: :tv_series, id: "tv-uuid"}
      progress = %{episodes_completed: 10, episodes_total: 10, episode_position_seconds: 0.0}

      assert Logic.playback_props(tv, nil, progress) == {"Watch again", "tv-uuid"}
    end
  end

  describe "playback_props/3 — movie (dispatcher)" do
    test "never watched → 'Play' on entity id" do
      movie = %{type: :movie, id: "mv-uuid"}
      assert Logic.playback_props(movie, nil, nil) == {"Play", "mv-uuid"}
    end

    test "partially watched WITH resume hint → 'Resume'" do
      movie = %{type: :movie, id: "mv-uuid"}
      hint = %{"action" => "resume", "name" => "Sample Movie"}

      progress = %{
        current_episode: nil,
        episode_position_seconds: 600.0,
        episode_duration_seconds: 7200.0,
        episodes_completed: 0,
        episodes_total: 1
      }

      assert Logic.playback_props(movie, hint, progress) == {"Resume", "mv-uuid"}
    end

    test "partially watched with NIL hint (the user-reported bug) → 'Resume', NOT 'Watch again'" do
      # The exact case from the bug report: a movie is partially watched
      # but home_live never populated resume_targets, so the hint is nil.
      # The previous logic returned {"Watch again", entity.id} here.
      movie = %{type: :movie, id: "be868a6e-a7d7-4f2e-b1f7-e948e0ab72dc"}

      progress = %{
        current_episode: nil,
        episode_position_seconds: 1500.0,
        episode_duration_seconds: 7200.0,
        episodes_completed: 0,
        episodes_total: 1
      }

      assert Logic.playback_props(movie, nil, progress) ==
               {"Resume", "be868a6e-a7d7-4f2e-b1f7-e948e0ab72dc"}
    end

    test "fully completed → 'Watch again'" do
      movie = %{type: :movie, id: "mv-uuid"}

      progress = %{
        episodes_completed: 1,
        episodes_total: 1,
        episode_position_seconds: 0.0
      }

      assert Logic.playback_props(movie, nil, progress) == {"Watch again", "mv-uuid"}
    end
  end

  describe "playback_props/3 — movie series (dispatcher)" do
    test "advance to next movie with hint → 'Play <name>'" do
      ms = %{type: :movie_series, id: "ms-uuid"}

      hint = %{
        "action" => "begin",
        "targetId" => "mv-2",
        "ordinal" => 2,
        "name" => "Second Movie"
      }

      progress = %{episodes_completed: 1, episodes_total: 3, episode_position_seconds: 0.0}

      assert Logic.playback_props(ms, hint, progress) == {"Play Second Movie", "mv-2"}
    end

    test "fully completed → 'Watch again'" do
      ms = %{type: :movie_series, id: "ms-uuid"}
      progress = %{episodes_completed: 3, episodes_total: 3, episode_position_seconds: 0.0}

      assert Logic.playback_props(ms, nil, progress) == {"Watch again", "ms-uuid"}
    end
  end

  describe "playback_props/3 — video object (dispatcher)" do
    test "never watched → 'Play'" do
      vo = %{type: :video_object, id: "vo-uuid"}
      hint = %{"action" => "begin", "name" => "Clip"}

      assert Logic.playback_props(vo, hint, nil) == {"Play", "vo-uuid"}
    end

    test "partially watched → 'Resume'" do
      vo = %{type: :video_object, id: "vo-uuid"}
      hint = %{"action" => "resume", "name" => "Clip"}

      progress = %{
        episodes_completed: 0,
        episodes_total: 1,
        episode_position_seconds: 30.0
      }

      assert Logic.playback_props(vo, hint, progress) == {"Resume", "vo-uuid"}
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
    alias MediaCentaurWeb.ViewModel.MovieListItem

    test "unwatched member plays fresh" do
      movie = build_movie(%{name: "Part One", content_url: "/m/1.mkv"})

      member = %MovieListItem.Library{
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

      member = %MovieListItem.Library{
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

      member = %MovieListItem.Library{
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

      member = %MovieListItem.Library{
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
end
