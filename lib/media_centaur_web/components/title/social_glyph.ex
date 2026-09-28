defmodule MediaCentaurWeb.Components.Title.SocialGlyph do
  @moduledoc """
  The social glyph: one flag (`Title.Flag`) drawn at its grade
  (`Title.Grade`) — plain, a white line drawing from the outline set;
  silver or gold, the solid glyph in brushed metal (`.social-glyph` in
  `app.css`). Every surface that shows what people did with a title
  draws it here: a person card's acts strip and opened rows, a title
  row, a Feed row's sentiment, the title detail's social capsule and
  social panel.

  `social_glyphs/1` is a title's flags in order, each at its grade. The size is
  the host's: `--glyph` on an ancestor, or a size utility in `class`.
  A glyph states; it never acts. `title` carries the sentence a pointer
  reader sees on hover.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaurWeb.Components.Title.Flag
  alias MediaCentaurWeb.Components.Title.Grade

  attr :flag, :atom, required: true, values: Flag.order()
  attr :grade, :atom, default: :plain, values: [:plain, :silver, :gold]
  attr :title, :string, default: nil, doc: "the hover sentence"

  attr :class, :any,
    default: nil,
    doc: "sizing, when no ancestor sets `--glyph` — Tailwind classes, a string or a list"

  def social_glyph(assigns) do
    ~H"""
    <span
      class={["social-glyph", @class]}
      data-flag={@flag}
      data-grade={@grade}
      title={@title}
    >
      <.icon name={glyph(@flag, @grade)} class="social-icon" />
    </span>
    """
  end

  attr :flags, :list, required: true, doc: "the title's flags, in `Flag.order/0`"
  attr :grades, :map, required: true, doc: "`%{flag => Grade.t()}` for every flag in `flags`"

  attr :titles, :map,
    default: %{},
    doc: "`%{flag => sentence}` — each glyph's hover sentence, when the host has one"

  attr :glyph_class, :any,
    default: nil,
    doc: "each glyph's sizing — Tailwind classes, a string or a list"

  attr :class, :any, default: nil, doc: "the group's layout — Tailwind classes, a string or a list"
  attr :rest, :global, doc: "`aria-hidden` where the host speaks the acts in words"

  @doc "A title's social glyphs in order, each at its grade, as one inline group."
  def social_glyphs(assigns) do
    ~H"""
    <span class={["inline-flex items-center", @class]} data-role="social-glyphs" {@rest}>
      <.social_glyph
        :for={flag <- @flags}
        flag={flag}
        grade={Map.fetch!(@grades, flag)}
        title={@titles[flag]}
        class={@glyph_class}
      />
    </span>
    """
  end

  @doc "The heroicon a flag draws in at a grade: the outline set at plain, the solid set under a metal."
  @spec glyph(Flag.flag(), Grade.t()) :: String.t()
  def glyph(flag, :plain), do: Flag.glyph(flag, :outline)
  def glyph(flag, _metal), do: Flag.glyph(flag, :solid)
end
