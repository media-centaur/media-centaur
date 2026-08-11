defmodule MediaCentaurWeb.Storybook.Composites.CinematicShell do
  @moduledoc """
  The cinematic modal frame — the tenant-agnostic half of the detail-modal
  technology. These variations exercise the frame's own states with
  deliberately plain slot content; the real tenants (the library detail
  panel, the acquisition plan modal, the Incoming title modal) each have
  their own story.

  The modal is **always present in the DOM** — `open` toggles a
  `data-state` attribute that drives CSS visibility/opacity, so the
  browser's `backdrop-filter` compositing layer stays warm.

  Backdrop imagery is intentionally absent (storybook's image server
  can't satisfy `/media-images/…`), so the open variations show the
  placeholder hero window — accurate to the "no artwork" state. The
  pinned-block scroll behaviour itself needs a real scroll context and is
  covered by `test/e2e/detail-backdrop.spec.js`, not the catalog.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.CinematicShell.cinematic_shell/1
  def render_source, do: :function
  def layout, do: :one_column

  # Each variation renders a real `position: fixed` overlay, so they
  # would otherwise stack on top of each other in a shared DOM and
  # only the last would be visible. Iframing isolates them.
  def container, do: {:iframe, style: "min-height: 560px; width: 100%;"}

  def template do
    """
    <div>
      <button
        type="button"
        class="btn btn-sm btn-primary"
        phx-click={Phoenix.LiveView.JS.push("psb-assign", value: %{open: true})}
        psb-code-hidden
      >
        Open modal
      </button>
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :closed,
        description:
          "Closed — the bare shell is in the DOM (`data-state=\"closed\"`) with no " <>
            "subject loaded (`present: false`). Click *Open modal* to flip the assigns.",
        attributes: %{
          id: "cinematic-closed",
          open: false,
          dismiss: :ephemeral,
          on_close: close_event(:closed)
        }
      },
      %Variation{
        id: :open_full,
        description:
          "Open, `full: true` — scrolling document: placeholder hero window, pinned " <>
            "orientation block with sample lockup content, and a body sheet long " <>
            "enough to scroll (the orientation block pins once the hero scrolls away).",
        attributes: %{
          id: "cinematic-full",
          open: true,
          dismiss: :ephemeral,
          on_close: close_event(:open_full),
          present: true,
          full: true,
          scroll_key: "sample-subject",
          view_key: :main
        },
        slots: [
          """
          <:hero_actions>
            <span class="text-xs text-base-content/60">hero actions</span>
          </:hero_actions>
          """,
          """
          <:orientation>
            <div class="px-6 pt-2">
              <h2 class="text-2xl font-bold text-white text-on-image-lg">Sample Subject</h2>
              <p class="italic text-sm text-white/85 text-on-image">A demonstrative tagline.</p>
            </div>
            <div class="px-4 pt-6 pb-4 text-sm text-base-content/70">
              Orientation block content — metadata, controls, synopsis.
            </div>
          </:orientation>
          """,
          """
          <:body>
            <div class="space-y-3 pt-2">
              <div :for={n <- 1..14} class="glass-inset rounded-lg p-4 text-sm text-base-content/70">
                Body row {n} — scrolls under the pinned orientation block.
              </div>
            </div>
          </:body>
          """
        ]
      },
      %Variation{
        id: :open_content_fit,
        description:
          "Open, `full: false`, no `:body` slot — the content-fit panel a bare movie " <>
            "gets: the panel hugs the orientation block and nothing scrolls.",
        attributes: %{
          id: "cinematic-fit",
          open: true,
          dismiss: :ephemeral,
          on_close: close_event(:open_content_fit),
          present: true,
          full: false
        },
        slots: [
          """
          <:orientation>
            <div class="px-6 pt-2">
              <h2 class="text-2xl font-bold text-white text-on-image-lg">Content-Fit Subject</h2>
            </div>
            <div class="px-4 pt-6 pb-8 text-sm text-base-content/70">
              A short document — the panel ends where this block does.
            </div>
          </:orientation>
          """
        ]
      }
    ]
  end

  defp close_event(variation_id) do
    {:eval,
     ~s|Phoenix.LiveView.JS.push("psb-assign", value: %{variation_id: #{inspect(variation_id)}, open: false})|}
  end
end
