defmodule MediaCentaurWeb.Storybook.CoreComponents.PageHeader do
  @moduledoc "Story for `<.page_header>` — the one page-title treatment (audit DS12)."

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.CoreComponents.page_header/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :title_only,
        attributes: %{title: "Status"}
      },
      %Variation{
        id: :with_subtitle,
        attributes: %{title: "Library"},
        slots: [~s|<:subtitle>12 movies · 3 shows</:subtitle>|]
      }
    ]
  end
end
