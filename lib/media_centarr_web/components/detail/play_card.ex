defmodule MediaCentarrWeb.Components.Detail.PlayCard do
  @moduledoc """
  Playback action row — Play/Resume button + thin progress bar + remaining
  text + a "Manage" toggle that flips the panel between `:main` (watch)
  and `:info` (manage) views.

  Mirrors the home hero CTA pair: the play button is always the primary
  variant (solid blue), the "Manage" toggle is always the secondary
  variant (soft blue). The play label ("Play", "Resume Episode 5", "Watch
  again", …) comes from `Detail.Logic.playback_props/3`. When `available`
  is false (storage offline), the play button is replaced with a disabled
  "Offline" pill.

  Naming distinction (UIDR-003): the home hero uses "More info" to *open*
  the modal. Inside the modal, "More info" reveals the credits sub-view
  (director / writers / cast grid + studio/country/links) — same label
  reused intentionally so users see the same word for "tell me more
  about this title". The "Manage" toggle is a separate concern (files,
  external ids, rematch).
  """

  use MediaCentarrWeb, :html

  attr :on_play, :string, required: true
  attr :target_id, :string, required: true
  attr :label, :string, required: true
  attr :percent, :integer, default: 0
  attr :remaining_text, :string, default: nil
  attr :available, :boolean, default: true
  attr :detail_view, :atom, default: :main

  attr :show_more_info, :boolean,
    default: false,
    doc:
      "renders the More info button between Play and Manage. Movies-only for v1; TV/collection detail panels pass `false`."

  def play_card(assigns) do
    has_progress = assigns.percent > 0
    assigns = assign(assigns, :has_progress, has_progress)

    ~H"""
    <div class="space-y-3 pt-1">
      <div :if={@has_progress} class="space-y-1">
        <div class="flex items-center gap-3">
          <div class="flex-1 h-1 rounded-full bg-base-content/10 overflow-hidden">
            <div
              class={"h-full rounded-full #{if @percent >= 100, do: "bg-success", else: "bg-info"}"}
              style={"width: #{@percent}%"}
            />
          </div>
          <span :if={@remaining_text} class="text-xs text-base-content/40 flex-shrink-0">
            {@remaining_text}
          </span>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <.button
          :if={@available}
          variant="primary"
          size="sm"
          phx-click={@on_play}
          phx-value-id={@target_id}
          data-nav-item
          data-entity-id={@target_id}
          tabindex="0"
        >
          <.icon name="hero-play-mini" class="size-4" /> {@label}
        </.button>
        <.button
          :if={!@available}
          variant="dismiss"
          size="sm"
          class="text-base-content/40 cursor-not-allowed pointer-events-none"
          title="Storage offline — check that your media drive is mounted"
        >
          <.icon name="hero-cloud-arrow-down-mini" class="size-4 opacity-60" /> Offline
        </.button>
        <.button
          :if={@show_more_info}
          variant="secondary"
          size="sm"
          phx-click="toggle_credits_view"
          data-nav-item
          tabindex="0"
        >
          <.icon
            name={
              if @detail_view == :credits,
                do: "hero-arrow-left-mini",
                else: "hero-information-circle-mini"
            }
            class="size-4"
          />
          {if @detail_view == :credits, do: "Back", else: "More info"}
        </.button>
        <.button
          variant="secondary"
          size="sm"
          phx-click="toggle_detail_view"
          data-nav-item
          tabindex="0"
        >
          <.icon
            name={if @detail_view == :info, do: "hero-arrow-left-mini", else: "hero-cog-6-tooth-mini"}
            class="size-4"
          />
          {if @detail_view == :info, do: "Back", else: "Manage"}
        </.button>
      </div>
    </div>
    """
  end
end
