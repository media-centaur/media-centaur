defmodule MediaCentaurWeb.Storybook.CoreComponents.ActionToast do
  @moduledoc """
  The one-action toast: the flash skin with a way back. Dismissal is the
  element's own `phx-click`, replayed by `FlashAutoDismiss` on expiry —
  under a live socket the toast self-closes after the dwell; in isolation
  it stays put, but the hook and `data-dismiss-after` wiring render,
  which is the contract the story locks.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.ActionToast.action_toast/1
  def render_source, do: :function

  # `toast toast-top toast-end` is position-fixed to the viewport; each
  # variation gets its own iframe so they don't stack on one corner.
  def container, do: {:iframe, style: "min-height: 160px; width: 100%;"}

  def variations do
    [
      %Variation{
        id: :undo,
        description: "A title ignored from the Recommendations tab, with Undo.",
        attributes: %{
          id: "toast-undo",
          message: "Sample Movie ignored",
          action: "Undo",
          on_action: {:eval, ~s|JS.push("ignore_undo")|},
          on_dismiss: {:eval, ~s|JS.push("ignore_undo_dismiss")|}
        }
      },
      %Variation{
        id: :long_message,
        description: "A long title wraps; the action keeps its place on the right.",
        attributes: %{
          id: "toast-long",
          message: "A Sample Movie With a Long Title That Runs On and On ignored",
          action: "Undo",
          on_action: {:eval, ~s|JS.push("ignore_undo")|},
          on_dismiss: {:eval, ~s|JS.push("ignore_undo_dismiss")|},
          dismiss_after: 10_000
        }
      }
    ]
  end
end
