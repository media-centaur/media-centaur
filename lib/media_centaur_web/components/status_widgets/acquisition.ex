defmodule MediaCentaurWeb.Components.StatusWidgets.Acquisition do
  @moduledoc """
  Downloads (acquisition) Activity widget: connectivity health + throughput figures.

  Rendered into the health-board drill-in's :activity slot via
  MediaCentaurWeb.StatusLive.ActivityWidgets, invoked with a plain data
  bundle (no change-tracking) from StatusLive.activity_bundle/1 — derive
  with Map.put/3, never assign/3.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [duration_since: 1, time_ago: 1]
  import MediaCentaurWeb.Components.StatusWidgets.Shared

  @doc "Downloads (acquisition) Activity widget: connectivity health + throughput figures."
  attr :acquisition_activity, :map,
    required: true,
    doc:
      "bundle from StatusLive: %{configured?, connectivity, last_poll_at, prowlarr_ready?, throughput} — connectivity is `MediaCentaur.Downloads.Connectivity.t()` as graded by the QueueMonitor"

  def acquisition_widget(assigns) do
    client =
      acq_client_status(
        assigns.acquisition_activity.connectivity,
        assigns.acquisition_activity.last_poll_at
      )

    prowlarr = acq_prowlarr_status(assigns.acquisition_activity.prowlarr_ready?)
    tone = worst_tone([client.tone, prowlarr.tone])

    assigns =
      assigns
      |> Map.put(:client, client)
      |> Map.put(:prowlarr, prowlarr)
      |> Map.put(:tone, tone)

    ~H"""
    <div
      class={["card glass-inset", acq_wash_class(@tone)]}
      data-testid="acquisition-widget"
    >
      <div class="card-body">
        <%!-- Unconfigured: single settings affordance, nothing else --%>
        <p :if={!@acquisition_activity.configured?} class="text-sm text-base-content/60">
          <.settings_link section="services">
            Acquisition isn't set up — configure a download client and Prowlarr in Settings.
          </.settings_link>
        </p>

        <div :if={@acquisition_activity.configured?}>
          <%!-- Band 1 · Connectivity (the only coloured band) --%>
          <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/55">
            Connectivity
          </h3>
          <div data-component="acquisition-connectivity" class="mt-2 space-y-2">
            <div class="flex items-center gap-2 text-sm">
              <span class="text-base-content/70 w-32 shrink-0">Download client</span>
              <span class={["size-2 rounded-full shrink-0", tone_chrome(@client.tone).dot]}></span>
              <span class={tone_chrome(@client.tone).text}>{@client.label}</span>
              <span :if={@client.detail} class="ml-auto text-xs text-base-content/55 tabular-nums">
                {@client.detail}
              </span>
            </div>
            <div class="flex items-center gap-2 text-sm">
              <span class="text-base-content/70 w-32 shrink-0">Prowlarr indexers</span>
              <span class={["size-2 rounded-full shrink-0", tone_chrome(@prowlarr.tone).dot]}></span>
              <span class={tone_chrome(@prowlarr.tone).text}>{@prowlarr.label}</span>
            </div>
          </div>

          <%!-- Band 2 · Throughput stat figures --%>
          <div
            data-component="acquisition-throughput"
            class="mt-4 pt-4 border-t border-base-content/10 grid grid-cols-3 gap-3"
          >
            <div>
              <div class="text-2xl font-semibold tabular-nums">
                {@acquisition_activity.throughput.acquired}
              </div>
              <div class="text-xs uppercase tracking-wider text-base-content/55">Acquired</div>
            </div>
            <div>
              <div class="text-2xl font-semibold tabular-nums">
                {acq_rate_label(@acquisition_activity.throughput.success_rate)}
              </div>
              <div class="text-xs uppercase tracking-wider text-base-content/55">Success</div>
            </div>
            <.link navigate={~p"/incoming"} class="block group">
              <div class="text-2xl font-semibold tabular-nums group-hover:text-primary">
                {@acquisition_activity.throughput.active}
              </div>
              <div class="text-xs uppercase tracking-wider text-base-content/55 group-hover:text-primary">
                Active
              </div>
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # The phases where an apply is genuinely in flight (a progress bar makes sense).

  # --- Acquisition widget helpers ---

  defp tone_chrome(:ok), do: %{dot: "bg-success", text: "text-success"}
  defp tone_chrome(:warning), do: %{dot: "bg-warning", text: "text-warning"}
  defp tone_chrome(:error), do: %{dot: "bg-error", text: "text-error"}
  defp tone_chrome(:muted), do: %{dot: "bg-base-content/30", text: "text-base-content/55"}

  defp acq_client_status(:live, last), do: %{label: "Connected", tone: :ok, detail: poll_suffix(last)}
  defp acq_client_status(:initializing, _last), do: %{label: "Connecting…", tone: :muted, detail: nil}

  # One failed poll — honest plumbing detail for this page (the rest of
  # the UI stays quiet on a blip), amber because it may be the first
  # tick of a real outage.
  defp acq_client_status({:transient_failure, _since}, last),
    do: %{label: "Retrying…", tone: :warning, detail: poll_suffix(last)}

  defp acq_client_status({:offline, since}, _last),
    do: %{label: "Offline", tone: :error, detail: "down #{duration_since(since)}"}

  defp acq_client_status(:auth_failed, _last), do: %{label: "Auth failed", tone: :error, detail: nil}

  defp acq_client_status(:not_configured, _last),
    do: %{label: "Not configured", tone: :muted, detail: nil}

  defp acq_prowlarr_status(true), do: %{label: "Reachable", tone: :ok}
  defp acq_prowlarr_status(false), do: %{label: "Unreachable", tone: :error}

  defp poll_suffix(nil), do: nil
  defp poll_suffix(%DateTime{} = at), do: "polled #{time_ago(at)}"

  defp acq_rate_label(nil), do: "—"
  defp acq_rate_label(rate), do: "#{rate}%"

  defp worst_tone(tones) do
    cond do
      :error in tones -> :error
      :warning in tones -> :warning
      true -> :ok
    end
  end

  # A faint wash over the whole card, never an edge bar: colour is the
  # signal, the card stays one shape (house rule, no accent bars).
  defp acq_wash_class(:error), do: "bg-error/5"
  defp acq_wash_class(:warning), do: "bg-warning/5"
  defp acq_wash_class(_), do: nil
end
