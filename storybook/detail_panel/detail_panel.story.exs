defmodule MediaCentarrWeb.Storybook.DetailPanel.DetailPanel do
  @moduledoc """
  Shared entity detail content rendered inside the entity modal — hero,
  metadata row, play card, facet strip, and the type-specific content
  list (movie / TV seasons + episodes / movie series). The Manage
  sub-view (`detail_view: :info`) layers files (grouped by directory,
  with quality badges + an "added on" date), External IDs, the
  Rematch action, and a quiet UUID footer. Delete confirmations are
  *inline* — there is no secondary modal.

  ## Variations covered

    1. `:movie_basic` — `:movie` entity, never watched, available, the
       simplest path through the play card and metadata row. No
       seasons, no episodes — exercises `content_list/1`'s fallthrough
       clause.
    2. `:movie_with_progress` — same movie with a partial watch
       progress record. The play CTA reads "Resume", the thin progress
       bar above the play row appears, and "remaining" copy fills in.
    3. `:tv_series_with_seasons` — `:tv_series` with two seasons; one
       expanded via `expanded_seasons: MapSet.new([1])`. Hits the
       season header, the watched/current/unwatched episode row mix,
       and the missing-episode fallback for a gap in the episode list.
    4. `:movie_series` — `:movie_series` with three child movies, one
       partially watched. Hits the chronological movie row.
    5. `:info_view_with_files` — `detail_view: :info` with grouped
       files. Renders the prominent "Delete this/all files" danger
       button at the top, always-visible per-folder + per-file delete
       affordances, quality badges parsed from filenames (4K / HDR /
       WEB / H265 …), an "added Xd ago" stamp per file, the External
       IDs section, the Rematch action, and the muted UUID footer.
    6. `:rematch_confirm` — `rematch_confirm: true` flips the Rematch
       action to its confirm state ("Confirm?" copy, `btn-error`
       styling). Captures the confirmation toggle.
    7. `:delete_pending_all_inline` — `delete_confirm: :all` flips the
       prominent danger button to "Click again to confirm — Delete
       all files (size)" with an inline Cancel link. No separate
       modal; the gesture lives where the button does.
    8. `:delete_pending_file_inline` — `delete_confirm: {:file, path}`
       targeting one of the rows in `detail_files`. That file row
       gets a danger-tinted background + the trash button widens to
       show "Click to confirm".
    9. `:offline` — `available: false`, `tmdb_ready: false`. Play
       button collapses to the "Offline" pill, episode thumbnails
       become empty placeholder rectangles, the Rematch action is
       replaced with the "needs TMDB" hint.

  ## Fudged data

  Image URLs are intentionally absent — `image_url/2` always builds a
  `/media-images/<content_url>` path that our placeholder image server
  can't satisfy in storybook, so the hero falls back to its built-in
  `hero-film` placeholder and episode thumbnails render as
  `bg-base-300/30` rectangles. That's accurate to the "no artwork
  scraped yet" state, just chosen here to avoid noise.

  Showcase-style PD/CC titles only — generic "Sample Movie", "Quiet
  Sample Series", and the like. No real titles per `CLAUDE.md`.

  ## Contract observations (for Phase 3 typed-attr migration)

  Recorded as input for `~/src/media-centarr/component-contract-plan.md`:

    * `entity: :map` — the single biggest smell. The same component
      renders three structurally different shapes (movie /
      tv_series / movie_series), each branched on `entity.type`. A
      `MediaCentarr.Library.Entity` ADT (or per-type variant struct)
      would let `attr` carry a real signature and let dialyzer catch
      the missing-field branches that plain `Map.get/3` swallows
      today.
    * `progress: :map` and `resume: :map` — two distinct map shapes
      pretending to be one type. `progress` is
      `ProgressSummary.t()` (already typespecced); `resume` is the
      Hint shape Logic dispatches on (`%{"action" => "resume" |
      "begin", "targetId" => ..., "seasonNumber" => ...}` —
      string-keyed because it's deserialised from the browser).
      Lifting both into named structs documents the boundary
      between server-computed progress and client-derived resume
      hints.
    * `delete_confirm: :any` — actually a sum type identifying the
      pending inline-confirm target: `nil | :all | {:file, path} |
      {:folder, path}`. The `:any` hides the discriminator; a tagged
      union (or `Ecto.Enum`-style atom + path payload struct) would
      let dialyzer catch the per-button match expressions in the
      template.
    * `tracking_status: :atom, default: nil` — observed values are
      `nil | :watching | :ignored | :unknown` (see `tracking_icon/1`
      catch-all). Should be a typed enum.
    * `expanded_seasons: :any, default: nil` — really `MapSet.t() |
      nil`, with `nil` meaning "compute the default with
      `auto_expand_season/2`". Worth either documenting the
      `nil`-as-sentinel contract or threading the default upstream.
    * `progress_records: :list` — a list of `WatchProgress` schema
      structs (preloaded), but the attr says nothing. Same fix as
      above: name the element shape.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentarr.Library.{WatchedFile, WatchProgress}

  def function, do: &MediaCentarrWeb.Components.DetailPanel.detail_panel/1
  def render_source, do: :function

  # The detail panel is naturally tall and wide — two-column would
  # collapse the hero and stack the metadata. One column shows the
  # production layout end-to-end.
  def layout, do: :one_column

  # Wrap each variation in a width-constrained, dark, scroll-bounded
  # container so the panel renders against the same chrome it gets
  # inside ModalShell — the panel itself is a `position: relative`
  # element that fills its parent. Without a sized parent the play
  # card and facet strip stretch to whatever the storybook column
  # gives them.
  #
  # `transform: translateZ(0)` creates a containing block scope so any
  # future `position: fixed` descendant (a flash, a popover) stays
  # inside its variation card instead of escaping to overlay every
  # variation below. Cheap insurance even without modals on screen
  # right now — the inline-confirm pattern killed the per-variation
  # delete-confirm modal that originally needed it.
  def template do
    """
    <div
      class="bg-base-100 rounded-lg overflow-hidden max-w-[860px] border border-base-content/10 relative"
      style="transform: translateZ(0);"
    >
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :movie_basic,
        description:
          "`:movie` entity, never watched, storage available, default detail view. " <>
            "Simplest path through `playback_props/3` (just `Play`), no progress bar, " <>
            "no content list (the fallthrough `content_list/1` clause).",
        attributes: %{
          entity: sample_movie_entity(),
          progress: nil,
          resume: nil,
          progress_records: [],
          available: true,
          tmdb_ready: true,
          expanded_seasons: MapSet.new()
        }
      },
      %Variation{
        id: :movie_with_progress,
        description:
          "Same movie, mid-watch — `progress` carries `episode_position_seconds` " <>
            "below `episode_duration_seconds`. The play card shows the thin " <>
            "progress bar, the CTA flips to **Resume**, and the remaining-time " <>
            "text appears at the right.",
        attributes: %{
          entity: sample_movie_entity(),
          progress: %{
            current_episode: nil,
            episode_position_seconds: 1800.0,
            episode_duration_seconds: 5400.0,
            episodes_completed: 0,
            episodes_total: 1
          },
          resume: nil,
          progress_records: [movie_progress_record(sample_movie_entity().id, partial: true)],
          available: true,
          tmdb_ready: true,
          expanded_seasons: MapSet.new()
        }
      },
      %Variation{
        id: :tv_series_with_seasons,
        description:
          "`:tv_series` with two seasons. `expanded_seasons: MapSet.new([1])` " <>
            "expands season 1 to show watched / current / unwatched episode rows + a " <>
            "missing-episode placeholder for the gap at episode 4. Season 2 stays " <>
            "collapsed showing only its header. The Resume CTA reads **Resume " <>
            "Episode 2** — driven by `resume_label_from_progress/2`.",
        attributes: tv_series_attrs()
      },
      %Variation{
        id: :movie_series,
        description:
          "`:movie_series` with three child movies (chronological). Movie 2 is " <>
            "partially watched and gets the resume target border; movie 1 is " <>
            "completed (dimmed); movie 3 is unwatched. `playback_props/3` " <>
            "produces **Resume Movie 2**.",
        attributes: movie_series_attrs()
      },
      %Variation{
        id: :info_view_with_files,
        description:
          "`detail_view: :info` swaps the content list for the Manage drawer. " <>
            "Top: prominent **Delete this/all files (size)** danger button, always " <>
            "visible. Per-folder + per-file delete affordances also always visible " <>
            "(not hover-gated). Each file row carries a quality-badge strip parsed " <>
            "from its filename (4K / HDR / WEB / H265 …) plus an `added Xd ago` " <>
            "stamp on the right. Below the file list: External IDs (one row per " <>
            "source, linked when known), the Rematch action, and a muted UUID " <>
            "footer chip. Files use `detail_files: " <>
            "[%{file: %WatchedFile{}, size: bytes}]`.",
        attributes: %{
          entity: sample_movie_entity(),
          progress: nil,
          resume: nil,
          progress_records: [],
          available: true,
          tmdb_ready: true,
          detail_view: :info,
          detail_files: sample_detail_files(),
          expanded_seasons: MapSet.new()
        }
      },
      %Variation{
        id: :rematch_confirm,
        description:
          "`rematch_confirm: true` in the info view — the **Rematch** action " <>
            "flips to a confirm prompt (button copy and `btn-error` styling " <>
            "change). Captures the rematch-confirmation toggle state.",
        attributes: %{
          entity: sample_movie_entity(),
          progress: nil,
          resume: nil,
          progress_records: [],
          available: true,
          tmdb_ready: true,
          detail_view: :info,
          detail_files: sample_detail_files(),
          rematch_confirm: true,
          expanded_seasons: MapSet.new()
        }
      },
      %Variation{
        id: :delete_pending_all_inline,
        description:
          "`delete_confirm: :all` — first click on the prominent danger button " <>
            "set the pending target. Button text flips to **Click again to " <>
            "confirm — Delete all files (size)** and an inline **Cancel** link " <>
            "appears beside it. No secondary modal — the gesture lives where the " <>
            "button does.",
        attributes: %{
          entity: sample_movie_entity(),
          progress: nil,
          resume: nil,
          progress_records: [],
          available: true,
          tmdb_ready: true,
          detail_view: :info,
          detail_files: sample_detail_files(),
          delete_confirm: :all,
          expanded_seasons: MapSet.new()
        }
      },
      %Variation{
        id: :delete_pending_file_inline,
        description:
          "`delete_confirm: {:file, path}` targeting one of the rows. That " <>
            "row's background switches to the danger tint, gets a thin error " <>
            "ring, and its trash button widens from the resting icon-only state " <>
            "to **🗑 Click to confirm**.",
        attributes: %{
          entity: sample_movie_entity(),
          progress: nil,
          resume: nil,
          progress_records: [],
          available: true,
          tmdb_ready: true,
          detail_view: :info,
          detail_files: sample_detail_files(),
          delete_confirm: {:file, "/media/movies/Sample Movie (1922)/Sample.Movie.1922.1080p.mkv"},
          expanded_seasons: MapSet.new()
        }
      },
      %Variation{
        id: :offline,
        description:
          "`available: false` + `tmdb_ready: false` — the play CTA collapses to " <>
            "the disabled **Offline** pill, episode thumbnails become quiet " <>
            "placeholder rectangles, and the info drawer's Rematch button is " <>
            "replaced by the \"needs TMDB\" hint.",
        attributes:
          Map.merge(tv_series_attrs(), %{
            available: false,
            tmdb_ready: false,
            detail_view: :info,
            detail_files: []
          })
      }
    ]
  end

  # --- Movie fixture ----------------------------------------------------

  @movie_id "11111111-1111-1111-1111-111111111111"

  defp sample_movie_entity do
    %{
      id: @movie_id,
      type: :movie,
      name: "A Sample Silent Picture",
      description:
        "An ordinary morning unspools into a series of small, surprising tableaux. " <>
          "A demonstration entity — descriptions render as `line-clamp-4` under the " <>
          "metadata row.",
      tagline: "Look closer.",
      date_published: "1922-09-04",
      duration: "PT1H30M",
      director: "Sample Director",
      content_rating: "PG",
      number_of_seasons: nil,
      aggregate_rating_value: 7.4,
      vote_count: 1284,
      original_language: "en",
      studio: "Public Domain Pictures",
      country_code: "US",
      network: nil,
      status: :released,
      genres: ["Drama", "Comedy"],
      images: [],
      external_ids: [
        %{source: "imdb", external_id: "tt0000000"},
        %{source: "tmdb", external_id: "1001"}
      ],
      extras: [],
      seasons: [],
      movies: [],
      watched_files: [],
      url: "https://example.invalid/movies/sample",
      content_url: "/media/movies/Sample Movie (1922)/Sample.Movie.1922.1080p.mkv",
      watch_progress: [],
      extra_progress: [],
      inserted_at: ~U[2026-04-01 00:00:00Z],
      updated_at: ~U[2026-04-01 00:00:00Z]
    }
  end

  defp movie_progress_record(movie_id, partial: true) do
    %WatchProgress{
      id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      movie_id: movie_id,
      position_seconds: 1800.0,
      duration_seconds: 5400.0,
      completed: false,
      last_watched_at: ~U[2026-04-30 22:15:00Z]
    }
  end

  # --- TV series fixture -----------------------------------------------

  @tv_id "22222222-2222-2222-2222-222222222222"
  @s1_id "22222222-2222-2222-2222-22220000s001"
  @s2_id "22222222-2222-2222-2222-22220000s002"

  defp tv_series_attrs do
    entity = sample_tv_entity()
    season_one_episodes = entity.seasons |> Enum.at(0) |> Map.get(:episodes)

    # Episode 1 watched, episode 2 currently being watched (the resume
    # target), episode 3 unwatched, episode 4 missing entirely (gap in
    # the episode list — exercises the missing_episode_row branch via
    # number_of_episodes: 5).
    [ep1, ep2 | _] = season_one_episodes

    progress_records = [
      %WatchProgress{
        id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01",
        episode_id: ep1.id,
        position_seconds: 0.0,
        duration_seconds: 1500.0,
        completed: true,
        last_watched_at: ~U[2026-04-28 21:00:00Z]
      },
      %WatchProgress{
        id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb02",
        episode_id: ep2.id,
        position_seconds: 600.0,
        duration_seconds: 1500.0,
        completed: false,
        last_watched_at: ~U[2026-04-30 21:30:00Z]
      }
    ]

    %{
      entity: entity,
      progress: %{
        current_episode: %{season: 1, episode: 2},
        episode_position_seconds: 600.0,
        episode_duration_seconds: 1500.0,
        episodes_completed: 1,
        episodes_total: 8
      },
      resume: nil,
      progress_records: progress_records,
      available: true,
      tmdb_ready: true,
      expanded_seasons: MapSet.new([1])
    }
  end

  defp sample_tv_entity do
    %{
      id: @tv_id,
      type: :tv_series,
      name: "Quiet Sample Series",
      description:
        "An anthology of small stories from a sleepy town. Each episode " <>
          "follows a different resident through a single afternoon.",
      tagline: nil,
      date_published: "1925-01-12",
      duration: nil,
      director: nil,
      content_rating: "TV-PG",
      number_of_seasons: 2,
      aggregate_rating_value: 8.1,
      vote_count: 312,
      original_language: "en",
      studio: nil,
      country_code: "US",
      network: "Public Domain Network",
      status: :ended,
      genres: ["Drama", "Anthology"],
      images: [],
      external_ids: [%{source: "tmdb", external_id: "2002"}],
      extras: [],
      seasons: [
        sample_season(@s1_id, 1, "Season 1", 5, [
          sample_episode(
            "33333333-3333-3333-3333-3333000s01e01",
            1,
            "The First Visit",
            "Mira returns to town after years away."
          ),
          sample_episode(
            "33333333-3333-3333-3333-3333000s01e02",
            2,
            "Letters",
            "A bundle of unsent letters surfaces."
          ),
          sample_episode(
            "33333333-3333-3333-3333-3333000s01e03",
            3,
            "The Mechanic",
            "An old engine is coaxed back to life."
          ),
          # Episode 4 intentionally omitted — number_of_episodes: 5
          # means the missing_episode_row placeholder fills in for
          # both 4 and 5.
          sample_episode(
            "33333333-3333-3333-3333-3333000s01e05",
            5,
            "First Snow",
            "Winter arrives early."
          )
        ]),
        sample_season(@s2_id, 2, "Season 2", 3, [
          sample_episode(
            "33333333-3333-3333-3333-3333000s02e01",
            1,
            "Return",
            "A familiar face appears at the diner."
          )
        ])
      ],
      movies: [],
      watched_files: [],
      url: "https://example.invalid/tv/quiet-sample",
      content_url: nil,
      watch_progress: [],
      extra_progress: [],
      inserted_at: ~U[2026-04-01 00:00:00Z],
      updated_at: ~U[2026-04-01 00:00:00Z]
    }
  end

  # --- Movie series fixture --------------------------------------------

  @ms_id "44444444-4444-4444-4444-444444444444"

  defp movie_series_attrs do
    entity = sample_movie_series_entity()
    [m1, m2, _m3] = entity.movies

    progress_records = [
      %WatchProgress{
        id: "cccccccc-cccc-cccc-cccc-cccccccccc01",
        movie_id: m1.id,
        position_seconds: 0.0,
        duration_seconds: 5400.0,
        completed: true,
        last_watched_at: ~U[2026-04-20 21:00:00Z]
      },
      %WatchProgress{
        id: "cccccccc-cccc-cccc-cccc-cccccccccc02",
        movie_id: m2.id,
        position_seconds: 1500.0,
        duration_seconds: 5700.0,
        completed: false,
        last_watched_at: ~U[2026-04-30 22:00:00Z]
      }
    ]

    %{
      entity: entity,
      progress: %{
        current_episode: %{season: 0, episode: 2},
        episode_position_seconds: 1500.0,
        episode_duration_seconds: 5700.0,
        episodes_completed: 1,
        episodes_total: 3
      },
      resume: nil,
      progress_records: progress_records,
      available: true,
      tmdb_ready: true,
      expanded_seasons: MapSet.new()
    }
  end

  defp sample_movie_series_entity do
    movies = [
      sample_child_movie(
        "55555555-5555-5555-5555-555555555501",
        "Sample Picture I",
        "1920-05-01",
        "PT1H30M",
        "/media/sample-picture-1.mkv",
        1,
        "The first chapter — a rumour leads three siblings into the hills."
      ),
      sample_child_movie(
        "55555555-5555-5555-5555-555555555502",
        "Sample Picture II",
        "1922-07-10",
        "PT1H35M",
        "/media/sample-picture-2.mkv",
        2,
        "A return to the same valley, years later."
      ),
      sample_child_movie(
        "55555555-5555-5555-5555-555555555503",
        "Sample Picture III",
        "1925-11-04",
        "PT1H40M",
        "/media/sample-picture-3.mkv",
        3,
        "The valley closes its books."
      )
    ]

    %{
      id: @ms_id,
      type: :movie_series,
      name: "Sample Picture Trilogy",
      description: "Three pictures, one valley.",
      tagline: nil,
      date_published: "1920-05-01",
      duration: nil,
      director: nil,
      content_rating: nil,
      number_of_seasons: nil,
      aggregate_rating_value: 7.8,
      vote_count: 540,
      original_language: "en",
      studio: nil,
      country_code: "US",
      network: nil,
      status: nil,
      genres: ["Adventure", "Drama"],
      images: [],
      external_ids: [],
      extras: [],
      seasons: [],
      movies: movies,
      watched_files: [],
      url: "https://example.invalid/series/sample-trilogy",
      content_url: nil,
      watch_progress: [],
      extra_progress: [],
      inserted_at: ~U[2026-04-01 00:00:00Z],
      updated_at: ~U[2026-04-01 00:00:00Z]
    }
  end

  # --- Detail files fixture --------------------------------------------

  defp sample_detail_files do
    [
      %{
        file: %WatchedFile{
          id: "ffffffff-ffff-ffff-ffff-ffffffffff01",
          file_path: "/media/movies/Sample Movie (1922)/Sample.Movie.1922.1080p.mkv",
          watch_dir: "/media/movies"
        },
        size: 4_294_967_296
      },
      %{
        file: %WatchedFile{
          id: "ffffffff-ffff-ffff-ffff-ffffffffff02",
          file_path: "/media/movies/Sample Movie (1922)/Sample.Movie.1922.1080p.subtitles.srt",
          watch_dir: "/media/movies"
        },
        size: 32_768
      },
      %{
        file: %WatchedFile{
          id: "ffffffff-ffff-ffff-ffff-ffffffffff03",
          file_path: "/media/archive/Sample.Movie.1922.480p.legacy.mkv",
          watch_dir: "/media/archive"
        },
        # `nil` size renders the "absent" badge — the file went missing
        # off disk after being indexed.
        size: nil
      }
    ]
  end

  # --- Plain-map child builders ----------------------------------------
  #
  # Episode/Season/Movie are kept as plain maps rather than schema
  # structs because the detail panel digs into nested associations
  # (`episode.images`, `movie.images`) via `image_url/2`, which calls
  # `Enum.find/2` on the field. Schema structs default those to
  # `%Ecto.Association.NotLoaded{}`, which is truthy but not enumerable
  # — so the `entity.images || []` guard in `image_url/2` doesn't fall
  # through and `Enum.find` crashes. Plain maps with `images: []`
  # sidestep the whole NotLoaded ceremony.

  defp sample_season(id, season_number, name, number_of_episodes, episodes) do
    %{
      id: id,
      season_number: season_number,
      name: name,
      number_of_episodes: number_of_episodes,
      episodes: episodes,
      extras: []
    }
  end

  defp sample_episode(id, episode_number, name, description) do
    %{
      id: id,
      episode_number: episode_number,
      name: name,
      description: description,
      duration: "PT25M",
      content_url: "/media/quiet-sample/episode-#{episode_number}.mkv",
      images: []
    }
  end

  defp sample_child_movie(id, name, date_published, duration, content_url, position, description) do
    %{
      id: id,
      name: name,
      description: description,
      date_published: date_published,
      duration: duration,
      director: "Sample Director",
      content_url: content_url,
      position: position,
      genres: ["Adventure"],
      status: :released,
      images: []
    }
  end
end
