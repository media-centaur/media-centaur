defmodule MediaCentarrWeb.Components.Detail.PlayCard do
  @moduledoc """
  Playback action row — Play/Resume button + thin progress bar + remaining
  text + a "More info" toggle that flips the panel between `:main` and
  `:info` views.

  Pure presentation: the per-type panel computes label/color/percent/
  remaining text and passes them in. When `available` is false (storage
  offline), the play button is replaced with a disabled "Offline" pill.
  """
  use MediaCentarrWeb, :html

  attr :on_play, :string, required: true
  attr :target_id, :string, required: true
  attr :label, :string, required: true
  attr :color, :string, required: true
  attr :percent, :integer, default: 0
  attr :remaining_text, :string, default: nil
  attr :available, :boolean, default: true
  attr :detail_view, :atom, default: :main

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
        <button
          :if={@available}
          phx-click={@on_play}
          phx-value-id={@target_id}
          class={"btn btn-soft btn-sm btn-#{@color}"}
          data-nav-item
          data-entity-id={@target_id}
          tabindex="0"
        >
          <.icon name="hero-play-mini" class="size-4" /> {@label}
        </button>
        <span
          :if={!@available}
          class="btn btn-sm btn-ghost text-base-content/40 cursor-not-allowed pointer-events-none"
          title="Storage offline — check that your media drive is mounted"
        >
          <.icon name="hero-cloud-arrow-down-mini" class="size-4 opacity-60" /> Offline
        </span>
        <button
          phx-click="toggle_detail_view"
          class={[
            "btn btn-sm",
            if(@detail_view == :info, do: "btn-soft btn-primary", else: "btn-ghost")
          ]}
          data-nav-item
          tabindex="0"
        >
          <.icon name="hero-information-circle-mini" class="size-4" />
          {if @detail_view == :info, do: "Back", else: "More"}
        </button>
      </div>
    </div>
    """
  end
end
