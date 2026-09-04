defmodule MediaCentaurWeb.Components.StatusWidgets.Social do
  @moduledoc """
  Social subsystem Activity widget: one diagnostic row per configured
  relay, then roster size and recommendation traffic.

  The rows are the *diagnostic* view of the relay list — state, how long,
  why, when it retries, when it was last heard (`RelayStatusRow`).
  Settings → Social lists the same relays to *edit* them; the two are
  different jobs, so this is not the duplicate a status widget usually
  must avoid. What stays out is the roster and the feed: the Friends tab
  owns those.

  Rendered into the health-board drill-in's :activity slot via
  MediaCentaurWeb.StatusLive.ActivityWidgets, invoked with a plain data
  bundle (no change-tracking) from StatusLive.activity_bundle/1 — derive
  with Map.put/3, never assign/3.
  """
  use MediaCentaurWeb, :html

  alias MediaCentaur.Format
  alias MediaCentaur.Social.Connections
  alias MediaCentaurWeb.RelayStatusRow

  @doc "Social subsystem Activity widget: per-relay diagnostic rows, friend count, sent/received traffic."
  attr :relay_status, :map,
    required: true,
    doc:
      "one `Social.Connections.entry/0` per configured relay, keyed by URL (the host merges the relay rows with `Social.Connections.status/0`); empty when no relay is configured"

  attr :friend_count, :integer, required: true, doc: "how many keys are on the roster"
  attr :sent_count, :integer, required: true, doc: "recommendations this install has sent"
  attr :received_count, :integer, required: true, doc: "recommendations received from friends"

  attr :last_received_at, :any,
    default: nil,
    doc: "`DateTime.t()` of the newest received recommendation, or nil when none"

  def social_widget(assigns) do
    now = DateTime.utc_now()

    assigns =
      assigns
      |> Map.put(:relay_line, relay_line(Map.values(assigns.relay_status)))
      |> Map.put(:rows, rows(assigns.relay_status, now))

    ~H"""
    <div class="card glass-inset" data-testid="social-widget">
      <div class="card-body">
        <h2 class="card-title text-lg">Social</h2>

        <p class="text-sm">{@relay_line}</p>

        <ul :if={@rows != []} class="mt-1 space-y-1 text-xs" data-component="relay-rows">
          <li
            :for={{url, row} <- @rows}
            id={"social-relay-#{dom_id(url)}"}
            class="flex flex-wrap items-baseline gap-x-3"
          >
            <span class="font-mono text-base-content/80">{row.host}</span>
            <span class="text-base-content/70">{row.label}</span>
            <span :if={row.details != []} class="text-base-content/50">
              {Enum.join(row.details, " · ")}
            </span>
          </li>
        </ul>

        <div class="mt-3 space-y-0.5 text-xs text-base-content/50">
          <p>{@friend_count} friends · {@sent_count} sent · {@received_count} received</p>
          <p :if={@last_received_at}>Last received {Format.relative_ago(@last_received_at)}</p>
        </div>

        <div class="mt-3 flex gap-4">
          <.link
            navigate={~p"/discovery/friends"}
            class="text-xs font-medium text-primary/70 transition-colors hover:text-primary"
          >
            Open Friends
          </.link>
          <.link
            :if={@rows != []}
            navigate={~p"/settings?section=social"}
            class="text-xs font-medium text-primary/70 transition-colors hover:text-primary"
          >
            Relay settings
          </.link>
        </div>
      </div>
    </div>
    """
  end

  # An install with no relays is not broken, so the line names the state
  # rather than reporting nought of nought.
  defp relay_line([]), do: "No relays configured"

  defp relay_line(entries) do
    connected = Enum.count(entries, &Connections.connected?/1)
    "Connected to #{connected} of #{length(entries)} relays"
  end

  defp rows(relay_status, now) do
    relay_status
    |> Enum.sort_by(fn {url, _entry} -> url end)
    |> Enum.map(fn {url, entry} -> {url, RelayStatusRow.build(url, entry, now)} end)
  end

  defp dom_id(url),
    do: url |> String.replace(~r/[^a-z0-9]+/i, "-") |> String.trim("-") |> String.downcase()
end
