defmodule MediaCentaurWeb.Components.Detail.Credits do
  @moduledoc """
  The credits line of a title: *Directed by*, *Written by* and *Created
  by*, each followed by the people in that role (`Detail.People`). A
  role with nobody in it draws no line; a crew with none of the three
  draws nothing.

  Two surfaces draw it: the Cast view's headline for an owned movie
  (`Detail.CastPanel`), and the body of the title detail for a title the
  library does not own, from its live preview (`DetailPanel`).
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.Library.Person
  alias MediaCentaurWeb.Components.Detail.People

  @roles [
    {:directed, "Directed by", ["Director"]},
    {:written, "Written by", ["Screenplay", "Writer", "Story"]},
    {:created, "Created by", ["Creator"]}
  ]

  @doc """
  The lines the crew earns, in the order they are drawn: each the role,
  its label and the people whose job is in it, in crew order. Roles with
  nobody are left out.
  """
  @spec lines([Person.t()]) :: [{atom(), String.t(), [Person.t()]}]
  def lines(crew) do
    for {role, label, jobs} <- @roles,
        people = Enum.filter(crew, &(&1.job in jobs)),
        people != [],
        do: {role, label, people}
  end

  attr :id, :string, required: true, doc: "prefix for each line's stable element id."

  attr :crew, :list,
    required: true,
    doc: "`MediaCentaur.Library.Person` structs with `job` — a title's crew."

  def credits(assigns) do
    assigns = assign(assigns, :lines, lines(assigns.crew))

    ~H"""
    <div :if={@lines != []} class="space-y-1.5 text-sm" data-component="title-credits">
      <p :for={{role, label, people} <- @lines} id={"#{@id}-#{role}"}>
        <span class="text-base-content/60">{label}</span>
        <People.people people={people} />
      </p>
    </div>
    """
  end
end
