defmodule MediaCentaurWeb.Components.Acquisition.PlanModal do
  @moduledoc """
  The plan-flow modal (UIDR-014): one continuous, URL-driven surface
  carrying a media-search request from targeting through approval —
  no wizard step-dots.

  Stages, driven by the host LiveView's `?plan=` param:

  * `:loading` — the targeting universe is being fetched.
  * `:targeting` — the series picker: quick-action presets, tri-state
    season rows, episode drill-in; in-library rows greyed (shown,
    never hidden), unaired rows inert.
  * `:movie_confirm` — the movie fast path: one card, two clicks.
  * `:board` — the live coverage board over the durable draft plan:
    unit cells in season rows (consecutive same-release cells fuse
    into a capsule — consolidation made visible), the chosen releases
    beneath with swap/exclude, gaps as an explicit warning row, and
    the approval footer. Refresh-safe by construction.
  * `:error` — targeting failed (TMDB unreachable etc.).

  Pure rendering; the host owns all state and events.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [format_size: 1]

  alias MediaCentaur.Acquisition.Targeting
  alias MediaCentaur.Acquisition.ViewModels.PlanBoard
  alias MediaCentaurWeb.AcquisitionLive.PlanLogic

  attr :open, :boolean, required: true

  attr :stage, :atom,
    default: :loading,
    values: [:loading, :targeting, :movie_confirm, :board, :error]

  attr :selection, :any,
    default: nil,
    doc: "%Targeting.Selection{} | nil — the picker's universe (targeting stage)."

  attr :chosen, :any,
    default: nil,
    doc: "MapSet of {season, episode} — the picker's chosen units (targeting stage)."

  attr :movie, :any,
    default: nil,
    doc: "%{tmdb_id, title, year, in_library?} | nil — the movie fast path's facts."

  attr :board, :any,
    default: nil,
    doc: "%PlanBoard{} | nil — the live coverage board (board stage)."

  attr :grab_future, :boolean, default: false
  attr :error, :string, default: nil, doc: "Targeting-stage failure copy (error stage)."

  attr :last_activity, :string,
    default: nil,
    doc: "Latest PlanEvents.SearchActivity line for the board's ticker, or nil."

  attr :alternatives, :any,
    default: nil,
    doc: "%{unit_id, items: [PlanBoard.Alternative.t()]} | nil — the open swap picker (board stage)."

  attr :on_close, :string, default: "close_plan"

  def plan_modal(assigns) do
    ~H"""
    <.modal id="plan-modal" open={@open} dismiss={:ephemeral} on_close={@on_close} data-plan-modal>
      <div class="flex-1 min-h-0 overflow-y-auto overflow-x-hidden thin-scrollbar">
        <div
          :if={@stage == :loading}
          class="p-10 flex items-center justify-center gap-3 text-sm text-base-content/50"
        >
          <span class="loading loading-spinner loading-sm"></span> Loading from TMDB…
        </div>

        <div :if={@stage == :error} class="p-8 text-center text-sm space-y-3">
          <p class="text-error">{@error || "Couldn't load this title from TMDB."}</p>
          <.button variant="dismiss" size="sm" phx-click={@on_close} data-nav-item tabindex="0">
            Close
          </.button>
        </div>

        <.targeting_stage
          :if={@stage == :targeting && @selection}
          selection={@selection}
          chosen={@chosen || MapSet.new()}
          grab_future={@grab_future}
          on_close={@on_close}
        />

        <.movie_stage :if={@stage == :movie_confirm && @movie} movie={@movie} on_close={@on_close} />

        <.board_stage
          :if={@stage == :board && @board}
          board={@board}
          alternatives={@alternatives}
          last_activity={@last_activity}
          on_close={@on_close}
        />
      </div>
    </.modal>
    """
  end

  # ---------------------------------------------------------------------------
  # Targeting stage
  # ---------------------------------------------------------------------------

  attr :selection, Targeting.Selection, required: true
  attr :chosen, :any, required: true, doc: "MapSet — typed at the public attr."
  attr :grab_future, :boolean, required: true
  attr :on_close, :string, required: true

  defp targeting_stage(assigns) do
    assigns = assign(assigns, :chosen_count, MapSet.size(assigns.chosen))

    ~H"""
    <div class="flex flex-col max-h-full">
      <div class="p-6 pb-4 space-y-4">
        <div class="flex items-baseline justify-between gap-3">
          <div class="min-w-0">
            <h2 class="text-2xl font-semibold truncate">
              {@selection.title}
              <.badge :if={@selection.tracked?} variant="warning" size="xs" class="ml-2 align-middle">
                Tracked
              </.badge>
            </h2>
            <p class="text-sm text-base-content/50 mt-1">{selection_meta(@selection)}</p>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <.button
            variant="neutral"
            size="sm"
            phx-click="plan_preset"
            phx-value-preset="everything_aired"
            data-nav-item
            tabindex="0"
          >
            Everything aired
          </.button>
          <.button
            variant="neutral"
            size="sm"
            phx-click="plan_preset"
            phx-value-preset="continue"
            data-nav-item
            tabindex="0"
          >
            Continue from my library
          </.button>
          <.button
            variant="neutral"
            size="sm"
            phx-click="plan_preset"
            phx-value-preset="latest_season"
            data-nav-item
            tabindex="0"
          >
            Latest season
          </.button>
          <span class="ml-auto text-sm text-base-content/50 tabular-nums">
            {@chosen_count} selected
          </span>
        </div>

        <div class="space-y-2">
          <.season_row
            :for={season <- @selection.seasons}
            season={season}
            selection={@selection}
            chosen={@chosen}
          />
        </div>
      </div>

      <div class="border-t border-base-content/10 px-6 py-4 flex items-center justify-between gap-4">
        <label class="flex items-center gap-2 text-sm text-base-content/70 cursor-pointer">
          <input
            type="checkbox"
            checked={@grab_future}
            class="checkbox checkbox-sm checkbox-primary"
            phx-click="plan_toggle_grab_future"
            data-nav-item
            tabindex="0"
          />
          <span>
            Also grab future episodes
            <span class="block text-[11px] text-base-content/40">hands off to release tracking</span>
          </span>
        </label>
        <div class="flex items-center gap-2">
          <.button variant="dismiss" size="sm" phx-click={@on_close} data-nav-item tabindex="0">
            Cancel
          </.button>
          <.button
            variant="primary"
            size="sm"
            phx-click="plan_create"
            aria-disabled={to_string(@chosen_count == 0)}
            class={@chosen_count == 0 && "opacity-50"}
            data-nav-item
            tabindex="0"
          >
            Plan {@chosen_count} {if @chosen_count == 1, do: "episode", else: "episodes"}
          </.button>
        </div>
      </div>
    </div>
    """
  end

  attr :season, Targeting.Season, required: true
  attr :selection, Targeting.Selection, required: true
  attr :chosen, :any, required: true, doc: "MapSet — typed at the public attr."

  defp season_row(assigns) do
    assigns =
      assign(assigns, :state, PlanLogic.season_state(assigns.chosen, assigns.selection, assigns.season))

    ~H"""
    <div class={["glass-inset rounded-lg", @state == :disabled && "opacity-50"]}>
      <div class="flex items-center gap-3 px-3 py-2">
        <.tri_checkbox
          state={@state}
          phx-click="plan_toggle_season"
          phx-value-season={@season.season_number}
        />
        <span class="text-sm font-medium">Season {@season.season_number}</span>
        <span class="text-sm text-base-content/40">{season_meta(@season)}</span>
      </div>
      <ul :if={@state != :disabled} class="border-t border-base-content/5">
        <li
          :for={episode <- @season.episodes}
          id={"plan-episode-#{episode.season_number}-#{episode.episode_number}"}
          class={[
            "flex items-baseline gap-3 pl-9 pr-3 py-1.5",
            (!episode.aired? || episode.in_library?) && "opacity-40"
          ]}
        >
          <.tri_checkbox
            :if={episode.aired? && !episode.in_library?}
            state={
              if MapSet.member?(@chosen, {episode.season_number, episode.episode_number}),
                do: :checked,
                else: :unchecked
            }
            small
            phx-click="plan_toggle_unit"
            phx-value-season={episode.season_number}
            phx-value-episode={episode.episode_number}
          />
          <span :if={!episode.aired? || episode.in_library?} class="w-4 flex-shrink-0"></span>
          <span class="min-w-0 flex-1 truncate text-sm">
            E{String.pad_leading(to_string(episode.episode_number), 2, "0")} · {episode.label}
          </span>
          <span :if={episode.in_library?} class="flex-shrink-0 text-xs text-base-content/40">
            In library
          </span>
          <span :if={!episode.aired?} class="flex-shrink-0 text-xs text-base-content/40">
            Unaired
          </span>
          <span
            :if={episode.aired? && !episode.in_library? && episode.air_date}
            class="flex-shrink-0 text-xs text-base-content/30 tabular-nums"
          >
            {episode.air_date}
          </span>
        </li>
      </ul>
    </div>
    """
  end

  attr :state, :atom,
    required: true,
    doc:
      ":checked | :indeterminate | :unchecked | :disabled — the closed set PlanLogic.season_state/3 returns; private component, exercised through the targeting variation."

  attr :small, :boolean, default: false

  attr :rest, :global,
    doc: "phx-click/phx-value-* passthrough — the checkbox is a dumb button; callers own the event."

  defp tri_checkbox(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "flex-shrink-0 rounded border flex items-center justify-center transition-colors",
        @small && "w-4 h-4",
        !@small && "w-[18px] h-[18px]",
        @state in [:checked, :indeterminate] && "bg-primary/80 border-primary",
        @state == :unchecked && "border-base-content/30 hover:border-base-content/60",
        @state == :disabled && "border-base-content/15"
      ]}
      disabled={@state == :disabled}
      data-nav-item
      tabindex="0"
      {@rest}
    >
      <.icon :if={@state == :checked} name="hero-check-mini" class="size-3 text-base-100" />
      <.icon :if={@state == :indeterminate} name="hero-minus-mini" class="size-3 text-base-100" />
    </button>
    """
  end

  # ---------------------------------------------------------------------------
  # Movie stage
  # ---------------------------------------------------------------------------

  attr :movie, :map,
    required: true,
    doc: "%{tmdb_id, title, year, in_library?} — assembled by the host LiveView."

  attr :on_close, :string, required: true

  defp movie_stage(assigns) do
    ~H"""
    <div class="p-6 space-y-4">
      <div class="flex items-center gap-4">
        <span class="flex-shrink-0 w-14 h-[84px] rounded-lg bg-base-content/10 flex items-center justify-center">
          <.icon name="hero-film" class="size-6 text-base-content/25" />
        </span>
        <div class="min-w-0">
          <h2 class="text-2xl font-semibold truncate">{@movie.title}</h2>
          <p class="text-xs text-base-content/50 mt-1">
            <.badge variant="type" size="xs">Movie</.badge>
            <span :if={@movie.year} class="ml-2">{@movie.year}</span>
          </p>
          <p class="text-sm mt-2 text-base-content/60">
            {if @movie.in_library?, do: "Already in your library.", else: "Not in your library."}
          </p>
        </div>
      </div>

      <div class="flex items-center justify-end gap-2 pt-2 border-t border-base-content/10">
        <.button variant="dismiss" size="sm" phx-click={@on_close} data-nav-item tabindex="0">
          Cancel
        </.button>
        <.button
          variant="primary"
          size="sm"
          phx-click="plan_create"
          aria-disabled={to_string(@movie.in_library?)}
          class={@movie.in_library? && "opacity-50"}
          data-nav-item
          tabindex="0"
        >
          Plan it
        </.button>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Board stage
  # ---------------------------------------------------------------------------

  attr :board, PlanBoard, required: true

  attr :alternatives, :any,
    required: true,
    doc: "%{unit_id, items} | nil — typed at the public attr."

  attr :last_activity, :string, required: true
  attr :on_close, :string, required: true

  defp board_stage(assigns) do
    ~H"""
    <div class="flex flex-col max-h-full">
      <div class="p-6 pb-4 space-y-4">
        <div>
          <h2 class="text-2xl font-semibold truncate">{@board.title}</h2>
          <p class="text-sm mt-1">
            <span :if={@board.status == :planning} class="text-base-content/50">
              <span class="loading loading-spinner loading-xs align-middle mr-1"></span>
              Planning · {@board.wanted} {if @board.movie?, do: "unit", else: "episodes"} wanted
            </span>
            <span :if={@board.status == :ready} class="text-info">
              Plan ready · {@board.covered} of {@board.wanted} covered
            </span>
            <span :if={@board.status == :committed} class="text-success">
              Committed — the pursuit has taken over.
            </span>
          </p>
        </div>

        <div :if={!@board.movie?} class="space-y-2">
          <div :for={season <- @board.seasons} class="flex items-start gap-3">
            <span class="flex-shrink-0 w-10 pt-2 text-sm text-base-content/40 tabular-nums">
              S{season.season_number}
            </span>
            <div class="flex flex-wrap items-center gap-1">
              <%= for run <- PlanLogic.cell_runs(season.cells) do %>
                <div
                  :if={match?({:capsule, _, _}, run)}
                  class="flex gap-px rounded-lg border border-primary/60 bg-primary/10 p-0.5"
                  title={run |> elem(2) |> hd() |> Map.get(:release_title)}
                >
                  <.board_cell :for={cell <- elem(run, 2)} cell={cell} in_capsule />
                </div>
                <.board_cell :if={match?({:cell, _}, run)} cell={elem(run, 1)} />
              <% end %>
            </div>
          </div>
        </div>

        <div :if={@board.releases != []} class="space-y-1.5">
          <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
            Releases — {length(@board.releases)}
          </h3>
          <div :for={release <- @board.releases} class="space-y-1.5">
            <div
              id={"plan-release-#{release.swap_unit_id}"}
              class="glass-inset rounded-lg px-3 py-2 flex items-center gap-3"
            >
              <.badge :if={release.scope_label} variant="ghost" size="xs" class="flex-shrink-0">
                {release.scope_label}
              </.badge>
              <span
                class="min-w-0 flex-1 truncate font-mono text-[13px] text-base-content/60"
                title={release.title}
              >
                {release.title}
              </span>
              <.badge :if={release.quality} variant="info" size="xs" class="flex-shrink-0">
                {release.quality}
              </.badge>
              <span :if={release.seeders} class="flex-shrink-0 text-sm text-success/80 tabular-nums">
                ▲ {release.seeders}
              </span>
              <span
                :if={release.size_bytes}
                class="flex-shrink-0 text-sm text-base-content/50 tabular-nums"
              >
                {format_size(release.size_bytes)}
              </span>
              <.button
                :if={@board.status == :ready}
                variant="neutral"
                size="xs"
                class="flex-shrink-0"
                phx-click={
                  if @alternatives && @alternatives.unit_id == release.swap_unit_id,
                    do: "plan_hide_alternatives",
                    else: "plan_show_alternatives"
                }
                phx-value-unit-id={release.swap_unit_id}
                title="See the other options for this"
                data-nav-item
                tabindex="0"
              >
                Options
              </.button>
            </div>

            <.alternatives_panel
              :if={@alternatives && @alternatives.unit_id == release.swap_unit_id}
              alternatives={@alternatives}
              release={release}
            />
          </div>
        </div>

        <div
          :if={@board.status == :ready && @board.gaps != []}
          class="glass-inset rounded-lg px-3 py-2 border border-warning/30 flex items-center gap-3"
        >
          <.icon name="hero-exclamation-triangle-mini" class="size-4 text-warning flex-shrink-0" />
          <span class="min-w-0 flex-1 text-sm text-warning/90 truncate">
            {length(@board.gaps)} not available right now — {Enum.join(@board.gaps, ", ")}
          </span>
          <.button
            variant="neutral"
            size="xs"
            phx-click="plan_search_again"
            data-nav-item
            tabindex="0"
          >
            Search again
          </.button>
        </div>

        <p :if={@board.error} class="text-xs text-error/80">{@board.error}</p>
        <p :if={@last_activity} class="text-sm text-base-content/40">{@last_activity}</p>
      </div>

      <div class="border-t border-base-content/10 px-6 py-4 flex items-center justify-between gap-4">
        <span class="text-sm text-base-content/50 tabular-nums">
          {@board.covered} of {@board.wanted} covered · {length(@board.releases)}
          {if length(@board.releases) == 1, do: "release", else: "releases"}
          <span :if={@board.total_size_bytes}>· ≈ {format_size(@board.total_size_bytes)}</span>
        </span>
        <div class="flex items-center gap-2">
          <.button
            :if={@board.status in [:planning, :ready]}
            variant="dismiss"
            size="sm"
            phx-click="plan_discard"
            data-nav-item
            tabindex="0"
          >
            Discard
          </.button>
          <.button
            :if={@board.status == :ready && @board.releases != []}
            variant="primary"
            size="sm"
            phx-click="plan_approve"
            data-nav-item
            tabindex="0"
          >
            Approve & grab {length(@board.releases)}
            {if length(@board.releases) == 1, do: "release", else: "releases"}
          </.button>
        </div>
      </div>
    </div>
    """
  end

  attr :alternatives, :map, required: true, doc: "%{unit_id, items} — typed at the public attr."
  attr :release, PlanBoard.Release, required: true

  defp alternatives_panel(assigns) do
    ~H"""
    <div class="glass-inset rounded-lg px-3 py-2 ml-4 space-y-1.5 border border-base-content/10">
      <p :if={@alternatives.items == []} class="text-xs text-base-content/40 py-1">
        Nothing else in the corpus right now — try a re-search.
      </p>

      <div
        :for={alternative <- @alternatives.items}
        id={"plan-alternative-#{@alternatives.unit_id}-#{:erlang.phash2(alternative.guid)}"}
        class="flex items-center gap-3"
      >
        <.badge :if={alternative.scope_label} variant="ghost" size="xs" class="flex-shrink-0">
          {alternative.scope_label}
        </.badge>
        <span
          class="min-w-0 flex-1 truncate font-mono text-[13px] text-base-content/60"
          title={alternative.title}
        >
          {alternative.title}
        </span>
        <span
          :if={alternative.suspicious?}
          class="flex-shrink-0 text-[10px] uppercase tracking-wider text-error/80"
          title="The release name looks like executable bait — only grab it if you're sure."
        >
          ⚠ looks fake
        </span>
        <.badge :if={alternative.quality} variant="info" size="xs" class="flex-shrink-0">
          {alternative.quality}
        </.badge>
        <span :if={alternative.seeders} class="flex-shrink-0 text-sm text-success/80 tabular-nums">
          ▲ {alternative.seeders}
        </span>
        <span
          :if={alternative.size_bytes}
          class="flex-shrink-0 text-sm text-base-content/50 tabular-nums"
        >
          {format_size(alternative.size_bytes)}
        </span>
        <.button
          variant="neutral"
          size="xs"
          class="flex-shrink-0"
          phx-click="plan_choose_release"
          phx-value-unit-id={@alternatives.unit_id}
          phx-value-guid={alternative.guid}
          data-nav-item
          tabindex="0"
        >
          Choose
        </.button>
      </div>

      <div class="flex items-center justify-end gap-2 pt-1 border-t border-base-content/5">
        <.button
          variant="dismiss"
          size="xs"
          phx-click="plan_swap_release"
          phx-value-unit-id={@alternatives.unit_id}
          phx-value-guid={@release.guid}
          title="Exclude this release everywhere and let the planner re-solve"
          data-nav-item
          tabindex="0"
        >
          None of these — re-solve
        </.button>
        <.button variant="dismiss" size="xs" phx-click="plan_search_again" data-nav-item tabindex="0">
          Search again
        </.button>
      </div>
    </div>
    """
  end

  attr :cell, PlanBoard.Cell, required: true
  attr :in_capsule, :boolean, default: false

  defp board_cell(assigns) do
    ~H"""
    <span
      id={"plan-cell-#{@cell.plan_unit_id}"}
      title={cell_title(@cell)}
      class={[
        "w-9 h-9 rounded-md flex items-center justify-center text-[13px] tabular-nums select-none",
        @cell.state == :searching &&
          "border border-dashed border-base-content/25 text-base-content/40 animate-pulse",
        @cell.state == :assigned && !@in_capsule &&
          "bg-primary/25 border border-primary/60 text-base-content/80",
        @cell.state == :assigned && @in_capsule && "bg-primary/20 text-base-content/80 rounded",
        @cell.state == :unfound && "border border-warning/50 text-warning/80",
        @cell.state == :excluded && "bg-base-content/5 text-base-content/25 line-through"
      ]}
    >
      {@cell.episode_number}
    </span>
    """
  end

  # ---------------------------------------------------------------------------

  defp cell_title(%PlanBoard.Cell{release_title: title} = cell) when is_binary(title),
    do: "#{cell.label} — #{title}"

  defp cell_title(%PlanBoard.Cell{state: :searching} = cell), do: "#{cell.label} — searching"
  defp cell_title(%PlanBoard.Cell{state: :unfound} = cell), do: "#{cell.label} — not available"
  defp cell_title(%PlanBoard.Cell{} = cell), do: cell.label

  defp selection_meta(%Targeting.Selection{} = selection) do
    aired = selection.seasons |> Enum.flat_map(& &1.episodes) |> Enum.count(& &1.aired?)
    owned = selection.seasons |> Enum.flat_map(& &1.episodes) |> Enum.count(& &1.in_library?)

    base = "#{aired} aired"
    if owned > 0, do: "#{base} · #{owned} already in your library", else: base
  end

  defp season_meta(%Targeting.Season{episodes: episodes}) do
    aired = Enum.count(episodes, & &1.aired?)

    if aired == 0 do
      "not yet aired"
    else
      "#{aired} aired"
    end
  end
end
