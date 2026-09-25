defmodule MediaCentaurWeb.Components.Discovery.IdentityTile do
  @moduledoc """
  The app's one drawing of a person (UIDR-046): a circle carrying the
  name's first letter — the monogram — or a photo when one exists. The
  reader's own tile is filled with the button primary and a white
  letter, so an own row is found without reading; a photo inside a 2px
  primary ring says the same. Three sizes, one per surface: 48 in the
  Feed's rail, 56 on a band, 64 on the Friends page. `aria-hidden`: the
  name is read from the surface's text, the tile is its redundant
  channel.

  No photo exists today — the social protocol carries no profile
  event — so every host passes `nil`; the attr is the space the design
  leaves for one.
  """

  use Phoenix.Component

  alias MediaCentaur.Format

  attr :name, :string, required: true, doc: "the display name; `Format.monogram/1` of it is the letter"
  attr :size, :integer, required: true, values: [48, 56, 64]
  attr :own?, :boolean, default: false
  attr :photo_url, :string, default: nil

  def identity_tile(assigns) do
    assigns = assign(assigns, :size_classes, size_classes(assigns.size))

    ~H"""
    <span
      class={[
        "relative grid shrink-0 place-items-center overflow-hidden rounded-full leading-none",
        @size_classes,
        !@photo_url && !@own? &&
          "bg-primary/20 font-semibold text-primary ring-1 ring-inset ring-primary/25 shadow-[0_2px_8px_oklch(0%_0_0/0.35)]",
        !@photo_url && @own? &&
          "bg-primary font-bold text-primary-content shadow-[0_2px_8px_oklch(0%_0_0/0.4)]",
        @photo_url && !@own? && "ring-1 ring-inset ring-base-content/20",
        @photo_url && @own? && "ring-2 ring-primary"
      ]}
      data-component="identity-tile"
      data-size={@size}
      data-own={@own?}
      aria-hidden="true"
    >
      <img
        :if={@photo_url}
        src={@photo_url}
        alt=""
        class="size-full object-cover"
        loading="eager"
        decoding="sync"
      />
      {if !@photo_url, do: Format.monogram(@name)}
    </span>
    """
  end

  # The states are disjoint branches rather than a base plus overrides:
  # class precedence is stylesheet order, not template order. The size
  # is checked here as well as by `values:` because a template's check is
  # compile-time only — a dynamic `size={@n}` would otherwise render an
  # unsized circle.
  defp size_classes(48), do: "size-12 text-[19px]"
  defp size_classes(56), do: "size-14 text-[22px]"
  defp size_classes(64), do: "size-16 text-[26px]"

  defp size_classes(size),
    do: raise(ArgumentError, "identity_tile size must be 48, 56 or 64, got: #{inspect(size)}")
end
