defmodule MediaCentaurWeb.Storybook.Status.SocialWidget do
  @moduledoc """
  Storybook coverage for the Social Activity widget — relay connectivity,
  roster size and recommendation traffic, with the last thing a relay
  complained about.

  Every variation is aggregates only: no relay list, no roster, no feed
  rows. The one navigation affordance is the link to the Social tab,
  which owns all three.
  """
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.StatusWidgets.Social.social_widget/1
  def render_source, do: :function

  defp entry(state, opts \\ []) do
    %{
      state: state,
      last_error: Keyword.get(opts, :last_error),
      since: Keyword.get(opts, :since, ~U[2026-09-02 11:55:00Z])
    }
  end

  def variations do
    [
      %Variation{
        id: :unconfigured,
        description:
          "Nothing set up yet — the line names the state rather than " <>
            "reporting nought of nought, and no error line appears.",
        attributes: %{
          relay_status: %{},
          friend_count: 0,
          sent_count: 0,
          received_count: 0
        }
      },
      %Variation{
        id: :healthy,
        description:
          "Every relay connected, traffic in both directions. The last " <>
            "received line is the only time vocabulary on the widget.",
        attributes: %{
          relay_status: %{
            "wss://relay-one.example/" => entry(:connected),
            "wss://relay-two.example/" => entry(:connected)
          },
          friend_count: 4,
          sent_count: 12,
          received_count: 27,
          last_received_at: DateTime.add(DateTime.utc_now(), -3 * 86_400, :second)
        }
      },
      %Variation{
        id: :degraded,
        description:
          "One relay of two is down and has said why. The reason is quiet " <>
            "text: recommendations still flow through the other one.",
        attributes: %{
          relay_status: %{
            "wss://relay-one.example/" => entry(:connected, since: ~U[2026-09-02 09:00:00Z]),
            "wss://relay-two.example/" =>
              entry(:disconnected,
                last_error: "connection refused",
                since: ~U[2026-09-02 11:58:00Z]
              )
          },
          friend_count: 4,
          sent_count: 12,
          received_count: 27,
          last_received_at: DateTime.add(DateTime.utc_now(), -90 * 60, :second)
        }
      },
      %Variation{
        id: :auth_failed,
        description:
          "The relay rejected this identity — an allowlist relay that has " <>
            "not been told about this npub. Nothing is connected.",
        attributes: %{
          relay_status: %{
            "wss://relay-private.example/" =>
              entry(:auth_failed, last_error: "auth-required: not on the allowlist")
          },
          friend_count: 2,
          sent_count: 3,
          received_count: 0
        }
      }
    ]
  end
end
