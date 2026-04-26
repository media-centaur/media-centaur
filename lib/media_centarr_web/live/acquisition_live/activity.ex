defmodule MediaCentarrWeb.AcquisitionLive.Activity do
  @moduledoc """
  Activity zone of the unified Downloads page — filter chips, search,
  and the table of `acquisition_grabs` rows (auto + manual). Renders
  cancel and re-arm buttons whose events are handled by the parent
  `AcquisitionLive`.

  Pure function component. State (filter, search, grabs) lives on the
  parent socket.
  """
  use Phoenix.Component

  alias MediaCentarrWeb.AcquisitionLive.ActivityLogic

  attr :grabs, :list, required: true
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
          :for={f <- [:active, :abandoned, :cancelled, :grabbed, :all]}
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

      <%= if @grabs == [] do %>
        <p class="text-sm text-base-content/50 py-8 text-center">
          {ActivityLogic.empty_state(@filter)}
        </p>
      <% else %>
        <div class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Title</th>
                <th>Episode</th>
                <th>Origin</th>
                <th>Status</th>
                <th>Last attempt</th>
                <th class="text-right">Attempts</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={grab <- @grabs}>
                <td class="font-medium">{grab.title}</td>
                <td class="text-base-content/60 tabular-nums">
                  {ActivityLogic.episode_label(grab)}
                </td>
                <td>
                  <span class={["badge badge-sm", ActivityLogic.origin_class(grab)]}>
                    {ActivityLogic.origin_label(grab)}
                  </span>
                </td>
                <td>
                  <span class={["badge badge-sm", ActivityLogic.status_class(grab.status)]}>
                    {ActivityLogic.status_label(grab)}
                  </span>
                </td>
                <td class="text-base-content/60 text-xs">
                  {ActivityLogic.last_attempt_summary(grab)}
                </td>
                <td class="text-right tabular-nums">{grab.attempt_count}</td>
                <td class="text-right space-x-1">
                  <button
                    :if={grab.status in ["searching", "snoozed"]}
                    phx-click="cancel_activity_grab"
                    phx-value-id={grab.id}
                    class="btn btn-ghost btn-xs"
                    data-nav-item
                    tabindex="0"
                  >
                    Cancel
                  </button>
                  <button
                    :if={grab.status in ["cancelled", "abandoned"]}
                    phx-click="rearm_activity_grab"
                    phx-value-id={grab.id}
                    class="btn btn-soft btn-primary btn-xs"
                    data-nav-item
                    tabindex="0"
                  >
                    Re-arm
                  </button>
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
