defmodule MediaCentaurWeb.Components.Social.IdentityTile do
  @moduledoc """
  The app's one drawing of a person (UIDR-046, UIDR-047, UIDR-053) from
  three facts — the **name**, the **picture**, the **hue** — and `own?`,
  whether the person is of this install (the reader, a profile) or a
  friend. A circle carrying one of three marks: the picture when there
  is one; else the **letter**, the first of the name; else the **person
  glyph**, for a friend with no name at all, so no letter is invented
  from Unnamed. The tile draws in the hue, the primary's angle when
  there is none: a friend's mark in the hue on its tint, a person of
  this install filled in it with a near-white mark, a picture ringed in
  it, 1 px for a friend and 2 px for one of this install. The recipe is
  `.identity-tile*` in `app.css`. Four sizes: 32 in the title detail's
  social panel and lead review and the sidebar's profile switcher, 40 on a Feed row and the rail's person
  card, 48 on the Friends page's and the Settings cards, 96 on the
  "Who's watching?" picker. `person_attrs/1` is how a `Social.Person`
  becomes those facts (UIDR-053 rule 4); `crop_previews/1` draws the
  same filled recipe around the crop stage's preview canvases.
  `aria-hidden`: the name is read from the surface's text, the tile is
  its redundant channel.

  `data-mark` names the mark drawn, for tests and probes.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.Format
  alias MediaCentaur.Hue
  alias MediaCentaur.Social.Person

  attr :name, :string,
    default: nil,
    doc:
      "the words the surface shows for the person (You for the reader's own); nil (or empty) draws the person glyph"

  attr :picture_url, :string, default: nil, doc: "the picture's versioned URL, or nil for none"

  attr :hue, :integer,
    default: nil,
    doc: "the hue the tile draws in (UIDR-048); nil draws the default Blue"

  attr :own?, :boolean,
    default: false,
    doc: "a person of this install — the reader, a profile — filled in the hue; a friend is tinted"

  attr :size, :integer,
    required: true,
    values: [32, 40, 48, 96],
    doc: "32, 40, 48 or 96; the moduledoc says which surface uses which"

  def identity_tile(assigns) do
    assigns =
      assign(assigns,
        size_classes: size_classes(assigns.size),
        glyph_classes: glyph_classes(assigns.size),
        mark: mark(assigns.picture_url, assigns.name)
      )

    ~H"""
    <span
      class={[
        "identity-tile relative grid shrink-0 place-items-center overflow-hidden rounded-full leading-none",
        @size_classes,
        if(@own?, do: "identity-tile-own font-bold", else: "identity-tile-friend font-semibold"),
        @mark == :avatar && "identity-tile-avatar"
      ]}
      {hue_style(@hue)}
      data-component="identity-tile"
      data-size={@size}
      data-own={@own?}
      data-mark={@mark}
      data-hue={@hue}
      aria-hidden="true"
    >
      <img
        :if={@mark == :avatar}
        src={@picture_url}
        alt=""
        class="size-full object-cover"
        loading="eager"
        decoding="sync"
      />
      <.icon :if={@mark == :glyph} name="hero-user-solid" class={@glyph_classes} />
      {if @mark == :letter, do: Format.monogram(@name)}
    </span>
    """
  end

  @doc """
  The tile's attrs for a `Social.Person` (ADR-074): the words the reader
  sees (`Format.person_name/1` for their own, so the tile takes the Y of
  You; the resolved name, else nil, for a friend), the avatar, the
  resolved hue, and the own flag. Spread it:
  `<.identity_tile {person_attrs(person)} size={40} />`.
  """
  @spec person_attrs(Person.t()) :: keyword()
  def person_attrs(%Person{} = person) do
    [
      name: person_words(person),
      picture_url: person.avatar_url,
      hue: Person.hue(person),
      own?: person.own?
    ]
  end

  @doc """
  The crop stage's two preview frames (`PictureField`'s `:preview`
  slot, *How it will look*): the filled tile's picture recipe at 48 and
  40, each holding the canvas the `ImageCrop` hook paints. The hue
  reaches them from the enclosing field's root.
  """
  def crop_previews(assigns) do
    ~H"""
    <span
      :for={size <- [48, 40]}
      class={[
        "identity-tile identity-tile-own identity-tile-avatar relative grid shrink-0 place-items-center overflow-hidden rounded-full",
        size_classes(size)
      ]}
      aria-hidden="true"
    >
      <canvas data-role="preview" width={size} height={size} class="size-full"></canvas>
    </span>
    """
  end

  @doc """
  The `style` attribute carrying `--hue`, to spread on the element the
  recipe draws (the tile, a swatch): absent when there is no hue so CSS
  draws the default. An attribute list because HEEx renders `style={nil}`
  as `style=""`, while a runtime spread drops a nil.
  """
  @spec hue_style(Hue.t() | nil) :: keyword()
  def hue_style(nil), do: []
  def hue_style(hue), do: [style: "--hue: #{hue}"]

  defp person_words(%Person{own?: true} = person), do: Format.person_name(person)
  defp person_words(%Person{} = person), do: Person.name(person)

  defp mark(url, _name) when is_binary(url), do: :avatar
  defp mark(_url, name) when is_binary(name) and name != "", do: :letter
  defp mark(_url, _name), do: :glyph

  # The size is checked here as well as by `values:` because a template's
  # check is compile-time only — a dynamic `size={@n}` would otherwise
  # render an unsized circle.
  defp size_classes(32), do: "size-8 text-sm"
  defp size_classes(40), do: "size-10 text-base"
  defp size_classes(48), do: "size-12 text-[19px]"
  defp size_classes(96), do: "size-24 text-[38px]"

  defp size_classes(size),
    do: raise(ArgumentError, "identity_tile size must be 32, 40, 48 or 96, got: #{inspect(size)}")

  defp glyph_classes(32), do: "size-4"
  defp glyph_classes(40), do: "size-5"
  defp glyph_classes(48), do: "size-6"
  defp glyph_classes(96), do: "size-12"
end
