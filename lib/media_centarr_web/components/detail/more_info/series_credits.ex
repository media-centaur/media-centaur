defmodule MediaCentarrWeb.Components.Detail.MoreInfo.SeriesCredits do
  @moduledoc """
  TV-series-shaped credit rendering for the More info panel — a
  *Created by* headline (mapped from TMDB `created_by`) plus a
  network / first-aired / status / country / language meta block.
  Sibling of `MovieCredits`; both are composed by `MoreInfoPanel`
  based on `entity.type`.

  Per-episode directors and writers are intentionally not surfaced
  for v1 — TMDB returns those via `aggregate_credits.crew` and the
  data is too noisy for a single show-level row. *Created by* is the
  closest analogue to the movie panel's *Directed by* / *Written by*.
  """

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :skip
  @storybook_reason "Composed by `MoreInfoPanel`; isolated rendering offers no design surface beyond what the shell story's `:tv_series` variations already cover."

  use MediaCentarrWeb, :html

  alias MediaCentarrWeb.Components.Detail.MoreInfo.People

  @tv_status_labels %{
    returning: "Returning",
    ended: "Ended",
    canceled: "Canceled",
    in_production: "In production",
    planned: "Planned"
  }

  attr :entity, :map,
    required: true,
    doc:
      "normalized series entity (see `MediaCentarr.Library.EntityShape.normalize/2`). Reads `:crew` (list of `MediaCentarr.Library.Person` structs) for Creator filtering."

  def headline(assigns) do
    crew = assigns.entity[:crew] || []
    assigns = assign(assigns, :creators, filter_crew(crew, ["Creator"]))

    ~H"""
    <div :if={@creators != []} class="space-y-1.5 text-sm">
      <p>
        <span class="text-base-content/60">Created by</span>
        <People.people people={@creators} />
      </p>
    </div>
    """
  end

  attr :entity, :map,
    required: true,
    doc:
      "normalized series entity. Reads `:network`, `:date_published` (first-aired), `:status`, `:country_code`, `:original_language`."

  def meta_block(assigns) do
    items =
      Enum.reject(
        [
          {"Network", assigns.entity[:network]},
          {"First aired", assigns.entity[:date_published]},
          {"Status", format_status(assigns.entity[:status])},
          {"Country", assigns.entity[:country_code]},
          {"Language", assigns.entity[:original_language]}
        ],
        fn {_label, value} -> value in [nil, ""] end
      )

    assigns = assign(assigns, :items, items)

    ~H"""
    <dl
      :if={@items != []}
      class="grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-2 text-sm border-t border-base-content/10 pt-4"
    >
      <div :for={{label, value} <- @items} class="flex flex-col">
        <dt class="text-xs uppercase tracking-wider text-base-content/50">{label}</dt>
        <dd class="text-base-content">{value}</dd>
      </div>
    </dl>
    """
  end

  defp filter_crew(crew, jobs), do: Enum.filter(crew, &(&1.job in jobs))

  defp format_status(nil), do: nil
  defp format_status(status) when is_atom(status), do: Map.get(@tv_status_labels, status)
  defp format_status(_), do: nil
end
