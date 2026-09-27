defmodule MediaCentaurWeb.Components.Discovery.IdentityTile do
  @moduledoc """
  The app's one drawing of a person (UIDR-046, UIDR-047): a circle
  carrying the **avatar** when the person has one the reader shows, else
  the **letter**, the first of the words the reader sees for them
  (`Format.person_name/1`, so the reader's own tile takes the Y of You).
  UIDR-047's third mark, the person glyph for a friend with no name at
  all, lands with the profiles campaign's phase 2, when a name can be
  missing. The reader's own tile is filled with the button primary and a
  white letter, so an own row is found without reading; an avatar inside
  a 2px primary ring says the same. Two sizes: 40 on a Feed row and the
  rail's person card, 48 on the Friends page's. `aria-hidden`: the name
  is read from the surface's text, the tile is its redundant channel.

  `data-mark` names the mark drawn, for tests and probes. No avatar
  exists yet (phase 3); the Person's `avatar_url` and the `:avatar` mark
  are the space the design leaves for one.
  """

  use Phoenix.Component

  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person

  attr :person, Person, required: true, doc: "as the reader sees them"
  attr :size, :integer, required: true, values: [40, 48]

  def identity_tile(assigns) do
    assigns =
      assign(assigns,
        size_classes: size_classes(assigns.size),
        mark: mark(assigns.person),
        own?: assigns.person.own?
      )

    ~H"""
    <span
      class={[
        "relative grid shrink-0 place-items-center overflow-hidden rounded-full leading-none",
        @size_classes,
        @mark == :letter && !@own? &&
          "bg-primary/20 font-semibold text-primary ring-1 ring-inset ring-primary/25 shadow-[0_2px_8px_oklch(0%_0_0/0.35)]",
        @mark == :letter && @own? &&
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
      {if @mark == :letter, do: Format.monogram(Format.person_name(@person))}
    </span>
    """
  end

  defp mark(%Person{avatar_url: url}) when is_binary(url), do: :avatar
  defp mark(%Person{}), do: :letter

  # The states are disjoint branches rather than a base plus overrides:
  # class precedence is stylesheet order, not template order. The size
  # is checked here as well as by `values:` because a template's check is
  # compile-time only — a dynamic `size={@n}` would otherwise render an
  # unsized circle.
  defp size_classes(40), do: "size-10 text-base"
  defp size_classes(48), do: "size-12 text-[19px]"

  defp size_classes(size),
    do: raise(ArgumentError, "identity_tile size must be 40 or 48, got: #{inspect(size)}")
end
