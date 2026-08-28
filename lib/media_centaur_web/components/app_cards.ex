defmodule MediaCentaurWeb.Components.AppCards do
  @moduledoc """
  Cards for the Apps launcher page.

  `banner_card/1` renders one app as a landscape card at Steam header
  art's native 460:215 ratio (forcing the 16:9 backdrop-card ratio would
  crop ~17% of the art) while sharing the established card chrome
  (`card-hover`, `glass-inset`) and the art-less fallback idiom from
  `ContinueWatchingRow` — a centered monogram when no banner is cached.

  In manage mode the card stops launching: clicking it opens the edit
  modal instead, and a remove button appears.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1, icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  attr :id, :string, required: true, doc: "DOM id (stable across renders)"
  attr :app_id, :string, required: true

  attr :name, :string, required: true

  attr :banner_url, :string,
    default: nil,
    doc: "cached banner web path; nil renders the monogram fallback"

  attr :manage, :boolean,
    default: false,
    doc: "manage mode: click edits instead of launching, remove button shown"

  def banner_card(assigns) do
    ~H"""
    <div
      id={@id}
      phx-click={if @manage, do: "edit_app", else: "launch_app"}
      phx-value-app-id={@app_id}
      phx-throttle="1000"
      class="card-hover relative aspect-[460/215] rounded-lg overflow-hidden glass-inset block w-full text-left cursor-pointer"
      data-nav-item
      data-app-id={@app_id}
      tabindex="0"
    >
      <img
        :if={@banner_url}
        src={sized_image_url(@banner_url, 640)}
        alt={@name}
        class="absolute inset-0 w-full h-full object-cover"
        loading="eager"
        decoding="sync"
      />
      <div
        :if={!@banner_url}
        class="absolute inset-0 flex flex-col items-center justify-center gap-1 text-base-content/60"
      >
        <span class="text-4xl font-semibold">{@name |> String.first() |> String.upcase()}</span>
        <span class="text-sm font-medium truncate max-w-[90%]">{@name}</span>
      </div>
      <.button
        :if={@manage}
        variant="destructive_inline"
        size="sm"
        shape="square"
        class="absolute top-2 right-2 z-10"
        phx-click="remove_app"
        phx-value-app-id={@app_id}
        data-nav-item
        tabindex="0"
        aria-label={"Remove #{@name}"}
      >
        <.icon name="hero-trash" class="size-4" />
      </.button>
    </div>
    """
  end
end
