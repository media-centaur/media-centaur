defmodule MediaCentarrWeb.AcquisitionLive.History do
  @moduledoc """
  History zone of the unified Downloads page — per-pursuit list of
  terminal pursuits (failed / cancelled / succeeded), filtered by
  lifecycle bucket and searchable by title or release filename.

  Pure function component. State (filter, search, rows) lives on the
  parent `AcquisitionLive` socket. Rows render as `PursuitRow`
  components (same as the Active Pursuits zone above) — clicking a
  row opens the pursuit modal where Cancel / Change target live.
  """

  use Phoenix.Component

  alias MediaCentarr.Acquisition.ViewModels.PursuitRow, as: PursuitRowVM
  alias MediaCentarrWeb.AcquisitionLive.HistoryLogic
  alias MediaCentarrWeb.Components.Acquisition.PursuitRow

  attr :rows, :list,
    required: true,
    doc: "list of `MediaCentarr.Acquisition.ViewModels.PursuitRow.t()` for terminal pursuits."

  attr :filter, :atom, required: true
  attr :search, :string, required: true

  def history_zone(assigns) do
    ~H"""
    <section data-nav-zone="history" class="space-y-3">
      <div class="flex items-baseline justify-between gap-3">
        <h2 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
          History
        </h2>
      </div>

      <div class="flex flex-wrap items-center gap-2">
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

      <%= if @rows == [] do %>
        <section class="glass-surface rounded-xl px-4 py-6 text-center text-sm text-base-content/40">
          {HistoryLogic.empty_state(@filter)}
        </section>
      <% else %>
        <div class="grid gap-3">
          <PursuitRow.pursuit_row :for={%PursuitRowVM{} = vm <- @rows} vm={vm} />
        </div>
      <% end %>
    </section>
    """
  end
end
