defmodule MediaCentarrWeb.Components.Detail.FacetStrip do
  @moduledoc """
  Single-row replacement for the old "At a glance" / "Genres & themes" /
  "Reception" stack — small label-on-top columns separated by faint vertical
  dividers, wrapping gracefully on narrow widths.

  Renders nothing when `facets` is empty so the calling template doesn't
  need to guard against it.
  """
  use MediaCentarrWeb, :html

  alias MediaCentarrWeb.Components.Detail.Facet

  attr :facets, :list,
    default: [],
    doc:
      "list of `MediaCentarrWeb.Components.Detail.Facet.t()` structs (constructed via `Detail.Logic.facets_for/2,3` or the `Facet.text/2`, `Facet.chips/2`, `Facet.rating/3` helpers). Phoenix has no list-of-typed-structs attr; element type is enforced via the inner `attr :facet, Facet`."

  def facet_strip(assigns) do
    ~H"""
    <div
      :if={@facets != []}
      class="grid grid-cols-[repeat(auto-fit,minmax(140px,1fr))] gap-y-3 py-2.5 border-y border-base-content/[0.07]"
    >
      <div
        :for={facet <- @facets}
        class="flex flex-col gap-0.5 px-4 first:pl-0 last:pr-0 border-l border-base-content/[0.07] first:border-l-0 min-w-0"
      >
        <span class="text-[0.65rem] uppercase tracking-wider text-base-content/40 font-semibold">
          {facet.label}
        </span>
        <.facet_value facet={facet} />
      </div>
    </div>
    """
  end

  attr :facet, Facet, required: true

  defp facet_value(%{facet: %Facet{kind: :text}} = assigns) do
    ~H"""
    <span class="text-sm text-base-content/90 truncate" title={@facet.value}>{@facet.value}</span>
    """
  end

  defp facet_value(%{facet: %Facet{kind: :chips}} = assigns) do
    ~H"""
    <span class="text-sm text-base-content/80">
      <%= for {item, idx} <- Enum.with_index(@facet.value) do %>
        <span :if={idx > 0} class="text-base-content/30 select-none mx-1">·</span>
        <span>{item}</span>
      <% end %>
    </span>
    """
  end

  defp facet_value(%{facet: %Facet{kind: :rating}} = assigns) do
    %{rating: rating, vote_count: vote_count} = assigns.facet.value
    assigns = assign(assigns, rating: rating, vote_count: vote_count)

    ~H"""
    <span class="text-sm text-base-content/90 flex items-baseline gap-1.5">
      <span class="text-success font-semibold tabular-nums">★ {Float.round(@rating, 1)}</span>
      <span :if={is_integer(@vote_count) && @vote_count > 0} class="text-xs text-base-content/45">
        {format_votes(@vote_count)}
      </span>
    </span>
    """
  end

  defp format_votes(count) when count >= 1000, do: "#{Float.round(count / 1000, 1)}k"
  defp format_votes(count), do: Integer.to_string(count)
end
