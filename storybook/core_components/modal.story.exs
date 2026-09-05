defmodule MediaCentaurWeb.Storybook.CoreComponents.Modal do
  @moduledoc """
  Story for the `<.modal>` seam — the single place `modal-backdrop`/`modal-panel`
  live. The `dismiss` attr is the formalized ephemeral-vs-persistent choice:
  `:ephemeral` closes on backdrop click + Escape; `:persistent` ignores both and
  relies on explicit in-panel controls (the report wizard's pattern).

  Each open variation renders a real `position: fixed` overlay, so they are
  iframed to keep them from stacking on top of one another.
  """
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Modal.modal/1
  def render_source, do: :function
  def layout, do: :one_column
  def container, do: {:iframe, style: "min-height: 420px; width: 100%;"}

  defp body do
    """
    <div class="p-6 space-y-3">
      <h2 class="text-lg font-semibold">Panel content</h2>
      <p class="text-sm text-base-content/70">
        The default slot is the panel body. Footers, headers, and scroll
        regions are the caller's responsibility.
      </p>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :ephemeral_open,
        description: "Ephemeral — backdrop click and Escape both fire `on_close`.",
        attributes: %{
          id: "story-modal-ephemeral",
          open: true,
          dismiss: :ephemeral,
          on_close: "psb-noop",
          size: :md
        },
        slots: [body()]
      },
      %Variation{
        id: :persistent_open,
        description:
          "Persistent — neither backdrop click nor Escape dismisses; the panel " <>
            "must supply its own Cancel/Close control.",
        attributes: %{
          id: "story-modal-persistent",
          open: true,
          dismiss: :persistent
        },
        slots: [body()]
      },
      %Variation{
        id: :small,
        description: "Small panel (confirmations / alerts).",
        attributes: %{
          id: "story-modal-sm",
          open: true,
          dismiss: :ephemeral,
          on_close: "psb-noop",
          size: :sm
        },
        slots: [body()]
      },
      %Variation{
        id: :raised_open,
        description:
          "`raised` — a modal stacked above another open modal (a confirm inside a picker) sits at z-index 60.",
        attributes: %{
          id: "story-modal-raised",
          open: true,
          dismiss: :persistent,
          raised: true
        },
        slots: ["<p class=\"p-6\">A confirm stacked above the modal underneath.</p>"]
      },
      %Variation{
        id: :closed,
        description: "Closed — still in the DOM, hidden via `data-state=\"closed\"`.",
        attributes: %{
          id: "story-modal-closed",
          open: false,
          dismiss: :ephemeral,
          on_close: "psb-noop"
        },
        slots: [body()]
      }
    ]
  end
end
