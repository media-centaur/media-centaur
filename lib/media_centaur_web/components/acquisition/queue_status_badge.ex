defmodule MediaCentaurWeb.Components.Acquisition.QueueStatusBadge do
  @moduledoc """
  Download-client connectivity notice for the Active Pursuits header.

  Deliberately **quiet when healthy.** This used to render a green "Live"
  pill, but sitting next to "Active pursuits" that read as *pursuit*
  liveness — when it only ever meant "we polled the download client
  recently," and most pursuit states (Searching, Decision needed, In
  review, Verifying, Done) never touch the client at all. So it now
  renders **nothing** while telemetry is fresh, connecting, or
  unconfigured, and surfaces a scoped warning only when the client is
  lagging, offline, or auth-failed.

  The healthy/degraded decision and the copy live in the pure
  `MediaCentaurWeb.AcquisitionLive.Logic.connectivity_notice/1`; this
  component is a thin renderer of its output.
  """

  use Phoenix.Component

  alias MediaCentaurWeb.AcquisitionLive.Logic

  attr :status, :any,
    required: true,
    doc:
      "Output of `MediaCentaur.Downloads.QueueStatus.derive/2`. Routed through `Logic.connectivity_notice/1` — only the degraded grades (`{:lagging, _}`, `{:offline, _}`, `:auth_failed`) render anything."

  def queue_status_badge(assigns) do
    assigns = assign(assigns, :notice, Logic.connectivity_notice(assigns.status))

    ~H"""
    <div :if={@notice} class="inline-flex items-center gap-2 text-xs">
      <span class={[
        "inline-flex items-center gap-1.5 px-2 py-1 rounded-full",
        tone_classes(@notice.tone)
      ]}>
        <span class={["w-1.5 h-1.5 rounded-full", dot_classes(@notice.tone)]}></span>
        <span class="font-medium">{@notice.label}</span>
      </span>

      <.link
        :if={@notice.reconfigure?}
        navigate="/settings"
        class="link link-primary text-xs"
      >
        Reconfigure
      </.link>
    </div>
    """
  end

  defp tone_classes(:warning), do: "bg-warning/10 text-warning"
  defp tone_classes(:error), do: "bg-error/10 text-error"

  defp dot_classes(:warning), do: "bg-warning"
  defp dot_classes(:error), do: "bg-error"
end
