defmodule MediaCentaurWeb.Components.Detail.SeasonList do
  @moduledoc """
  The TV-series content list of the detail modal: the season accordion
  with its dense episode rows, gap/upcoming placeholders, per-season
  extras, and the list-level "Show details" toggle.

  Renders exclusively from the typed
  `[%MediaCentaurWeb.ViewModel.SeasonView{}]` list composed by
  `MediaCentaurWeb.ViewModel.SeriesDetail` — each `SeasonView` carries
  tagged `EpisodeListItem.{Library, Missing, Upcoming}` items the
  renderer pattern-matches on. No tuple ADTs, no shape-guessing.

  Row chrome (watched toggle, progress underline, state classes,
  spoiler-blur) comes from `Detail.PlayableRow`, shared with the
  collection list and extras so the row families can't drift.
  """

  use MediaCentaurWeb, :html

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)

  @storybook_status :skip
  @storybook_reason "State matrix pinned by the detail_panel story's TV variations, which render this list inside the layout that gives its states meaning; shared row chrome pinned by the PlayableRow stories. A standalone story would duplicate those fixtures verbatim."

  import MediaCentaurWeb.LiveHelpers
  import MediaCentaurWeb.Components.Detail.PlayableRow, only: [blur_spoilers?: 2, row_class: 2]

  alias MediaCentaurWeb.Components.Detail.ExtrasSection
  alias MediaCentaurWeb.Components.Detail.Logic
  alias MediaCentaurWeb.Components.Detail.PlayableRow
  alias MediaCentaurWeb.ViewModel.EpisodeListItem

  attr :seasons, :list,
    required: true,
    doc: "`[%MediaCentaurWeb.ViewModel.SeasonView{}]` from `SeriesDetail.compose/1`."

  attr :entity_id, :string, required: true
  attr :expanded_seasons, MapSet, required: true

  attr :expanded_item_details, MapSet,
    default: nil,
    doc: "leaf (episode) ids with open synopsis disclosures."

  attr :all_episode_details_open, :boolean,
    default: false,
    doc: "list-level episode-details toggle — ORed with `expanded_item_details` per row."

  attr :extras, :list,
    default: [],
    doc: "entity-level extras (pre-filtered via `Logic.entity_extras/1`), rendered after the seasons."

  attr :extra_progress_by_id, :map,
    default: %{},
    doc: "`%{Ecto.UUID.t() => WatchProgress.t()}` keyed by extra id."

  attr :on_play, :string, required: true
  attr :spoiler_free, :boolean, default: false
  attr :available, :boolean, default: true

  def season_list(assigns) do
    ~H"""
    <div :if={@seasons != []} class="pt-3 space-y-3">
      <%!-- Deliberately not a nav item: it belongs with the other list-wide
            controls in Manage rather than sitting in the middle of the
            keyboard path between the action row and the first season. Mouse
            only until it moves there. --%>
      <div class="flex justify-end">
        <button
          type="button"
          phx-click="toggle_all_episode_details"
          data-role="episode-details-toggle"
          aria-pressed={to_string(@all_episode_details_open)}
          class={[
            "flex items-center gap-1.5 text-xs cursor-pointer rounded-md px-2 py-1 -my-1 transition-colors hover:bg-base-content/10",
            if(@all_episode_details_open,
              do: "text-base-content/70",
              else: "text-base-content/55 hover:text-base-content/70"
            )
          ]}
        >
          <.icon name="hero-bars-3-bottom-left-mini" class="size-3.5" />
          {if @all_episode_details_open, do: "Hide details", else: "Show details"}
        </button>
      </div>
      <.season_section
        :for={season_view <- @seasons}
        season={season_view}
        expanded={MapSet.member?(@expanded_seasons, season_view.season_number)}
        expanded_item_details={@expanded_item_details}
        all_episode_details_open={@all_episode_details_open}
        extra_progress_by_id={@extra_progress_by_id}
        entity_id={@entity_id}
        on_play={@on_play}
        spoiler_free={@spoiler_free}
        available={@available}
      />
      <ExtrasSection.extras_section
        extras={@extras}
        extra_progress_by_id={@extra_progress_by_id}
        entity_id={@entity_id}
        on_play={@on_play}
      />
    </div>
    """
  end

  # --- Season Section ---

  attr :season, :map,
    required: true,
    doc: "`%MediaCentaurWeb.ViewModel.SeasonView{}` — typed season bucket."

  attr :expanded, :boolean, required: true

  attr :expanded_item_details, MapSet,
    default: nil,
    doc: "leaf (episode) ids with open synopsis disclosures."

  attr :all_episode_details_open, :boolean, default: false

  attr :extra_progress_by_id, :map,
    default: %{},
    doc: "`%{Ecto.UUID.t() => WatchProgress.t()}` keyed by extra id."

  attr :entity_id, :string, required: true
  attr :on_play, :string, required: true
  attr :spoiler_free, :boolean, default: false
  attr :available, :boolean, default: true

  defp season_section(assigns) do
    ~H"""
    <%!-- `data-nav-group` marks the disclosure: LEFT anywhere inside collapses
          the season by finding this group's expanded head, which is also where
          the cursor lands (the rows it was standing on are about to go away).
          `aria-expanded` is the state — correct markup for a disclosure and the
          only signal the input system reads, so there is no parallel attribute
          saying the same thing. The id keeps morphdom from rebuilding the
          header across that patch, which would drop focus. --%>
    <div data-nav-group id={"season-#{@entity_id}-#{@season.season_number}"}>
      <button
        phx-click="toggle_season"
        phx-value-season={@season.season_number}
        aria-expanded={to_string(@expanded)}
        class="flex items-baseline gap-2 w-full text-sm font-medium text-base-content/70 hover:text-base-content cursor-pointer"
        data-nav-item
        tabindex="0"
      >
        <.icon
          name={if @expanded, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
          class="size-4 self-center"
        />
        <span>{@season.name || "Season #{@season.season_number}"}</span>
        <span class="flex-1" />
        <span
          :if={@season.kind == :library && !season_complete?(@season)}
          class="text-xs text-base-content/55 tabular-nums"
        >
          {season_progress_label(@season.watched_count, @season.total_count)}
        </span>
        <.icon
          :if={@season.kind == :library && season_complete?(@season)}
          name="hero-check-mini"
          class="size-3.5 self-center text-success"
        />
        <span :if={@season.kind == :future} class="text-xs text-base-content/55">
          upcoming
        </span>
      </button>

      <div :if={@expanded} class="mt-1">
        <.season_item
          :for={item <- @season.items}
          id={"episode-#{@entity_id}-#{@season.season_number}-#{item_episode_number(item)}"}
          item={item}
          details_open={
            @all_episode_details_open ||
              (match?(%EpisodeListItem.Library{}, item) &&
                 MapSet.member?(@expanded_item_details || MapSet.new(), item.episode.id))
          }
          entity_id={@entity_id}
          on_play={@on_play}
          spoiler_free={@spoiler_free}
          available={@available}
        />
        <ExtrasSection.extras_section
          extras={@season.extras}
          extra_progress_by_id={@extra_progress_by_id}
          entity_id={@entity_id}
          on_play={@on_play}
          class="pt-2"
        />
      </div>
    </div>
    """
  end

  # --- Season item dispatch ---
  #
  # Pattern-matches on the `EpisodeListItem` struct type. No tuple
  # ADTs, no shape-guessing — the typed contract IS the dispatch
  # criterion.

  attr :item, :map, required: true, doc: "%EpisodeListItem.{Library | Missing | Upcoming}{}"
  attr :details_open, :boolean, default: false
  attr :entity_id, :string, required: true
  attr :on_play, :string, required: true
  attr :spoiler_free, :boolean, default: false
  attr :available, :boolean, default: true

  attr :id, :string, required: true, doc: "stable DOM id for the row (UIDR-012)."

  defp season_item(%{item: %EpisodeListItem.Library{}} = assigns) do
    ~H"""
    <.episode_row
      id={@id}
      item={@item}
      details_open={@details_open}
      entity_id={@entity_id}
      on_play={@on_play}
      spoiler_free={@spoiler_free}
      available={@available}
    />
    """
  end

  defp season_item(%{item: %EpisodeListItem.Missing{}} = assigns) do
    ~H"""
    <.missing_episode_row id={@id} item={@item} />
    """
  end

  defp season_item(%{item: %EpisodeListItem.Upcoming{}} = assigns) do
    ~H"""
    <.upcoming_episode_row id={@id} item={@item} />
    """
  end

  # --- Episode Row ---

  attr :item, :map,
    required: true,
    doc: "`%MediaCentaurWeb.ViewModel.EpisodeListItem.Library{}` — typed library episode."

  attr :details_open, :boolean,
    default: false,
    doc: "whether the synopsis/thumbnail disclosure below the dense row is open."

  attr :entity_id, :string, required: true
  attr :on_play, :string, required: true
  attr :spoiler_free, :boolean, default: false
  attr :available, :boolean, default: true

  # Dense one-line row (2026-08-04 orientation design): number · title ·
  # runtime · watched toggle. Synopsis + thumbnail render only behind the
  # per-row disclosure — the list is an index, not a reading surface.
  attr :id, :string, required: true, doc: "stable DOM id for the row (UIDR-012)."

  defp episode_row(assigns) do
    assigns =
      assigns
      |> assign(:episode, assigns.item.episode)
      |> assign(:season_number, assigns.item.season_number)
      |> assign(:progress, assigns.item.progress)
      |> assign(:state, assigns.item.state)
      |> assign(:is_resume_target, assigns.item.is_resume_target)
      |> assign(:thumbnail, image_url(assigns.item.episode, "thumb"))

    ~H"""
    <div
      id={@id}
      class={[
        "px-2 py-1.5 rounded cursor-pointer hover:bg-base-content/5",
        row_class(@state, @is_resume_target)
      ]}
      data-role="episode-row"
      data-resume-target={@is_resume_target || nil}
      phx-click={@on_play}
      phx-value-id={@episode.id}
      data-nav-item
      tabindex="0"
    >
      <div class="flex items-center gap-3 text-sm">
        <span class={[
          "w-6 flex-shrink-0 text-right font-mono text-xs tabular-nums",
          if(@is_resume_target, do: "text-primary font-semibold", else: "text-base-content/55")
        ]}>
          {@episode.episode_number}
        </span>
        <span class={[
          "flex-1 min-w-0 truncate text-base-content/90",
          blur_spoilers?(@spoiler_free, @state) && "spoiler-blur"
        ]}>
          {@episode.name || "—"}
        </span>
        <button
          :if={@episode.description || @thumbnail}
          type="button"
          phx-click="toggle_item_details"
          phx-value-item-id={@episode.id}
          data-nav-sub-item
          class="flex-shrink-0 p-1.5 -m-1 rounded-md cursor-pointer text-base-content/55 hover:text-base-content/70 hover:bg-base-content/10 transition-colors"
          aria-expanded={to_string(@details_open)}
          aria-label={if @details_open, do: "Hide episode details", else: "Show episode details"}
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
          duration_seconds={@episode.duration_seconds}
          phx-value-entity-id={@entity_id}
          phx-value-container-type="episode"
          phx-value-container-id={@episode.id}
        />
      </div>
      <div :if={@details_open} class="mt-2 ml-9 mb-1 flex items-start gap-3">
        <img
          :if={@thumbnail && @available}
          src={sized_image_url(@thumbnail, 240)}
          class={[
            "w-28 aspect-video rounded object-cover object-top flex-shrink-0",
            blur_spoilers?(@spoiler_free, @state) && "spoiler-blur"
          ]}
        />
        <p
          :if={@episode.description}
          class={[
            "text-xs text-base-content/55 leading-relaxed",
            blur_spoilers?(@spoiler_free, @state) && "spoiler-blur"
          ]}
        >
          {@episode.description}
        </p>
      </div>
      <PlayableRow.progress_underline :if={@state == :current} progress={@progress} class="ml-9" />
    </div>
    """
  end

  # --- Missing Episode Row ---

  attr :item, :map,
    required: true,
    doc: "`%MediaCentaurWeb.ViewModel.EpisodeListItem.Missing{}`"

  attr :id, :string, required: true, doc: "stable DOM id for the row (UIDR-012)."

  defp missing_episode_row(assigns) do
    ~H"""
    <div
      id={@id}
      class="p-2 rounded opacity-30"
      data-role="missing-episode-row"
      data-nav-item
      tabindex="0"
    >
      <div class="flex items-center gap-3 text-sm">
        <span class="w-6 flex-shrink-0 text-right text-base-content/55 font-mono text-xs tabular-nums">
          {@item.episode_number}
        </span>
        <span class="flex-1 min-w-0 truncate text-base-content/70 italic">
          Episode {@item.episode_number}
        </span>
      </div>
    </div>
    """
  end

  # --- Upcoming Episode Row ---
  #
  # Visual contract (per `defaults/storybook` `:tv_series_with_upcoming_inline`
  # and siblings): muted opacity, no thumbnail, no description, no
  # watched toggle, no `phx-click` (not actionable in v1). Right-side
  # date pill carries the air-date copy. `data-nav-item` is omitted —
  # the row isn't focusable until it becomes clickable.

  attr :item, :map,
    required: true,
    doc: "`%MediaCentaurWeb.ViewModel.EpisodeListItem.Upcoming{}`"

  attr :id, :string, required: true, doc: "stable DOM id for the row (UIDR-012)."

  defp upcoming_episode_row(assigns) do
    ~H"""
    <div id={@id} class="p-2 rounded opacity-60" data-role="upcoming-episode-row">
      <div class="flex items-center gap-3 text-sm">
        <span class="w-6 flex-shrink-0 text-right text-base-content/55 font-mono text-xs tabular-nums">
          {@item.episode_number}
        </span>
        <span class="flex-1 min-w-0 truncate text-base-content/70">
          {@item.title || "Episode #{@item.episode_number}"}
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

  # --- Helpers ---

  # A complete season shows only the check icon — no "watched" label
  # next to it (the label renders exclusively for incomplete seasons).
  defp season_complete?(%{watched_count: watched, total_count: total}),
    do: watched == total and (total || 0) > 0

  defp season_progress_label(watched, total), do: "#{total - watched} remaining"

  # The three item kinds carry the episode number in two places.
  defp item_episode_number(%{episode: %{episode_number: number}}), do: number
  defp item_episode_number(%{episode_number: number}), do: number
end
