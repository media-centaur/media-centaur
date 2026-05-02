defmodule MediaCentarrWeb.Storybook.Detail.Section do
  @moduledoc """
  Consistent section wrapper for the entity detail panel — a small
  uppercase header with tracking, followed by an `inner_block` slot for
  the body content.

  The component is structural: it pins the visual rhythm (header style,
  vertical spacing) so every detail-panel block looks the same regardless
  of its body content. The body itself is freeform — short paragraphs,
  lists, or composed sub-components all work.

  The contract is deliberately minimal: a required `title` string and a
  required `inner_block` slot. There is no description/subtitle attr —
  callers compose richer bodies inside the slot itself.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.Components.Detail.Section.section/1
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="w-full max-w-3xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :with_children,
        description:
          "Title + a single line of body content. The smallest realistic " <>
            "shape — header sits above the body with the standard `space-y-2` gap.",
        attributes: %{title: "Overview"},
        slots: ["A short overview paragraph rendered inside the section body."]
      },
      %Variation{
        id: :paragraph_body,
        description:
          "Title + a longer prose body. Pins that the header style stays " <>
            "compact regardless of how tall the body grows.",
        attributes: %{title: "Synopsis"},
        slots: [
          """
          <p class="text-base-content/80">
            A multi-sentence synopsis used to fill the section body. The wrapper
            does not constrain prose width or line-height; those are inherited
            from the surrounding panel context, which keeps the section purely
            structural.
          </p>
          """
        ]
      },
      %Variation{
        id: :list_body,
        description:
          "Title + a structured list body — pins that arbitrary block " <>
            "content works inside the slot, not just text nodes.",
        attributes: %{title: "Cast"},
        slots: [
          """
          <ul class="list-disc list-inside text-base-content/80 space-y-1">
            <li>Person One — Lead</li>
            <li>Person Two — Supporting</li>
            <li>Person Three — Supporting</li>
          </ul>
          """
        ]
      },
      %Variation{
        id: :multi_block_body,
        description:
          "Title + multiple stacked blocks inside the slot. The section " <>
            "itself doesn't add inter-block spacing beyond `space-y-2`; " <>
            "callers wrap their own layout if they need more.",
        attributes: %{title: "Details"},
        slots: [
          """
          <div class="space-y-3">
            <div>First detail block — a leading summary line.</div>
            <div class="text-base-content/70">
              Second detail block — secondary information rendered below.
            </div>
          </div>
          """
        ]
      },
      %Variation{
        id: :long_title,
        description:
          "Long title — pins that the uppercase header tracks and wraps " <>
            "without breaking the layout above the body.",
        attributes: %{title: "A Considerably Longer Section Heading"},
        slots: ["Body content sits under a header that has wrapped to two lines."]
      },
      %Variation{
        id: :empty_children,
        description:
          "Title with an empty slot — verifies graceful degradation when a " <>
            "caller renders the wrapper but has no body content to show. " <>
            "Only the header is visible; no spacing artifacts appear.",
        attributes: %{title: "Empty Section"},
        slots: [""]
      }
    ]
  end
end
