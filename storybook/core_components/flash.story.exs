defmodule MediaCentaurWeb.Storybook.CoreComponents.Flash do
  @moduledoc """
  Rubric-bar story for `flash/1` — every `kind`, hidden vs. visible,
  no-title, long-body wrapping, and the auto-dismiss attr.

  The `@kinds` list is kept in sync with `attr :kind, values: [...]` on
  the live component. Adding a kind there means adding it here too.

  The `auto_dismiss` variation pins `dismiss_after` (the timed-close attr).
  The countdown itself is the `FlashAutoDismiss` hook, which only runs under
  a live socket — in isolation the toast stays put, but the `phx-hook` /
  `data-dismiss-after` wiring renders, which is the contract the story locks.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.CoreComponents.flash/1
  def imports, do: [{MediaCentaurWeb.CoreComponents, show: 1, button: 1}]
  def render_source, do: :function

  # Flash uses `class="toast toast-top toast-end"` which is position-fixed
  # to the viewport. Without iframe isolation, every variation stacks at
  # the same top-right coordinates and only one is visible. Each variation
  # gets its own iframe so the fixed positioning is scoped per-preview.
  def container, do: {:iframe, style: "min-height: 220px; width: 100%;"}

  # Mirrors `attr :kind, values: [:info, :error]` in core_components.ex.
  @kinds [:info, :error]

  def template do
    """
    <div>
      <.button phx-click={show("#:variation_id")}>
        Trigger flash
      </.button>
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    # Each top-level Variation lives in its own iframe (see container/0
    # above), so each flash's `position: fixed` is isolated. We avoid
    # putting two visible flashes in one VariationGroup because they'd
    # stack at the same fixed top-right coordinate.
    Enum.flat_map(@kinds, fn kind ->
      [
        %Variation{
          id: String.to_atom("#{kind}_visible"),
          description: "#{kind} flash, visible",
          attributes: %{
            kind: kind,
            title: title_for(kind)
          },
          slots: [body_for(kind)]
        },
        %Variation{
          id: String.to_atom("#{kind}_hidden"),
          description: "#{kind} flash, hidden until trigger button is clicked",
          attributes: %{
            kind: kind,
            hidden: true,
            title: title_for(kind)
          },
          slots: [body_for(kind)]
        }
      ]
    end) ++
      [
        %Variation{
          id: :without_title,
          description: "Body only — no title line",
          attributes: %{
            kind: :info
          },
          slots: ["A short status update with no accompanying title."]
        },
        %Variation{
          id: :long_body,
          description: "Long body — verifies wrapping inside the toast width",
          attributes: %{
            kind: :error,
            title: "Something went sideways"
          },
          slots: [
            "The operation could not complete because a downstream service " <>
              "returned an unexpected response. The system has logged the " <>
              "details and will retry shortly. If the problem persists, open " <>
              "the Console drawer and look for entries tagged with the relevant " <>
              "component to understand what went wrong."
          ]
        },
        %Variation{
          id: :auto_dismiss,
          description:
            "`dismiss_after: 4000` — renders the FlashAutoDismiss hook + " <>
              "`data-dismiss-after`. Under a live socket the toast self-closes " <>
              "after the dwell; in isolation it stays put (no socket).",
          attributes: %{
            kind: :info,
            title: "Saved",
            dismiss_after: 4000
          },
          slots: ["Your changes were saved."]
        }
      ]
  end

  defp title_for(:info), do: "Did you know?"
  defp title_for(:error), do: "Oops!"

  defp body_for(:info), do: "Library scan finished — 3 new items added."
  defp body_for(:error), do: "Sorry, something just crashed."
end
