defmodule MediaCentarrWeb.AutoGrabsLive do
  @moduledoc """
  Auto-grabs activity page — visibility into the auto-acquisition pipeline.

  Lists every `acquisition_grabs` row with status filter chips (Active /
  Abandoned / Cancelled / Grabbed / All) and a title search. Per-row
  actions: Cancel (active grabs) and Re-arm (abandoned/cancelled grabs).

  Mounted at `/download/auto-grabs`. Gated by
  `Capabilities.prowlarr_ready?/0` — same predicate as the sidebar entry.
  Stale page loads after Prowlarr revocation redirect to the library.

  Subscribes to `acquisition:updates` so lifecycle broadcasts (armed,
  snoozed, abandoned, cancelled, grab_submitted) refresh the list live.
  """

  use MediaCentarrWeb, :live_view

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Capabilities
  alias MediaCentarrWeb.AutoGrabsLive.Logic

  @filters ~w(active abandoned cancelled grabbed all)a

  @impl true
  def mount(_params, _session, socket) do
    if Capabilities.prowlarr_ready?() do
      if connected?(socket) do
        Acquisition.subscribe()
        Capabilities.subscribe()
      end

      {:ok,
       socket
       |> assign(filter: :active, search: "")
       |> load_grabs()}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  @impl true
  def handle_event("set_filter", %{"filter" => filter}, socket) do
    filter = String.to_existing_atom(filter)
    filter = if filter in @filters, do: filter, else: :active

    {:noreply,
     socket
     |> assign(filter: filter)
     |> load_grabs()}
  end

  def handle_event("set_search", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(search: search)
     |> load_grabs()}
  end

  def handle_event("cancel_grab", %{"id" => id}, socket) do
    case Acquisition.cancel_grab(id, "user_disabled") do
      {:ok, _} -> {:noreply, load_grabs(socket)}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Grab no longer exists")}
    end
  end

  def handle_event("rearm_grab", %{"id" => id}, socket) do
    case Acquisition.rearm_grab(id) do
      {:ok, _} -> {:noreply, load_grabs(socket)}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Grab no longer exists")}
    end
  end

  @impl true
  def handle_info({event, _}, socket)
      when event in [
             :grab_submitted,
             :auto_grab_armed,
             :auto_grab_snoozed,
             :auto_grab_abandoned,
             :auto_grab_cancelled
           ] do
    {:noreply, load_grabs(socket)}
  end

  def handle_info(:capabilities_changed, socket) do
    if Capabilities.prowlarr_ready?() do
      {:noreply, socket}
    else
      {:noreply, push_navigate(socket, to: "/")}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load_grabs(socket) do
    grabs =
      socket.assigns.filter
      |> Acquisition.list_auto_grabs()
      |> Logic.filter_by_search(socket.assigns.search)

    assign(socket, grabs: grabs)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app flash={@flash} current_path="/download/auto-grabs">
      <div class="max-w-5xl mx-auto space-y-6 py-6">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Auto-grabs</h1>
          <.link navigate="/download" class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-up-right" class="size-4" /> Manual search
          </.link>
        </div>

        <div class="glass-surface rounded-xl p-4 space-y-4">
          <div class="flex flex-wrap items-center gap-2">
            <button
              :for={f <- [:active, :abandoned, :cancelled, :grabbed, :all]}
              phx-click="set_filter"
              phx-value-filter={Atom.to_string(f)}
              class={[
                "btn btn-sm",
                @filter == f && "btn-primary",
                @filter != f && "btn-ghost"
              ]}
              data-nav-item
              tabindex="0"
            >
              {Logic.filter_label(f)}
            </button>

            <form phx-change="set_search" class="ml-auto">
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
              {Logic.empty_state(@filter)}
            </p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Title</th>
                    <th>Episode</th>
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
                      {Logic.episode_label(grab)}
                    </td>
                    <td>
                      <span class={[
                        "badge badge-sm",
                        Logic.status_class(grab.status)
                      ]}>
                        {Logic.status_label(grab)}
                      </span>
                    </td>
                    <td class="text-base-content/60 text-xs">
                      {Logic.last_attempt_summary(grab)}
                    </td>
                    <td class="text-right tabular-nums">{grab.attempt_count}</td>
                    <td class="text-right space-x-1">
                      <button
                        :if={grab.status in ["searching", "snoozed"]}
                        phx-click="cancel_grab"
                        phx-value-id={grab.id}
                        class="btn btn-ghost btn-xs"
                        data-nav-item
                        tabindex="0"
                      >
                        Cancel
                      </button>
                      <button
                        :if={grab.status in ["cancelled", "abandoned"]}
                        phx-click="rearm_grab"
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
        </div>
      </div>
    </Layouts.app>
    """
  end
end
