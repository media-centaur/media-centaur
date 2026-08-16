defmodule MediaCentaurWeb.Components.StatusWidgets.Shared do
  @moduledoc """
  Shared helpers for the per-subsystem Status Activity widgets
  (`MediaCentaurWeb.Components.StatusWidgets.*`).
  """
  use MediaCentaurWeb, :html

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :skip
  @storybook_reason "Thin Settings deep-link wrapper (slot content + a hover cog); exercised in situ by the widgets that embed it."

  @doc false
  # Wraps a status-page reference to a configured value so it deep-links to the
  # Settings section that owns it (e.g. the update-automation row → ?section=system).
  # Keeps the wrapped content's own colour; adds a muted cog that brightens to
  # primary on hover, signalling "this jumps to Settings".
  attr :section, :string,
    required: true,
    doc: ~s|Settings section id, e.g. "updates", "library", "tmdb"|

  attr :class, :any, default: nil, doc: "extra classes for the link wrapper"
  slot :inner_block, required: true

  def settings_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/settings?section=#{@section}"}
      class={["group/setting inline-flex items-center hover:text-primary transition-colors", @class]}
    >
      {render_slot(@inner_block)}
      <.icon
        name="hero-cog-6-tooth-mini"
        class="size-3 ml-1 shrink-0 text-base-content/30 group-hover/setting:text-primary transition-colors"
      />
    </.link>
    """
  end
end
