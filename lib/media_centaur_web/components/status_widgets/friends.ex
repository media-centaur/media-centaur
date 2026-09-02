defmodule MediaCentaurWeb.Components.StatusWidgets.Friends do
  @moduledoc """
  Friends subsystem Activity widget: relay connectivity, roster size and
  recommendation traffic — aggregates only.

  Deliberately carries no relay list and no roster: the Friends tab owns
  those, and a status widget that reprints them would be a second place
  to read the same rows. What it adds is the count the tab cannot show at
  a glance ("connected to 2 of 3"), the last thing a relay complained
  about, and how much has moved in each direction.

  Rendered into the health-board drill-in's :activity slot via
  MediaCentaurWeb.StatusLive.ActivityWidgets, invoked with a plain data
  bundle (no change-tracking) from StatusLive.activity_bundle/1 — derive
  with Map.put/3, never assign/3.
  """
  use MediaCentaurWeb, :html

  alias MediaCentaur.Format

  @doc "Friends subsystem Activity widget: relay connectivity, friend count, sent/received traffic."
  attr :relay_status, :map,
    required: true,
    doc:
      "one `%{state, last_error, since}` entry per configured relay, keyed by URL (the host merges the relay rows with `Friends.Connections.status/0`); empty when no relay is configured"

  attr :friend_count, :integer, required: true, doc: "how many keys are on the roster"
  attr :sent_count, :integer, required: true, doc: "recommendations this install has sent"
  attr :received_count, :integer, required: true, doc: "recommendations received from friends"

  attr :last_received_at, :any,
    default: nil,
    doc: "`DateTime.t()` of the newest received recommendation, or nil when none"

  def friends_widget(assigns) do
    entries = Map.values(assigns.relay_status)

    assigns =
      assigns
      |> Map.put(:relay_line, relay_line(entries))
      |> Map.put(:last_error, last_error(entries))

    ~H"""
    <div class="card glass-inset" data-testid="friends-widget">
      <div class="card-body">
        <h2 class="card-title text-lg">Friends</h2>

        <p class="text-sm">{@relay_line}</p>

        <p :if={@last_error} class="text-xs text-base-content/50" data-component="relay-last-error">
          {@last_error}
        </p>

        <div class="mt-3 space-y-0.5 text-xs text-base-content/50">
          <p>{@friend_count} friends · {@sent_count} sent · {@received_count} received</p>
          <p :if={@last_received_at}>Last received {Format.relative_ago(@last_received_at)}</p>
        </div>

        <div class="mt-3">
          <.link
            navigate={~p"/discovery/friends"}
            class="text-xs font-medium text-primary/70 transition-colors hover:text-primary"
          >
            Open the Friends tab
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
    connected = Enum.count(entries, &(&1.state == :connected))
    "Connected to #{connected} of #{length(entries)} relays"
  end

  # The newest complaint any relay has recorded — one line, because the
  # per-relay breakdown belongs to the Friends tab.
  defp last_error(entries) do
    entries
    |> Enum.filter(& &1.last_error)
    |> Enum.max_by(& &1.since, DateTime, fn -> nil end)
    |> case do
      nil -> nil
      entry -> entry.last_error
    end
  end
end
