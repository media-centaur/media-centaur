defmodule MediaCentaurWeb.Components.Detail.CastPanel do
  @moduledoc """
  *Cast* sub-view of the detail modal — the people behind the title.

  Movies open with a *Directed by* / *Written by* headline; that pair is
  the only show-level credit worth a line, so series render the grid
  alone — per-episode directors and writers stay excluded (TMDB's
  `aggregate_credits.crew` is too noisy for a single show-level row).

  The catalog facts this view once carried (network, genres, rating,
  language) live in the hero facet strip; the file facts (probed tech
  line, subtitle languages, remembered tracks) live in the Manage view
  next to the files they describe.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.Components.Detail.{CastGrid, People}

  attr :entity, :map,
    required: true,
    doc:
      "entity-map produced by `MediaCentaur.Library.Views.DetailItem.to_entity_map/1`. Reads `:type` (movie headline dispatch), `:crew` and `:cast`."

  attr :cast_filter, :string,
    default: "",
    doc: "current cast filter query, owned by the host LiveView and forwarded to `CastGrid`."

  attr :cast_limit, :integer,
    default: nil,
    doc:
      "how many cast matches to render, owned by the host LiveView (`EntityModal`); `nil` falls back to one page."

  def cast_panel(assigns) do
    ~H"""
    <section class="space-y-6 pt-2 pb-4">
      <.movie_headline entity={@entity} />
      <CastGrid.cast_grid
        cast={@entity[:cast] || []}
        filter={@cast_filter}
        limit={@cast_limit || CastGrid.page_size()}
      />
    </section>
    """
  end

  defp movie_headline(%{entity: %{type: :movie}} = assigns) do
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

  defp movie_headline(assigns), do: ~H""

  defp filter_crew(crew, jobs), do: Enum.filter(crew, &(&1.job in jobs))
end
