defmodule MediaCentarrWeb.Components.Acquisition.QueueStatusBadge do
  @moduledoc """
  Compact freshness pill rendered next to the active-queue header on
  the Downloads page. Surfaces whether the queue we're showing is
  actually fresh, lagging, or fully disconnected — distinguishing
  "the queue is empty" from "we can't reach qBittorrent."

  Driven by `MediaCentarr.Downloads.QueueStatus.derive/2`. Pure
  visual; no event bindings except the optional reconfigure link in
  the auth-failed state.
  """

  use Phoenix.Component

  attr :status, :any,
    required: true,
    doc:
      "Output of `QueueStatus.derive/2` — :live | :initializing | {:lagging, ms} | {:offline, since} | :auth_failed | :not_configured"

  def queue_status_badge(assigns) do
    ~H"""
    <div class="inline-flex items-center gap-2 text-xs">
      <span class={[
        "inline-flex items-center gap-1.5 px-2 py-1 rounded-full",
        tone_classes(@status)
      ]}>
        <span class={["w-1.5 h-1.5 rounded-full", dot_classes(@status)]}></span>
        <span class="font-medium">{label(@status)}</span>
      </span>

      <.link
        :if={@status == :auth_failed}
        navigate="/settings"
        class="link link-primary text-xs"
      >
        Reconfigure
      </.link>
    </div>
    """
  end

  defp tone_classes(:live), do: "bg-success/10 text-success"
  defp tone_classes(:initializing), do: "bg-base-content/5 text-base-content/60"
  defp tone_classes({:lagging, _}), do: "bg-warning/10 text-warning"
  defp tone_classes({:offline, _}), do: "bg-error/10 text-error"
  defp tone_classes(:auth_failed), do: "bg-error/10 text-error"
  defp tone_classes(:not_configured), do: "bg-base-content/5 text-base-content/60"

  defp dot_classes(:live), do: "bg-success animate-pulse"
  defp dot_classes(:initializing), do: "bg-base-content/40 animate-pulse"
  defp dot_classes({:lagging, _}), do: "bg-warning"
  defp dot_classes({:offline, _}), do: "bg-error"
  defp dot_classes(:auth_failed), do: "bg-error"
  defp dot_classes(:not_configured), do: "bg-base-content/40"

  defp label(:live), do: "Live"
  defp label(:initializing), do: "Connecting…"
  defp label({:lagging, ms}), do: "Updated #{format_age(ms)} ago"
  defp label({:offline, since}), do: "Offline · last update #{format_since(since)}"
  defp label(:auth_failed), do: "Auth failed"
  defp label(:not_configured), do: "Not configured"

  defp format_age(ms) when ms < 1000, do: "<1s"
  defp format_age(ms) when ms < 60_000, do: "#{div(ms, 1000)}s"
  defp format_age(ms) when ms < 3_600_000, do: "#{div(ms, 60_000)}m"
  defp format_age(ms), do: "#{div(ms, 3_600_000)}h"

  defp format_since(%DateTime{} = since) do
    seconds = DateTime.diff(DateTime.utc_now(), since, :second)
    format_age(seconds * 1000)
  end

  defp format_since(_), do: "—"
end
