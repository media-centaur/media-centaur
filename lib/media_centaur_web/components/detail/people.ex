defmodule MediaCentaurWeb.Components.Detail.People do
  @moduledoc """
  Shared person-rendering helpers for the detail modal — comma-separated
  linked names when a TMDB person id is present, plain text otherwise.
  Used by the Cast view's movie credits headline.
  """

  use MediaCentaurWeb, :html

  attr :people, :list,
    required: true,
    doc: "list of `MediaCentaur.Library.Person` structs with `tmdb_person_id` + `name`."

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
      "`MediaCentaur.Library.Person` struct. Renders as a TMDB link when `tmdb_person_id` is present, plain text otherwise."

  def person_link(%{person: %{tmdb_person_id: id}} = assigns) when is_integer(id) do
    ~H"""
    <a
      href={"https://www.themoviedb.org/person/#{@person.tmdb_person_id}"}
      target="_blank"
      rel="noopener noreferrer"
      class="font-medium text-base-content hover:text-primary transition-colors"
    >
      {@person.name}
    </a>
    """
  end

  def person_link(assigns) do
    ~H"""
    <span class="font-medium text-base-content">{@person.name}</span>
    """
  end
end
