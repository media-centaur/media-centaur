defmodule MediaCentaurWeb.Components.Detail.CollectionList do
  @moduledoc """
  The movie-collection content list of the detail modal: dense member
  rows (poster + synopsis behind a per-row disclosure), muted upcoming
  rows for announced parts of a tracked collection, and entity-level
  extras.

  Renders exclusively from the typed
  `[%MediaCentaurWeb.ViewModel.MovieListItem{}]` list composed by
  `MediaCentaurWeb.ViewModel.CollectionDetail` — tagged
  `MovieListItem.{Library, Upcoming}` items the renderer
  pattern-matches on. The collection counterpart of
  `Detail.SeasonList`.

  Row chrome (watched toggle, progress underline, state classes,
  spoiler-blur) comes from `Detail.PlayableRow`, shared with the season
  list and extras so the row families can't drift.
  """

  use MediaCentaurWeb, :html

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)

  @storybook_status :skip
  @storybook_reason "State matrix pinned by the detail_panel story's movie_series variations, which render this list inside the layout that gives its states meaning; shared row chrome pinned by the PlayableRow stories. A standalone story would duplicate those fixtures verbatim."

  import MediaCentaurWeb.LiveHelpers
  import MediaCentaurWeb.LibraryFormatters, only: [extract_year: 1]
  import MediaCentaurWeb.Components.Detail.PlayableRow, only: [blur_spoilers?: 2, row_class: 2]

  alias MediaCentaurWeb.Components.Detail.ExtrasSection
  alias MediaCentaurWeb.Components.Detail.Logic
  alias MediaCentaurWeb.Components.Detail.PlayableRow
  alias MediaCentaurWeb.ViewModel.MovieListItem

  attr :movie_items, :list,
    required: true,
    doc: "`[%MediaCentaurWeb.ViewModel.MovieListItem{}]` from `CollectionDetail.compose/1`."

  attr :expanded_movie_details, MapSet,
    default: nil,
    doc: "movie ids of rows whose synopsis/poster disclosure is open."

  attr :entity_id, :string, required: true

  attr :extras, :list,
    default: [],
    doc: "entity-level extras (pre-filtered via `Logic.entity_extras/1`), rendered after the movies."

  attr :extra_progress_by_id, :map,
    default: %{},
    doc: "`%{Ecto.UUID.t() => WatchProgress.t()}` keyed by extra id."

  attr :on_play, :string, required: true
  attr :spoiler_free, :boolean, default: false
  attr :available, :boolean, default: true

  def collection_list(assigns) do
    assigns =
      assign(assigns, :expanded_movie_details, assigns.expanded_movie_details || MapSet.new())

    ~H"""
    <div class="pt-3">
      <div :if={@movie_items != []}>
        <.collection_item
          :for={item <- @movie_items}
          item={item}
          details_open={
            match?(%MovieListItem.Library{}, item) &&
              MapSet.member?(@expanded_movie_details, item.movie.id)
          }
          entity_id={@entity_id}
          on_play={@on_play}
          spoiler_free={@spoiler_free}
          available={@available}
        />
      </div>
      <ExtrasSection.extras_section
        extras={@extras}
        extra_progress_by_id={@extra_progress_by_id}
        entity_id={@entity_id}
        on_play={@on_play}
      />
    </div>
    """
  end

  # --- Collection item dispatch ---
  #
  # Pattern-matches on the `MovieListItem` struct type, mirroring
  # `SeasonList.season_item/1` — the typed contract IS the dispatch
  # criterion.

  attr :item, :map, required: true, doc: "%MovieListItem.{Library | Upcoming}{}"
  attr :details_open, :boolean, default: false
  attr :entity_id, :string, required: true
  attr :on_play, :string, required: true
  attr :spoiler_free, :boolean, default: false
  attr :available, :boolean, default: true

  defp collection_item(%{item: %MovieListItem.Library{}} = assigns) do
    ~H"""
    <.movie_row
      item={@item}
      details_open={@details_open}
      entity_id={@entity_id}
      on_play={@on_play}
      spoiler_free={@spoiler_free}
      available={@available}
    />
    """
  end

  defp collection_item(%{item: %MovieListItem.Upcoming{}} = assigns) do
    ~H"""
    <.upcoming_movie_row item={@item} />
    """
  end

  # --- Movie Row ---

  attr :item, :map,
    required: true,
    doc: "`%MediaCentaurWeb.ViewModel.MovieListItem.Library{}` — typed member movie."

  attr :details_open, :boolean,
    default: false,
    doc: "whether the synopsis/poster disclosure below the dense row is open."

  attr :entity_id, :string, required: true
  attr :on_play, :string, required: true
  attr :spoiler_free, :boolean, default: false
  attr :available, :boolean, default: true

  # Dense one-line row in the episode-row idiom: title · year · runtime ·
  # disclosure chevron · watched toggle. Poster and synopsis render only
  # behind the per-row disclosure — the list is an index, not a reading
  # surface.
  defp movie_row(assigns) do
    assigns =
      assigns
      |> assign(:movie, assigns.item.movie)
      |> assign(:state, assigns.item.state)
      |> assign(:progress, assigns.item.progress)
      |> assign(:is_resume_target, assigns.item.is_resume_target)
      |> assign(:thumbnail, image_url(assigns.item.movie, "poster"))
      # `description` / `duration_seconds` are optional display fields —
      # read via `Map.get` so a Movie struct and the projection map both
      # work without a `KeyError` crashing the whole panel render.
      |> assign(:description, Map.get(assigns.item.movie, :description))
      |> assign(:duration_seconds, Map.get(assigns.item.movie, :duration_seconds))

    ~H"""
    <div
      id={"movie-row-#{@movie.id}"}
      class={[
        "px-2 py-1.5 rounded cursor-pointer hover:bg-base-content/5",
        row_class(@state, @is_resume_target)
      ]}
      data-role="movie-row"
      data-resume-target={@is_resume_target || nil}
      phx-click={@on_play}
      phx-value-id={@movie.id}
      data-nav-item
      tabindex="0"
    >
      <div class="flex items-center gap-3 text-sm">
        <span class="flex-1 min-w-0 truncate text-base-content/90">
          {@movie.name || "—"}
          <span :if={@movie.date_published} class="text-base-content/50 ml-1">
            ({extract_year(@movie.date_published)})
          </span>
        </span>
        <button
          :if={@description || @thumbnail}
          type="button"
          phx-click="toggle_movie_details"
          phx-value-movie-id={@movie.id}
          data-nav-sub-item
          class="flex-shrink-0 p-1.5 -m-1 rounded-md cursor-pointer text-base-content/30 hover:text-base-content/70 hover:bg-base-content/10 transition-colors"
          aria-expanded={to_string(@details_open)}
          aria-label={if @details_open, do: "Hide movie details", else: "Show movie details"}
        >
          <.icon
            name={if @details_open, do: "hero-chevron-up-mini", else: "hero-chevron-down-mini"}
            class="size-4"
          />
        </button>
        <PlayableRow.watched_toggle
          event="toggle_watched"
          state={@state}
          progress={@progress}
          duration_seconds={@duration_seconds}
          phx-value-entity-id={@entity_id}
          phx-value-container-type="movie"
          phx-value-container-id={@movie.id}
        />
      </div>
      <div :if={@details_open} class="mt-2 mb-1 flex items-start gap-3">
        <img
          :if={@thumbnail && @available}
          src={sized_image_url(@thumbnail, 160)}
          class="w-16 aspect-[2/3] rounded object-cover flex-shrink-0"
        />
        <p
          :if={@description}
          class={[
            "text-xs text-base-content/50 leading-relaxed",
            blur_spoilers?(@spoiler_free, @state) && "spoiler-blur"
          ]}
        >
          {@description}
        </p>
      </div>
      <PlayableRow.progress_underline :if={@state == :current} progress={@progress} />
    </div>
    """
  end

  # --- Upcoming Movie Row ---
  #
  # An announced collection part (release-tracking overlay). Same visual
  # contract as the upcoming episode row: muted, no thumbnail, no watched
  # toggle, no `phx-click` (not actionable), right-side date pill. Not
  # focusable until it becomes clickable.

  attr :item, :map,
    required: true,
    doc: "`%MediaCentaurWeb.ViewModel.MovieListItem.Upcoming{}`"

  defp upcoming_movie_row(assigns) do
    ~H"""
    <div
      id={"upcoming-movie-#{@item.part_tmdb_id}"}
      class="p-2 rounded opacity-60"
      data-role="upcoming-movie-row"
    >
      <div class="flex items-center gap-3 text-sm">
        <div class="w-12 flex-shrink-0 flex justify-center">
          <.icon name="hero-film-mini" class="size-4 text-base-content/30" />
        </div>
        <span class="flex-1 min-w-0 truncate text-base-content/70">
          {@item.title || "—"}
        </span>
        <div class="flex items-center gap-2 flex-shrink-0">
          <.badge variant="ghost" size="sm" class="gap-1">
            <.icon name="hero-calendar-mini" class="size-3" />
            {Logic.upcoming_pill_copy(@item)}
          </.badge>
        </div>
      </div>
    </div>
    """
  end
end
