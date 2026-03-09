defmodule MediaCentaurWeb.Components.DrawerShell do
  @moduledoc """
  Right-docked sidebar shell for the DetailPanel.

  Used by Library Browse zone. No backdrop overlay — grid remains visible and
  interactive. Provides slide-in animation, cross-fade on entity swap, and
  dismiss via Escape / close button.
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

  def drawer_shell(assigns) do
    ~H"""
    <aside
      id="detail-drawer"
      class="drawer-panel glass-surface"
      phx-window-keydown={@on_close}
      phx-key="Escape"
      data-detail-mode="drawer"
    >
      <button
        phx-click={@on_close}
        class="absolute top-3 right-3 z-10 btn btn-ghost btn-circle btn-sm"
        aria-label="Close"
      >
        <.icon name="hero-x-mark-mini" class="size-5" />
      </button>

      <div class="overflow-y-auto max-h-screen">
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
    </aside>
    """
  end
end
