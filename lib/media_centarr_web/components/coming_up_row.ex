defmodule MediaCentarrWeb.Components.ComingUpRow do
  @moduledoc """
  4-card digest row of upcoming tracked releases. Used on Home as a
  "Coming Up This Week" preview that links to /upcoming.

  Each item is a map: `%{id, name, subtitle, badge, backdrop_url}`.
  `badge` is `%{label, variant}` with variant in `:success | :info | :default`.
  """
  use Phoenix.Component

  attr :items, :list, required: true

  def coming_up_row(assigns) do
    ~H"""
    <div :if={@items != []} data-component="coming-up" class="grid grid-cols-2 sm:grid-cols-4 gap-4">
      <div :for={item <- @items} class="relative aspect-[16/9] rounded-lg overflow-hidden glass-inset">
        <img
          :if={item.backdrop_url}
          src={item.backdrop_url}
          class="absolute inset-0 w-full h-full object-cover object-top"
          loading="lazy"
        />
        <div class="absolute inset-0 bg-gradient-to-t from-black/85 via-black/20 to-transparent">
        </div>
        <span class={[
          "absolute top-2 right-2 text-[10px] font-semibold uppercase tracking-wider px-1.5 py-0.5 rounded",
          badge_class(item.badge.variant)
        ]}>
          {item.badge.label}
        </span>
        <div class="absolute bottom-2 left-2 right-2">
          <div class="text-[10px] uppercase tracking-wider text-white/70 truncate">
            {item.subtitle}
          </div>
          <div class="text-sm font-semibold text-white drop-shadow truncate">{item.name}</div>
        </div>
      </div>
    </div>
    """
  end

  defp badge_class(:success), do: "bg-success/20 text-success"
  defp badge_class(:info), do: "bg-info/20 text-info"
  defp badge_class(_), do: "bg-base-content/15 text-base-content/70"
end
