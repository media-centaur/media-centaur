defmodule MediaCentaurWeb.Storybook.DetailPanel.DetailPanel do
  @moduledoc """
  The library detail modal — `DetailPanel` is the library tenant of
  `CinematicShell`, so each variation renders the **whole modal**: the
  always-in-DOM `<.modal>` shell, the panel-fixed backdrop + atmosphere,
  the scrollport, the pinned orientation block (identity lockup,
  metadata row, play card), and the type-specific content —
  TV seasons + episodes, the collection poster rail (UIDR-023), extras
  for leaves (no facet strip anywhere: every type dropped its catalog
  facts with the Cast view). The Manage
  sub-view (`detail_view: :info`) delegates to
  `Detail.ManagePanel.manage_panel/1` — a toolbar card (Delete all,
  Rematch, Refresh artwork, external IDs + UUID) over a collapsed
  folder ledger; its state matrix lives in the ManagePanel story, the
  variations here pin the view swap and attr forwarding. Delete
  confirmations are *inline* — there is no secondary modal.

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
       The `seasons_view` attr is a `[%SeasonView{}]` carrying typed
       `%EpisodeListItem.Library{}` and `%EpisodeListItem.Missing{}`
       items — the TV-series content list reads exclusively from this
       structure (per ADR ViewModel migration).
    4. `:tv_series_spoiler_free` — same library shape as 3 but
       `spoiler_free: true`. Unwatched episodes blur their thumbnail,
       title, and description (`.spoiler-blur`); the leading episode
       number stays legible. Watched / current rows render unblurred.
    5. `:tv_series_with_upcoming_inline` — same shape as 3 but with
       `%EpisodeListItem.Upcoming{}` items mixed in: one replacing a
       Missing slot, one appended after the last library episode in
       S1. Pill copy reads "in Xd" because `air_date` is in the
       future.
    6. `:tv_series_aired_not_in_library` — TV variation with an
       Upcoming item whose `sub_status: :aired_not_in_library`
       (released but file not yet imported). Pill copy reads
       "aired Xd ago".
    7. `:tv_series_only_future` — entity has zero library seasons;
       releases project a synthetic `kind: :future` SeasonView. Hits
       the no-watched-count branch on the season header.
    8. `:tv_series_untracked` — same library shape as 3 but
       `tracking_status: nil`. Confirms the bell-icon affordance is
       absent and no upcoming/future-season content renders.
    9. `:movie_series` — the movie-first collection modal (UIDR-023):
       the selected member (movie 2, in progress) renders the
       standalone-movie panel — saga eyebrow, member synopsis, Resume
       with the member's own progress row — over the poster rail built
       from the typed `movies_view` (watched check on movie 1,
       progress underline on the lit movie 2, unselected tiles dimmed).
    9b. `:movie_series_with_upcoming` — a tracked collection's announced
       fourth part renders as a muted, unpickable rail tile with the
       air-date pill, and widens the eyebrow's "of N".
    10. `:info_view_with_files` — `detail_view: :info` with a small
       (≤ 6 files) inventory: the folder ledger auto-expands, showing
       file rows (quality badges, "added Xd ago", per-file delete)
       under the toolbar card.
    10b. `:info_view_collapsed_ledger` — a large inventory rests as
       collapsed folder summary rows; zero file rows at rest.
    11. `:rematch_confirm` — `rematch_confirm: true` flips the Rematch
       action to its confirm state ("Confirm?" copy, `btn-error`
       styling). Captures the confirmation toggle.
    12. `:delete_pending_all_inline` — `delete_confirm: :all` flips the
       prominent danger button to "Click again to confirm — Delete
       all files (size)" with an inline Cancel link. No separate
       modal; the gesture lives where the button does.
    13. `:delete_pending_file_inline` — `delete_confirm: {:file, path}`
       targeting one of the rows in `detail_files`. That file row
       gets a danger-tinted background + the trash button widens to
       show "Click to confirm".
    14. `:offline` — `available: false`, `tmdb_ready: false`. Play
       button collapses to the "Offline" pill, episode thumbnails
       become empty placeholder rectangles, the Rematch action is
       replaced with the "needs TMDB" hint.
    15. `:tv_series_all_episode_details_open` — `all_episode_details_open: true`
       opens every episode row's synopsis/thumbnail block at once
       (the list-level "Show details" toggle above the seasons,
       ORed with per-row `expanded_item_details`).

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

  Recorded as input for `~/src/media-centaur/component-contract-plan.md`:

    * **Both content-list paths are typed** —
      `MediaCentaurWeb.ViewModel.{SeriesDetail, SeasonView,
      EpisodeListItem.{Library, Missing, Upcoming}}` for TV
      (`seasons_view`) and `MediaCentaurWeb.ViewModel.{CollectionDetail,
      MovieListItem.{Library, Upcoming}}` for collections
      (`movies_view`). `Detail.SeasonList` / `Detail.CollectionRail`
      consume them exclusively.
    * `entity: :map` — still the biggest remaining smell on the
      top-level component. Movie and movie_series renders dispatch on
      `entity.type` with `Map.get/3` field access. Same `Entity` ADT
      idea applies; the TV-series migration is a working blueprint.
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

  # Per the data-decoupling policy (ADR-029), `WatchProgress` is private
  # to `MediaCentaur.Library` — its boundary doesn't export the schema.
  # The component declares `attr :progress_records, :list` (loose-typed),
  # so this story uses plain maps with the same fields. `WatchedFile` IS
  # exported and stays aliased.
  alias MediaCentaur.Library.{Person, WatchedFile}
  alias MediaCentaurWeb.ViewModel.EpisodeListItem
  alias MediaCentaurWeb.ViewModel.MovieListItem
  alias MediaCentaurWeb.ViewModel.SeasonView

  def function, do: &MediaCentaurWeb.Components.DetailPanel.detail_panel/1
  def render_source, do: :function

  # The detail panel is naturally tall and wide — two-column would
  # collapse the hero and stack the metadata. One column shows the
  # production layout end-to-end.
  def layout, do: :one_column

  # Each variation renders a real `position: fixed` overlay (the
  # component is the modal now), so they would otherwise stack in a
  # shared DOM and only the last would be visible. Iframing isolates
  # them.
  def container, do: {:iframe, style: "min-height: 720px; width: 100%;"}

  # Variations that start closed pair with this trigger; open ones wire
  # `on_close` to the same event so closing updates the variation's
  # assigns rather than walking the modal out of the DOM.
  def template do
    """
    <div>
      <button
        type="button"
        class="btn btn-sm btn-primary"
        phx-click={Phoenix.LiveView.JS.push("psb-assign", value: %{open: true})}
        psb-code-hidden
      >
        Open modal
      </button>
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [closed_variation() | Enum.map(content_variations(), &open_in_modal/1)]
  end

  # Every content variation shows an open modal and closes via
  # psb-assign, keeping the iframe's assigns in charge of visibility.
  defp open_in_modal(%Variation{id: id, attributes: attributes} = variation) do
    %{
      variation
      | attributes: Map.merge(attributes, %{open: true, on_close: close_event(id)})
    }
  end

  defp close_event(variation_id) do
    {:eval,
     ~s|Phoenix.LiveView.JS.push("psb-assign", value: %{variation_id: #{inspect(variation_id)}, open: false})|}
  end

  defp closed_variation do
    %Variation{
      id: :closed,
      description:
        "Closed state — the modal shell is in the DOM but visually hidden via " <>
          "`data-state=\"closed\"`, keeping the blur compositing layer warm. " <>
          "Click *Open modal* above to flip the assigns.",
      attributes: %{open: false, entity: nil}
    }
  end

  defp content_variations do
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
        id: :tv_series_all_collapsed,
        description:
          "`expanded_seasons: MapSet.new()` — every season collapsed to its " <>
            "header row. Since the 2026-08-05 auto-orient design this is no " <>
            "longer how a series in progress opens (the host seeds the current " <>
            "season from `Orientation.initial_expanded_seasons/1`); it is the " <>
            "**completed-series** state, where there is no next episode and the " <>
            "rows serve as a compact rewatch index. Play controls left, synopsis " <>
            "right (top-aligned, no rule), progress hairline on the hero's bottom " <>
            "edge. The PlayCard renders no progress row for TV.",
        attributes: Map.put(tv_series_attrs(), :expanded_seasons, MapSet.new())
      },
      %Variation{
        id: :tv_series_with_seasons,
        description:
          "`:tv_series` with two seasons. `expanded_seasons: MapSet.new([1])` " <>
            "expands season 1 into dense one-line episode rows (number · title · " <>
            "runtime · watched toggle — no synopsis, no thumbnail) + a " <>
            "missing-episode placeholder for the gap at episode 4. Season 2 stays " <>
            "collapsed showing only its header. The Resume CTA reads **Resume " <>
            "Episode 2** — driven by `resume_label_from_progress/2`. " <>
            "`seasons_view` is the typed `[%SeasonView{}]` contract.",
        attributes: tv_series_attrs()
      },
      %Variation{
        id: :tv_series_episode_details_open,
        description:
          "Same shape, with episode 3's disclosure open " <>
            "(`expanded_item_details` carrying its episode id) — the dense row " <>
            "grows an inline synopsis + thumbnail block beneath it. The chevron " <>
            "flips to point up and `aria-expanded` is true.",
        attributes:
          Map.put(
            tv_series_attrs(),
            :expanded_item_details,
            MapSet.new(["33333333-3333-3333-3333-3333000s01e03"])
          )
      },
      %Variation{
        id: :tv_series_all_episode_details_open,
        description:
          "Same shape, with the list-level episode-details toggle on " <>
            "(`all_episode_details_open: true`) — every episode row in the " <>
            "expanded season grows its inline synopsis + thumbnail block, and " <>
            "the toggle above the seasons reads **Hide details** " <>
            "(`aria-pressed=\"true\"`). Per-row disclosures stay independent " <>
            "underneath (ORed, not overwritten).",
        attributes: Map.put(tv_series_attrs(), :all_episode_details_open, true)
      },
      %Variation{
        id: :tv_series_spoiler_free,
        description:
          "Same library shape but `spoiler_free: true`. Unwatched episodes have " <>
            "their title `.spoiler-blur`'d in the dense row (and synopsis/thumbnail " <>
            "behind the disclosure); the leading episode number stays legible for " <>
            "navigation. Watched / current rows (episodes 1–2) render unblurred. " <>
            "Hover or keyboard focus on a row reveals it " <>
            "(`[data-role=\"episode-row\"]:hover`).",
        attributes: Map.put(tv_series_attrs(), :spoiler_free, true)
      },
      %Variation{
        id: :tv_series_with_upcoming_inline,
        description:
          "Same library shape as 3, but with three `%EpisodeListItem.Upcoming{}` " <>
            "rows mixed in: one fills the S1 episode-4 gap (replacing the missing " <>
            "row), one extends S1 past `number_of_episodes`, and one populates a " <>
            "future S2. All have `sub_status: :unaired` and `air_date` in the " <>
            "future, so the date pill reads \"in Xd\". The Upcoming row has " <>
            "no thumbnail, no watched toggle, and `data-nav-item` is omitted.",
        attributes: tv_series_with_upcoming_attrs()
      },
      %Variation{
        id: :tv_series_aired_not_in_library,
        description:
          "TV variation with one `%EpisodeListItem.Upcoming{sub_status: " <>
            ":aired_not_in_library}` carrying a past `air_date` — TMDB knows it " <>
            "aired but the file hasn't been imported. Pill copy reads " <>
            "\"aired Xd ago\" instead of the future-tense form.",
        attributes: tv_series_aired_not_in_library_attrs()
      },
      %Variation{
        id: :tv_series_only_future,
        description:
          "Library has one minimal season; releases project a synthetic " <>
            "`%SeasonView{kind: :future}` for an upcoming Season 2. The future " <>
            "season's header omits the watched-count copy (`watched_count: " <>
            "nil`) — only library seasons display \"X remaining\".",
        attributes: tv_series_only_future_attrs()
      },
      %Variation{
        id: :tv_series_untracked,
        description:
          "Same library shape as 3 but `tracking_status: nil`: the show isn't " <>
            "tracked in `ReleaseTracking`, so the bell affordance in the hero " <>
            "actions slot is absent and `seasons_view` carries no Upcoming items " <>
            "or future seasons. Confirms no-regression for the untracked case.",
        attributes: tv_series_untracked_attrs()
      },
      %Variation{
        id: :movie_series,
        description:
          "The movie-first collection modal (UIDR-023): the selected member " <>
            "(movie 2, in progress) renders the standalone-movie panel — saga " <>
            "eyebrow (\"… · Part 2 of 3\"), member synopsis, **Resume** with the " <>
            "member's own progress row and watched toggle — over the poster " <>
            "rail: watched check on movie 1, progress underline on the lit " <>
            "movie 2, dimmed movie 3. `movies_view` is the typed " <>
            "`[%MovieListItem{}]` contract the rail reads exclusively.",
        attributes: movie_series_attrs()
      },
      %Variation{
        id: :movie_series_with_upcoming,
        description:
          "Tracked collection with an announced fourth part: the " <>
            "`MovieListItem.Upcoming` tile renders muted and unpickable after " <>
            "the library members, with the air-date pill, and the eyebrow " <>
            "widens to \"Part 2 of 4\" (release-tracking overlay, same idiom " <>
            "as TV's upcoming episode rows).",
        attributes: movie_series_with_upcoming_attrs()
      },
      %Variation{
        id: :info_view_with_files,
        description:
          "`detail_view: :info` swaps the content list for the Manage sheet " <>
            "(`Detail.ManagePanel`): toolbar card (Delete all / Rematch / " <>
            "Refresh artwork, external IDs + UUID as its quiet lower edge) over " <>
            "the folder ledger. Three files ≤ the auto-expand threshold, so " <>
            "every group opens and the file rows (quality badges, `added Xd " <>
            "ago`, per-file delete) are visible. Files use `detail_files: " <>
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
        id: :info_view_collapsed_ledger,
        description:
          "A large inventory (8 files, two folders — above the auto-expand " <>
            "threshold) rests as collapsed folder summary rows: name, count, " <>
            "size, and a quiet Delete per row. Zero file rows at rest — the " <>
            "wall of rows is the thing this layout killed. " <>
            "`expanded_file_groups: nil` is the automatic default.",
        attributes: %{
          entity: sample_movie_entity(),
          progress: nil,
          resume: nil,
          progress_records: [],
          available: true,
          tmdb_ready: true,
          detail_view: :info,
          detail_files: sample_season_detail_files(),
          expanded_seasons: MapSet.new()
        }
      },
      %Variation{
        id: :rematch_confirm,
        description:
          "`rematch_confirm: true` — the **Rematch** action in the toolbar " <>
            "card flips to a confirm prompt (button copy and `btn-error` " <>
            "styling change). Captures the rematch-confirmation toggle state.",
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
        id: :delete_in_flight_all,
        description:
          "`deleting: :all` — the async delete is running (the gesture's third " <>
            "state, after idle → confirm). The prominent danger button reads " <>
            "**Deleting… Delete all files (size)** and every delete button on " <>
            "the panel is disabled so a second destructive op can't be stacked " <>
            "on the busy modal. Captures the feedback that replaced the silent " <>
            "process-blocking delete.",
        attributes: %{
          entity: sample_movie_entity(),
          progress: nil,
          resume: nil,
          progress_records: [],
          available: true,
          tmdb_ready: true,
          detail_view: :info,
          detail_files: sample_detail_files(),
          deleting: :all,
          expanded_seasons: MapSet.new()
        }
      },
      %Variation{
        id: :tv_series_cast_view,
        description:
          "`detail_view: :cast` on a TV series — opens the Cast panel: " <>
            "the aggregate-cast grid alone. The movie counterpart adds a " <>
            "Directed by / Written by headline above the grid.",
        attributes: Map.put(tv_series_attrs(), :detail_view, :cast)
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
      date_published: ~D[1922-09-04],
      duration_seconds: 5400,
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

  # Plain-map progress records mirror `MediaCentaur.Library.WatchProgress`
  # — all three foreign keys (`movie_id`, `episode_id`, `video_object_id`)
  # included with explicit `nil` for the unused ones, since plain maps
  # don't get the schema's struct defaults and the consuming code does
  # `record.episode_id` which would otherwise raise KeyError.
  defp movie_progress_record(movie_id, partial: true) do
    %{
      id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      movie_id: movie_id,
      episode_id: nil,
      video_object_id: nil,
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
    progress_records = sample_tv_progress_records(entity)

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
      tracking_status: :watching,
      expanded_seasons: MapSet.new([1]),
      seasons_view: build_library_only_seasons_view(entity, progress_records, {1, 2})
    }
  end

  # S1 has releases for the missing slot (episode 4, replaces the
  # Missing) and one episode beyond number_of_episodes (episode 6, the
  # season grows by one row). A second future season (S3) appears as
  # its own collapsible — episodes 1 and 2 unaired.
  defp tv_series_with_upcoming_attrs do
    base = tv_series_attrs()
    entity = base.entity

    [s1_view, s2_view] = base.seasons_view

    # Replace Missing(4) with Upcoming(4); add Upcoming(6) past
    # number_of_episodes.
    new_items =
      Enum.map(s1_view.items, fn
        %EpisodeListItem.Missing{episode_number: 4} ->
          %EpisodeListItem.Upcoming{
            season_number: 1,
            episode_number: 4,
            title: "The Far Hike",
            air_date: Date.add(Date.utc_today(), 7),
            sub_status: :unaired
          }

        other ->
          other
      end) ++
        [
          %EpisodeListItem.Upcoming{
            season_number: 1,
            episode_number: 6,
            title: "After the Snow",
            air_date: Date.add(Date.utc_today(), 21),
            sub_status: :unaired
          }
        ]

    s1_view = %{s1_view | items: new_items}

    s3_future = %SeasonView{
      season_number: 3,
      name: nil,
      kind: :future,
      items: [
        %EpisodeListItem.Upcoming{
          season_number: 3,
          episode_number: 1,
          title: "Spring Returns",
          air_date: Date.add(Date.utc_today(), 60),
          sub_status: :unaired
        },
        %EpisodeListItem.Upcoming{
          season_number: 3,
          episode_number: 2,
          title: "An Old Letter",
          air_date: Date.add(Date.utc_today(), 67),
          sub_status: :unaired
        }
      ],
      extras: [],
      watched_count: nil,
      total_count: 2
    }

    %{
      base
      | entity: entity,
        # Expand S1 + S3 to actually show the new rows.
        expanded_seasons: MapSet.new([1, 3]),
        seasons_view: [s1_view, s2_view, s3_future]
    }
  end

  defp tv_series_aired_not_in_library_attrs do
    base = tv_series_attrs()
    [s1_view, s2_view] = base.seasons_view

    # Replace S1's missing(4) slot with an aired-not-in-library upcoming
    # — air_date in the past. Pill copy reads "aired Xd ago".
    s1_view = %{
      s1_view
      | items:
          Enum.map(s1_view.items, fn
            %EpisodeListItem.Missing{episode_number: 4} ->
              %EpisodeListItem.Upcoming{
                season_number: 1,
                episode_number: 4,
                title: "The Quiet Hour",
                air_date: Date.add(Date.utc_today(), -3),
                sub_status: :aired_not_in_library
              }

            other ->
              other
          end)
    }

    %{base | seasons_view: [s1_view, s2_view]}
  end

  defp tv_series_only_future_attrs do
    entity =
      sample_tv_entity()
      |> Map.put(:seasons, [])
      |> Map.put(:number_of_seasons, 1)

    s1_future = %SeasonView{
      season_number: 1,
      name: nil,
      kind: :future,
      items: [
        %EpisodeListItem.Upcoming{
          season_number: 1,
          episode_number: 1,
          title: "Pilot",
          air_date: Date.add(Date.utc_today(), 14),
          sub_status: :unaired
        },
        %EpisodeListItem.Upcoming{
          season_number: 1,
          episode_number: 2,
          title: "The Letter",
          air_date: Date.add(Date.utc_today(), 21),
          sub_status: :unaired
        }
      ],
      extras: [],
      watched_count: nil,
      total_count: 2
    }

    %{
      entity: entity,
      progress: nil,
      resume: nil,
      progress_records: [],
      available: true,
      tmdb_ready: true,
      tracking_status: :watching,
      expanded_seasons: MapSet.new([1]),
      seasons_view: [s1_future]
    }
  end

  defp tv_series_untracked_attrs do
    base = tv_series_attrs()
    %{base | tracking_status: nil}
  end

  defp sample_tv_progress_records(entity) do
    season_one_episodes = entity.seasons |> Enum.at(0) |> Map.get(:episodes)
    [ep1, ep2 | _] = season_one_episodes

    [
      %{
        id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01",
        movie_id: nil,
        episode_id: ep1.id,
        video_object_id: nil,
        position_seconds: 0.0,
        duration_seconds: 1500.0,
        completed: true,
        last_watched_at: ~U[2026-04-28 21:00:00Z]
      },
      %{
        id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb02",
        movie_id: nil,
        episode_id: ep2.id,
        video_object_id: nil,
        position_seconds: 600.0,
        duration_seconds: 1500.0,
        completed: false,
        last_watched_at: ~U[2026-04-30 21:30:00Z]
      }
    ]
  end

  defp build_library_only_seasons_view(entity, progress_records, resume_episode_key) do
    progress_by_episode_id =
      progress_records
      |> Enum.filter(& &1.episode_id)
      |> Map.new(&{&1.episode_id, &1})

    Enum.map(entity.seasons, fn season ->
      build_library_season_view(season, progress_by_episode_id, resume_episode_key)
    end)
  end

  defp build_library_season_view(season, progress_by_episode_id, resume_episode_key) do
    items = build_library_items(season, progress_by_episode_id, resume_episode_key)
    watched = Enum.count(season.episodes, &watched?(&1, progress_by_episode_id))

    %SeasonView{
      season_number: season.season_number,
      name: season.name,
      kind: :library,
      items: items,
      extras: season.extras,
      watched_count: watched,
      total_count: max(length(season.episodes), season.number_of_episodes)
    }
  end

  defp build_library_items(season, progress_by_episode_id, resume_episode_key) do
    episode_map = Map.new(season.episodes, &{&1.episode_number, &1})
    upper = max(season.number_of_episodes, length(season.episodes))

    if upper == 0 do
      []
    else
      for n <- 1..upper do
        case Map.get(episode_map, n) do
          nil ->
            %EpisodeListItem.Missing{
              season_number: season.season_number,
              episode_number: n
            }

          episode ->
            progress = Map.get(progress_by_episode_id, episode.id)

            %EpisodeListItem.Library{
              episode: episode,
              season_number: season.season_number,
              progress: progress,
              state: episode_state(progress),
              is_resume_target: resume_episode_key == {season.season_number, episode.episode_number}
            }
        end
      end
    end
  end

  defp watched?(episode, progress_by_episode_id) do
    case Map.get(progress_by_episode_id, episode.id) do
      %{completed: true} -> true
      _ -> false
    end
  end

  defp episode_state(nil), do: :unwatched

  defp episode_state(%{completed: true}), do: :watched

  defp episode_state(%{position_seconds: pos}) when is_number(pos) and pos > 0.0, do: :current

  defp episode_state(_), do: :unwatched

  defp sample_tv_entity do
    %{
      id: @tv_id,
      type: :tv_series,
      name: "Quiet Sample Series",
      description:
        "An anthology of small stories from a sleepy town. Each episode " <>
          "follows a different resident through a single afternoon.",
      tagline: nil,
      date_published: ~D[1925-01-12],
      duration_seconds: nil,
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
      imdb_id: "tt0000200",
      cast:
        Enum.map(0..7, fn i ->
          %Person{
            name: "Sample Actor #{i + 1}",
            character: "Sample Role #{i + 1}",
            tmdb_person_id: 1000 + i,
            profile_path: nil,
            order: i
          }
        end),
      crew: [
        %Person{
          tmdb_person_id: 11,
          name: "Sample Creator A",
          job: "Creator",
          department: "Creator",
          profile_path: nil
        },
        %Person{
          tmdb_person_id: 12,
          name: "Sample Creator B",
          job: "Creator",
          department: "Creator",
          profile_path: nil
        }
      ],
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
      %{
        id: "cccccccc-cccc-cccc-cccc-cccccccccc01",
        movie_id: m1.id,
        episode_id: nil,
        video_object_id: nil,
        position_seconds: 0.0,
        duration_seconds: 5400.0,
        completed: true,
        last_watched_at: ~U[2026-04-20 21:00:00Z]
      },
      %{
        id: "cccccccc-cccc-cccc-cccc-cccccccccc02",
        movie_id: m2.id,
        episode_id: nil,
        video_object_id: nil,
        position_seconds: 1500.0,
        duration_seconds: 5700.0,
        completed: false,
        last_watched_at: ~U[2026-04-30 22:00:00Z]
      }
    ]

    [m1_item, m2_item, m3_item] = movie_series_items(entity, progress_records)

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
      movies_view: [m1_item, m2_item, m3_item],
      # The movie-first subject (UIDR-023): movie 2 selected — composed
      # through the same `member_subject/1` the live path uses, so the
      # story breaks when the composition contract does.
      member_view: %{
        member: m2_item,
        subject: MediaCentaurWeb.ViewModel.CollectionDetail.member_subject(m2_item),
        ordinal: {2, 3}
      },
      available: true,
      tmdb_ready: true,
      expanded_seasons: MapSet.new()
    }
  end

  defp movie_series_with_upcoming_attrs do
    base = movie_series_attrs()

    upcoming = %MovieListItem.Upcoming{
      part_tmdb_id: 900_004,
      title: "Sample Picture IV",
      air_date: Date.add(Date.utc_today(), 45),
      sub_status: :unaired
    }

    %{
      base
      | movies_view: base.movies_view ++ [upcoming],
        member_view: %{base.member_view | ordinal: {2, 4}}
    }
  end

  # Typed `MovieListItem.Library` fixtures mirroring what
  # `CollectionDetail.build/4` composes: movie 1 watched, movie 2
  # current + resume target, movie 3 unwatched.
  defp movie_series_items(entity, progress_records) do
    [m1, m2, m3] = entity.movies
    [p1, p2] = progress_records

    [
      %MovieListItem.Library{movie: m1, progress: p1, state: :watched, is_resume_target: false},
      %MovieListItem.Library{movie: m2, progress: p2, state: :current, is_resume_target: true},
      %MovieListItem.Library{movie: m3, progress: nil, state: :unwatched, is_resume_target: false}
    ]
  end

  defp sample_movie_series_entity do
    movies = [
      sample_child_movie(
        "55555555-5555-5555-5555-555555555501",
        "Sample Picture I",
        ~D[1920-05-01],
        5400,
        "/media/sample-picture-1.mkv",
        1,
        "The first chapter — a rumour leads three siblings into the hills."
      ),
      sample_child_movie(
        "55555555-5555-5555-5555-555555555502",
        "Sample Picture II",
        ~D[1922-07-10],
        5700,
        "/media/sample-picture-2.mkv",
        2,
        "A return to the same valley, years later."
      ),
      sample_child_movie(
        "55555555-5555-5555-5555-555555555503",
        "Sample Picture III",
        ~D[1925-11-04],
        6000,
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
      date_published: ~D[1920-05-01],
      duration_seconds: nil,
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
          media_dir: "/media/movies"
        },
        size: 4_294_967_296
      },
      %{
        file: %WatchedFile{
          id: "ffffffff-ffff-ffff-ffff-ffffffffff02",
          file_path: "/media/movies/Sample Movie (1922)/Sample.Movie.1922.1080p.subtitles.srt",
          media_dir: "/media/movies"
        },
        size: 32_768
      },
      %{
        file: %WatchedFile{
          id: "ffffffff-ffff-ffff-ffff-ffffffffff03",
          file_path: "/media/archive/Sample.Movie.1922.480p.legacy.mkv",
          media_dir: "/media/archive"
        },
        # `nil` size renders the "absent" badge — the file went missing
        # off disk after being indexed.
        size: nil
      }
    ]
  end

  # Eight files across two season folders — above the ledger's ≤6
  # auto-expand threshold, so the Manage sheet rests collapsed.
  defp sample_season_detail_files do
    for season <- 1..2, episode <- 1..4 do
      %{
        file: %WatchedFile{
          id: "ffffffff-ffff-ffff-ffff-fffffffff#{season}0#{episode}",
          file_path:
            "/media/tv/Sample Show/Season #{season}/Sample.Show.S0#{season}E0#{episode}.1080p.WEB-DL.mkv",
          media_dir: "/media/tv"
        },
        size: 183_500_800
      }
    end
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
      duration_seconds: 1500,
      content_url: "/media/quiet-sample/episode-#{episode_number}.mkv",
      images: []
    }
  end

  defp sample_child_movie(id, name, date_published, duration_seconds, content_url, position, description) do
    %{
      id: id,
      name: name,
      description: description,
      date_published: date_published,
      duration_seconds: duration_seconds,
      director: "Sample Director",
      content_url: content_url,
      position: position,
      genres: ["Adventure"],
      status: :released,
      images: []
    }
  end
end
