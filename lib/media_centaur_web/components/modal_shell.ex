defmodule MediaCentaurWeb.Components.ModalShell do
  @moduledoc """
  Centered overlay shell for the DetailPanel.

  Always present in the DOM so the browser keeps the `backdrop-filter`
  compositing layer warm. Toggled via `data-state="open"/"closed"` +
  CSS visibility/opacity — no first-frame blur jank on open.
  """
  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.Components.DetailPanel

  attr :open, :boolean, default: false
  attr :entity, :map, default: nil
  attr :progress, :map, default: nil
  attr :resume, :map, default: nil
  attr :progress_records, :list, default: []
  attr :expanded_seasons, :any, default: nil
  attr :on_play, :string, default: "play"
  attr :on_close, :string, default: "close_detail"

  def modal_shell(assigns) do
    ~H"""
    <div
      id="detail-modal"
      class="modal-backdrop"
      data-state={if @open, do: "open", else: "closed"}
      phx-click={@open && @on_close}
      phx-window-keydown={@open && @on_close}
      phx-key="Escape"
      data-detail-mode="modal"
    >
      <div class="modal-panel bg-base-100" phx-click-away={@open && @on_close}>
        <div :if={@entity} class="flex flex-col flex-1 min-h-0">
          <button
            phx-click={@on_close}
            class="absolute top-3 right-3 z-10 btn btn-ghost btn-circle btn-sm"
            aria-label="Close"
          >
            <.icon name="hero-x-mark-mini" class="size-5" />
          </button>

          <DetailPanel.detail_panel
            entity={@entity}
            progress={@progress}
            resume={@resume}
            progress_records={@progress_records}
            expanded_seasons={@expanded_seasons}
            on_play={@on_play}
            on_close={@on_close}
          />
        </div>
      </div>
    </div>
    """
  end
end
