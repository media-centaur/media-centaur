defmodule MediaManagerWeb.LoggingLive do
  use MediaManagerWeb, :live_view

  alias MediaManager.Log
  alias MediaManagerWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(MediaManager.PubSub, "logging:updates")
        assign_log_state(socket)
      else
        socket
        |> assign(enabled_components: [], all_components: [], suppressed_frameworks: [])
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_component", %{"component" => component}, socket) do
    component = String.to_existing_atom(component)

    if component in socket.assigns.enabled_components do
      Log.disable(component)
    else
      Log.enable(component)
    end

    {:noreply, assign_log_state(socket)}
  end

  def handle_event("enable_all", _params, socket) do
    Log.all()
    {:noreply, assign_log_state(socket)}
  end

  def handle_event("disable_all", _params, socket) do
    Log.none()
    {:noreply, assign_log_state(socket)}
  end

  def handle_event("toggle_framework", %{"key" => key}, socket) do
    key = String.to_existing_atom(key)

    if key in socket.assigns.suppressed_frameworks do
      Log.unsuppress_framework(key)
    else
      Log.suppress_framework(key)
    end

    {:noreply, assign_log_state(socket)}
  end

  @impl true
  def handle_info(:log_settings_changed, socket) do
    {:noreply, assign_log_state(socket)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp assign_log_state(socket) do
    {enabled, all} = Log.status()

    socket
    |> assign(enabled_components: enabled)
    |> assign(all_components: all)
    |> assign(suppressed_frameworks: Log.suppressed_frameworks())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/logging">
      <div class="space-y-6">
        <h1 class="text-2xl font-bold">Logging</h1>

        <.thinking_logs
          enabled={@enabled_components}
          all={@all_components}
        />

        <.framework_logs suppressed={@suppressed_frameworks} />
      </div>
    </Layouts.app>
    """
  end

  defp thinking_logs(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title text-lg">Thinking Logs</h2>
          <div class="flex gap-2">
            <button phx-click="enable_all" class="btn btn-xs btn-outline btn-success">
              Enable all
            </button>
            <button phx-click="disable_all" class="btn btn-xs btn-outline">
              Disable all
            </button>
          </div>
        </div>

        <p class="text-sm text-base-content/60">
          Per-component decision logs. Enable a component to see its thinking in the terminal.
        </p>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 mt-2">
          <div
            :for={component <- @all}
            class="flex items-center justify-between p-3 rounded-lg bg-base-200"
          >
            <div>
              <span class="font-medium">{component}</span>
              <p class="text-xs text-base-content/50">{component_description(component)}</p>
            </div>
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-success"
              checked={component in @enabled}
              phx-click="toggle_component"
              phx-value-component={component}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp framework_logs(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body">
        <h2 class="card-title text-lg">Framework Logs</h2>

        <p class="text-sm text-base-content/60">
          Suppress noisy library output at runtime. Suppressed modules only emit warning and above.
        </p>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-2">
          <div
            :for={{key, _mod} <- Log.framework_modules()}
            class="flex items-center justify-between p-3 rounded-lg bg-base-200"
          >
            <div>
              <span class="font-medium">{framework_label(key)}</span>
              <p class="text-xs text-base-content/50">{framework_description(key)}</p>
            </div>
            <label class="flex items-center gap-2 cursor-pointer">
              <span class={[
                "text-xs",
                if(key in @suppressed, do: "text-warning", else: "text-success")
              ]}>
                {if key in @suppressed, do: "suppressed", else: "active"}
              </span>
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-warning"
                checked={key in @suppressed}
                phx-click="toggle_framework"
                phx-value-key={key}
              />
            </label>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp component_description(:watcher), do: "file events, size checks, detection"
  defp component_description(:pipeline), do: "processing steps, batch results"
  defp component_description(:tmdb), do: "API calls, rate limiting, confidence"
  defp component_description(:playback), do: "play/pause/stop, session lifecycle"
  defp component_description(:channel), do: "library sync, entity pushes"
  defp component_description(:library), do: "entity resolver, browser, admin"

  defp framework_label(:ecto), do: "Ecto SQL queries"
  defp framework_label(:phoenix), do: "Phoenix requests"
  defp framework_label(:live_view), do: "LiveView events"

  defp framework_description(:ecto), do: "full SQL dumped on every query"
  defp framework_description(:phoenix), do: "HTTP request logs for every interaction"
  defp framework_description(:live_view), do: "mount, handle_event, handle_params logs"
end
