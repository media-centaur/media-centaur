defmodule MediaCentaurWeb.Storybook.AppCards.BannerArt do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.AppCards.banner_art/1
  def render_source, do: :function

  def template do
    ~s|<div class="max-w-xs"><.psb-variation/></div>|
  end

  def variations do
    [
      %Variation{
        id: :with_banner,
        description: "A cached banner (the fixture 404s in storybook chrome; the frame still resolves)",
        attributes: %{name: "Sample Game", banner_url: "/media-images/images/apps/demo-1/banner.jpg"}
      },
      %Variation{
        id: :monogram,
        description: "No banner — the monogram",
        attributes: %{name: "Emulator", banner_url: nil}
      },
      %Variation{
        id: :painted,
        description:
          "The inner block paints the frame instead: the picture field's How it will look canvas (blank until the crop hook draws)",
        attributes: %{name: "Sample App", class: "w-32"},
        slots: [
          ~s|<canvas data-role="preview" width="460" height="215" class="absolute inset-0 size-full"></canvas>|
        ]
      }
    ]
  end
end
