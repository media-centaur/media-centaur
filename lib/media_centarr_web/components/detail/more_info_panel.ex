defmodule MediaCentarrWeb.Components.Detail.MoreInfoPanel do
  @moduledoc """
  "More info" sub-view of the movie detail modal — opened from the
  PlayCard's *More info* button. Renders movie-specific extras: linked
  director(s) and writers above a grid of cast cards (no horizontal
  scroll), then a meta block (studio, country, language, runtime,
  release date), and external links (TMDB, IMDb when present).

  Movies-only for v1. TV series have no equivalent yet because we don't
  store crew or imdb_id on `Library.TVSeries`.

  Person names link to TMDB person pages when `tmdb_person_id` is
  present; otherwise rendered as plain text. Profile photos hotlink
  from `image.tmdb.org/t/p/w185{path}` — same convention the rest of the
  app uses for unimported TMDB artwork.
  """

  use MediaCentarrWeb, :html

  attr :entity, :map,
    required: true,
    doc:
      "normalized entity map (see `MediaCentarr.Library.EntityShape.normalize/2`). Reads `:cast`, `:crew`, `:imdb_id`, `:url`, `:studio`, `:country_code`, `:original_language`, `:duration`, `:date_published`."

  def more_info_panel(assigns) do
    crew = assigns.entity[:crew] || []

    assigns =
      assigns
      |> assign(:directors, filter_crew(crew, ["Director"]))
      |> assign(:writers, filter_crew(crew, ["Screenplay", "Writer", "Story"]))
      |> assign(:cast, assigns.entity[:cast] || [])

    ~H"""
    <section class="space-y-6 pt-2 pb-4">
      <div :if={@directors != [] or @writers != []} class="space-y-1.5 text-sm">
        <p :if={@directors != []}>
          <span class="text-base-content/60">Directed by</span>
          <.people people={@directors} />
        </p>
        <p :if={@writers != []}>
          <span class="text-base-content/60">Written by</span>
          <.people people={@writers} />
        </p>
      </div>

      <div :if={@cast != []}>
        <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/60 mb-3">
          Cast
        </h3>
        <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 gap-3">
          <.card :for={person <- @cast} person={person} />
        </div>
      </div>

      <.meta_block entity={@entity} />

      <.external_links entity={@entity} />
    </section>
    """
  end

  defp filter_crew(crew, jobs), do: Enum.filter(crew, &(&1["job"] in jobs))

  attr :people, :list, required: true, doc: "list of crew or cast maps with `tmdb_person_id` + `name`."

  defp people(assigns) do
    ~H"""
    <span>
      <%= for {person, idx} <- Enum.with_index(@people) do %>
        <span :if={idx > 0} class="text-base-content/60">, </span>
        <.person_link person={person} />
      <% end %>
    </span>
    """
  end

  attr :person, :map,
    required: true,
    doc:
      "string-keyed person map (`tmdb_person_id`, `name`) — used for both crew and cast. Renders as a TMDB link when `tmdb_person_id` is present, plain text otherwise."

  defp person_link(%{person: %{"tmdb_person_id" => id}} = assigns) when is_integer(id) do
    ~H"""
    <a
      href={"https://www.themoviedb.org/person/#{@person["tmdb_person_id"]}"}
      target="_blank"
      rel="noopener noreferrer"
      class="font-medium text-base-content hover:text-primary transition-colors"
    >
      {@person["name"]}
    </a>
    """
  end

  defp person_link(assigns) do
    ~H"""
    <span class="font-medium text-base-content">{@person["name"]}</span>
    """
  end

  attr :person, :map,
    required: true,
    doc:
      "single cast entry — string-keyed map matching `MediaCentarr.Library.Movie.cast` shape (`name`, `character`, `tmdb_person_id`, `profile_path`, `order`). Loose-typed because the value lives inside a `{:array, :map}` Ecto column where keys are JSON-serialised."

  defp card(%{person: %{"tmdb_person_id" => id}} = assigns) when is_integer(id) do
    ~H"""
    <a
      href={"https://www.themoviedb.org/person/#{@person["tmdb_person_id"]}"}
      target="_blank"
      rel="noopener noreferrer"
      class="group focus:outline-none focus:ring-2 focus:ring-primary rounded-md"
    >
      <.photo person={@person} />
      <p class="mt-1.5 text-xs font-semibold leading-tight text-base-content line-clamp-2 group-hover:text-primary transition-colors">
        {@person["name"]}
      </p>
      <p
        :if={@person["character"]}
        class="mt-0.5 text-[11px] leading-tight text-base-content/60 line-clamp-2"
      >
        {@person["character"]}
      </p>
    </a>
    """
  end

  defp card(assigns) do
    ~H"""
    <div>
      <.photo person={@person} />
      <p class="mt-1.5 text-xs font-semibold leading-tight text-base-content line-clamp-2">
        {@person["name"]}
      </p>
      <p
        :if={@person["character"]}
        class="mt-0.5 text-[11px] leading-tight text-base-content/60 line-clamp-2"
      >
        {@person["character"]}
      </p>
    </div>
    """
  end

  attr :person, :map,
    required: true,
    doc: "same string-keyed map as `card/1` — see that doc for shape rationale."

  defp photo(%{person: %{"profile_path" => path}} = assigns) when is_binary(path) do
    ~H"""
    <img
      src={"https://image.tmdb.org/t/p/w185#{@person["profile_path"]}"}
      alt={@person["name"]}
      loading="lazy"
      class="w-full aspect-[5/7] rounded-md object-cover bg-base-300"
    />
    """
  end

  defp photo(assigns) do
    ~H"""
    <div class="w-full aspect-[5/7] rounded-md bg-base-300/60 flex items-center justify-center">
      <.icon name="hero-user" class="size-10 text-base-content/30" />
    </div>
    """
  end

  attr :entity, :map, required: true, doc: "normalized entity map — see top-level attr."

  defp meta_block(assigns) do
    items =
      Enum.reject(
        [
          {"Studio", assigns.entity[:studio]},
          {"Country", assigns.entity[:country_code]},
          {"Language", assigns.entity[:original_language]},
          {"Runtime", format_runtime(assigns.entity[:duration])},
          {"Released", assigns.entity[:date_published]}
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

  attr :entity, :map, required: true, doc: "normalized entity map — see top-level attr."

  defp external_links(assigns) do
    ~H"""
    <div class="flex items-center gap-3 text-sm border-t border-base-content/10 pt-4">
      <a
        :if={@entity[:url]}
        href={@entity[:url]}
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1 text-base-content/70 hover:text-primary transition-colors"
      >
        TMDB <.icon name="hero-arrow-top-right-on-square-mini" class="size-3.5" />
      </a>
      <a
        :if={@entity[:imdb_id]}
        href={"https://www.imdb.com/title/#{@entity[:imdb_id]}/"}
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1 text-base-content/70 hover:text-primary transition-colors"
      >
        IMDb <.icon name="hero-arrow-top-right-on-square-mini" class="size-3.5" />
      </a>
    </div>
    """
  end

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
