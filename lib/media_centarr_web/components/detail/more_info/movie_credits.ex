defmodule MediaCentarrWeb.Components.Detail.MoreInfo.MovieCredits do
  @moduledoc """
  Movie-shaped credit rendering for the More info panel — the
  *Directed by* / *Written by* headline pair plus the
  studio/country/language/runtime/release meta block. Sibling of
  `MediaCentarrWeb.Components.Detail.MoreInfo.SeriesCredits`; both are
  composed by `MoreInfoPanel` based on `entity.type`.
  """

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :skip
  @storybook_reason "Composed by `MoreInfoPanel`; isolated rendering offers no design surface beyond what the shell story's movie variations already cover."

  use MediaCentarrWeb, :html

  alias MediaCentarrWeb.Components.Detail.MoreInfo.People

  attr :entity, :map,
    required: true,
    doc:
      "normalized movie entity (see `MediaCentarr.Library.EntityShape.normalize/2`). Reads `:crew` (list of `MediaCentarr.Library.Person` structs) for director/writer filtering."

  def headline(assigns) do
    crew = assigns.entity[:crew] || []

    assigns =
      assigns
      |> assign(:directors, filter_crew(crew, ["Director"]))
      |> assign(:writers, filter_crew(crew, ["Screenplay", "Writer", "Story"]))

    ~H"""
    <div :if={@directors != [] or @writers != []} class="space-y-1.5 text-sm">
      <p :if={@directors != []}>
        <span class="text-base-content/60">Directed by</span>
        <People.people people={@directors} />
      </p>
      <p :if={@writers != []}>
        <span class="text-base-content/60">Written by</span>
        <People.people people={@writers} />
      </p>
    </div>
    """
  end

  attr :entity, :map,
    required: true,
    doc:
      "normalized movie entity. Reads `:studio`, `:country_code`, `:original_language`, `:duration`, `:date_published`."

  def meta_block(assigns) do
    items =
      Enum.reject(
        [
          {"Studio", assigns.entity[:studio]},
          {"Country", assigns.entity[:country_code]},
          {"Language", assigns.entity[:original_language]},
          {"Runtime", format_runtime(assigns.entity[:duration])},
          {"Released", MediaCentarr.Format.iso_date(assigns.entity[:date_published])}
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

  # ISO-8601 duration (e.g. "PT1H47M") → "1h 47m"
  defp format_runtime(nil), do: nil
  defp format_runtime(""), do: nil

  defp format_runtime(iso) when is_binary(iso) do
    case Regex.run(~r/^PT(?:(\d+)H)?(?:(\d+)M)?$/, iso) do
      [_, h, m] when h != "" and m != "" -> "#{h}h #{m}m"
      [_, h, ""] -> "#{h}h"
      [_, "", m] -> "#{m}m"
      _ -> iso
    end
  end
end
