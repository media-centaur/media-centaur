defmodule MediaCentaurWeb.Components.Incoming.Ledger do
  @moduledoc """
  The History archive — the Incoming page's ONE history surface
  (DDR-015), and the History tab's whole content. The tab *is* "View
  all": lifecycle filter chips (`set_history_filter`, `:all` leading
  and default), title/release search (`set_history_search`), and the
  caller-rendered grouped rows — always open, no glimpse and no
  disclosure to click through. The old shared-page treatment (a
  four-row glimpse, "Show earlier", a persisted "View all" toggle)
  existed to keep history quiet on a single-scroll page; the tab does
  that job now.

  Storage sits as the ambient foot line, reusing
  `DownloadStorage.calm_summary/1`. An empty archive renders the
  filter-specific honest answer (`HistoryLogic.empty_state/1`) under
  the chips — the chips stay so widening the filter stays possible.

  No section header: the zone tab already says History.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaurWeb.Components.Acquisition.DownloadStorage
  alias MediaCentaurWeb.IncomingLive.HistoryLogic

  attr :filter, :atom,
    default: :all,
    doc: "Lifecycle filter (see `HistoryLogic.filter_atoms/0`) — `:all` is the tab's face."

  attr :search, :string, default: "", doc: "Title/release search needle."

  attr :archive_empty?, :boolean,
    default: false,
    doc: "Whether the filtered archive has no rows — renders the filter-specific empty state."

  attr :storage_drives, :list,
    default: [],
    doc:
      "Media-dir drive maps (`Storage.measure_all/0` shape) — the foot line renders `DownloadStorage.calm_summary/1` when it has one to give."

  slot :archive,
    doc:
      "Caller-provided render block for the archive entries — the parent's grouped-compact-rows helper, so the rendering path stays consistent with the In-flight zone."

  def ledger(assigns) do
    assigns = assign(assigns, :storage_summary, DownloadStorage.calm_summary(assigns.storage_drives))

    ~H"""
    <section data-component="incoming-ledger" data-nav-zone="ledger" class="space-y-3">
      <div class="flex flex-wrap items-center gap-2">
        <button
          :for={filter_atom <- HistoryLogic.filter_atoms()}
          phx-click="set_history_filter"
          phx-value-filter={Atom.to_string(filter_atom)}
          class={[
            "btn btn-sm",
            @filter == filter_atom && "btn-primary",
            @filter != filter_atom && "btn-ghost"
          ]}
          data-nav-item
          tabindex="0"
        >
          {HistoryLogic.filter_label(filter_atom)}
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

      <div
        :if={@archive_empty?}
        class="scrim-surface rounded-xl px-4 py-6 text-center text-sm text-base-content/40"
      >
        {HistoryLogic.empty_state(@filter)}
      </div>
      <div :if={!@archive_empty?} class="grid grid-cols-1 gap-2">
        {render_slot(@archive)}
      </div>

      <div :if={@storage_summary} class="flex items-center justify-end px-1">
        <span class="inline-flex items-center gap-1.5 text-xs text-base-content/35">
          <.icon name="hero-circle-stack-mini" class="size-3.5" /> {@storage_summary}
        </span>
      </div>
    </section>
    """
  end
end
