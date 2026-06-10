defmodule MediaCentaurWeb.AcquisitionLive.History do
  @moduledoc """
  History zone of the unified Downloads page — per-pursuit list of
  terminal pursuits (failed / cancelled / succeeded), filtered by
  lifecycle bucket and searchable by title or release filename.

  Pure function component. Lives in the ledger rail of the command-center
  layout at 2xl+ (always visible there); below 2xl it joins the stacked
  page as a collapsed-by-default disclosure. State (filter, search,
  entries) lives on the parent `AcquisitionLive` socket. Entries are the
  `Logic.group_pursuit_rows/2` mixed list of `{:single, vm}` and
  `{:group, data}` tagged tuples — the rendering helper on the parent
  pattern-matches and dispatches to `PursuitRow` (compact density) or
  `PursuitGroup` accordingly.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaurWeb.AcquisitionLive.HistoryLogic

  attr :empty?, :boolean, required: true
  attr :filter, :atom, required: true
  attr :search, :string, required: true

  attr :open?, :boolean,
    default: false,
    doc:
      "Disclosure state below the 2xl breakpoint — History is terminal-state bookkeeping, collapsed by default so the stacked page leads with active pursuits. The parent toggles via `toggle_history` and auto-expands on history deep-links. At 2xl+ the zone sits in the ledger rail and is always visible; this attr has no visual effect there."

  slot :inner_block,
    required: true,
    doc:
      "Caller-provided render block for the entries list. Receives the parent's grouped-compact-rows helper so the rendering path stays consistent with the Active Pursuits zone."

  def history_zone(assigns) do
    ~H"""
    <section data-nav-zone="history" class="max-w-4xl space-y-3 2xl:max-w-none">
      <%!-- Below 2xl: disclosure toggle (collapsed by default). At 2xl+ the
            zone lives in the ledger rail where History IS the content — the
            toggle hides and a static heading shows instead; `@open?` has no
            visual effect at rail widths. --%>
      <button
        type="button"
        phx-click="toggle_history"
        class="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wider text-base-content/50 hover:text-base-content/80 transition-colors 2xl:hidden"
        data-nav-item
        tabindex="0"
      >
        <.icon
          name={if @open?, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
          class="size-3.5"
        /> History
      </button>
      <h2 class="hidden text-xs font-medium uppercase tracking-wider text-base-content/50 2xl:block">
        History
      </h2>

      <div class={["flex flex-wrap items-center gap-2", !@open? && "hidden 2xl:flex"]}>
        <button
          :for={f <- HistoryLogic.filter_atoms()}
          phx-click="set_history_filter"
          phx-value-filter={Atom.to_string(f)}
          class={[
            "btn btn-sm",
            @filter == f && "btn-primary",
            @filter != f && "btn-ghost"
          ]}
          data-nav-item
          tabindex="0"
        >
          {HistoryLogic.filter_label(f)}
        </button>

        <form phx-change="set_history_search" class="ml-auto">
          <input
            type="search"
            name="search"
            value={@search}
            placeholder="Filter by title or release…"
            class="input input-bordered input-sm w-64"
            data-nav-item
            tabindex="0"
          />
        </form>
      </div>

      <section
        :if={@empty?}
        class={[
          "scrim-surface rounded-xl px-4 py-6 text-center text-sm text-base-content/40",
          !@open? && "hidden 2xl:block"
        ]}
      >
        {HistoryLogic.empty_state(@filter)}
      </section>
      <div :if={!@empty?} class={["grid grid-cols-1 gap-2", !@open? && "hidden 2xl:grid"]}>
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end
end
