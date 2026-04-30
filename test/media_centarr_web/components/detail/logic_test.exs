defmodule MediaCentarrWeb.Components.Detail.LogicTest do
  use ExUnit.Case, async: true

  import MediaCentarr.TestFactory

  alias MediaCentarrWeb.Components.Detail.Facet
  alias MediaCentarrWeb.Components.Detail.Logic

  describe "facets_for/2 with :movie" do
    test "returns Director / Original language / Studio / Genres / Rating in order" do
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
               %Facet{label: "Original language", kind: :text, value: "de"},
               %Facet{label: "Studio", kind: :text, value: "Prana Film"},
               %Facet{label: "Genres", kind: :chips, value: ["Horror", "Silent"]},
               %Facet{label: "Rating", kind: :rating, value: %{rating: 7.9, vote_count: 1234}}
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
    test "returns Network / Original language / Genres / Rating in order" do
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
               %Facet{label: "Original language", kind: :text, value: "en"},
               %Facet{label: "Genres", kind: :chips, value: ["Drama"]},
               %Facet{label: "Rating", kind: :rating, value: %{rating: 8.2, vote_count: 5500}}
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
        build_movie(%{date_published: "1977-05-25", position: 1}),
        build_movie(%{date_published: "1980-05-21", position: 2}),
        build_movie(%{date_published: "1983-05-25", position: 3})
      ]

      movie_series =
        build_movie_series(%{
          movies: movies,
          genres: ["Sci-Fi"],
          aggregate_rating_value: 8.5
        })

      facets = Logic.facets_for(:movie_series, movie_series, movies)

      assert %Facet{label: "Movies", kind: :text, value: "3"} in facets
      assert %Facet{label: "First released", kind: :text, value: "1977"} in facets
      assert %Facet{label: "Latest", kind: :text, value: "1983"} in facets
      assert %Facet{label: "Genres", kind: :chips, value: ["Sci-Fi"]} in facets
      assert %Facet{label: "Rating", kind: :rating, value: %{rating: 8.5, vote_count: nil}} in facets
    end

    test "tolerates movies missing date_published" do
      movies = [
        build_movie(%{date_published: nil}),
        build_movie(%{date_published: "1999-12-31"})
      ]

      facets = Logic.facets_for(:movie_series, build_movie_series(), movies)

      assert %Facet{label: "Movies", kind: :text, value: "2"} in facets
      assert %Facet{label: "First released", kind: :text, value: "1999"} in facets
      assert %Facet{label: "Latest", kind: :text, value: "1999"} in facets
    end

    test "shows movie count even when no dates available" do
      movies = [build_movie(%{date_published: nil}), build_movie(%{date_published: nil})]
      facets = Logic.facets_for(:movie_series, build_movie_series(), movies)

      assert %Facet{label: "Movies", kind: :text, value: "2"} in facets
      refute Enum.any?(facets, &(&1.label == "First released"))
      refute Enum.any?(facets, &(&1.label == "Latest"))
    end

    test "returns empty list when there are no movies and no metadata" do
      assert Logic.facets_for(:movie_series, build_movie_series(), []) == []
    end
  end

  describe "year_from_date/1" do
    test "extracts year from ISO date string" do
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

  describe "format_duration/1" do
    test "formats ISO 8601 duration to human form" do
      assert Logic.format_duration("PT1H55M") == "1h 55m"
      assert Logic.format_duration("PT2H32M") == "2h 32m"
      assert Logic.format_duration("PT45M") == "45m"
    end

    test "returns nil for nil and empty input" do
      assert Logic.format_duration(nil) == nil
      assert Logic.format_duration("") == nil
    end

    test "returns nil for malformed (non-ISO) strings instead of crashing" do
      assert Logic.format_duration("90 minutes") == nil
      assert Logic.format_duration("garbage") == nil
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
end
