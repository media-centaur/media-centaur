defmodule MediaCentaurWeb.Storybook.Status.SocialWidget do
  @moduledoc """
  Storybook coverage for the Social Activity widget — one diagnostic row
  per configured relay (state, how long, why, when it retries, when it was
  last heard), then roster size and recommendation traffic.

  The rows are the diagnostic view of the relay list; Settings → Social
  is the editing view. The two links at the foot go to each.
  """
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.StatusWidgets.Social.social_widget/1
  def render_source, do: :function

  defp ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)
  defp ahead(seconds), do: DateTime.add(DateTime.utc_now(), seconds, :second)

  defp entry(state, opts) do
    %{
      state: state,
      last_error: Keyword.get(opts, :last_error),
      since: Keyword.get(opts, :since, ago(2 * 3600)),
      last_heard_at: Keyword.get(opts, :last_heard_at),
      retry_at: Keyword.get(opts, :retry_at)
    }
  end

  defp traffic(overrides \\ []) do
    Map.merge(
      %{friend_count: 4, sent_count: 12, received_count: 27, last_received_at: ago(3 * 86_400)},
      Map.new(overrides)
    )
  end

  def variations do
    [
      %Variation{
        id: :unconfigured,
        description:
          "Nothing set up yet — the line names the state rather than " <>
            "reporting nought of nought, and there are no rows.",
        attributes:
          Map.put(
            traffic(friend_count: 0, sent_count: 0, received_count: 0, last_received_at: nil),
            :relay_status,
            %{}
          )
      },
      %Variation{
        id: :healthy,
        description: "Every relay synced and recently heard from.",
        attributes:
          Map.put(traffic(), :relay_status, %{
            "wss://relay-one.example/" => entry(:synced, last_heard_at: ago(25)),
            "wss://relay-two.example/" => entry(:synced, since: ago(90), last_heard_at: ago(3))
          })
      },
      %Variation{
        id: :degraded,
        description:
          "One relay of two is down: how long, why, and when the next attempt is. " <>
            "Recommendations still flow through the other one.",
        attributes:
          Map.put(traffic(last_received_at: ago(90 * 60)), :relay_status, %{
            "wss://relay-one.example/" => entry(:synced, last_heard_at: ago(12)),
            "ws://localhost:7777/" =>
              entry(:disconnected,
                last_error: "connection refused",
                since: ago(3 * 3600),
                retry_at: ahead(42)
              )
          })
      },
      %Variation{
        id: :connected_not_synced,
        description:
          "The socket is up but the feed has not been answered — a relay that " <>
            "closed the subscription shows the reason beside the heard time.",
        attributes:
          Map.put(traffic(), :relay_status, %{
            "wss://relay-one.example/" =>
              entry(:connected, last_error: "error: overloaded", since: ago(40), last_heard_at: ago(5))
          })
      },
      %Variation{
        id: :auth_failed,
        description:
          "The relay rejected this identity — an allowlist relay that has " <>
            "not been told about this npub. No retry: waiting fixes nothing.",
        attributes:
          Map.put(
            traffic(friend_count: 2, sent_count: 3, received_count: 0, last_received_at: nil),
            :relay_status,
            %{
              "wss://relay-private.example/" =>
                entry(:auth_failed, last_error: "restricted: this key is not a member of this relay")
            }
          )
      },
      %Variation{
        id: :connecting,
        description: "Fresh boot: nothing heard from either relay yet.",
        attributes:
          Map.put(traffic(), :relay_status, %{
            "wss://relay-one.example/" => entry(:connecting, since: ago(2)),
            "wss://relay-two.example/" => entry(:connecting, since: ago(2))
          })
      }
    ]
  end
end
