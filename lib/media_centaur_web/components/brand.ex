defmodule MediaCentaurWeb.Components.Brand do
  @moduledoc """
  The app's mark: the centaur over its name, centred — the one drawing of
  "this is Media Centaur" on a surface that stands alone, with no rail or
  bar to say so. The pairing page and the profile picker show it in a
  compact window (`campaigns/adaptive-layout.md`): a phone opens on them
  cold, where a TV or a desktop already sits inside the app's chrome. The
  setup tour and Settings → System draw the same `centaur-logo` image at
  their own sizes.
  """
  use Phoenix.Component
  use MediaCentaurWeb, :verified_routes

  attr :class, :any, default: nil, doc: "placement — a compact-only lockup is `hidden max-compact:flex`"

  def brand(assigns) do
    ~H"""
    <div class={["flex flex-col items-center gap-2", @class]} data-component="brand">
      <img src={~p"/images/centaur-logo.png"} alt="" class="centaur-logo size-16 object-contain" />
      <span class="text-xs font-semibold uppercase tracking-[0.22em] text-base-content/55">
        Media Centaur
      </span>
    </div>
    """
  end
end
