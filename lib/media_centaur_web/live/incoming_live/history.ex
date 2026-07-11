defmodule MediaCentaurWeb.IncomingLive.History do
  @moduledoc """
  History zone of the unified Downloads page — per-pursuit list of
  terminal pursuits (failed / cancelled / succeeded), filtered by
  lifecycle bucket and searchable by title or release filename.

  Pure function component. Sits at the bottom of the page as a
  collapsed-by-default disclosure at every width — History is
  terminal-state bookkeeping, so the page leads with active pursuits.
  State (filter, search, entries) lives on the parent `IncomingLive`
  socket. Entries are the `Logic.group_pursuit_rows/2` mixed list of
  `{:single, vm}` and `{:group, data}` tagged tuples — the rendering
  helper on the parent pattern-matches and dispatches to `PursuitRow`
  (compact density) or `PursuitGroup` accordingly.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaurWeb.IncomingLive.HistoryLogic

  attr :empty?, :boolean, required: true
  attr :filter, :atom, required: true
  attr :search, :string, required: true

  attr :open?, :boolean,
    default: false,
    doc:
      "Disclosure state — History is terminal-state bookkeeping, collapsed by default so the page leads with active pursuits. The parent toggles via `toggle_history` and auto-expands on history deep-links."

  slot :inner_block,
    required: true,
    doc:
      "Caller-provided render block for the entries list. Receives the parent's grouped-compact-rows helper so the rendering path stays consistent with the Active Pursuits zone."

  def history_zone(assigns) do
    ~H"""
    <section data-nav-zone="history" class="space-y-3">
      <button
        type="button"
        phx-click="toggle_history"
        class="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wider text-base-content/50 hover:text-base-content/80 transition-colors"
        data-nav-item
        tabindex="0"
      >
        <.icon
          name={if @open?, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
          class="size-3.5"
        /> History
      </button>

      <div :if={@open?} class="flex flex-wrap items-center gap-2">
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
        :if={@open? && @empty?}
        class="scrim-surface rounded-xl px-4 py-6 text-center text-sm text-base-content/40"
      >
        {HistoryLogic.empty_state(@filter)}
      </section>
      <div :if={@open? && !@empty?} class="grid grid-cols-1 gap-2">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end
end
