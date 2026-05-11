defmodule MediaCentarrWeb.AcquisitionLive.Activity do
  @moduledoc """
  Activity zone of the unified Downloads page — filter chips, search,
  and the table of `acquisition_targets` rows (auto + manual). Renders
  cancel and re-arm buttons whose events are handled by the parent
  `AcquisitionLive`.

  Pure function component. State (filter, search, targets) lives on
  the parent socket.
  """
  use Phoenix.Component

  import MediaCentarrWeb.CoreComponents, only: [badge: 1, button: 1]

  alias MediaCentarr.Acquisition.TargetStatus
  alias MediaCentarrWeb.AcquisitionLive.ActivityLogic

  attr :targets, :list,
    required: true,
    doc:
      "list of `MediaCentarr.Acquisition.Target.t()` rows preloaded with the fields read by `ActivityLogic` (status, attempt_count, title, etc.)."

  attr :filter, :atom, required: true
  attr :search, :string, required: true

  def activity_zone(assigns) do
    ~H"""
    <section data-nav-zone="activity" class="glass-surface rounded-xl p-4 space-y-4">
      <div class="flex items-baseline justify-between gap-3">
        <h2 class="text-sm font-medium uppercase tracking-wider text-base-content/50">
          Activity
        </h2>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <button
          :for={f <- ActivityLogic.filter_atoms()}
          phx-click="set_activity_filter"
          phx-value-filter={Atom.to_string(f)}
          class={[
            "btn btn-sm",
            @filter == f && "btn-primary",
            @filter != f && "btn-ghost"
          ]}
          data-nav-item
          tabindex="0"
        >
          {ActivityLogic.filter_label(f)}
        </button>

        <form phx-change="set_activity_search" class="ml-auto">
          <input
            type="search"
            name="search"
            value={@search}
            placeholder="Filter by title…"
            class="input input-bordered input-sm w-64"
            data-nav-item
            tabindex="0"
          />
        </form>
      </div>

      <%= if @targets == [] do %>
        <p class="text-sm text-base-content/50 py-8 text-center">
          {ActivityLogic.empty_state(@filter)}
        </p>
      <% else %>
        <div class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Title</th>
                <th>Origin</th>
                <th>Status</th>
                <th>Last attempt</th>
                <th class="text-right">Attempts</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={target <- @targets}>
                <td class="font-medium">{target.title}</td>
                <td>
                  <.badge variant={ActivityLogic.origin_variant(target)}>
                    {ActivityLogic.origin_label(target)}
                  </.badge>
                </td>
                <td>
                  <.badge variant={ActivityLogic.status_variant(target.status)}>
                    {ActivityLogic.status_label(target)}
                  </.badge>
                </td>
                <td class="text-base-content/60 text-xs">
                  {ActivityLogic.last_attempt_summary(target)}
                </td>
                <td class="text-right tabular-nums">{target.attempt_count}</td>
                <td class="text-right space-x-1">
                  <.button
                    :if={TargetStatus.in_flight?(target.status)}
                    variant="dismiss"
                    size="xs"
                    phx-click="cancel_activity_target"
                    phx-value-id={target.id}
                    data-nav-item
                    tabindex="0"
                  >
                    Cancel
                  </.button>
                  <.button
                    :if={TargetStatus.rearmable?(target.status)}
                    variant="secondary"
                    size="xs"
                    phx-click="rearm_activity_target"
                    phx-value-id={target.id}
                    data-nav-item
                    tabindex="0"
                  >
                    Re-arm
                  </.button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </section>
    """
  end
end
