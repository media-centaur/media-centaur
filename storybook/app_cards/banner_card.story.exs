defmodule MediaCentaurWeb.Storybook.AppCards.BannerCard do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.AppCards.banner_card/1
  def render_source, do: :function

  def template do
    ~s|<div class="max-w-sm"><.psb-variation/></div>|
  end

  def variations do
    [
      %Variation{
        id: :with_banner,
        description: "Cached Steam header art (the miss serves a banner-shaped placeholder SVG)",
        attributes: %{
          id: "app-card-demo-1",
          app_id: "demo-1",
          name: "Sample Game",
          banner_url: "/media-images/images/apps/demo-1/banner.jpg"
        }
      },
      %Variation{
        id: :monogram_fallback,
        description: "Manual app without artwork — monogram fallback",
        attributes: %{
          id: "app-card-demo-2",
          app_id: "demo-2",
          name: "Emulator",
          banner_url: nil
        }
      },
      %Variation{
        id: :manage_mode,
        description: "Manage mode — click edits, remove button visible",
        attributes: %{
          id: "app-card-demo-3",
          app_id: "demo-3",
          name: "Sample Game",
          banner_url: "/media-images/images/apps/demo-3/banner.jpg",
          manage: true
        }
      }
    ]
  end
end
