defmodule MediaCentaurWeb.Components.ModalShell do
  @moduledoc """
  Centered overlay shell for the DetailPanel.

  Used by Continue Watching zone. Provides backdrop blur, focus trap (grid inert),
  entrance animation, and dismiss via Escape / click-outside / close button.
  """
  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.Components.DetailPanel

  attr :entity, :map, required: true
  attr :progress, :map, default: nil
  attr :resume, :map, default: nil
  attr :progress_records, :list, default: []
  attr :watch_dirs, :list, default: []
  attr :expanded_seasons, :any, default: nil
  attr :expanded_episodes, :any, default: nil
  attr :on_play, :string, default: "play"
  attr :on_close, :string, default: "close_detail"

  def modal_shell(assigns) do
    ~H"""
    <div
      id="detail-modal"
      class="modal-backdrop"
      phx-click={@on_close}
      phx-window-keydown={@on_close}
      phx-key="Escape"
      data-detail-mode="modal"
    >
      <div class="modal-panel bg-base-100" phx-click-away={@on_close}>
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
          watch_dirs={@watch_dirs}
          expanded_seasons={@expanded_seasons}
          expanded_episodes={@expanded_episodes}
          on_play={@on_play}
          on_close={@on_close}
        />
      </div>
    </div>
    """
  end
end
