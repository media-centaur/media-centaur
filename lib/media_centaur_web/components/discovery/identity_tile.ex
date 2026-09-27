defmodule MediaCentaurWeb.Components.Discovery.IdentityTile do
  @moduledoc """
  The app's one drawing of a person (UIDR-046, UIDR-047): a circle
  carrying one of three marks. The **avatar** when the person has one the
  reader shows; else the **letter**, the first of the words the reader
  sees for them (`Format.person_name/1`, so the reader's own tile takes
  the Y of You); else the **person glyph**, for a friend with no name at
  all — neither an override nor a published one — so no letter is
  invented from Unnamed. The reader's own tile is filled with the button
  primary and a white mark, so an own row is found without reading; an
  avatar inside a 2px primary ring says the same. Two sizes: 40 on a
  Feed row and the rail's person card, 48 on the Friends page's and the
  Settings profile card.
  `aria-hidden`: the name is read from the surface's text, the tile is
  its redundant channel.

  `data-mark` names the mark drawn, for tests and probes.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person

  attr :person, Person, required: true, doc: "as the reader sees them"
  attr :size, :integer, required: true, values: [40, 48]

  def identity_tile(assigns) do
    assigns =
      assign(assigns,
        size_classes: size_classes(assigns.size),
        glyph_classes: glyph_classes(assigns.size),
        mark: mark(assigns.person),
        own?: assigns.person.own?
      )

    ~H"""
    <span
      class={[
        "relative grid shrink-0 place-items-center overflow-hidden rounded-full leading-none",
        @size_classes,
        @mark != :avatar && !@own? &&
          "bg-primary/20 font-semibold text-primary ring-1 ring-inset ring-primary/25 shadow-[0_2px_8px_oklch(0%_0_0/0.35)]",
        @mark != :avatar && @own? &&
          "bg-primary font-bold text-primary-content shadow-[0_2px_8px_oklch(0%_0_0/0.4)]",
        @mark == :avatar && !@own? && "ring-1 ring-inset ring-base-content/20",
        @mark == :avatar && @own? && "ring-2 ring-primary"
      ]}
      data-component="identity-tile"
      data-size={@size}
      data-own={@own?}
      data-mark={@mark}
      aria-hidden="true"
    >
      <img
        :if={@mark == :avatar}
        src={@person.avatar_url}
        alt=""
        class="size-full object-cover"
        loading="eager"
        decoding="sync"
      />
      <.icon :if={@mark == :glyph} name="hero-user-solid" class={@glyph_classes} />
      {if @mark == :letter, do: Format.monogram(Format.person_name(@person))}
    </span>
    """
  end

  defp mark(%Person{avatar_url: url}) when is_binary(url), do: :avatar
  defp mark(%Person{own?: false} = person), do: if(Person.name(person), do: :letter, else: :glyph)
  defp mark(%Person{own?: true}), do: :letter

  # The states are disjoint branches rather than a base plus overrides:
  # class precedence is stylesheet order, not template order. The size
  # is checked here as well as by `values:` because a template's check is
  # compile-time only — a dynamic `size={@n}` would otherwise render an
  # unsized circle.
  defp size_classes(40), do: "size-10 text-base"
  defp size_classes(48), do: "size-12 text-[19px]"

  defp size_classes(size),
    do: raise(ArgumentError, "identity_tile size must be 40 or 48, got: #{inspect(size)}")

  defp glyph_classes(40), do: "size-5"
  defp glyph_classes(48), do: "size-6"
end
