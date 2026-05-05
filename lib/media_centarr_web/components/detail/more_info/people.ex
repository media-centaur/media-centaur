defmodule MediaCentarrWeb.Components.Detail.MoreInfo.People do
  @moduledoc """
  Shared person-rendering helpers for the More info panel — used by both
  the movie credits row (Directed by / Written by) and the series
  credits row (Created by). Renders comma-separated linked names when a
  TMDB person id is present, plain text otherwise.
  """

  use MediaCentarrWeb, :html

  attr :people, :list,
    required: true,
    doc:
      "list of crew/cast maps with `tmdb_person_id` + `name` (string keys — entries originate in JSON-serialised :array, :map columns)."

  def people(assigns) do
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
      "string-keyed person map (`tmdb_person_id`, `name`). Renders as a TMDB link when `tmdb_person_id` is present, plain text otherwise."

  def person_link(%{person: %{"tmdb_person_id" => id}} = assigns) when is_integer(id) do
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

  def person_link(assigns) do
    ~H"""
    <span class="font-medium text-base-content">{@person["name"]}</span>
    """
  end
end
