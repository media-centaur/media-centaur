defmodule MediaCentaurWeb.Components.Acquisition.PlanLine do
  @moduledoc """
  One line of the plan board's manifest (UIDR-029 as amended
  2026-11-06): a release with the episode cells it covers, or a group of
  cells sharing one outcome with that outcome's decision at the line's
  end. The board is the list of these; every episode appears once, in
  the line that explains it.

  A release line draws the release's facts (`ReleaseFacts`) with
  *Options* and ✕ on a ready board, its duplicate-data warning when it
  has one (*Remove it & re-solve*), and its cells as one capsule. An
  outcome line draws its sentence, its decision — *Show them* · *Take
  lower quality for this show*, *Search again* (and *Show them anyway*
  for a movie's rejected world), *Grab the pack* — and its cells by
  season. A coloured edge marks a line that carries a decision; a
  release line and the dropped line have none. A movie's lines show no
  cells.

  Each line is one `data-nav-item` of the `plan_lines` TREE; its
  controls and then its cells are `data-nav-sub-item`s, so RIGHT reaches
  the common controls first. A cell is the per-episode control: pressing
  it drops the episode from the plan or puts it back; its tip is the
  episode's label through the app tooltip.

  Pure rendering; the host owns every event.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [format_size: 1]

  alias MediaCentaur.Acquisition.ViewModels.PlanBoard
  alias MediaCentaurWeb.Components.Acquisition.CellVocabulary
  alias MediaCentaurWeb.Components.Acquisition.ReleaseFacts

  attr :line, PlanBoard.Line, required: true

  attr :ready?, :boolean,
    required: true,
    doc: "the board is ready — the lines carry their controls; while planning they carry none"

  attr :movie?, :boolean, required: true, doc: "a movie's line draws no cells"

  attr :picker_open, :boolean,
    default: false,
    doc: "the release picker is open under this line — Options / Show them read Hide"

  attr :rejectable?, :boolean,
    default: false,
    doc:
      "the not-found line of a movie whose gap verdict is the rejected world (UIDR-022): " <>
        "offers Show them anyway"

  def plan_line(assigns) do
    ~H"""
    <div
      id={"plan-line-#{@line.id}"}
      data-plan-line={@line.kind}
      data-nav-item
      tabindex="0"
      class={[
        "glass-inset rounded-lg px-4 py-3 space-y-2 border",
        edge(@line.kind)
      ]}
    >
      <.release_facts_row
        :if={@line.kind == :release}
        line={@line}
        ready?={@ready?}
        picker_open={@picker_open}
      />
      <.outcome_row
        :if={@line.kind != :release}
        line={@line}
        movie?={@movie?}
        ready?={@ready?}
        picker_open={@picker_open}
        rejectable?={@rejectable?}
      />

      <div
        :if={@line.kind == :release && @line.release.overlap}
        class="flex items-center gap-3 pt-2 border-t border-base-content/5 text-sm text-warning/90"
      >
        <span class="min-w-0 flex-1">{@line.release.overlap.description}</span>
        <.button
          variant="risky"
          size="xs"
          class="flex-shrink-0"
          phx-click="plan_swap_release"
          phx-value-unit-id={@line.release.overlap.exclude_unit_id}
          phx-value-guid={@line.release.overlap.exclude_guid}
          data-tip="Exclude this release everywhere and let the planner re-solve without it"
          data-nav-sub-item
          tabindex="0"
        >
          {@line.release.overlap.action_label}
        </.button>
      </div>

      <.cells :if={!@movie?} line={@line} />
    </div>
    """
  end

  # The coloured edge is the decision's: lower quality (info), not found
  # and a pack offer (warning). A release line and the dropped line carry
  # none; the searching line carries none — nothing to decide yet.
  defp edge(:below_preference), do: "border-info/30"
  defp edge(:not_found), do: "border-warning/30"
  defp edge(:offer), do: "border-warning/30"
  defp edge(_kind), do: "border-transparent"

  attr :line, PlanBoard.Line, required: true
  attr :ready?, :boolean, required: true
  attr :picker_open, :boolean, required: true

  defp release_facts_row(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <ReleaseFacts.release_facts entry={release_entry(@line.release)} />
      <.button
        :if={@ready?}
        variant="neutral"
        size="xs"
        class="flex-shrink-0"
        phx-click={if @picker_open, do: "plan_hide_alternatives", else: "plan_show_alternatives"}
        phx-value-unit-id={@line.release.swap_unit_id}
        data-tip="See the other options for this"
        data-nav-sub-item
        tabindex="0"
      >
        {if @picker_open, do: "Hide", else: "Options"}
      </.button>
      <.button
        :if={@ready?}
        variant="destructive_inline"
        size="xs"
        shape="square"
        class="flex-shrink-0"
        phx-click="plan_swap_release"
        phx-value-unit-id={@line.release.swap_unit_id}
        phx-value-guid={@line.release.guid}
        data-tip="Remove this release — exclude it everywhere and re-solve"
        aria-label="Remove this release"
        data-nav-sub-item
        tabindex="0"
      >
        <.icon name="hero-x-mark-mini" class="size-3.5" />
      </.button>
    </div>
    """
  end

  attr :line, PlanBoard.Line, required: true
  attr :movie?, :boolean, required: true
  attr :ready?, :boolean, required: true
  attr :picker_open, :boolean, required: true
  attr :rejectable?, :boolean, required: true

  defp outcome_row(assigns) do
    assigns = assign(assigns, :count, assigns.line |> PlanBoard.Line.cells() |> length())

    ~H"""
    <div class="flex items-center gap-3">
      <span class="min-w-0 flex-1 text-sm">
        <%= case @line.kind do %>
          <% :searching -> %>
            <span class="text-base-content/70">
              <span class="loading loading-spinner loading-xs align-middle mr-1"></span>
              Searching — {count(@count, @movie?)} still to find.
            </span>
          <% :below_preference -> %>
            <span class="block text-base-content/90">{below_preference_line(@line.below, @movie?)}</span>
            <span class="block text-xs text-base-content/55 mt-1">
              Taking them uses the best release there is, for this title only. Your quality preference for everything else stays as it is.
            </span>
          <% :not_found -> %>
            <%!-- The verdict above already says why and names what is
                  missing; the line names the outcome and carries the act. --%>
            <span class="block text-warning/90">
              Not found{if !@movie?, do: " — #{count(@count, false)}"}
            </span>
          <% :offer -> %>
            <span class="text-warning/90">
              No right-sized release for {@line.offer.unit_label} — only a {@line.offer.scope_label}<span :if={
                @line.offer.size_bytes
              }>, {format_size(@line.offer.size_bytes)}</span>, which brings episodes you didn't ask for.
            </span>
          <% :excluded -> %>
            <span class="text-base-content/55">
              Dropped by you — {count(@count, false)}. Press an episode to put it back.
            </span>
        <% end %>
      </span>

      <%!-- The decision, at the line's end. --%>
      <%= case @line.kind do %>
        <% :below_preference -> %>
          <.button
            :if={@line.below.unit_id}
            variant="neutral"
            size="xs"
            class="flex-shrink-0"
            phx-click={if @picker_open, do: "plan_hide_alternatives", else: "plan_show_alternatives"}
            phx-value-unit-id={@line.below.unit_id}
            data-nav-sub-item
            tabindex="0"
          >
            {if @picker_open, do: "Hide", else: "Show them"}
          </.button>
          <.button
            :if={@ready?}
            variant="action"
            size="xs"
            class="flex-shrink-0"
            phx-click="plan_accept_lower_quality"
            data-tip="Grab the best of what exists for this title, and keep accepting lower quality for it"
            data-nav-sub-item
            tabindex="0"
          >
            {if @movie?, do: "Take lower quality", else: "Take lower quality for this show"}
          </.button>
        <% :not_found -> %>
          <.button
            :if={@rejectable?}
            variant="neutral"
            size="xs"
            class="flex-shrink-0"
            phx-click={if @picker_open, do: "plan_hide_rejected", else: "plan_show_rejected"}
            data-nav-sub-item
            tabindex="0"
          >
            {if @picker_open, do: "Hide", else: "Show them anyway"}
          </.button>
          <.button
            :if={@ready?}
            variant="neutral"
            size="xs"
            class="flex-shrink-0"
            phx-click="plan_search_again"
            data-nav-sub-item
            tabindex="0"
          >
            Search again
          </.button>
        <% :offer -> %>
          <.button
            :if={@ready?}
            variant="risky"
            size="xs"
            class="flex-shrink-0"
            phx-click="plan_choose_release"
            phx-value-unit-id={@line.offer.unit_id}
            phx-value-guid={@line.offer.guid}
            data-tip={@line.offer.title}
            data-nav-sub-item
            tabindex="0"
          >
            Grab the pack
          </.button>
        <% _kind -> %>
      <% end %>
    </div>
    """
  end

  attr :line, PlanBoard.Line, required: true

  # The line's cells by season. A release line's cells are its capsule
  # (consecutive same-release cells fused, UIDR-014); an outcome line's
  # cells wear their state.
  defp cells(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-x-4 gap-y-1.5">
      <div :for={row <- @line.rows} class="flex items-center gap-2">
        <span
          :if={row.season_number}
          class="w-6 flex-shrink-0 text-xs text-base-content/55 tabular-nums"
        >
          S{row.season_number}
        </span>
        <div
          :if={@line.kind == :release && length(row.cells) > 1}
          class="flex flex-wrap gap-px rounded-lg border border-primary/60 bg-primary/10 p-0.5"
        >
          <.cell :for={cell <- row.cells} cell={cell} in_capsule />
        </div>
        <div :if={@line.kind != :release || length(row.cells) == 1} class="flex flex-wrap gap-1">
          <.cell :for={cell <- row.cells} cell={cell} />
        </div>
      </div>
    </div>
    """
  end

  attr :cell, PlanBoard.Cell, required: true
  attr :in_capsule, :boolean, default: false

  # The cell is the per-unit control: pressing it drops that episode from
  # the plan, pressing again puts it back. Tailwind v4 Preflight sets no
  # cursor on a button, so it is spelled out.
  defp cell(assigns) do
    ~H"""
    <button
      type="button"
      id={"plan-cell-#{@cell.plan_unit_id}"}
      data-nav-sub-item
      tabindex="0"
      data-tip={@cell.label}
      aria-label={@cell.label}
      aria-pressed={to_string(@cell.state == :excluded)}
      phx-click="plan_toggle_unit_excluded"
      phx-value-unit-id={@cell.plan_unit_id}
      class={[
        "w-9 h-9 rounded-md flex items-center justify-center text-[13px] tabular-nums",
        "select-none cursor-pointer",
        @cell.state |> CellVocabulary.from_plan_state(@in_capsule) |> CellVocabulary.cell_treatment()
      ]}
    >
      {@cell.episode_number}
    </button>
    """
  end

  # One grouped sentence for the below-preference line (UIDR-029). Never
  # says "floor" — user copy calls it the quality preference.
  defp below_preference_line(%PlanBoard.BelowPreference{} = below, movie?) do
    releases = "#{below.releases} #{if below.releases == 1, do: "release", else: "releases"}"

    cond do
      movie? -> "This movie is available only in lower quality — #{releases} found."
      below.units == 1 -> "#{below.unit_label} is available only in lower quality — #{releases} found."
      true -> "#{below.units} episodes are available only in lower quality — #{releases} found."
    end
  end

  defp count(1, true), do: "the movie"
  defp count(1, false), do: "1 episode"
  defp count(n, _movie?), do: "#{n} episodes"

  defp release_entry(%PlanBoard.Release{} = release) do
    %ReleaseFacts.Entry{
      title: release.title,
      scope_label: release.scope_label,
      quality: release.quality,
      size_bytes: release.size_bytes,
      seeders: release.seeders
    }
  end
end
